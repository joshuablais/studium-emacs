;;; magit.el --- Description -*- lexical-binding: t; -*-

(use-package transient
  :ensure (:host github :repo "magit/transient")
  :demand t)
(elpaca-wait)

(use-package magit-section :demand t)
(elpaca-wait)

(use-package magit
  :defer t
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1
        magit-bury-buffer-function #'magit-restore-window-configuration))

(use-package forge
  :after magit
  :init
  (setq forge-add-default-bindings t)
  :config
  (dolist (entry '(("codeberg.org" "codeberg.org/api/v1" "codeberg.org" forge-forgejo-repository)
                   ("forge.labrynth.org" "forge.labrynth.org/api/v1" "forge.labrynth.org" forge-forgejo-repository)))
    (add-to-list 'forge-alist entry)))

(add-hook 'git-commit-mode-hook #'meow-insert)

(with-eval-after-load 'magit
  (define-key magit-status-mode-map (kbd "p") #'magit-push)
  (define-key magit-status-mode-map (kbd "SPC") nil)
  (define-key magit-log-mode-map (kbd "SPC") nil)
  (define-key magit-diff-mode-map (kbd "SPC") nil))

(provide 'magit-config)
