;;; universal-launcher.el --- Minibuffer launcher  -*- lexical-binding: t; -*-

;;; Commentary:
;; Sources are (GROUP FETCH KEY).  FETCH returns candidate strings carrying
;; `ul-type' and `ul-payload' text properties.  KEY, when non-nil, returns a
;; cheap fingerprint of FETCH's inputs; FETCH reruns only when it changes.
;; KEY nil means FETCH runs every popup (only for cheap, volatile sources).
;; No timers.  Icons are computed only for rows Vertico actually displays.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'recentf)
(require 'nerd-icons)
(recentf-mode 1)

(autoload 'url-hexify-string "url-util")
(defvar org-agenda-files)
(declare-function org-agenda-files "org")
(declare-function org-map-entries "org")
(declare-function org-get-heading "org")
(declare-function org-get-todo-state "org")
(declare-function org-fold-show-context "org-fold")

(defgroup universal-launcher nil "Minibuffer launcher." :group 'convenience)

;;;; Sources

(defvar universal-launcher-sources
  '(("Context"      universal-launcher--actions)
    ("Active"       universal-launcher--buffers)
    ("Active"       universal-launcher--windows)
    ("Tasks"        universal-launcher--tasks     universal-launcher--tasks-key)
    ("Files & Apps" universal-launcher--files     universal-launcher--files-key)
    ("Files & Apps" universal-launcher--apps      universal-launcher--apps-key)
    ("Web"          universal-launcher--bookmarks universal-launcher--bookmarks-key)
    ("System"       universal-launcher--ssh-hosts universal-launcher--ssh-key)
    ("System"       universal-launcher--commands  universal-launcher--commands-key)
    ("Tools"        universal-launcher--kill-ring)
    ("Tools"        universal-launcher--emojis    ignore))
  "List of (GROUP FETCH KEY).  `ignore' as KEY means compute once.")

(defcustom universal-launcher-bookmarks-file "~/org/bookmarks.org"
  "Org file scanned for URLs." :type 'file)

(defcustom universal-launcher-mode-actions
  '((t nil "Capture" ("Quick note" . org-capture))
    (org-mode nil "Org"
     ("Open Agenda" . org-agenda) ("Refile" . org-refile)
     ("Archive subtree" . org-archive-subtree) ("Set tags" . org-set-tags-command))
    ((go-mode go-ts-mode) "go.mod" "Go"
     ("Run tests" . "go test -v ./...") ("Build" . "go build")
     ("Run main" . "go run .") ("Tidy modules" . "go mod tidy") ("Format code" . gofmt))
    ((rust-mode rust-ts-mode) "Cargo.toml" "Rust"
     ("Build" . "cargo build") ("Run tests" . "cargo test")
     ("Run" . "cargo run") ("Check" . "cargo check"))
    (emacs-lisp-mode nil "Elisp"
     ("Eval buffer" . eval-buffer) ("Eval defun" . eval-defun) ("Load file" . load-file))
    ((nix-mode nix-ts-mode) nil "Nix"
     ("Rebuild switch" . "sudo nixos-rebuild switch")
     ("Rebuild test" . "sudo nixos-rebuild test")
     ("Update flake" . "nix flake update"))
    ((markdown-mode gfm-mode) nil "Markdown"
     ("Preview" . markdown-preview) ("Export to HTML" . markdown-export)))
  "Entries (MODES ROOT-FILE LABEL . ACTIONS).
MODES is t, a mode, or a list of modes; derived modes match.  ROOT-FILE,
when non-nil, is located upward to set `default-directory'.  Each action
is (NAME . COMMAND) or (NAME . SHELL-STRING).  Unbound commands are hidden."
  :type 'sexp)

(defcustom universal-launcher-custom-actions nil
  "Global actions: (NAME . COMMAND), (NAME . SHELL-STRING),
or the old form (NAME . (TYPE . ACTION))."
  :type 'sexp)

(defvar universal-launcher--common-emojis
  '(("Smiling Face" . "😊") ("Heart" . "❤️") ("Thumbs Up" . "👍")
    ("Thinking Face" . "🤔") ("Fire" . "🔥") ("Star" . "⭐")
    ("Check Mark" . "✅") ("Rocket" . "🚀") ("Party Popper" . "🎉")
    ("Eyes" . "👀") ("Laughing Face" . "😂") ("Clapping Hands" . "👏")
    ("Folded Hands" . "🙏") ("Muscle" . "💪") ("Sparkles" . "✨")
    ("Warning" . "⚠️") ("Information" . "ℹ️") ("Question Mark" . "❓")
    ("Prohibited" . "🚫") ("Calendar" . "📅") ("Clock" . "⏰")
    ("Mail" . "📧") ("Lock" . "🔒") ("Magnifying Glass" . "🔍")
    ("Light Bulb" . "💡")))

;;;; Icons (computed once at load; per-file icons computed lazily)

(defvar universal-launcher--type-icons
  (cl-flet ((i (fn name color) (funcall fn name :face `(:foreground ,color :height 0.9))))
    `((buffer   . ,(i #'nerd-icons-octicon "nf-oct-file_code"     "#3d424a"))
      (window   . ,(i #'nerd-icons-mdicon  "nf-md-monitor"        "#8b919a"))
      (app      . ,(i #'nerd-icons-faicon  "nf-fa-cube"           "#e0dcd4"))
      (command  . ,(i #'nerd-icons-octicon "nf-oct-terminal"      "#98c379"))
      (bookmark . ,(i #'nerd-icons-octicon "nf-oct-bookmark"      "#b8c4b8"))
      (ssh      . ,(i #'nerd-icons-faicon  "nf-fa-server"         "#98c379"))
      (task     . ,(i #'nerd-icons-octicon "nf-oct-checklist"     "#61afef"))
      (kill     . ,(i #'nerd-icons-faicon  "nf-fa-clipboard"      "#c678dd"))
      (emoji    . ,(i #'nerd-icons-mdicon  "nf-md-emoticon"       "#e5c07b"))
      (action   . ,(i #'nerd-icons-mdicon  "nf-md-lightning_bolt" "#e5c07b")))))

(defvar universal-launcher--group-icons
  (cl-flet ((i (fn name color) (funcall fn name :face `(:foreground ,color :weight bold))))
    `(("Context"      . ,(i #'nerd-icons-mdicon  "nf-md-lightning_bolt" "#e5c07b"))
      ("Active"       . ,(i #'nerd-icons-mdicon  "nf-md-view_dashboard" "#61afef"))
      ("Tasks"        . ,(i #'nerd-icons-octicon "nf-oct-checklist"     "#61afef"))
      ("Files & Apps" . ,(i #'nerd-icons-mdicon  "nf-md-apps"           "#c678dd"))
      ("Web"          . ,(i #'nerd-icons-mdicon  "nf-md-web"            "#e06c75"))
      ("System"       . ,(i #'nerd-icons-mdicon  "nf-md-cog"            "#98c379"))
      ("Tools"        . ,(i #'nerd-icons-mdicon  "nf-md-hammer_wrench"  "#d19a66")))))

;;;; Primitives

(defun universal-launcher--cand (text type payload)
  (propertize text 'ul-type type 'ul-payload payload))

(defun universal-launcher--stamp (path)
  "Fingerprint PATH as (TRUENAME . MTIME).
Store paths (Guix, Nix) all have mtime 1; a new profile generation is
visible only through the resolved symlink target."
  (let* ((file-name-handler-alist nil)
         (true (file-truename path)))
    (cons true (file-attribute-modification-time (file-attributes true)))))

(defun universal-launcher--sway (cmd)
  (call-process "swaymsg" nil 0 nil cmd))

(defun universal-launcher--spawn (cmd)
  "Run shell CMD detached from Emacs.  Under sway, sway is the parent."
  (if (getenv "SWAYSOCK")
      (universal-launcher--sway (concat "exec " cmd))
    (call-process "setsid" nil 0 nil "-f" "sh" "-c" cmd)))

;;;; Volatile sources (every popup; all cheap)

(defun universal-launcher--buffers ()
  (cl-loop for b in (buffer-list)
           for name = (buffer-name b)
           unless (string-prefix-p " " name)
           collect (universal-launcher--cand (concat "Buffer: " name) 'buffer b)))

(defun universal-launcher--windows ()
  "Sway views, via one get_tree call.  Replaces X11-only wmctrl."
  (when (getenv "SWAYSOCK")
    (with-temp-buffer
      (when (eq 0 (call-process "swaymsg" nil t nil "-r" "-t" "get_tree"))
        (goto-char (point-min))
        (let (acc)
          (cl-labels
              ((walk (n)
                 (when (plist-get n :pid)
                   (let ((app (or (plist-get n :app_id)
                                  (plist-get (plist-get n :window_properties) :class)
                                  "?")))
                     (unless (string-match-p "\\`[Ee]macs\\'" app)
                       (push (universal-launcher--cand
                              (format "Window: %s  %s %s" app (or (plist-get n :name) "")
                                      (propertize (format "#%d" (plist-get n :id))
                                                  'face 'shadow))
                              'window (plist-get n :id))
                             acc))))
                 (mapc #'walk (plist-get n :nodes))
                 (mapc #'walk (plist-get n :floating_nodes))))
            (walk (json-parse-buffer :object-type 'plist :null-object nil)))
          (nreverse acc))))))

(defun universal-launcher--kill-ring ()
  (cl-loop for item in kill-ring
           for i from 1 to 15
           when (and (stringp item) (string-match-p "[^[:space:]]" item))
           collect (universal-launcher--cand
                    (format "Clip %d: %s" i
                            (truncate-string-to-width
                             (string-replace "\n" " ↩ " (substring-no-properties item))
                             60 nil nil "…"))
                    'kill item)))

(defun universal-launcher--mode-match-p (modes)
  (or (eq modes t)
      (cl-some (lambda (m) (provided-mode-derived-p major-mode m))
               (ensure-list modes))))

(defun universal-launcher--actions ()
  (let (acc)
    (pcase-dolist (`(,modes ,root ,label . ,actions) universal-launcher-mode-actions)
      (when (universal-launcher--mode-match-p modes)
        (let ((dir (or (and root (locate-dominating-file default-directory root))
                       default-directory)))
          (pcase-dolist (`(,name . ,act) actions)
            (when (or (stringp act) (fboundp act))
              (push (universal-launcher--cand (format "%s: %s" label name)
                                              'action (cons dir act))
                    acc))))))
    (pcase-dolist (`(,name . ,act) universal-launcher-custom-actions)
      (push (universal-launcher--cand (concat "Custom: " name) 'action
                                      (cons default-directory
                                            (if (consp act) (cdr act) act)))
            acc))
    (nreverse acc)))

;;;; Fingerprinted sources

(defun universal-launcher--files-key ()
  (copy-sequence recentf-list))

(defun universal-launcher--files ()
  (mapcar (lambda (f)
            (universal-launcher--cand
             (concat "File: " (file-name-nondirectory f) "  "
                     (propertize (abbreviate-file-name (or (file-name-directory f) ""))
                                 'face 'font-lock-comment-face))
             'file f))
          recentf-list))

(defun universal-launcher--app-dirs ()
  "XDG application dirs in precedence order.  Covers Guix, Nix, and
flatpak exports, provided Emacs inherited the session's XDG_DATA_DIRS."
  (cl-loop for d in (cons (or (getenv "XDG_DATA_HOME") "~/.local/share")
                          (split-string (or (getenv "XDG_DATA_DIRS")
                                            "/usr/local/share:/usr/share")
                                        ":" t))
           for a = (expand-file-name "applications" d)
           when (file-directory-p a) collect a))

(defun universal-launcher--apps-key ()
  (mapcar #'universal-launcher--stamp (universal-launcher--app-dirs)))

(defun universal-launcher--parse-desktop ()
  "Parse [Desktop Entry] in the current buffer to (NAME . EXEC), or nil."
  (goto-char (point-min))
  (when (re-search-forward "^\\[Desktop Entry\\][ \t]*$" nil t)
    (let ((end (save-excursion
                 (if (re-search-forward "^\\[" nil t) (match-beginning 0) (point-max))))
          name exec type hide)
      (while (re-search-forward "^\\([A-Za-z0-9-]+\\)[ \t]*=[ \t]*\\(.*\\)$" end t)
        (pcase (match-string 1)
          ("Name" (setq name (or name (match-string 2))))
          ("Exec" (setq exec (or exec (match-string 2))))
          ("Type" (setq type (match-string 2)))
          ((or "NoDisplay" "Hidden")
           (when (equal (match-string 2) "true") (setq hide t)))))
      (when (and name exec (equal type "Application") (not hide))
        (cons name (string-trim
                    (string-replace "%%" "%"
                                    (replace-regexp-in-string
                                     "%[fFuUdDnNickvm]" "" exec t t))))))))

(defun universal-launcher--apps ()
  "Desktop entries.  First desktop-file ID wins, per the XDG spec, so a
user override (including Hidden=true) shadows the system entry."
  (let ((seen (make-hash-table :test #'equal))
        (file-name-handler-alist nil)
        (coding-system-for-read 'utf-8)
        acc)
    (with-temp-buffer
      (dolist (dir (universal-launcher--app-dirs))
        (dolist (f (directory-files dir t "\\.desktop\\'" t))
          (let ((id (file-name-nondirectory f)))
            (unless (gethash id seen)
              (puthash id t seen)
              (erase-buffer)
              (insert-file-contents f)
              (when-let* ((app (universal-launcher--parse-desktop)))
                (push (universal-launcher--cand (concat "App: " (car app))
                                                'app (cdr app))
                      acc)))))))
    (sort acc #'string<)))

(defun universal-launcher--path-dirs ()
  (parse-colon-path (getenv "PATH")))

(defun universal-launcher--commands-key ()
  (mapcar #'universal-launcher--stamp (universal-launcher--path-dirs)))

(defun universal-launcher--commands ()
  "Names in PATH, first occurrence wins.  No per-file stat: profile bin
dirs contain only executables, and stat x 4000 was the cost."
  (let ((seen (make-hash-table :test #'equal :size 4096))
        (file-name-handler-alist nil)
        acc)
    (dolist (dir (universal-launcher--path-dirs))
      (when (file-directory-p dir)
        (dolist (name (directory-files dir nil "\\`[^.]" t))
          (unless (gethash name seen)
            (puthash name t seen)
            (push (universal-launcher--cand (concat "Run: " name) 'command name) acc)))))
    (sort acc #'string<)))

(defun universal-launcher--domain (url)
  (if (string-match "\\`https?://\\(?:www\\.\\)?\\([^/]+\\)" url) (match-string 1 url) url))

(defun universal-launcher--bookmarks-key ()
  (universal-launcher--stamp (expand-file-name universal-launcher-bookmarks-file)))

(defun universal-launcher--bookmarks ()
  "Org links and bare URLs, by regex.  No `org-mode', no hooks."
  (let ((file (expand-file-name universal-launcher-bookmarks-file))
        (seen (make-hash-table :test #'equal))
        acc)
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (cl-flet ((add (url desc)
                    (let ((url (if (string-match-p "[^/]/\\'" url) (substring url 0 -1) url)))
                      (unless (gethash url seen)
                        (puthash url t seen)
                        (push (universal-launcher--cand
                               (concat "Bookmark: "
                                       (if (string-empty-p desc)
                                           (universal-launcher--domain url)
                                         desc))
                               'bookmark url)
                              acc)))))
          ;; Org links first so their descriptions beat bare-URL fallbacks.
          (while (re-search-forward
                  "\\[\\[\\(https?://[^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]" nil t)
            (add (match-string-no-properties 1) (or (match-string-no-properties 2) "")))
          (goto-char (point-min))
          (while (re-search-forward "https?://[^][ \t\n<>\"]+" nil t)
            (add (match-string-no-properties 0) "")))))
    (sort acc #'string<)))

(defun universal-launcher--ssh-key ()
  (universal-launcher--stamp (expand-file-name "~/.ssh/config")))

(defun universal-launcher--ssh-hosts ()
  (let ((config (expand-file-name "~/.ssh/config"))
        (case-fold-search t)
        acc)
    (when (file-readable-p config)
      (with-temp-buffer
        (insert-file-contents config)
        (while (re-search-forward "^[ \t]*Host[ \t]+\\(.+\\)$" nil t)
          ;; `Host a b c' declares three patterns.
          (dolist (h (split-string (match-string-no-properties 1)))
            (unless (string-match-p "[*?!]" h)
              (push (universal-launcher--cand (concat "SSH: " h) 'ssh h) acc))))))
    (nreverse acc)))

(defun universal-launcher--tasks-key ()
  "Edit tick for visited agenda files, stamp otherwise.  Any edit
invalidates, so cached (BUFFER . POS) payloads are always current."
  (when (and (featurep 'org) org-agenda-files)
    (mapcar (lambda (f)
              (if-let* ((b (get-file-buffer f)))
                  (buffer-chars-modified-tick b)
                (universal-launcher--stamp f)))
            (org-agenda-files t))))

(defun universal-launcher--tasks ()
  (when (and (featurep 'org) org-agenda-files)
    (let (acc)
      (org-map-entries
       (lambda ()
         (push (universal-launcher--cand
                (format "Task: %s %s  %s"
                        (propertize (or (org-get-todo-state) "TODO") 'face 'org-todo)
                        (org-get-heading t t t t)
                        (propertize (buffer-name) 'face 'font-lock-comment-face))
                'task (cons (current-buffer) (point)))
               acc))
       "+TODO=\"TODO\"|+TODO=\"NEXT\"|+TODO=\"STARTED\""
       'agenda)
      (nreverse acc))))

(defun universal-launcher--emojis ()
  (mapcar (lambda (e)
            (universal-launcher--cand (format "Emoji: %s %s" (car e) (cdr e)) 'emoji (cdr e)))
          universal-launcher--common-emojis))

;;;; Collection

(defvar universal-launcher--memo (make-hash-table :test #'eq)
  "FETCH -> (FINGERPRINT . CANDIDATES).")

(defun universal-launcher--fetch (group fetch key)
  (let ((title (concat (alist-get group universal-launcher--group-icons "" nil #'equal)
                       "  " group)))
    (cl-flet ((run ()
                (let ((cands (funcall fetch)))
                  (dolist (c cands cands)
                    (put-text-property 0 (length c) 'ul-group title c)))))
      (if (null key)
          (run)
        (let ((k (funcall key))
              (hit (gethash fetch universal-launcher--memo)))
          (if (and hit (equal k (car hit)))
              (cdr hit)
            (cdr (puthash fetch (cons k (run)) universal-launcher--memo))))))))

(defun universal-launcher--collect ()
  (let ((gc-cons-threshold most-positive-fixnum))
    (cl-loop for (group fetch key) in universal-launcher-sources
             append (universal-launcher--fetch group fetch key))))

;;;; Completion table

(defun universal-launcher--group (cand transform)
  (if transform cand (get-text-property 0 'ul-group cand)))

(defun universal-launcher--affix (cands)
  "Called by Vertico for visible rows only, so icon cost is O(screen)."
  (mapcar (lambda (c)
            (let ((type (get-text-property 0 'ul-type c)))
              (list c
                    (concat (if (eq type 'file)
                                (nerd-icons-icon-for-file (get-text-property 0 'ul-payload c))
                              (alist-get type universal-launcher--type-icons ""))
                            " ")
                    "")))
          cands))

(defun universal-launcher--table (cands)
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (category . universal-launcher)
                   (group-function . universal-launcher--group)
                   (affixation-function . universal-launcher--affix)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity))
      (complete-with-action action cands string pred))))

;;;; Calculator

(defconst universal-launcher--math-re
  (rx bos (+ (or (any "0-9" ?- ?+ ?* ?/ ?^ ?% ?! ?\( ?\) ?. ?, ?\s)
                 "sin" "cos" "tan" "sqrt" "exp" "ln" "log" "pi"))
      eos))

(defun universal-launcher--math-p (s)
  (and (string-match-p universal-launcher--math-re s)
       (string-match-p "[0-9]" s)
       (string-match-p (rx (or (any ?- ?+ ?* ?/ ?^ ?% ?!)
                               "sin" "cos" "tan" "sqrt" "exp" "ln" "log"))
                       s)))

(defun universal-launcher--calc (expr)
  (let ((r (calc-eval expr)))          ; error => list, success => string
    (if (stringp r)
        (progn (kill-new r) (message "%s = %s (copied)" expr r))
      (message "Invalid expression: %s" expr))))

;;;; Dispatch

(defun universal-launcher--execute (cand)
  (let ((payload (get-text-property 0 'ul-payload cand)))
    (pcase (get-text-property 0 'ul-type cand)
      ('buffer   (when (buffer-live-p payload) (switch-to-buffer payload)))
      ('window   (universal-launcher--sway (format "[con_id=%d] focus" payload)))
      ((or 'app 'command) (universal-launcher--spawn payload))
      ('file     (find-file payload))
      ('bookmark (browse-url payload))
      ('ssh      (universal-launcher--ssh-connect payload))
      ('task     (pop-to-buffer-same-window (car payload))
                 (goto-char (cdr payload))
                 (org-fold-show-context)
                 (recenter))
      ('kill     (if buffer-read-only (kill-new payload) (insert payload)))
      ('emoji    (kill-new payload) (message "Copied %s" payload))
      ('action   (let ((default-directory (car payload)))
                   (if (stringp (cdr payload))
                       (async-shell-command (cdr payload))
                     (call-interactively (cdr payload))))))))

(defvar universal-launcher-history nil)
(defvar universal-launcher--input ""
  "Raw minibuffer input before exit; Vertico replaces it with the selection.")

;;;###autoload
(defun universal-launcher-popup ()
  "Launch anything; evaluate math; fall back to web search.
Math is judged on what you typed, not on what Vertico had selected."
  (interactive)
  (setq universal-launcher--input "")
  (let* ((cands (universal-launcher--collect))
         (sel (minibuffer-with-setup-hook
                  (lambda ()
                    (setq-local completion-ignore-case t)
                    (add-hook 'post-command-hook
                              (lambda ()
                                (setq universal-launcher--input
                                      (minibuffer-contents-no-properties)))
                              nil t))
                (completing-read "Launch: " (universal-launcher--table cands)
                                 nil nil nil 'universal-launcher-history)))
         (input (string-trim universal-launcher--input)))
    (cond
     ((universal-launcher--math-p input) (universal-launcher--calc input))
     ((string-empty-p sel) nil)
     ((when-let* ((c (car (member sel cands))))
        (universal-launcher--execute c)
        t))
     (t (universal-launcher--web-search sel)))))

;; Web search function
(defcustom universal-launcher-default-search-engine "DuckDuckGo"
  "Default search engine for web searches."
  :type 'string
  :group 'universal-launcher)

(defvar universal-launcher--last-search-engine nil
  "Last used search engine.")

(defun universal-launcher--web-search (query)
  "Search the web with QUERY using default browser.
If QUERY looks like a URL, navigate directly to it.
Otherwise, prompt for a search engine.
C-u prefix forces engine re-selection."
  (interactive
   (list (cond
          ((use-region-p)
           (buffer-substring-no-properties (region-beginning) (region-end)))
          ((thing-at-point 'symbol t))
          (t nil))))
  (let* ((search-engines
          '(("Google" . "https://www.google.com/search?q=")
            ("Searx" . "https://searx.labrynth.org/search?q=")
            ("Hister" . "http://127.0.0.1:4433/?q=")
            ("Go documentation" . "https://pkg.go.dev/search?q=")
            ("ArchWiki" . "https://wiki.archlinux.org/index.php?search=")
            ("DuckDuckGo" . "https://duckduckgo.com/?q=")
            ("Marginalia" . "https://search.marginalia.nu/search?query=")
            ("Reddit" . "https://www.reddit.com/search/?q=")
            ("Wiby" . "https://wiby.me/?q=")
            ("Anna's Archive" . "https://annas-archive.gl/search?q=")
            ("Wikipedia" . "https://en.wikipedia.org/w/index.php?search=")
            ("4get" . "https://4get.ca/web?s=")
            ("Goodreads" . "https://www.goodreads.com/search?q=")
            ("Nix Packages" . "https://search.nixos.org/packages?channel=25.05&query=")
            ("Guix Packages" . "https://toys.whereis.social/?search=")
            ("NixOS Options" . "https://search.nixos.org/options?channel=25.05&query=")
            ("DevDocs.io" . "https://devdocs.io/#q=")
            ("Doom discourse" . "https://discourse.doomemacs.org/search?q=")
            ("Doom issues" . "https://github.com/doomemacs/doomemacs/issues?q=")
            ("GitHub" . "https://github.com/search?q=")
            ("Google Images" . "https://www.google.com/search?tbm=isch&q=")
            ("Google Maps" . "https://www.google.com/maps/search/")
            ("Internet Archive" . "https://archive.org/search.php?query=")
            ("Kagi" . "https://kagi.com/search?q=")
            ("MDN" . "https://developer.mozilla.org/en-US/search?q=")
            ("Project Gutenberg" . "https://www.gutenberg.org/ebooks/search/?query=")
            ("Rust Docs" . "https://doc.rust-lang.org/std/?search=")
            ("SourceGraph" . "https://sourcegraph.com/search?q=")
            ("StackOverflow" . "https://stackoverflow.com/search?q=")
            ("Wolfram Alpha" . "https://www.wolframalpha.com/input/?i=")
            ("YouTube" . "https://www.youtube.com/results?search_query=")
            ("Perplexity" . "https://www.perplexity.ai/search/new?q=")
            ("Hacker News" . "https://hn.algolia.com/?q=")
            ("Lobsters" . "https://lobste.rs/search?q=")
            ("arXiv" . "https://arxiv.org/search/?query=")
            ("Semantic Scholar" . "https://www.semanticscholar.org/search?q=")
            ("Google Scholar" . "https://scholar.google.com/scholar?q=")
            ("Go Issues" . "https://github.com/golang/go/issues?q=")
            ("Crates.io" . "https://crates.io/search?q=")
            ("MELPA" . "https://melpa.org/#/?q=")
            ("Man Pages" . "https://man.archlinux.org/search?q=")
            ("Yandex" . "https://yandex.com/search/?text=")
            ("Emacs Docs" . "https://www.gnu.org/software/emacs/manual/html_node/emacs/index.html?search=")
            ))
         (engine (completing-read
                  (format "Search engine (default %s): "
                          (or universal-launcher--last-search-engine
                              universal-launcher-default-search-engine))
                  (mapcar #'car search-engines)
                  nil t nil nil
                  (or universal-launcher--last-search-engine
                      universal-launcher-default-search-engine)))
         (url-base (cdr (assoc engine search-engines)))
         (query (or query
                    (read-string (format "Search %s: " engine)
                                 (thing-at-point 'symbol t)))))
    (setq universal-launcher--last-search-engine engine)
    (if (string-match-p "^\\(https?://\\|www\\.\\)" query)
        (browse-url (if (string-prefix-p "www." query)
                        (concat "https://" query)
                      query))
      (browse-url (concat url-base (url-hexify-string query))))))

(defun universal-launcher--ssh-connect (host)
  "Connect to SSH HOST using best available terminal."
  (cond
   ;; Prefer vterm if available
   ((fboundp 'vterm)
    (let* ((buffer-name (format "*ssh-%s*" host))
           (existing-buffer (get-buffer buffer-name)))
      (if existing-buffer
          (progn
            (switch-to-buffer existing-buffer)
            (delete-other-windows))
        ;; Create new vterm and send SSH command
        (let ((buf (vterm buffer-name)))
          (with-current-buffer buf
            (vterm-send-string (format "ssh %s" host))
            (vterm-send-return))
          (switch-to-buffer buf)
          (delete-other-windows)))))

   ;; Fallback to eshell
   ((fboundp 'eshell)
    (let ((buffer (generate-new-buffer (format "*ssh-%s*" host))))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (eshell-mode)
      (insert (format "ssh %s" host))
      (eshell-send-input)))

   ;; Last resort: shell-mode
   (t
    (let ((buffer (get-buffer-create (format "*ssh-%s*" host))))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (unless (comint-check-proc buffer)
        (shell buffer))
      (goto-char (point-max))
      (insert (format "ssh %s" host))
      (comint-send-input)))))

;; Pay the cold cost once, while you're idle, instead of on first popup.
(run-with-idle-timer 2 nil #'universal-launcher--collect)

(provide 'universal-launcher)
;;; universal-launcher.el ends here
