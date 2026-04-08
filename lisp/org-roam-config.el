;;; org-roam-config.el --- Description -*- lexical-binding: t; -*-

;; roam
(use-package org-roam
  :ensure t
  :hook (org-mode . org-roam-db-autosync-mode)
  :commands (org-roam-node-find
             org-roam-node-insert
             org-roam-dailies-goto-today
             org-roam-buffer-toggle
             org-roam-db-sync
             org-roam-capture)
  :init
  (setq org-roam-directory "~/org/roam"
        org-roam-database-connector 'sqlite-builtin
        org-roam-completion-everywhere t
        org-roam-db-location (expand-file-name "org-roam.db" "~/org/roam")
        org-roam-v2-ack t)
  :config
  (setq org-roam-db-update-on-save nil)

  (unless (file-exists-p org-roam-directory)
    (make-directory org-roam-directory t))

  (setq org-roam-capture-templates
        '(("d" "default" plain "%?"
           :target (file+head "${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: \n\n")
           :unnarrowed t)

          ("c" "concept" plain "%?"
           :target (file+head "concepts/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :concept:\n\n")
           :unnarrowed t)

          ("C" "Contact" plain
           "* Contact Info
:PROPERTIES:
:EMAIL: %^{Email}
:PHONE: %^{Phone}
:BIRTHDAY: %^{Birthday (YYYY-MM-DD +1y)}t
:LOCATION: %^{Location}
:LAST_CONTACTED: %U
:END:

** Communications

** Notes
%?"
           :target (file+head "contacts/${slug}.org"
                              "#+title: ${title}\n#+filetags: %^{Tags}\n#+created: %U\n")
           :unnarrowed t)

          ("b" "book" plain "%?"
           :target (file+head "books/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+author: \n#+filetags: :book:\n\n* Summary\n\n* Key Ideas\n\n* Quotes\n\n* Related\n\n")
           :unnarrowed t)

          ("p" "person" plain "%?"
           :target (file+head "people/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :person:\n\n* Background\n\n* Key Ideas\n\n* Works\n\n")
           :unnarrowed t)

          ("t" "tech" plain "%?"
           :target (file+head "tech/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :tech:\n\n")
           :unnarrowed t)

          ("T" "theology" plain "%?"
           :target (file+head "faith/theology/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :theology:faith:\n\n* Doctrine\n\n* Scripture\n\n* Tradition\n\n* Application\n\n")
           :unnarrowed t)

          ("w" "writing" plain "%?"
           :target (file+head "writing/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :writing:draft:\n\n")
           :unnarrowed t)

          ("P" "project" plain "%?"
           :target (file+head "projects/${slug}.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :project:private:\n\n* Overview\n\n* Goals\n\n* Status\n\n* Notes\n\n")
           :unnarrowed t)))

  (setq org-roam-dailies-directory "daily/"
        org-roam-dailies-capture-templates
        '(("d" "default" entry "* %<%H:%M>: %?"
           :target (file+head "%<%Y-%m-%d>.org"
                              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: %<%Y-%m-%d %A>\n#+filetags: :daily:\n\n")))))

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
