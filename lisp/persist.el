;;; persist.el -*- lexical-binding: t; -*-

(use-package easysession
  :ensure t
  :custom
  (easysession-save-interval (* 10 60))
  :config
  (easysession-setup))

(provide 'persist)
