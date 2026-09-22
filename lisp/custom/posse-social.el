;;; posse-social.el --- Multi-platform POSSE system -*- lexical-binding: t; -*-

;;; Commentary:
;; Composes a post, saves it to the local microblog JSON, and opens
;; pre-filled browser composer tabs for X, Mastodon, Bluesky, and Threads.
;; No API credentials required — relies on each platform's public
;; intent/share URL scheme, which pre-fills the composer but still
;; requires a manual click to publish (by platform design).
;; If media is attached, it's copied to the system clipboard for manual
;; paste into each composer — no intent URL accepts binary payload.

;;; Code:

(defvar my-microblog-json-path "~/Development/joshuablais.com/src/content/notes/notes.json"
  "Path to the microblog JSON file.")

(defvar my-microblog-images-dir "~/Development/joshuablais.com/public/images/microblog/"
  "Directory to store microblog images.")

(defvar my-mastodon-instance "mastodon.social"
  "Your home Mastodon instance, used for the /share intent URL.")

(defconst my-post-delimiter "^----$"
  "Regexp marking the line after which buffer content is the actual post.")

(defun my-post-social ()
  "Compose a post: save to microblog, then open pre-filled composer tabs."
  (interactive)
  (let ((buf (get-buffer-create "*Post Composer*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "# Compose your post below (300 chars for Bluesky compatibility).\n")
      (insert "# Everything after the ---- line is your post.\n----\n")
      (org-mode)
      (goto-char (point-max))

      (setq-local media-path nil)

      (use-local-map (copy-keymap org-mode-map))
      (local-set-key (kbd "C-c C-c")
                     (lambda () (interactive) (my-send-post-from-buffer)))
      (local-set-key (kbd "C-c C-a")
                     (lambda () (interactive) (my-select-media-for-tweet)))
      (local-set-key (kbd "C-c C-k")
                     (lambda () (interactive)
                       (when (y-or-n-p "Cancel this post? ")
                         (kill-buffer)
                         (message "Post canceled.")))))

    (switch-to-buffer buf)
    (message "Compose below ----. C-c C-c to save + open tabs, C-c C-a to attach media, C-c C-k to cancel.")))

(defun my-select-media-for-tweet ()
  "Select media to attach to the post."
  (interactive)
  (let ((file (expand-file-name (read-file-name "Select media file: " nil nil t))))
    (if (and file
             (file-exists-p file)
             (string-match-p "\\(?:png\\|jpg\\|jpeg\\|gif\\|mp4\\)$" file))
        (with-current-buffer "*Post Composer*"
          (setq-local media-path file)
          (message "Media selected: %s" (file-name-nondirectory file)))
      (message "Error: Selected file does not exist or is not a supported media type."))))

(defun my-post-buffer-content ()
  "Extract post text after the ---- delimiter line.
Falls back to the whole buffer if the delimiter is missing,
so edits to the header don't silently corrupt extraction."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward my-post-delimiter nil t)
        (string-trim (buffer-substring-no-properties (1+ (point)) (point-max)))
      (string-trim (buffer-string)))))

(defun my-add-to-microblog (text media-path)
  "Add post to local microblog JSON file with proper JSON structure."
  (let* ((images-dir (expand-file-name my-microblog-images-dir))
         (json-file (expand-file-name my-microblog-json-path))
         (timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))
         (image-url "")
         (existing-data nil))

    (unless (file-directory-p images-dir)
      (make-directory images-dir t))

    (when (and media-path (file-exists-p media-path))
      (let* ((file-ext (file-name-extension media-path))
             (new-filename (format "%s.%s"
                                   (format-time-string "%Y%m%d-%H%M%S")
                                   file-ext))
             (dest-path (expand-file-name new-filename images-dir)))
        (copy-file media-path dest-path)
        (setq image-url (format "/images/microblog/%s" new-filename))
        (message "Image copied: %s -> %s"
                 (file-name-nondirectory media-path)
                 new-filename)))

    (when (file-exists-p json-file)
      (with-temp-buffer
        (insert-file-contents json-file)
        (setq existing-data (json-parse-buffer :array-type 'list :object-type 'alist))))

    (let ((new-entry `((text . ,(or text ""))
                       (image . ,image-url)
                       (timestamp . ,timestamp))))
      (setq existing-data (cons new-entry existing-data))
      (with-temp-file json-file
        (insert (json-encode existing-data)))
      (message "Microblog entry added: %s | %s | %s"
               timestamp
               (if (string-empty-p image-url) "no image" "with image")
               (if (string-empty-p text) "no text" (format "%.50s..." text))))))

(defun my-copy-image-to-clipboard (image-path)
  "Copy IMAGE-PATH to the clipboard via wl-copy, declared as image/png
regardless of actual format.

This mislabels the MIME type deliberately: Chromium's native-Wayland
clipboard paste handler was empirically confirmed to accept only
image/png as a declared type, even when the underlying bytes are
JPEG — it trusts the declared --type rather than sniffing content.
Real conversion (ImageMagick) was tested and works but is unneeded
overhead given this. If a paste target ever starts validating actual
image bytes against the declared type, this will break silently and
need real conversion again."
  (unless (executable-find "wl-copy")
    (error "wl-copy not found — are you on Wayland?"))
  (let ((exit-code (call-process "wl-copy" image-path nil nil "--type" "image/png")))
    (unless (eq exit-code 0)
      (error "wl-copy exited with code %s" exit-code))
    (message "Image copied to clipboard (labeled image/png).")))

(defun my-open-social-intents (text)
  "Open pre-filled composer tabs for X, Mastodon, Bluesky, and Threads.
Each site requires a manual click to publish — no intent URL
scheme supports one-shot posting, by platform design."
  (let* ((encoded (url-hexify-string text))
         (urls (list
                (format "https://x.com/intent/tweet?text=%s" encoded)
                (format "https://%s/share?text=%s" my-mastodon-instance encoded)
                (format "https://bsky.app/intent/compose?text=%s" encoded)
                (format "https://www.threads.com/intent/post?text=%s" encoded))))
    (dolist (url urls)
      (browse-url url))))

(defun my-send-post-from-buffer ()
  "Save the post to the local microblog, then open browser composer tabs."
  (interactive)
  (let* ((post-text (my-post-buffer-content))
         (media (buffer-local-value 'media-path (current-buffer))))

    (cond
     ((and (string-empty-p post-text) (not media))
      (message "Post must contain either text or media (or both)."))
     ((and (not (string-empty-p post-text)) (> (length post-text) 300))
      (message "Post exceeds 300 characters (%d). Please shorten it."
               (length post-text)))
     ((and media (not (file-exists-p media)))
      (message "Selected media file does not exist: %s" media))
     ((not (yes-or-no-p (format "Post %d chars%s to microblog + open tabs? "
                                (length post-text)
                                (if media " + image" ""))))
      (message "Post not sent."))
     (t
      (my-add-to-microblog post-text media)
      (when media
        (my-copy-image-to-clipboard media))
      (unless (string-empty-p post-text)
        (my-open-social-intents post-text))
      (when media
        (message "Image on clipboard — paste it into each composer manually; no intent URL accepts media."))
      (kill-buffer)))))

(global-set-key (kbd "C-c t t") #'my-post-social)

(provide 'posse-social)
;;; my-posse.el ends here
