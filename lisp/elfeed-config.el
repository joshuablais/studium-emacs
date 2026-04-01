;;; elfeed-config.el --- Description -*- lexical-binding: t; -*-
(use-package elfeed
  :ensure t
  :defer t
  :custom
  (elfeed-db-directory "~/.elfeed")
  (elfeed-search-filter "@1-week-ago +unread -news")
  :config
  (make-directory "~/.elfeed" t)
  (load (expand-file-name "lisp/custom/elfeed-download" user-emacs-directory))
  (elfeed-download-setup)
  (run-at-time nil (* 60 60) #'elfeed-update)
  (define-key elfeed-search-mode-map (kbd "d") #'elfeed-download-current-entry)
  (define-key elfeed-search-mode-map (kbd "O") #'elfeed-search-browse-url))

(use-package elfeed-org
  :ensure t
  :after elfeed
  :custom
  (rmh-elfeed-org-files '("~/emacs-meow/elfeed.org"))
  :config
  (elfeed-org))

(use-package elfeed-tube
  :ensure t
  :after elfeed
  :config
  (elfeed-tube-setup)
  (define-key elfeed-show-mode-map (kbd "F")     #'elfeed-tube-fetch)
  (define-key elfeed-show-mode-map (kbd "C-x C-s") #'elfeed-tube-save)
  (define-key elfeed-search-mode-map (kbd "F")     #'elfeed-tube-fetch)
  (define-key elfeed-search-mode-map (kbd "C-x C-s") #'elfeed-tube-save))

(provide 'elfeed-config)
;;; elfeed-config.el ends here
