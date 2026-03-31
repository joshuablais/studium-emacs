;;; persist.el -*- lexical-binding: t; -*-

(use-package easysession
  :ensure t
  :custom
  (easysession-save-interval (* 10 60))
  :config
  (easysession-setup))

(define-key my-leader-map (kbd "<TAB> s") #'easysession-save)
(define-key my-leader-map (kbd "<TAB> l") #'easysession-switch-to)
(define-key my-leader-map (kbd "<TAB> R") #'easysession-rename)
(define-key my-leader-map (kbd "<TAB> D") #'easysession-delete)

(provide 'persist)
