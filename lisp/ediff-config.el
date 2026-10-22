;;; ediff-config.el --- Description -*- lexical-binding: t; -*-

(setq ediff-split-window-function #'split-window-horizontally
      ediff-window-setup-function #'ediff-setup-windows-plain
      ediff-diff-options "-w")   ; ignore whitespace changes

;; Restore your window layout when you quit ediff
(winner-mode 1)
(add-hook 'ediff-after-quit-hook-internal #'winner-undo)

(provide 'ediff-config)
