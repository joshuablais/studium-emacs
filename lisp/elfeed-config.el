;;; elfeed-config.el --- RSS via Miniflux/Fever -*- lexical-binding: t; -*-

;;; Credentials & endpoint

(defvar jb/miniflux-host "miniflux.labrynth.org")
(defvar jb/miniflux-fever-user "joshua")
(defvar jb/miniflux-pass-entry "Empirica/MinifluxFever"
  "Path in the password store holding the Miniflux *Fever* password.")

(defun jb/pass (entry)
  "Return the first line of password-store ENTRY, or signal an error."
  (with-temp-buffer
    (let ((status (call-process "pass" nil t nil "show" entry)))
      (unless (zerop status)
        (error "pass show %s failed (exit %s): %s"
               entry status (string-trim (buffer-string))))
      (goto-char (point-min))
      (let ((line (buffer-substring-no-properties
                   (point) (line-end-position))))
        (when (string-empty-p line)
          (error "pass entry %s is empty" entry))
        line))))

;;; mpv playback

(defun jb/elfeed-play-in-mpv ()
  "Play current elfeed show entry in mpv."
  (interactive)
  (let ((url (elfeed-entry-link elfeed-show-entry)))
    (unless url (user-error "No URL for this entry"))
    (start-process "elfeed-mpv" nil "mpv"
                   "--ytdl-format=bestvideo[height<=1080]+bestaudio/best"
                   "--save-position-on-quit"
                   url)))

(defun jb/elfeed-search-play-in-mpv ()
  "Play selected elfeed search entry in mpv."
  (interactive)
  (let* ((entry (elfeed-search-selected :ignore-region))
         (url   (elfeed-entry-link entry)))
    (unless url (user-error "No URL for this entry"))
    (elfeed-untag entry 'unread)
    (elfeed-search-update-entry entry)
    (start-process "elfeed-mpv" nil "mpv"
                   "--ytdl-format=bestvideo[height<=1080]+bestaudio/best"
                   "--save-position-on-quit"
                   url)))

;;; elfeed

(use-package elfeed
  :ensure t
  :custom
  (elfeed-db-directory "~/.elfeed")
  (elfeed-search-filter "@1-week-ago +unread")
  (elfeed-use-curl t)
  :config
  (make-directory "~/.elfeed" t)
  (elfeed-set-timeout 36000)
  ;; Guarded: an error here would abort the rest of :config, silently
  ;; costing you every keybinding below it.
  (let ((dl (expand-file-name "lisp/custom/elfeed-download" user-emacs-directory)))
    (if (or (file-exists-p (concat dl ".el"))
            (file-exists-p (concat dl ".elc")))
        (progn
          (load dl)
          (elfeed-download-setup)
          (define-key elfeed-search-mode-map (kbd "d")
                      #'elfeed-download-current-entry))
      (message "elfeed-download not found at %s; skipping" dl)))
  (define-key elfeed-search-mode-map (kbd "O") #'elfeed-search-browse-url)
  (define-key elfeed-search-mode-map (kbd "v") #'jb/elfeed-search-play-in-mpv)
  (define-key elfeed-show-mode-map   (kbd "v") #'jb/elfeed-play-in-mpv))

;;; elfeed-protocol (Miniflux via Fever)

(defvar jb/elfeed-protocol-initialized nil)

(defun jb/elfeed-protocol-init (&optional force)
  "Wire Miniflux Fever into elfeed.  Idempotent unless FORCE."
  (interactive "P")
  (when (or force (not jb/elfeed-protocol-initialized))
    (let* ((pw    (jb/pass jb/miniflux-pass-entry))
           (entry (list (format "fever+https://%s@%s"
                                jb/miniflux-fever-user jb/miniflux-host)
                        :api-url  (format "https://%s/fever/" jb/miniflux-host)
                        :password pw))
           (feeds (list entry)))
      ;; Honour the defcustom's :set handler if this version has one;
      ;; plain setq would bypass it and the side effect would be lost.
      (when (boundp 'elfeed-protocol-feeds)
        (funcall (or (get 'elfeed-protocol-feeds 'custom-set) #'set-default)
                 'elfeed-protocol-feeds feeds))
      ;; elfeed-feeds is what elfeed actually iterates.  Authoritative.
      (setq elfeed-feeds feeds)
      (elfeed-protocol-enable)
      (unless elfeed-feeds
        (error "elfeed-feeds is nil after wiring"))
      (setq jb/elfeed-protocol-initialized t)
      (message "elfeed: Miniflux/Fever wired -> %s"
               (car (car elfeed-feeds))))))

(defun jb/elfeed-update ()
  "Ensure protocol wiring, then update."
  (interactive)
  (jb/elfeed-protocol-init)
  (elfeed-update))

(defun jb/elfeed-protocol-init-advice (&rest _)
  "Advice wrapper so re-evaluating this file does not stack advice."
  (jb/elfeed-protocol-init))

(use-package elfeed-protocol
  :ensure t
  :after elfeed
  :config
  ;; Defer credential resolution until you actually open elfeed, so
  ;; gpg-agent is guaranteed live and failures surface as backtraces.
  (advice-add 'elfeed :before #'jb/elfeed-protocol-init-advice)
  (run-at-time "1 min" (* 60 60) #'jb/elfeed-update))

;;; elfeed-tube

(use-package elfeed-tube
  :ensure t
  :after elfeed
  :config
  (elfeed-tube-setup)
  (define-key elfeed-show-mode-map (kbd "F")       #'elfeed-tube-fetch)
  (define-key elfeed-show-mode-map (kbd "C-x C-s") #'elfeed-tube-save))

(provide 'elfeed-config)
;;; elfeed-config.el ends here
