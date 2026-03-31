;;; meow-keys.el --- Keybindings -*- lexical-binding: t; -*-

;; Leader map — bound to SPC in meow-setup.el via meow-normal/motion-define-key
(defvar my-leader-map (make-sparse-keymap) "Primary leader keymap.")

;; Window bindings
(define-key my-leader-map (kbd "w v") #'split-window-right)
(define-key my-leader-map (kbd "w s") #'split-window-below)
(define-key my-leader-map (kbd "w d") #'delete-window)

;; Buffer
(define-key my-leader-map (kbd "b k") (lambda () (interactive) (kill-buffer (current-buffer))))
(define-key my-leader-map (kbd "b l") #'my/switch-to-last-buffer)
(define-key my-leader-map (kbd "b b") #'switch-to-buffer)
(define-key my-leader-map (kbd "b n") #'next-buffer)
(define-key my-leader-map (kbd "b i") #'ibuffer)

;; Files and buffers
(define-key my-leader-map (kbd ".") #'find-file)
(define-key my-leader-map (kbd ",") #'consult-buffer)
(define-key my-leader-map (kbd "/") #'consult-ripgrep)
(define-key my-leader-map (kbd "f r") #'consult-recent-file)

;; Project
(define-key my-leader-map (kbd "SPC") #'project-find-file)
(define-key my-leader-map (kbd "p R") #'project-query-replace-regexp)

;; Search
(define-key my-leader-map (kbd "s o") #'universal-launcher--web-search)

;; Paste into minibuffer
(define-key minibuffer-local-map (kbd "C-S-v") #'yank)

;; Kill word backwards in minibuffer
(dolist (map (list minibuffer-local-map
                   minibuffer-local-ns-map
                   minibuffer-local-completion-map
                   minibuffer-local-must-match-map
                   minibuffer-local-isearch-map))
  (define-key map (kbd "C-w") #'backward-kill-word))

;; Window movement
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

;; Bookmarks
(define-key my-leader-map (kbd "b m") #'bookmark-set)
(define-key my-leader-map (kbd "b P") #'bookmark-save)
(define-key my-leader-map (kbd "b D") #'bookmark-delete)
(define-key my-leader-map (kbd "RET") #'bookmark-jump)
(define-key my-leader-map (kbd "o b") #'browse-url-of-file)
(define-key my-leader-map (kbd "x")   #'org-capture)

;; Save
(global-set-key (kbd "C-s") #'save-buffer)
(global-set-key (kbd "C-r") #'undo-redo)

;; Clipboard yank in insert state
(with-eval-after-load 'meow
  (define-key meow-insert-state-keymap (kbd "C-v") #'clipboard-yank))

;; Save all buffers
(defun my/save-all-buffers ()
  "Save all modified buffers without prompting."
  (interactive)
  (save-some-buffers t))
(define-key my-leader-map (kbd "b S") #'my/save-all-buffers)

(defun my/switch-to-last-buffer ()
  "Switch to the most recently visited buffer."
  (interactive)
  (switch-to-buffer (other-buffer (current-buffer) 1)))

;; Tabs
(global-set-key (kbd "C-<tab>")   #'tab-next)
(global-set-key (kbd "C-S-<tab>") #'tab-previous)

;; Eval region
(global-set-key (kbd "C-x C-r") #'eval-region)

;; Programs
(define-key my-leader-map (kbd "o T") #'vterm-here)
(define-key my-leader-map (kbd "o d") #'dirvish)
(define-key my-leader-map (kbd "e r") #'my/erc-connect)
(define-key my-leader-map (kbd "e w") #'eww)
(define-key my-leader-map (kbd "e e") #'elfeed)
(define-key my-leader-map (kbd "e u") #'elfeed-update)
(define-key my-leader-map (kbd "e v") #'elfeed-tube-mpv)
(define-key my-leader-map (kbd "e g") #'gptel)
(define-key my-leader-map (kbd "e s") #'gptel-send)

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

(define-key my-leader-map (kbd "f y") #'my/yank-buffer-path)

(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "Y") #'my/yank-buffer-path))

;; Reload config
(defun my/reload-config ()
  (interactive)
  (load-file user-init-file)
  (message "Config reloaded."))
(global-set-key (kbd "C-c r") #'my/reload-config)

;; Config and snippets hotkeys
(define-key my-leader-map (kbd "f p")
            (lambda () (interactive)
              (let ((default-directory "~/nixos-config/dotfiles/emacs/"))
                (call-interactively #'find-file))))

(define-key my-leader-map (kbd "f s")
            (lambda () (interactive)
              (let ((default-directory "~/nixos-config/dotfiles/emacs/snippets/"))
                (call-interactively #'find-file))))

(provide 'meow-keys)
;;; keys.el ends here
