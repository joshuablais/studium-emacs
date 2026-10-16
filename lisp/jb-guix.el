;;; jb-guix.el -*- lexical-binding: t; -*-

(use-package geiser
  :ensure nil
  :init
  (setq geiser-active-implementations '(guile)
        geiser-mode-start-repl-p t))

(use-package geiser-guile
  :ensure nil
  :init
  (setq geiser-guile-binary (or (executable-find "guile")
                                (expand-file-name "~/.guix-profile/bin/guile"))
        geiser-guile-case-sensitive-p t))

(use-package guix
  :ensure nil
  :commands (guix guix-installed-user-packages guix-packages-by-name))

(provide 'jb-guix)
