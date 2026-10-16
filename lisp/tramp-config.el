;;; tramp-config.el --- TRAMP configuration -*- lexical-binding: t; -*-

;; Plain variables: safe to set before tramp loads
(setq tramp-default-method "sshx"
      tramp-verbose 1
      tramp-connection-timeout 30
      tramp-use-file-notifications nil
      auto-revert-remote-files nil
      remote-file-name-inhibit-locks t
      remote-file-name-inhibit-cache 30)

;; Anything that mutates tramp's own lists waits for tramp
(with-eval-after-load 'tramp
  (add-to-list 'tramp-connection-properties
               (list (regexp-quote "192.168.0.53") "term-name" "dumb"))
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path)
  (add-to-list 'tramp-remote-path "/run/current-system/profile/bin")
  (add-to-list 'tramp-remote-path "/run/current-system/profile/sbin")
  (add-to-list 'tramp-remote-path "/home/joshua/.guix-profile/bin"))

;; Remote dirs never count as VC projects
(defun jb-tramp--no-remote-vc (orig-fn dir)
  (unless (file-remote-p dir)
    (funcall orig-fn dir)))

(with-eval-after-load 'project
  (advice-add 'project-try-vc :around #'jb-tramp--no-remote-vc))

(provide 'tramp-config)
