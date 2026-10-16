;;; magit-config.el --- Magit and Forge -*- lexical-binding: t; -*-

(use-package magit
  :ensure t
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1
        magit-bury-buffer-function #'magit-restore-window-configuration)
  (keymap-set magit-status-mode-map "p" #'magit-push))

(use-package forge
  :ensure t
  :after magit
  :demand t
  :init
  (setq forge-add-default-bindings t)
  :config
  (add-to-list 'forge-alist
               '("forge.labrynth.org" "forge.labrynth.org/api/v1"
                 "forge.labrynth.org" forge-forgejo-repository)))

(provide 'magit-config)
