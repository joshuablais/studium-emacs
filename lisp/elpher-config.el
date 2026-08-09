;;; elpher-config.el --- Description -*- lexical-binding: t; -*-

(use-package elpher
  :ensure (:host github :repo "emacsmirror/elpher")
  :defer t
  :bind (:map elpher-mode-map
              ("b" . elpher-back)
              ("a" . elpher-bookmark-link)))

(with-eval-after-load 'org
  (setq org-return-follows-link t)
  (org-link-set-parameters
   "gemini"
   :follow (lambda (path _) (elpher-go (concat "gemini://" path))))
  (org-link-set-parameters
   "gopher"
   :follow (lambda (path _) (elpher-go (concat "gopher://" path)))))

(provide 'elpher-config)
