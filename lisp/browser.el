;;; browser.el --- eww-first browsing, external browser by exception -*- lexical-binding: t; -*-

;;; External browser — swap these two lines to change browsers.
;; Find the app_id with: swaymsg -t get_tree | grep app_id
(defvar jb/external-browser "chromium"
  "Program for external browsing: chromium, librewolf, firefox, ...")

(defvar jb/external-browser-app-id "chromium"
  "Sway app_id of `jb/external-browser', used to focus it.")

(defun jb/focus-external-browser ()
  (call-process "swaymsg" nil 0 nil
                (format "[app_id=\"%s\"] focus" jb/external-browser-app-id)))

(defun jb/browse-url-external (url &rest _args)
  "Open URL in `jb/external-browser', detached from Emacs, then focus it."
  (call-process jb/external-browser nil 0 nil url)
  (run-with-timer 0.15 nil #'jb/focus-external-browser))

(defun jb/browse-url-mpv (url &rest _args)
  "Open URL in mpv, detached from Emacs."
  (call-process "mpv" nil 0 nil url))

(defun jb/browse-url-pdf (url &rest _args)
  "Fetch remote PDF and open it in pdf-tools."
  (let ((tmp (make-temp-file "emacs-pdf-" nil ".pdf")))
    (url-copy-file url tmp t)
    (find-file-other-window tmp)
    (pdf-view-mode)))

;;; Routing
(defvar jb/external-domains
  '("github.com" "gitlab.com" "codeberg.org" "forge.labrynth.org"
    "google.com" "annas-archive.gl" "search.nixos.org" "toys.whereis.social"
    "goodreads.com" "youtube.com" "reddit.com" "kagi.com"
    "perplexity.ai" "wolframalpha.com" "sourcegraph.com"
    "archive.org" "yandex.com" "searx.labrynth.org" "127.0.0.1:4433"
    "wikipedia.org")
  "Domains (and their subdomains) that go to the external browser, not eww.")

(defconst jb/url-tail "\\(?:[?#]\\|\\'\\)"
  "Matches end of URL path: query, fragment, or end of string.")

(defun jb/domains-regexp (domains)
  "Anchored regexp matching DOMAINS and any subdomain of them."
  (concat "\\`https?://\\(?:[^/?#]*\\.\\)?"
          (regexp-opt domains)
          "\\(?:[:/?#]\\|\\'\\)"))

;; First match wins. File type beats domain (archive.org PDF -> pdf-tools).
;; Every key must be a regexp, not a predicate: eww-use-browse-url is built from them.
(setq browse-url-handlers
      `((,(concat "\\.mp4" jb/url-tail) . jb/browse-url-mpv)
        (,(concat "\\.pdf" jb/url-tail) . jb/browse-url-pdf)
        ("\\`gemini://" . elpher-browse-url-elpher)
        ("\\`gopher://" . elpher-browse-url-elpher)
        (,(jb/domains-regexp jb/external-domains) . jb/browse-url-external)))

;; No catch-all handler: unmatched URLs fall through to
;; browse-url-default-handlers (mailto:, man:, ...) and then to eww.
(setq browse-url-browser-function #'eww-browse-url
      browse-url-secondary-browser-function #'jb/browse-url-external)

;; Links clicked inside eww skip browse-url entirely unless they match
;; this regexp. Derive it from the handler table so the routing has one
;; source of truth. defcustom doesn't clobber a value set before eww loads.
(setq eww-use-browse-url
      (mapconcat #'identity
                 (cons "\\`mailto:" (mapcar #'car browse-url-handlers))
                 "\\|"))

;;; eww
(setq eww-search-prefix "https://searx.labrynth.org/search?q=")
(setq eww-download-directory (expand-file-name "~/Downloads/"))
(setq eww-auto-rename-buffer 'title)

(setq shr-width 100
      shr-max-width 120
      shr-indentation 4
      shr-use-fonts nil
      shr-max-image-size '(800 . 600)
      shr-image-animate t)

(use-package shr-tag-pre-highlight
  :ensure t
  :after shr
  :config
  (add-to-list 'shr-external-rendering-functions
               '(pre . shr-tag-pre-highlight)))

(use-package language-detection
  :ensure t)

(defun jb/eww-download-image-at-point ()
  "Download image at point to `eww-download-directory'."
  (interactive)
  (let ((url (or (get-text-property (point) 'image-url)
                 (get-text-property (point) 'shr-url))))
    (unless url (user-error "No image at point"))
    (let* ((path (car (url-path-and-query (url-generic-parse-url url))))
           (dest (expand-file-name (file-name-nondirectory path)
                                   eww-download-directory)))
      (url-copy-file url dest t)
      (message "Saved: %s" dest))))

;; Stock bindings worth knowing:
;;   &          current page -> external browser
;;   C-u RET    link at point -> external browser
;;   M-RET      link at point -> new eww buffer
;;   R          eww-readable
(with-eval-after-load 'eww
  (define-key eww-mode-map (kbd "=") #'text-scale-increase)
  (define-key eww-mode-map (kbd "-") #'text-scale-decrease)
  (define-key eww-mode-map (kbd "0") #'text-scale-adjust)
  (define-key eww-mode-map (kbd "B") #'eww-back-url)
  (define-key eww-mode-map (kbd "F") #'eww-forward-url)
  (define-key eww-mode-map (kbd "a") #'eww-add-bookmark)
  (define-key eww-mode-map (kbd "U") #'shr-copy-url)
  (define-key eww-mode-map (kbd "D") #'jb/eww-download-image-at-point))

;;; Browser tabs via CDP — Chromium-family only (see note below)
(defvar jb/browser-debug-port 9222
  "CDP remote debugging port. Launch browser with --remote-debugging-port=9222.")

(defun jb/browser-tabs ()
  "Return page tabs from the CDP endpoint."
  (let ((raw (shell-command-to-string
              (format "curl -sf http://localhost:%d/json" jb/browser-debug-port))))
    (when (string-empty-p raw)
      (user-error "No CDP endpoint on :%d" jb/browser-debug-port))
    (seq-filter (lambda (tab) (string= (alist-get 'type tab) "page"))
                (json-parse-string raw :array-type 'list :object-type 'alist))))

(defun jb/switch-browser-tab ()
  "Switch to a browser tab via CDP, then focus the browser."
  (interactive)
  (let* ((candidates (mapcar (lambda (tab)
                               (cons (format "%s  %s"
                                             (alist-get 'title tab)
                                             (alist-get 'url tab))
                                     (alist-get 'id tab)))
                             (jb/browser-tabs)))
         (choice (completing-read "Tab: " (mapcar #'car candidates) nil t))
         (id (cdr (assoc choice candidates))))
    (call-process "curl" nil nil nil "-s" "-X" "POST"
                  (format "http://localhost:%d/json/activate/%s"
                          jb/browser-debug-port id))
    (jb/focus-external-browser)))

;; jb/bookmarks-file, jb/org-heading-paths, jb/org-find-or-create-olp,
;; jb/bookmark-browser-tab: unchanged from your version — paste them here.

(provide 'browser)
