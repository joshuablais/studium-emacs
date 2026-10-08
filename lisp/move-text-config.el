;;; move-text-config.el -*- lexical-binding: t; -*-

(use-package move-text
  :ensure t
  :defer t)

;; Movement
(global-set-key (kbd "M-<down>")  #'move-text-down)
(global-set-key (kbd "M-<up>")    #'move-text-up)

(provide 'move-text-config)
