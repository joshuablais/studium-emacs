;;; flash-config.el --- Labelled jumps -*- lexical-binding: t; -*-

;; Avy remains: link-hint renders its hints through it.
(use-package avy
  :ensure t
  :custom
  (avy-keys '(?a ?r ?s ?t ?n ?e ?i ?o))   ; Colemak-DH home row
  (avy-style 'at-full)
  (avy-all-windows t))

(use-package flash
  :ensure t
  :demand t
  :custom
  ;; Colemak-DH: home row, inner index, top row, bottom row.
  (flash-labels "arstneiogmwfpluycdhxzbvkjq")
  (flash-multi-window t)
  (flash-backdrop t)
  (flash-autojump t)
  (flash-rainbow nil)
  (flash-jumplist t)                ; push mark before jumping
  (flash-min-pattern-length 2)      ; no labels on the first char
  :bind*
  ("C-j" . flash-jump)
  :config
  (require 'flash-isearch)
  (flash-isearch-mode 1))

(provide 'flash-config)
