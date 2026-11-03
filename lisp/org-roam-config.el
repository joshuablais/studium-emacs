;;; org-roam-config.el --- Description -*- lexical-binding: t; -*-

(defun my/org-roam-filetags-prompt ()
  "Prompt for filetags from existing org-roam tags."
  (let* ((tags (seq-uniq (flatten-list
                          (org-roam-db-query
                           [:select [tag] :from tags]))))
         (selected (completing-read-multiple "Tags: " tags)))
    (format ":%s:" (string-join selected ":"))))

(use-package org-roam
  :ensure t
  :commands (org-roam-node-find
             org-roam-node-insert
             org-roam-dailies-goto-today
             org-roam-dailies-capture-today
             org-roam-buffer-toggle
             org-roam-db-sync
             org-roam-capture)
  :init
  (setq org-roam-directory "~/org/roam"
        org-roam-database-connector 'sqlite-builtin
        org-roam-completion-everywhere t
        org-roam-db-location (expand-file-name "org-roam.db" "~/org/roam"))

  (defun my/org-roam-enable-autosync ()
    "Enable autosync once, on the first Org buffer, then unhook."
    (remove-hook 'org-mode-hook #'my/org-roam-enable-autosync)
    (org-roam-db-autosync-mode 1))
  (add-hook 'org-mode-hook #'my/org-roam-enable-autosync)

  :config
  (make-directory org-roam-directory t)

  (setq org-roam-capture-templates
        '(("d" "default" plain "%?"
           :target (file+head "${slug}.org"
                              "#+title: ${title}\n#+filetags: %(my/org-roam-filetags-prompt)\n\n")
           :unnarrowed t)))

  (defconst my/daily-head
    (concat "#+title: %<%Y-%m-%d %A>\n"
            "#+filetags: :daily:\n\n"
            "* TODAY\n"
            "* Notes\n")
    "Skeleton inserted only when a daily file is first created.")

  (setq org-roam-dailies-directory "daily/"
        org-roam-dailies-capture-templates
        `(("d" "default" entry "* %<%H:%M>: %?"
           :target (file+head+olp "%<%Y-%m-%d>.org" ,my/daily-head ("Notes")))
          ("t" "todo" entry "* TODO %?"
           :target (file+head+olp "%<%Y-%m-%d>.org" ,my/daily-head ("TODAY"))))))

(use-package org-roam-ui
  :ensure t
  :defer t
  :commands (org-roam-ui-mode org-roam-ui-open)
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t
        org-roam-ui-open-on-start nil))

(provide 'org-roam-config)
