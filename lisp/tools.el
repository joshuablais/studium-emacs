;;; tools.el --- Description -*- lexical-binding: t; -*-

(use-package helpful
  :ensure t
  :bind
  ([remap describe-command]  . helpful-command)
  ([remap describe-function] . helpful-callable)
  ([remap describe-key]      . helpful-key)
  ([remap describe-symbol]   . helpful-symbol)
  ([remap describe-variable] . helpful-variable)
  :custom
  (helpful-max-buffers 7))

(use-package git-modes
  :ensure t
  :mode (("/\\.gitignore\\'" . gitignore-mode)
         ("/\\.gitconfig\\'" . gitconfig-mode)
         ("/\\.gitattributes\\'" . gitattributes-mode)))

(use-package server
  :ensure nil
  :hook (after-init . server-start))

;; show colors of kex codes
(use-package rainbow-mode
  :hook ((prog-mode . rainbow-mode)
         (emacs-lisp-mode . rainbow-mode)
         (org-mode . rainbow-mode)))

;; link hint search and jump
(use-package link-hint
  :ensure t)

(defun my/scratch-popup ()
  "Open scratch buffer as a bottom popup at 30% height."
  (interactive)
  (select-window
   (display-buffer
    (get-buffer-create "*scratch*")
    '((display-buffer-reuse-window
       display-buffer-in-side-window)
      (side . bottom)
      (slot . 0)
      (window-height . 0.3)
      (window-parameters . ((no-delete-other-windows . t)))))))

;; Messages buffer
(defun my/messages-popup ()
  "Open *Messages* buffer as a bottom popup and focus it."
  (interactive)
  (select-window
   (display-buffer
    (get-buffer-create "*Messages*")
    '((display-buffer-reuse-window
       display-buffer-in-side-window)
      (side . bottom)
      (slot . 1)
      (window-height . 0.3)
      (window-parameters . ((no-delete-other-windows . t))))))
  (local-set-key (kbd "q") #'quit-window)
  (goto-char (point-max)))

(global-set-key (kbd "C-h C-m") #'my/messages-popup)
(which-key-add-key-based-replacements "C-h C-m" "messages popup")

(defun jb/checks ()
  "Execute my bash script."
  (interactive)
  (shell-command "~/.config/scripts/Misc/checks"))

;; Password store helper script
(defun my/read-secret (entry)
  "Return the first line of pass ENTRY, or nil if unavailable."
  (require 'password-store)
  (ignore-errors
    (password-store-get entry)))

(defun jb/just (recipe)
  "Run a just RECIPE from the project root through `compile'."
  (interactive
   (let* ((root (project-root (project-current t)))
          (default-directory root)
          (recipes (ignore-errors
                     (process-lines "just" "--summary"))))
     ;; --summary returns one space-separated line; split it.
     (setq recipes (and recipes
                        (split-string (car recipes) "[ \n]+" t)))
     (unless recipes
       (user-error "No just recipes found in %s" root))
     (list (completing-read "just: " recipes nil t))))
  (let ((default-directory (project-root (project-current t))))
    (compile (format "just %s" recipe))))

(provide 'tools)
