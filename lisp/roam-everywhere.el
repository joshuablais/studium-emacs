;;; roam-everywhere.el --- Capture anywhere, paste back into the app -*- lexical-binding: t; -*-

;;; Commentary:
;; Trigger from ANY app's text field, write in a real org-roam daily capture
;; (full Meow/flash/org/flyspell — it's a genuine Emacs buffer), finalize with
;; C-c C-c, and the body is pasted back into the window you came from.
;;
;; The origin window is recovered AFTER the fact by walking Sway's focus
;; stack: every container node carries a `focus' array listing children
;; most-recently-focused first. We take the most recent leaf that isn't
;; Emacs. This is necessary because emacs-launcher focuses Emacs before
;; the elisp runs, so "currently focused" is already Emacs by then.
;;
;; Targeting is by con_id, which every Sway node has — so this works
;; identically for Wayland-native apps (app_id) and XWayland apps
;; (window_properties.class): Thunderbird, Signal, Discord, Telegram,
;; Firefox, terminals, anything.
;;
;; Sway keybind (unchanged, no snapshot needed):
;;   bindsym $mod+Ctrl+e exec $launcher '(jb/roam-capture-everywhere)'

;;; Code:

(require 'org-capture)
(require 'seq)

(defvar jb/roam-paste-delay 0.15
  "Seconds after finalize before refocusing the origin window and pasting.
Too short: paste fires before focus lands. Too long: sluggish. Tune it.")

(defvar jb/roam-self-app-ids '("emacs" "Emacs")
  "app_id / class values identifying Emacs itself, skipped when
determining the origin window.")

(defvar jb/roam--capture-frame nil)
(defvar jb/roam--return-conid nil)
(defvar jb/roam--stashed nil)

;;;###autoload
(defun jb/roam-capture-everywhere ()
  "Org-roam daily capture from anywhere; on finalize, paste the body
into the window that was focused when the capture was triggered."
  (interactive)
  (require 'org-roam)          ; pulls in dailies via org-roam's own setup
  (setq jb/roam--capture-frame (selected-frame)
        jb/roam--return-conid (jb/roam--origin-conid))
  (add-hook 'org-capture-prepare-finalize-hook #'jb/roam--stash-body)
  (add-hook 'org-capture-after-finalize-hook #'jb/roam--inject-and-cleanup)
  (condition-case err
      (org-roam-dailies-capture-today)
    (error
     (jb/roam--remove-hooks)
     (signal (car err) (cdr err)))))


;;;; Origin-window discovery via Sway's focus stack

(defun jb/roam--sway-tree ()
  "Return the Sway tree as an alist."
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
  "Leaf windows under NODE, most-recently-focused first.
Sway's per-node `focus' array is a recency-ordered list of child ids."
  (if (jb/roam--window-p node)
      (list node)
    (let* ((children (jb/roam--node-children node))
           (by-id    (mapcar (lambda (c) (cons (alist-get 'id c) c)) children))
           (order    (alist-get 'focus node))
           (ordered  (append
                      ;; children in focus order first ...
                      (delq nil (mapcar (lambda (id) (alist-get id by-id)) order))
                      ;; ... then any not listed in `focus'
                      (seq-remove (lambda (c) (memq (alist-get 'id c) order))
                                  children))))
      (apply #'append (mapcar #'jb/roam--leaves-by-recency ordered)))))

(defun jb/roam--origin-conid ()
  "con_id (string) of the most recently focused non-Emacs window.
Never matches on a specific app, so it works for every program."
  (let* ((leaves (jb/roam--leaves-by-recency (jb/roam--sway-tree)))
         (target (seq-find (lambda (n) (not (jb/roam--emacs-p n))) leaves)))
    (when target (number-to-string (alist-get 'id target)))))


;;;; Capture body extraction

(defun jb/roam--stash-body ()
  "Grab the body under the capture heading, excluding the heading line
and any metadata drawer. Tuned for a `* HH:MM: %?' daily template."
  (setq jb/roam--stashed
        (save-excursion
          (goto-char (point-min))
          (if (re-search-forward "^\\*+ .*$" nil t)
              (progn
                (forward-line 1)
                (org-end-of-meta-data t)
                (string-trim
                 (buffer-substring-no-properties (point) (point-max))))
            (string-trim
             (buffer-substring-no-properties (point-min) (point-max)))))))


;;;; Injection

(defun jb/roam--inject-and-cleanup ()
  "Copy the stashed body to the Wayland clipboard, then refocus and paste."
  (jb/roam--remove-hooks)
  (message "roam-everywhere: stashed %d chars → con_id %s"
           (length (or jb/roam--stashed ""))
           (or jb/roam--return-conid "none"))
  (when (and jb/roam--stashed (> (length jb/roam--stashed) 0))
    (let ((proc (make-process
                 :name "wl-copy" :command '("wl-copy")
                 :connection-type 'pipe :noquery t)))
      (process-send-string proc jb/roam--stashed)
      (process-send-eof proc))
    ;; Don't delete the frame (it may be the only one). Refocusing the
    ;; origin window is what moves focus off Emacs.
    (run-with-timer jb/roam-paste-delay nil #'jb/roam--refocus-and-paste))
  (setq jb/roam--stashed nil))

(defun jb/roam--refocus-and-paste ()
  "Refocus the origin window by con_id and paste. App-agnostic."
  (if jb/roam--return-conid
      (progn
        (call-process "swaymsg" nil nil nil
                      (format "[con_id=%s] focus" jb/roam--return-conid))
        (sleep-for 0.05)
        (call-process "wtype" nil nil nil "-M" "ctrl" "v" "-m" "ctrl"))
    (message "roam-everywhere: no origin window found"))
  (setq jb/roam--return-conid nil))

(defun jb/roam--remove-hooks ()
  (remove-hook 'org-capture-prepare-finalize-hook #'jb/roam--stash-body)
  (remove-hook 'org-capture-after-finalize-hook #'jb/roam--inject-and-cleanup))

(provide 'roam-everywhere)
;;; roam-everywhere.el ends here
