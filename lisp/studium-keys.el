;;; studium-keys.el --- Description -*- lexical-binding: t; -*-
(keymap-global-set "C->" #'my/indent-right)
(keymap-global-set "C-<" #'my/indent-left)
(keymap-global-set "C-b" #'consult-buffer)
(keymap-global-set "C-x C-r" #'eval-region)
(keymap-global-set "C-x g" #'magit-status)
(keymap-global-set "C-c M" #'consult-register-store)
(keymap-global-set "C-c J" #'consult-register)
(keymap-global-set "C-<left>"  #'windmove-left)
(keymap-global-set "C-<right>" #'windmove-right)
(keymap-global-set "C-<down>"  #'windmove-down)
(keymap-global-set "C-<up>"    #'windmove-up)
(keymap-global-set "C-x k" #'kill-current-buffer)
(keymap-global-set "C--" #'text-scale-decrease)
(keymap-global-set "C-=" #'text-scale-increase)
(keymap-global-set "C-f" #'find-file)
;; Files and Consult
(keymap-global-set "C-c /" #'consult-ripgrep)
(keymap-global-set "C-c f r" #'consult-recent-file)
(keymap-global-set "C-c f y" #'my/yank-buffer-path)
;; Projects
(keymap-global-set "C-c SPC" #'project-find-file)
(keymap-global-set "C-c p R" #'project-query-replace-regexp)
;; Buffer
(keymap-global-set "C-c b S" #'my/save-all-buffers)
;; Bookmarks
(keymap-global-set "C-c b m" #'bookmark-set)
(keymap-global-set "C-c b P" #'bookmark-save)
(keymap-global-set "C-c b D" #'bookmark-delete)
(keymap-global-set "C-c RET" #'bookmark-jump)
(keymap-global-set "C-c o b" #'browse-url-of-file)
;; Org
(keymap-global-set "C-c c" #'org-capture)
(keymap-global-set "C-c n r i" #'org-roam-capture)
(keymap-global-set "C-c n r f" #'org-roam-node-find)
'("n j" . org-roam-dailies-capture-today)
;; Miscellaneous
(keymap-global-unset "C-t")
(keymap-global-set "C-t !" #'jb/run-command)
(keymap-global-set "C-t t" #'jb/ghostel)
(keymap-global-set "C-t T" #'jb/ghostel-here)
(keymap-global-set "C-t o C" #'jb/checks)
(keymap-global-set "C-t o D" #'jb/download-media)
;; Lookup
(keymap-global-set "C-c s T" #'powerthesaurus-lookup-synonyms-dwim)
(keymap-global-set "C-c s t" #'dictionary-search)
(keymap-global-set "C-c s o" #'universal-launcher--web-search)
(keymap-global-set "C-c s l" #'link-hint-open-link)
;; Open
(keymap-global-set "C-c o m" #'mu4e)
(keymap-global-set "C-c o d" #'dirvish)
(keymap-global-set "C-c y m" #'mu4e-org-mode)
;; Net
(keymap-global-set "C-c e r" #'my/erc-connect)
(keymap-global-set "C-c e w" #'eww)
(keymap-global-set "C-c e l" #'elpher)
(keymap-global-set "C-c e e" #'elfeed)
(keymap-global-set "C-c e u" #'elfeed-update)
(keymap-global-set "C-c e v" #'elfeed-tube-mpv)
;; Misc
(keymap-global-set "C-c t z" #'my/zen-mode)
(keymap-global-set "C-c B"   #'my/scratch-popup)
;; Workspaces
(keymap-global-set "C-c w n" #'+workspace/new)
(keymap-global-set "C-c w d" #'+workspace/delete)
(keymap-global-set "C-c w r" #'+workspace/rename)
(keymap-global-set "C-c w w" #'+workspace/switch-to)
(keymap-global-set "C-c p p" #'+workspace/switch-to-project)
;; Testing
(keymap-global-set "C-c m t a" #'my/test-all)
(keymap-global-set "C-c m t f" #'my/test-file)
(keymap-global-set "C-c m t t" #'my/test-at-point)
(keymap-global-set "C-c m t s" #'my/test-single)
(keymap-global-set "C-c m t r" #'my/test-rerun)
(keymap-global-set "C-c m t b" #'my/bench-all)
(keymap-global-set "C-c m t p" #'my/bench-at-point)
;; Emms
(keymap-global-set "C-c m u" #'my/update-emms-from-mpd)
(keymap-global-set "C-c m d" #'emms-play-directory-tree)
(keymap-global-set "C-c m p" #'emms-playlist-mode-go)
(keymap-global-set "C-c m h" #'emms-shuffle)
(keymap-global-set "C-c m o" #'emms-browser)
(keymap-global-set "C-'" #'repeat)

(defun studium/find-config ()
  "Find a file in the Emacs config."
  (interactive)
  (let ((default-directory "~/.config/guix/dotfiles/emacs/"))
    (call-interactively #'find-file)))

(defun studium/find-snippet ()
  "Find a file in the snippets directory."
  (interactive)
  (let ((default-directory "~/.config/guix/dotfiles/emacs/snippets/"))
    (call-interactively #'find-file)))

(keymap-global-set "C-c f p" #'studium/find-config)
(keymap-global-set "C-c f s" #'studium/find-snippet)

;; File path yanking
(defun my/yank-buffer-path (&optional root)
  "Copy current buffer's file path to kill ring."
  (interactive)
  (let ((filename (or (and (derived-mode-p 'dired-mode)
                           (dired-get-file-for-visit))
                      (buffer-file-name))))
    (if filename
        (let ((path (if root
                        (file-relative-name filename root)
                      (abbreviate-file-name filename))))
          (kill-new path)
          (message "Copied: %s" path))
      (message "Buffer is not visiting a file"))))

;; remove undo and use consult line
(with-eval-after-load 'undo-tree
  (keymap-unset undo-tree-map "C-/" t))
(keymap-global-set "C-/" #'consult-line)
(keymap-global-set "C-S-u" #'undo-only)
(keymap-global-set "C-S-r" #'undo-tree-redo)

;; Replace meow-inner/outer
(defconst studium--pairs '((?\( . ?\)) (?\[ . ?\]) (?\{ . ?\}) (?< . ?>)))

(defun studium--pair-bounds (open close)
  "Bounds of the nearest OPEN...CLOSE pair enclosing point, or nil."
  (save-excursion
    (let ((ppss (syntax-ppss)))
      (if (and (eq (char-syntax open) ?\() (not (nth 8 ppss)))
          ;; The mode parses this bracket: walk up its list structure.
          (let ((pos (nth 1 ppss)))
            (while (and pos (not (eq (char-after pos) open)))
              (setq pos (nth 1 (syntax-ppss pos))))
            (when-let* ((pos)
                        (end (ignore-errors (scan-sexps pos 1))))
              (cons pos end)))
        ;; It doesn't (prose, comments, angle brackets): count characters.
        (let ((re (regexp-opt (list (string open) (string close))))
              (origin (point)) (depth 0) beg end)
          (while (and (not beg) (re-search-backward re nil t))
            (cond ((not (eq (char-after) open)) (setq depth (1+ depth)))
                  ((zerop depth) (setq beg (point)))
                  (t (setq depth (1- depth)))))
          (goto-char origin)
          (setq depth 0)
          (while (and beg (not end) (re-search-forward re nil t))
            (cond ((not (eq (char-before) close)) (setq depth (1+ depth)))
                  ((zerop depth) (setq end (point)))
                  (t (setq depth (1- depth)))))
          (and beg end (cons beg end)))))))

(defun studium--quote-bounds (ch)
  "Bounds of the CH-quoted span enclosing point, or nil."
  (save-excursion
    (let ((ppss (syntax-ppss)) (origin (point)) (s (string ch)))
      (if (and (nth 3 ppss) (eq (char-after (nth 8 ppss)) ch))
          ;; A real string in this mode: the parser knows where it ends.
          (when-let* ((end (ignore-errors (scan-sexps (nth 8 ppss) 1))))
            (cons (nth 8 ppss) end))
        ;; Prose: an odd count of quotes before point on this line means inside.
        (when (and (/= 0 (% (how-many (regexp-quote s) (pos-bol) origin) 2))
                   (search-backward s (pos-bol) t))
          (let ((beg (point)))
            (goto-char origin)
            (when (search-forward s (pos-eol) t)
              (cons beg (point)))))))))

(defun studium--thing (ch)
  "Return (OUTER . INNER) for the thing keyed by CH; each is (BEG . END)."
  (let* ((ch (or (car (rassq ch studium--pairs)) ch))
         (closer (alist-get ch studium--pairs))
         (delimited (cond (closer (studium--pair-bounds ch closer))
                          ((memq ch '(?\" ?\' ?`)) (studium--quote-bounds ch)))))
    (cond
     (delimited
      (cons delimited (cons (1+ (car delimited)) (1- (cdr delimited)))))
     ((eq ch ?l)
      (cons (cons (pos-bol) (pos-bol 2)) (cons (pos-bol) (pos-eol))))
     (t
      (when-let* ((b (pcase ch
                       (?e (bounds-of-thing-at-point 'symbol))
                       (?p (bounds-of-thing-at-point 'paragraph))
                       (?d (bounds-of-thing-at-point 'defun))
                       (?w (cons (window-start) (window-end nil t)))
                       (?b (cons (point-min) (point-max))))))
        (cons b b))))))

(defun studium--mark-thing (prompt pick)
  (let ((thing (or (studium--thing
                    (read-char (concat prompt " ( [ { < \" ' ` e p d l w b: ")))
                   (user-error "No such thing around point"))))
    (goto-char (car (funcall pick thing)))
    (push-mark (cdr (funcall pick thing)) nil t)))

(defun studium/mark-inner ()
  "Select the inside of the thing named by the next key."
  (interactive)
  (studium--mark-thing "Inner of" #'cdr))

(defun studium/mark-bounds ()
  "Select the thing named by the next key, delimiters included."
  (interactive)
  (studium--mark-thing "Bounds of" #'car))

(keymap-global-set "M-i" #'studium/mark-inner)    ; was tab-to-tab-stop
(keymap-global-set "M-o" #'studium/mark-bounds)   ; unbound by default

;; Resizing windows
(global-set-key (kbd "S-<right>") (lambda () (interactive)
                                    (if (window-in-direction 'left)
                                        (shrink-window-horizontally 5)
                                      (enlarge-window-horizontally 5))))
(global-set-key (kbd "S-<left>")  (lambda () (interactive)
                                    (if (window-in-direction 'right)
                                        (shrink-window-horizontally 5)
                                      (enlarge-window-horizontally 5))))
(global-set-key (kbd "S-<up>")    (lambda () (interactive)
                                    (if (window-in-direction 'below)
                                        (shrink-window 2)
                                      (enlarge-window 2))))
(global-set-key (kbd "S-<down>")  (lambda () (interactive)
                                    (if (window-in-direction 'above)
                                        (shrink-window 2)
                                      (enlarge-window 2))))

(defvar-keymap studium-fold-map
  :repeat t
  "a" #'kirigami-toggle-fold
  "o" #'kirigami-open-fold   "O" #'kirigami-open-fold-rec
  "c" #'kirigami-close-fold
  "r" #'kirigami-open-folds  "m" #'kirigami-close-folds)
(keymap-global-set "C-z" (cons "fold" studium-fold-map))

;; Tab behaviour
(setq tab-always-indent 'complete)
(setq-default indent-tabs-mode nil)
(setq-default tab-width 4)

(defun studium--shift (cols)
  "Shift the current line or all lines touched by the region by COLS."
  (let ((beg (if (use-region-p)
                 (save-excursion (goto-char (region-beginning)) (pos-bol))
               (pos-bol)))
        (end (if (use-region-p) (region-end) (pos-eol)))
        (deactivate-mark nil))            ; keep the region for the next press
    (indent-rigidly beg end cols)))

(defun my/indent-right ()
  "Indent region or line right."
  (interactive)
  (studium--shift tab-width))

(defun my/indent-left ()
  "Indent region or line left."
  (interactive)
  (studium--shift (- tab-width)))

(defun my/save-all-buffers ()
  "Save all modified buffers without prompting."
  (interactive)
  (save-some-buffers t))

(provide 'studium-keys)
