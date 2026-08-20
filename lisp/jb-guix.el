;;; jb-guix.el -*- lexical-binding: t; -*-
(use-package geiser
  :ensure nil
  :demand t)

(use-package geiser-guile
  :ensure nil
  :demand t
  :config
  (setq geiser-guile-binary (or (executable-find "guile")
                                "/home/joshua/.guix-profile/bin/guile")
        geiser-guile-case-sensitive-p t
        geiser-active-implementations '(guile)))

(use-package guix
  :ensure nil
  :commands (guix guix-installed-user-packages guix-packages-by-name)
  :init
  (require 'guix nil t))

(provide 'jb-guix)
