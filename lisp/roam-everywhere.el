;;; roam-everywhere.el --- Capture anywhere, paste back into the app -*- lexical-binding: t; -*-

;;; Commentary:
;; Trigger from ANY app's text field, write in a real org-roam daily capture
;; (full Meow/flash/org/flyspell — it's a genuine Emacs buffer), finalize with
;; C-c C-c, and the body lands in the window you came from. C-c C-k aborts
;; cleanly and injects nothing.
;;
;; Origin window is recovered AFTER the fact by walking Sway's focus stack:
;; every container node carries a `focus' array ordered most-recently-focused
;; first. We take the most recent leaf that isn't Emacs — necessary because
;; emacs-launcher focuses Emacs before the elisp runs. Targeting is by con_id,
;; which every node has, so Wayland-native and XWayland apps work alike.
;;
;; Clipboard timing note: `wl-copy' forks and stays resident as the selection
;; owner, and XWayland apps (Thunderbird, some URL bars) read the MIRRORED X11
;; selection, which lags that handoff. Setting the clipboard early and pasting
;; later reliably yields the PREVIOUS owner's content in those apps. So we set
;; it synchronously, after refocus, immediately before the keystroke.
;;
;; Sway keybind:
;;   bindsym $mod+Ctrl+e exec $launcher '(jb/roam-capture-everywhere)'

;;; Code:

(require 'org-capture)
(require 'seq)
(require 'cl-lib)

(defvar jb/roam-paste-delay 0.15
  "Seconds after finalize before refocusing the origin window.")

(defvar jb/roam-clipboard-settle 0.12
  "Seconds to wait after setting the clipboard before sending Ctrl+V.
XWayland apps read a mirrored X11 selection that lags the Wayland one;
too short and they paste the previous clipboard owner's content.")

(defvar jb/roam-injection-method 'paste
  "How to inject text into the origin window.
`paste' — wl-copy + Ctrl+V. Fast, exact, but depends on clipboard handoff.
`type'  — wtype keystrokes, no clipboard at all. Slower, immune to the
          XWayland selection lag, and uses Shift+Return for newlines so
          chat apps don't send on every line.")

(defvar jb/roam-self-app-ids '("emacs" "Emacs")
  "app_id / class values identifying Emacs itself, skipped when
determining the origin window.")

(defvar jb/roam--return-conid nil)
(defvar jb/roam--stashed nil)
(defvar jb/roam--armed nil
  "Non-nil only between a capture started by `jb/roam-capture-everywhere'
and its injection. Prevents unrelated captures from injecting, and stale
text from a previous capture being reused.")

;;;###autoload
(defun jb/roam-capture-everywhere ()
  "Org-roam daily capture from anywhere; on finalize, inject the body
into the window that was focused when the capture was triggered."
  (interactive)
  (require 'org-roam)
  (jb/roam--reset-state)
  (setq jb/roam--armed t
        jb/roam--return-conid (jb/roam--origin-conid))
  (add-hook 'org-capture-prepare-finalize-hook #'jb/roam--stash-body)
  (add-hook 'org-capture-after-finalize-hook #'jb/roam--inject)
  (condition-case err
      (org-roam-dailies-capture-today)
    (error
     (jb/roam--remove-hooks)
     (jb/roam--reset-state)
     (signal (car err) (cdr err)))))

(defun jb/roam--reset-state ()
  (setq jb/roam--stashed nil
        jb/roam--return-conid nil
        jb/roam--armed nil))


;;;; Origin-window discovery via Sway's focus stack

(defun jb/roam--sway-tree ()
  (json-parse-string (shell-command-to-string "swaymsg -t get_tree -r")
                     :object-type 'alist :array-type 'list
                     :null-object nil :false-object nil))

(defun jb/roam--node-children (node)
  (append (alist-get 'nodes node) (alist-get 'floating_nodes node)))

(defun jb/roam--window-p (node)
  "Non-nil if NODE is a real window (a leaf with a surface)."
  (and (null (jb/roam--node-children node))
       (or (alist-get 'app_id node)
           (alist-get 'window_properties node)
           (alist-get 'pid node))))

(defun jb/roam--emacs-p (node)
  "Non-nil if NODE is an Emacs window (Wayland app_id or XWayland class)."
  (let ((app   (alist-get 'app_id node))
        (class (alist-get 'class (alist-get 'window_properties node))))
    (or (member app jb/roam-self-app-ids)
        (member class jb/roam-self-app-ids))))

(defun jb/roam--leaves-by-recency (node)
  "Leaf windows under NODE, most-recently-focused first."
  (if (jb/roam--window-p node)
      (list node)
    (let* ((children (jb/roam--node-children node))
           (by-id    (mapcar (lambda (c) (cons (alist-get 'id c) c)) children))
           (order    (alist-get 'focus node))
           (ordered  (append
                      (delq nil (mapcar (lambda (id) (alist-get id by-id)) order))
                      (seq-remove (lambda (c) (memq (alist-get 'id c) order))
                                  children))))
      (apply #'append (mapcar #'jb/roam--leaves-by-recency ordered)))))

(defun jb/roam--origin-conid ()
  "con_id (string) of the most recently focused non-Emacs window."
  (let* ((leaves (jb/roam--leaves-by-recency (jb/roam--sway-tree)))
         (target (seq-find (lambda (n) (not (jb/roam--emacs-p n))) leaves)))
    (when target (number-to-string (alist-get 'id target)))))


;;;; Capture body extraction

(defun jb/roam--stash-body ()
  "Grab the body of the entry being captured — the one point is in.
Anchoring on point rather than `point-min' matters: today's daily file
usually already holds earlier entries, and scanning from the top grabs the
FIRST heading's body. Bounding by the subtree end stops us swallowing
later entries."
  (when jb/roam--armed
    (setq jb/roam--stashed
          (save-excursion
            (condition-case nil
                (progn
                  (org-back-to-heading t)
                  (let ((end (save-excursion (org-end-of-subtree t t) (point))))
                    (forward-line 1)
                    (org-end-of-meta-data t)
                    (string-trim
                     (buffer-substring-no-properties (min (point) end) end))))
              (error
               (string-trim
                (buffer-substring-no-properties (point-min) (point-max)))))))))


;;;; Injection

(defun jb/roam--inject ()
  "Dispatch injection after capture finalize, unless aborted or empty."
  (jb/roam--remove-hooks)
  (cond
   ((not jb/roam--armed)
    (jb/roam--reset-state))
   ((bound-and-true-p org-note-abort)
    (message "roam-everywhere: aborted, nothing injected")
    (jb/roam--reset-state))
   ((or (null jb/roam--stashed) (string-empty-p jb/roam--stashed))
    (message "roam-everywhere: empty capture, nothing injected")
    (jb/roam--reset-state))
   (t
    (message "roam-everywhere: %d chars → con_id %s (%s)"
             (length jb/roam--stashed)
             (or jb/roam--return-conid "none")
             jb/roam-injection-method)
    ;; Thread text and conid through as timer args — no shared mutable
    ;; state across the async boundary, so a second capture started in
    ;; the interval cannot corrupt this one.
    (let ((conid jb/roam--return-conid)
          (text  jb/roam--stashed))
      (jb/roam--reset-state)
      (run-with-timer jb/roam-paste-delay nil
                      #'jb/roam--refocus-and-inject conid text)))))

(defun jb/roam--refocus-and-inject (conid text)
  "Refocus window CONID, then inject TEXT per `jb/roam-injection-method'."
  (if (not conid)
      (message "roam-everywhere: no origin window found")
    (call-process "swaymsg" nil nil nil (format "[con_id=%s] focus" conid))
    (sleep-for 0.03)
    (pcase jb/roam-injection-method
      ('type  (jb/roam--type-text text))
      (_      (jb/roam--paste-text text)))))

(defun jb/roam--paste-text (text)
  "Set the clipboard to TEXT synchronously, then send Ctrl+V.
Setting it here — after refocus, immediately before the keystroke — is
deliberate: an earlier async `wl-copy' loses the race to XWayland's
mirrored X11 selection, which is why Thunderbird and URL bars pasted
stale content. `select-enable-clipboard' is bound off so Emacs's own
kill-ring sync cannot overwrite us mid-flight."
  (let ((select-enable-clipboard nil))
    (with-temp-buffer
      (insert text)
      ;; Blocks until wl-copy has taken selection ownership.
      (call-process-region (point-min) (point-max) "wl-copy" nil nil nil))
    (sleep-for jb/roam-clipboard-settle)
    (call-process "wtype" nil nil nil "-M" "ctrl" "v" "-m" "ctrl")))

(defun jb/roam--type-text (text)
  "Type TEXT via wtype, no clipboard involved.
Newlines are sent as Shift+Return so chat apps insert a line break
instead of sending the message."
  (let ((lines (split-string text "\n")))
    (cl-loop for line in lines
             for first = t then nil
             do (unless first
                  (call-process "wtype" nil nil nil
                                "-M" "shift" "-k" "Return" "-m" "shift"))
             do (unless (string-empty-p line)
                  (call-process "wtype" nil nil nil line)))))

(defun jb/roam--remove-hooks ()
  (remove-hook 'org-capture-prepare-finalize-hook #'jb/roam--stash-body)
  (remove-hook 'org-capture-after-finalize-hook #'jb/roam--inject))

(provide 'roam-everywhere)
;;; roam-everywhere.el ends here
