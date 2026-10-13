;;; hyperbole-config.el --- Description -*- lexical-binding: t; -*-

(use-package hyperbole
  :ensure t
  :custom
  (hsys-org-enable-smart-keys 'nil)
  :config
  (add-to-list 'auto-mode-alist '("/\\.hyperb/HYPB\\'" . org-mode))
  (hyperbole-mode 1))

(provide 'hyperbole-config)
