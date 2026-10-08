;;; meow-setup.el --- Description -*- lexical-binding: t; -*-

;; define keys
(setq meow-keypad-ctrl-meta-prefix ?G)
(setq meow-keypad-meta-prefix ?M)

(defun meow-setup ()
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-colemak-dh)

  (meow-leader-define-key
   ;; Org
   '("C" . org-capture)
   '("n r i" . org-roam-capture)
   '("n r f" . org-roam-node-find)
   '("n j" . org-roam-dailies-capture-today)

   ;; Miscellaneous
   '("!" . jb/run-command)
   '("o t" . jb/ghostel)
   '("o T" . jb/ghostel-here)
   '("o C" . jb/checks)
   '("o D" . jb/download-media)
   '("s T" . powerthesaurus-lookup-synonyms-dwim)
   '("s t" . dictionary-search)
   '("t z" . my/zen-mode)
   '("o m" . mu4e)
   '("y m" . mu4e-org-mode)
   '("o d" . dirvish)
   '("e r" . my/erc-connect)
   '("e w" . eww)
   '("e l" . elpher)
   '("e e" . elfeed)
   '("e u" . elfeed-update)
   '("e v" . elfeed-tube-mpv)
   '("s o" . universal-launcher--web-search)
   '("s l" . link-hint-open-link)
   '("B" . my/scratch-popup)

   ;; Workspaces
   '("<TAB> s" . easysession-save)
   '("<TAB> l" . easysession-switch-to)
   '("<TAB> R" . easysession-rename)
   '("<TAB> D" . easysession-delete)
   '("<TAB> n" . +workspace/new)
   '("<TAB> d" . +workspace/delete)
   '("<TAB> r" . +workspace/rename)
   '("<TAB> <TAB>" . +workspace/switch-to)
   '("p p" . +workspace/switch-to-project)

   ;; Testing
   '("m t a" . my/test-all)
   '("m t f" . my/test-file)
   '("m t t" . my/test-at-point)
   '("m t s" . my/test-single)
   '("m t r" . my/test-rerun)
   '("m t b" . my/bench-all)
   '("m t p" . my/bench-at-point)

   ;; Emms
   '("m u" . my/update-emms-from-mpd)
   '("m d" . emms-play-directory-tree)
   '("m p" . emms-playlist-mode-go)
   '("m h" . emms-shuffle)
   '("m o" . emms-browser)

   '("f p" . (lambda () (interactive)
               (let ((default-directory "~/.config/guix/dotfiles/emacs/"))
                 (call-interactively #'find-file))))
   '("f s" . (lambda () (interactive)
               (let ((default-directory "~/.config/guix/dotfiles/emacs/snippets/"))
                 (call-interactively #'find-file)))))

  (meow-motion-define-key
   '("f" . flash-jump)
   ;; '("/" . consult-line)
   '("<escape>" . ignore))

  (meow-normal-define-key
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("f" . flash-jump)
   '("i" . meow-insert)
   '("l" . meow-line)
   '("L" . (lambda () (interactive) (meow-line 1) (meow-reverse)))
   '("m" . meow-mark-word)
   '("M" . meow-mark-symbol)
   '("N" . meow-next-expand)
   '("@" . kmacro-end-or-call-macro)
   '("z o" . kirigami-open-fold)
   '("z O" . kirigami-open-fold-rec)
   '("z c" . kirigami-close-fold)
   '("z a" . kirigami-toggle-fold)
   '("z r" . kirigami-open-folds)
   '("z m" . kirigami-close-folds)
   '(">" . my/indent-right)
   '("<" . my/indent-left)
   '("'" . repeat)
   '("<escape>" . ignore))

  (setq meow-mode-state-list
        '((dired-mode . motion)
          (elfeed-search-mode . motion)
          (org-mode . normal)
          (elfeed-show-mode . motion)
          (erc-mode . insert)
          (vterm-mode . insert)
          (ghostel-mode . insert)
          (pdf-view-mode . motion)
          (calibredb-search-mode . motion)
          (dirvish-mode . motion)
          (messages-buffer-mode . motion)
          (help-mode . motion)
          (info-mode . motion)
          (occur-mode . motion)
          (pass-mode . motion)
          (grep-mode . motion)
          (compilation-mode . motion)
          (messages-buffer-mode . motion)
          (special-mode . motion))))

(use-package meow
  :demand t
  :config
  (meow-setup)
  (meow-global-mode 1)
  (meow-thing-register 'angle
                       '(regexp "<" ">")
                       '(regexp "<" ">"))
  (meow-thing-register 'double-quote
                       '(regexp "\"" "\"")
                       '(regexp "\"" "\""))
  (meow-thing-register 'single-quote
                       '(regexp "'" "'")
                       '(regexp "'" "'"))
  (meow-thing-register 'backtick
                       '(regexp "`" "`")
                       '(regexp "`" "`"))
  (setq meow-char-thing-table
        '((?\( . round)
          (?\[ . square)
          (?\{ . curly)
          (?\< . angle)
          (?\" . double-quote)
          (?\' . single-quote)
          (?\` . backtick)
          (?e . symbol)
          (?w . window)
          (?b . buffer)
          (?p . paragraph)
          (?l . line)
          (?d . defun))))

;; Tab behaviour
(setq tab-always-indent 'complete)
(setq-default indent-tabs-mode nil)
(setq-default tab-width 4)

(defun my/indent-right ()
  "Indent region or line right."
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) tab-width)
    (indent-rigidly (line-beginning-position) (line-end-position) tab-width)))

(defun my/indent-left ()
  "Indent region or line left."
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) (- tab-width))
    (indent-rigidly (line-beginning-position) (line-end-position) (- tab-width))))

(keymap-global-set "C-b"   #'switch-to-buffer)
(keymap-global-set "C-x C-r" #'eval-region)
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


;; File path yanking
(defun my/yank-buffer-path (&optional root)
  "Copy current buffer's file path to kill ring."
  (interactive)
  (let ((filename (or (and (ignerived-mode-p 'dired-mode)
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

(provide 'meow-setup)
;;; meow-setup.el ends here
