;;; meow-setup.el --- Description -*- lexical-binding: t; -*-

;; Setup if there are any leader keys breaking
;; (defvar my-leader-map (make-sparse-keymap) "Primary leader keymap.")

(defun meow-setup ()
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-colemak-dh)

  (meow-leader-define-key
   '("?" . meow-cheatsheet)

   ;; Files and Consult
   '("." . find-file)
   '("/" . consult-ripgrep)
   '("f r" . consult-recent-file)
   '("f y" . my/yank-buffer-path)

   ;; Projects
   '("SPC" . project-find-file)
   '("p R" . project-query-replace-regexp)

   ;; Window bindings
   '("w v" . split-window-right)
   '("w s" . split-window-below)
   '("w d" . delete-window)

   ;; Buffer
   '("," . consult-buffer)
   '("b k" . (lambda () (interactive) (kill-buffer (current-buffer))))
   '("b l" . (lambda () (interactive) (switch-to-buffer nil)))
   '("b b" . switch-to-buffer)
   '("b n" . next-buffer)
   '("b i" . ibuffer)
   '("b S" . my/save-all-buffers)

   ;; Bookmarks
   '("b m" . bookmark-set)
   '("b P" . bookmark-save)
   '("b D" . bookmark-delete)
   '("RET" . bookmark-jump)
   '("o b" . browse-url-of-file)

   ;; Org
   '("X" . org-capture)

   ;; Magit
   '("G" . (lambda () (interactive) (require 'magit) (magit-status)))

   ;; Miscellaneous
   '("!" . jb/run-command)
   '("o t" . my/vterm)
   '("s T" . powerthesaurus-lookup-synonyms-dwim)
   '("s t" . dictionary-search)
   '("t z" . my/zen-mode)
   '("o m" . mu4e)
   '("y m" . mu4e-org-mode)
   '("o d" . dirvish)
   '("e r" . my/erc-connect)
   '("e w" . eww)
   '("e e" . elfeed)
   '("e u" . elfeed-update)
   '("e v" . elfeed-tube-mpv)
   '("e g" . gptel)
   '("e s" . gptel-send)
   '("s o" . universal-launcher--web-search)
   '("s l" . link-hint-open-link)
   '("B" . my/scratch-popup)
   '("j c" . my/jitsi-create-room)
   '("y y" . jb/clipboard-manager)

   ;; Workspaces
   '("<TAB> s" . easysession-save)
   '("<TAB> l" . easysession-switch-to)
   '("<TAB> R" . easysession-rename)
   '("<TAB> D" . easysession-rename)
   '("<TAB> <TAB>" . +workspace/display)
   '("<TAB> n" . +workspace/new)
   '("<TAB> d" . +workspace/delete)
   '("<TAB> r" . +workspace/rename)
   '("<TAB> ." . +workspace/switch-to)
   '("<TAB> [" . tab-bar-switch-to-prev-tab)
   '("<TAB> ]" . tab-bar-switch-to-next-tab)
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
   '("m x" . emms-pause)
   '("m s" . emms-stop)
   '("m b" . emms-previous)
   '("m n" . emms-next)
   '("m o" . emms-browser)

   ;; meow digits
   '("1" . meow-digit-argument)
   '("2" . meow-digit-argument)
   '("3" . meow-digit-argument)
   '("4" . meow-digit-argument)
   '("5" . meow-digit-argument)
   '("6" . meow-digit-argument)
   '("7" . meow-digit-argument)
   '("8" . meow-digit-argument)
   '("9" . meow-digit-argument)
   '("0" . meow-digit-argument)
   '("f p" . (lambda () (interactive)
               (let ((default-directory "~/nixos-config/dotfiles/emacs/"))
                 (call-interactively #'find-file))))
   '("f s" . (lambda () (interactive)
               (let ((default-directory "~/nixos-config/dotfiles/emacs/snippets/"))
                 (call-interactively #'find-file)))))

  (meow-motion-define-key
   ;; Navigation
   '("e" . meow-prev)
   '("n" . meow-next)
   '("h" . meow-left)
   '("i" . meow-right-expand)
   '("w" . meow-next-word)
   '("W" . meow-next-symbol)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("L" . meow-goto-line)
   '("^" . back-to-indentation)
   ;; Selection
   '("l" . meow-line)
   '("m" . meow-mark-word)
   '("M" . meow-mark-symbol)
   '("v" . meow-search)
   '("V" . meow-visit)
   '("%" . meow-block)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   ;; Yank
   '("y" . meow-clipboard-save)
   '("g" . meow-cancel-selection)
   ;; Jump
   '("f" . flash-jump)
   '("/" . consult-line)
   '("<escape>" . ignore))

  (meow-normal-define-key
   '("0" . meow-expand-0)
   '("1" . meow-expand-1)
   '("2" . meow-expand-2)
   '("3" . meow-expand-3)
   '("4" . meow-expand-4)
   '("5" . meow-expand-5)
   '("6" . meow-expand-6)
   '("7" . meow-expand-7)
   '("8" . meow-expand-8)
   '("9" . meow-expand-9)
   '("-" . negative-argument)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("/" . consult-line)
   '("*" . meow-visit)
   '("%" . meow-block)
   '("^" . back-to-indentation)
   '("a" . meow-append)
   '("A" . (lambda () (interactive) (end-of-line) (meow-insert)))
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("c" . meow-change)
   '("C" . (lambda () (interactive) (meow-kill) (meow-insert)))
   '("d" . meow-clipboard-kill)
   '("D" . meow-kill)
   '("e" . meow-prev)
   '("E" . meow-prev-expand)
   '("f" . flash-jump)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("i" . meow-insert)
   '("I" . (lambda () (interactive) (beginning-of-line) (meow-insert)))
   '("j" . meow-join)
   '("l" . meow-line)
   '("L" . meow-goto-line)
   '("m" . meow-mark-word)
   '("M" . meow-mark-symbol)
   '("n" . meow-next)
   '("N" . meow-next-expand)
   '("o" . meow-open-below)
   '("O" . meow-open-above)
   '("p" . my/meow-paste)
   '("C-v" . my/meow-paste)
   '("q" . meow-quit)
   '("r" . meow-replace)
   '("s" . meow-change-char)
   '("S" . meow-pop-selection)
   '("t" . meow-till)
   '("u" . undo-tree-undo)
   '("U" . meow-undo-in-selection)
   '("v" . meow-search)
   '("V" . meow-visit)
   '("w" . meow-next-word)
   '("W" . meow-next-symbol)
   '("x" . meow-delete)
   '("X" . meow-backward-delete)
   '("y" . meow-clipboard-save)
   '("z o" . kirigami-open-fold)
   '("z O" . kirigami-open-fold-rec)
   '("z c" . kirigami-close-fold)
   '("z a" . kirigami-toggle-fold)
   '("z r" . kirigami-open-folds)
   '("z m" . kirigami-close-folds)
   '(">" . my/indent-right)
   '("<" . my/indent-left)
   '("'" . repeat)
   '("<tab>" . my/smart-tab)
   '("TAB" . my/smart-tab)
   '("<escape>" . ignore))

  (setq meow-mode-state-list
        '((dired-mode . motion)
          (elfeed-search-mode . motion)
          (elfeed-show-mode . motion)
          (erc-mode . motion)
          (pdf-view-mode . motion)
          (calibredb-search-mode . motion)
          (dirvish-mode . motion)
          (messages-buffer-mode . motion)
          (help-mode . motion)
          (info-mode . motion)
          (occur-mode . motion)
          (grep-mode . motion)
          (compilation-mode . motion)
          (messages-buffer-mode . motion)
          (special-mode . motion))))

(use-package meow
  :demand t
  :config
  (meow-setup)
  (meow-global-mode 1))

(defun my/smart-tab ()
  "Smart tab: org-cycle, corfu, region indent, or indent to mode."
  (interactive)
  (cond
   ((derived-mode-p 'org-mode) (org-cycle))
   ((and (derived-mode-p 'magit-mode)
         (fboundp 'magit-section-toggle))
    (call-interactively #'magit-section-toggle))
   ((and (derived-mode-p 'dired-mode)
         (fboundp 'dirvish-subtree-toggle))
    (dirvish-subtree-toggle))
   ((and (bound-and-true-p corfu-mode)
         (frame-live-p (bound-and-true-p corfu--frame)))
    (corfu-next))
   ((use-region-p) (indent-region (region-beginning) (region-end)))
   (t (indent-according-to-mode))))

(global-set-key (kbd "TAB") #'my/smart-tab)
(global-set-key (kbd "<tab>") #'my/smart-tab)

(defun my/meow-paste ()
  "Replace selection if active with system clipboard, otherwise paste."
  (interactive)
  (if (use-region-p)
      (progn
        (delete-region (region-beginning) (region-end))
        (clipboard-yank))
    (clipboard-yank)))

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

;;Save all buffers
(defun my/save-all-buffers ()
  "Save all modified buffers without prompting."
  (interactive)
  (save-some-buffers t))

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

;; Tabs
(global-set-key (kbd "C-<tab>")   #'tab-next)
(global-set-key (kbd "C-S-<tab>") #'tab-previous)

;; Eval region
(global-set-key (kbd "C-x C-r") #'eval-region)

;; Window movement
(global-set-key (kbd "C-w") #'backward-kill-word)
(global-set-key (kbd "C-<left>")  #'windmove-left)
(global-set-key (kbd "C-<right>") #'windmove-right)
(global-set-key (kbd "C-<down>")  #'windmove-down)
(global-set-key (kbd "C-<up>")    #'windmove-up)

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

;; Zoom
(global-set-key (kbd "C-=") #'text-scale-increase)
(global-set-key (kbd "C--") #'text-scale-decrease)

;; Save
(global-set-key (kbd "C-v") #'clipboard-yank)
(define-key minibuffer-local-map (kbd "C-v") #'yank)
(global-set-key (kbd "C-s") #'save-buffer)
(global-set-key (kbd "C-r") #'undo-tree-redo)

;; Reload config
(defun my/reload-config ()
  (interactive)
  (load-file user-init-file)
  (message "Config reloaded."))
(global-set-key (kbd "C-c r") #'my/reload-config)

(provide 'meow-setup)
;;; meow-setup.el ends here
