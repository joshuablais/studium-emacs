;;; universal-launcher.el --- Minibuffer launcher  -*- lexical-binding: t; -*-

;;; Commentary:
;; Two kinds of candidate:
;;
;; Static   (GROUP FETCH KEY) sources.  FETCH returns strings carrying
;;          `ul-type' and `ul-payload'.  KEY returns a cheap fingerprint of
;;          FETCH's inputs; FETCH reruns only when it changes.  KEY nil means
;;          every popup (cheap, volatile sources only).
;;
;; Dynamic  A pure function of the input: calculator, unit conversion,
;;          URL, !bang search, web search.  They are injected by a
;;          completion *style*, not the table, so they bypass the user's
;;          `completion-styles' (orderless would otherwise filter "5!" or
;;          "!gh foo" away as negations).  What you see selected is exactly
;;          what RET does.  No input scraping, no hidden fallbacks.
;;
;; Ranking: match quality (name prefix > word start > infix), then
;; frecency (exponentially decayed launch counts), then length.  An empty
;; prompt opens on a "Frequent" group.  Timers: a debounced save and a
;; one-shot idle warm-up, nothing periodic.

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
(declare-function math-read-expr "calc-ext")
(declare-function math-units-in-expr-p "calc-units")
(declare-function math-consistent-units-p "calc-units")
(declare-function math-single-units-in-expr-p "calc-units")
(declare-function math-convert-units "calc-units")
(declare-function math-convert-temperature "calc-units")
(declare-function math-simplify-units "calc-units")
(declare-function math-remove-units "calc-units")
(declare-function math-build-units-table "calc-units")
(declare-function math-float "calc-ext")
(declare-function math-format-value "calc-ext")
(declare-function calc-normalize "calc")
(defvar math-standard-units)
(declare-function vterm "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")
(declare-function eshell-send-input "esh-mode")
(declare-function comint-check-proc "comint")
(declare-function comint-send-input "comint")

(defgroup universal-launcher nil "Minibuffer launcher." :group 'convenience)

;;;; Faces — Compline

;; bg #1a1d21  base4 #3d424a  base6 #676d77  base7 #8b919a  base8 #e0dcd4
;; fg #f0efeb  fg-alt #ccc4b4 red #cdacac   green #b8c4b8  blue #b4bcc4
;; cyan #b4c0c8 yellow #d4ccb4 teal #b4c4bc dark-cyan #98a4ac
;; Faces, not hex literals: icons inherit them, so a theme or
;; `customize-face' restyles the launcher live.

(defface universal-launcher-group   '((t :foreground "#ccc4b4" :weight bold)) "Group titles.")
(defface universal-launcher-dim     '((t :foreground "#676d77"))  "Prefixes, paths, ids.")
(defface universal-launcher-result  '((t :foreground "#f0efeb" :weight bold)) "Calculator results.")
(defface universal-launcher-todo    '((t :foreground "#cdacac" :weight bold)) "Task keywords.")
(defface universal-launcher-buffer  '((t :foreground "#b4bcc4")) "Buffer icon.")
(defface universal-launcher-window  '((t :foreground "#b4c0c8")) "Window icon.")
(defface universal-launcher-app     '((t :foreground "#e0dcd4")) "App icon.")
(defface universal-launcher-file    '((t :foreground "#d4ccb4")) "File icon.")
(defface universal-launcher-command '((t :foreground "#b8c4b8")) "Command icon.")
(defface universal-launcher-bookmark '((t :foreground "#b4c4bc")) "Bookmark icon.")
(defface universal-launcher-ssh     '((t :foreground "#98a4ac")) "SSH icon.")
(defface universal-launcher-task    '((t :foreground "#d4ccb4")) "Task icon.")
(defface universal-launcher-kill    '((t :foreground "#cdacac")) "Clipboard icon.")
(defface universal-launcher-emoji   '((t :foreground "#d4ccb4")) "Emoji icon.")
(defface universal-launcher-action  '((t :foreground "#ccc4b4")) "Action icon.")
(defface universal-launcher-calc    '((t :foreground "#b4bcc4")) "Calculator icon.")
(defface universal-launcher-search  '((t :foreground "#b4c0c8")) "Search icon.")
(defface universal-launcher-url     '((t :foreground "#b4c4bc")) "URL icon.")
(defface universal-launcher-frequent '((t :foreground "#d4ccb4")) "Frequent group icon.")

;;;; Configuration

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

(defcustom universal-launcher-frecency-half-life (* 7 86400)
  "Seconds for a launch's weight to halve." :type 'number)

(defcustom universal-launcher-frequent-count 8
  "Rows in the Frequent group shown on an empty prompt.  0 disables."
  :type 'natnum)

(defcustom universal-launcher-frecency-file
  (locate-user-emacs-file "universal-launcher-frecency.eld")
  "Where launch statistics persist." :type 'file)

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

(defcustom universal-launcher-default-search-engine "DuckDuckGo"
  "Engine used by the plain \"Search\" candidate."
  :type 'string)

(defcustom universal-launcher-search-engines
  '(("DuckDuckGo"        "d"     "https://duckduckgo.com/?q=")
    ("Google"            "g"     "https://www.google.com/search?q=")
    ("Searx"             "sx"    "https://searx.labrynth.org/search?q=")
    ("Hister"            "h"     "http://127.0.0.1:4433/?q=")
    ("Kagi"              "k"     "https://kagi.com/search?q=")
    ("Marginalia"        "m"     "https://search.marginalia.nu/search?query=")
    ("Wiby"              "wb"    "https://wiby.me/?q=")
    ("4get"              "4g"    "https://4get.ca/web?s=")
    ("Yandex"            "y"     "https://yandex.com/search/?text=")
    ("Perplexity"        "px"    "https://www.perplexity.ai/search/new?q=")
    ("Wikipedia"         "w"     "https://en.wikipedia.org/w/index.php?search=")
    ("Wolfram Alpha"     "wa"    "https://www.wolframalpha.com/input/?i=")
    ("Go documentation"  "go"    "https://pkg.go.dev/search?q=")
    ("Go Issues"         "goi"   "https://github.com/golang/go/issues?q=")
    ("Rust Docs"         "rs"    "https://doc.rust-lang.org/std/?search=")
    ("Crates.io"         "cr"    "https://crates.io/search?q=")
    ("GitHub"            "gh"    "https://github.com/search?q=")
    ("SourceGraph"       "sg"    "https://sourcegraph.com/search?q=")
    ("StackOverflow"     "so"    "https://stackoverflow.com/search?q=")
    ("MDN"               "mdn"   "https://developer.mozilla.org/en-US/search?q=")
    ("DevDocs.io"        "dd"    "https://devdocs.io/#q=")
    ("Man Pages"         "man"   "https://man.archlinux.org/search?q=")
    ("ArchWiki"          "aw"    "https://wiki.archlinux.org/index.php?search=")
    ("Guix Packages"     "gp"    "https://toys.whereis.social/?search=")
    ("Nix Packages"      "np"    "https://search.nixos.org/packages?channel=25.05&query=")
    ("NixOS Options"     "no"    "https://search.nixos.org/options?channel=25.05&query=")
    ("MELPA"             "melpa" "https://melpa.org/#/?q=")
    ("Emacs Docs"        "ed"    "https://www.gnu.org/software/emacs/manual/html_node/emacs/index.html?search=")
    ("Doom discourse"    "dmd"   "https://discourse.doomemacs.org/search?q=")
    ("Doom issues"       "dmi"   "https://github.com/doomemacs/doomemacs/issues?q=")
    ("Hacker News"       "hn"    "https://hn.algolia.com/?q=")
    ("Lobsters"          "lo"    "https://lobste.rs/search?q=")
    ("Reddit"            "r"     "https://www.reddit.com/search/?q=")
    ("YouTube"           "yt"    "https://www.youtube.com/results?search_query=")
    ("arXiv"             "ax"    "https://arxiv.org/search/?query=")
    ("Semantic Scholar"  "ss"    "https://www.semanticscholar.org/search?q=")
    ("Google Scholar"    "gs"    "https://scholar.google.com/scholar?q=")
    ("Internet Archive"  "ia"    "https://archive.org/search.php?query=")
    ("Project Gutenberg" "pg"    "https://www.gutenberg.org/ebooks/search/?query=")
    ("Anna's Archive"    "aa"    "https://annas-archive.gl/search?q=")
    ("Goodreads"         "gr"    "https://www.goodreads.com/search?q=")
    ("Google Images"     "gi"    "https://www.google.com/search?tbm=isch&q=")
    ("Google Maps"       "gm"    "https://www.google.com/maps/search/"))
  "Entries (NAME BANG URL-PREFIX).  In the launcher, `!BANG query'
searches that engine directly."
  :type '(repeat (list string string string)))

;;;; Icons (built once; faces are symbols, so they track the theme)

(defvar universal-launcher--type-icons
  (cl-flet ((i (fn name face) (funcall fn name :face face)))
    `((buffer   . ,(i #'nerd-icons-octicon "nf-oct-file_code"     'universal-launcher-buffer))
      (window   . ,(i #'nerd-icons-mdicon  "nf-md-monitor"        'universal-launcher-window))
      (app      . ,(i #'nerd-icons-faicon  "nf-fa-cube"           'universal-launcher-app))
      (command  . ,(i #'nerd-icons-octicon "nf-oct-terminal"      'universal-launcher-command))
      (bookmark . ,(i #'nerd-icons-octicon "nf-oct-bookmark"      'universal-launcher-bookmark))
      (ssh      . ,(i #'nerd-icons-faicon  "nf-fa-server"         'universal-launcher-ssh))
      (task     . ,(i #'nerd-icons-octicon "nf-oct-checklist"     'universal-launcher-task))
      (kill     . ,(i #'nerd-icons-faicon  "nf-fa-clipboard"      'universal-launcher-kill))
      (emoji    . ,(i #'nerd-icons-mdicon  "nf-md-emoticon"       'universal-launcher-emoji))
      (action   . ,(i #'nerd-icons-mdicon  "nf-md-lightning_bolt" 'universal-launcher-action))
      (calc     . ,(i #'nerd-icons-faicon  "nf-fa-calculator"     'universal-launcher-calc))
      (url      . ,(i #'nerd-icons-mdicon  "nf-md-link_variant"   'universal-launcher-url))
      (search   . ,(i #'nerd-icons-octicon "nf-oct-search"        'universal-launcher-search))
      (pick     . ,(i #'nerd-icons-mdicon  "nf-md-format_list_bulleted" 'universal-launcher-search)))))

(defvar universal-launcher--group-titles
  (cl-flet ((g (fn name face title)
              (cons title (concat (funcall fn name :face face) "  "
                                  (propertize title 'face 'universal-launcher-group)))))
    (list (g #'nerd-icons-mdicon  "nf-md-star"           'universal-launcher-frequent "Frequent")
          (g #'nerd-icons-faicon  "nf-fa-calculator"     'universal-launcher-calc     "Calculate")
          (g #'nerd-icons-mdicon  "nf-md-lightning_bolt" 'universal-launcher-action   "Context")
          (g #'nerd-icons-mdicon  "nf-md-view_dashboard" 'universal-launcher-buffer   "Active")
          (g #'nerd-icons-octicon "nf-oct-checklist"     'universal-launcher-task     "Tasks")
          (g #'nerd-icons-mdicon  "nf-md-apps"           'universal-launcher-app      "Files & Apps")
          (g #'nerd-icons-mdicon  "nf-md-web"            'universal-launcher-bookmark "Web")
          (g #'nerd-icons-mdicon  "nf-md-cog"            'universal-launcher-command  "System")
          (g #'nerd-icons-mdicon  "nf-md-hammer_wrench"  'universal-launcher-kill     "Tools")
          (g #'nerd-icons-octicon "nf-oct-search"        'universal-launcher-search   "Search"))))

(defun universal-launcher--title (group)
  (or (cdr (assoc group universal-launcher--group-titles))
      (propertize group 'face 'universal-launcher-group)))

;;;; Primitives

(defun universal-launcher--cand (prefix text type payload)
  "Candidate \"PREFIX: TEXT\".  The prefix is matchable but dimmed."
  (propertize (concat (propertize (concat prefix ": ") 'face 'universal-launcher-dim) text)
              'ul-type type 'ul-payload payload))

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
           collect (universal-launcher--cand "Buffer" name 'buffer b)))

(defun universal-launcher--windows ()
  "Sway views, via one get_tree call."
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
                              "Window"
                              (format "%s  %s %s" app (or (plist-get n :name) "")
                                      (propertize (format "#%d" (plist-get n :id))
                                                  'face 'universal-launcher-dim))
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
                    (format "Clip %d" i)
                    (truncate-string-to-width
                     (string-replace "\n" " ↩ " (substring-no-properties item))
                     60 nil nil "…")
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
              (push (universal-launcher--cand label name 'action (cons dir act)) acc))))))
    (pcase-dolist (`(,name . ,act) universal-launcher-custom-actions)
      (push (universal-launcher--cand "Custom" name 'action
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
             "File"
             (concat (file-name-nondirectory f) "  "
                     (propertize (abbreviate-file-name (or (file-name-directory f) ""))
                                 'face 'universal-launcher-dim))
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
                (push (universal-launcher--cand "App" (car app) 'app (cdr app)) acc)))))))
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
            (push (universal-launcher--cand "Run" name 'command name) acc)))))
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
                               "Bookmark"
                               (if (string-empty-p desc) (universal-launcher--domain url) desc)
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
              (push (universal-launcher--cand "SSH" h 'ssh h) acc))))))
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
                "Task"
                (format "%s %s  %s"
                        (propertize (or (org-get-todo-state) "TODO") 'face 'universal-launcher-todo)
                        (org-get-heading t t t t)
                        (propertize (buffer-name) 'face 'universal-launcher-dim))
                'task (cons (current-buffer) (point)))
               acc))
       "+TODO=\"TODO\"|+TODO=\"NEXT\"|+TODO=\"STARTED\""
       'agenda)
      (nreverse acc))))

(defun universal-launcher--emojis ()
  "Every single-codepoint emoji Emacs knows, named by Unicode."
  (let ((seen (make-hash-table)) acc)
    (maphash (lambda (name ch)
               (when (and (eq (aref char-script-table ch) 'emoji)
                          (not (gethash ch seen)))
                 (puthash ch t seen)
                 (push (universal-launcher--cand
                        "Emoji" (format "%s %s" (downcase name) (string ch))
                        'emoji (string ch))
                       acc)))
             (ucs-names))
    (sort acc #'string<)))

;;;; Collection

(defvar universal-launcher--memo (make-hash-table :test #'eq)
  "FETCH -> (FINGERPRINT . CANDIDATES).")

(defun universal-launcher--fetch (group fetch key)
  (let ((title (universal-launcher--title group)))
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

;;;; Frecency

(defvar universal-launcher--stats nil
  "KEY -> (SCORE . TIME).  SCORE is decayed to TIME; KEY is candidate text.")

(defvar universal-launcher--save-timer nil)

(defun universal-launcher--decay (entry now)
  (* (car entry) (expt 2.0 (/ (- (cdr entry) now) universal-launcher-frecency-half-life))))

(defun universal-launcher--stats-load ()
  (unless universal-launcher--stats
    (setq universal-launcher--stats (make-hash-table :test #'equal))
    (when (file-readable-p universal-launcher-frecency-file)
      (with-temp-buffer
        (insert-file-contents universal-launcher-frecency-file)
        (pcase-dolist (`(,k ,s . ,tm) (ignore-errors (read (current-buffer))))
          (puthash k (cons s tm) universal-launcher--stats))))))

(defun universal-launcher--stats-save ()
  "Persist, dropping entries decayed below relevance."
  (when universal-launcher--stats
    (let ((now (float-time)) acc)
      (maphash (lambda (k e)
                 (if (< (universal-launcher--decay e now) 0.05)
                     (remhash k universal-launcher--stats)
                   (push (cons k e) acc)))
               universal-launcher--stats)
      (with-temp-file universal-launcher-frecency-file
        (let ((print-length nil) (print-level nil))
          (prin1 acc (current-buffer)))))))

(add-hook 'kill-emacs-hook #'universal-launcher--stats-save)

(defun universal-launcher--record (cand)
  (unless (memq (get-text-property 0 'ul-type cand) '(kill window))
    (let* ((k (substring-no-properties cand))
           (now (float-time))
           (e (gethash k universal-launcher--stats)))
      (puthash k (cons (1+ (if e (universal-launcher--decay e now) 0)) now)
               universal-launcher--stats))
    (when (timerp universal-launcher--save-timer)
      (cancel-timer universal-launcher--save-timer))
    (setq universal-launcher--save-timer
          (run-with-idle-timer 10 nil #'universal-launcher--stats-save))))

(defun universal-launcher--scores ()
  "Snapshot KEY -> current score for this popup."
  (let ((now (float-time)) (h (make-hash-table :test #'equal)))
    (maphash (lambda (k e) (puthash k (universal-launcher--decay e now) h))
             universal-launcher--stats)
    h))

;;;; Calculator and unit conversion

(defconst universal-launcher--math-re
  (rx bos (+ (or (any "0-9" ?- ?+ ?* ?/ ?^ ?% ?! ?\( ?\) ?. ?, ?\s ?× ?÷)
                 "sin" "cos" "tan" "sqrt" "exp" "ln" "log" "pi"))
      eos))

(defconst universal-launcher--number-re
  (rx bos (? "-") digit (* (any digit ".")) (? "e" (? (any "-+")) (+ digit)) eos))

(defconst universal-launcher--convert-re
  (rx bos (group (? "-") (any digit ".") (*? anything))
      (+ space) (or "to" "in" "->" "=>") (+ space)
      (group (+ (not space))) eos))

(defun universal-launcher--math-p (s)
  (and (string-match-p universal-launcher--math-re s)
       (string-match-p "[0-9]" s)
       (string-match-p (rx (or (any ?- ?+ ?* ?/ ?^ ?% ?! ?× ?÷)
                               "sin" "cos" "tan" "sqrt" "exp" "ln" "log"))
                       s)))

(defun universal-launcher--calc (s)
  "Evaluate S with calc; a number string, or nil."
  (when (universal-launcher--math-p s)
    (let ((expr (string-replace "×" "*" (string-replace "÷" "/" s))))
      ;; Thousands separators: calc reads "1,000" as a vector.
      (while (string-match "\\([0-9]\\),\\([0-9]\\{3\\}\\)" expr)
        (setq expr (replace-match "\\1\\2" t nil expr)))
      (let ((r (ignore-errors (calc-eval expr))))   ; parse error => list
        (and (stringp r) (string-match-p universal-launcher--number-re r) r)))))

(defun universal-launcher--trim-float (s)
  (if (string-suffix-p "." s) (substring s 0 -1) s))

(defun universal-launcher--convert (s)
  "Evaluate \"QTY UNITS to UNITS\" with calc-units; (NUMBER . UNITS) or nil."
  (when (string-match universal-launcher--convert-re s)
    (let ((from (match-string 1 s)) (to (match-string 2 s)))
      (require 'calc-units)
      (ignore-errors
        (let ((expr (math-read-expr from)) (new (math-read-expr to)))
          (when (and (not (eq (car-safe expr) 'error)) (not (eq (car-safe new) 'error))
                     (math-units-in-expr-p expr nil) (math-units-in-expr-p new nil)
                     (math-consistent-units-p expr new))
            (let* ((u (math-single-units-in-expr-p expr))
                   (temp-p (lambda (sym) (nth 3 (assq sym math-standard-units))))
                   ;; Temperatures are affine: 0 degC is not 0 degF.
                   (r (math-simplify-units
                       (if (and (consp u) (funcall temp-p (car u))
                                (eq (car-safe new) 'var) (funcall temp-p (nth 1 new)))
                           (math-convert-temperature
                            expr (list 'var (car u) (intern (format "var-%s" (car u)))) new)
                         (math-convert-units expr new)))))
              (cons (universal-launcher--trim-float
                     (math-format-value (math-float (calc-normalize (math-remove-units r)))))
                    to))))))))

;;;; Dynamic candidates

(defconst universal-launcher--url-re
  (rx bos (or "http://" "https://" "www.") (+ (not space)) eos))

(defconst universal-launcher--domain-re
  (rx bos (+ (any alnum ?-)) (* "." (+ (any alnum ?-))) "." (>= 2 alpha)
      (? (any "/:?#") (* (not space))) eos))

(defun universal-launcher--dyn (input type group payload text)
  (propertize text 'ul-type type 'ul-payload payload 'ul-input input
              'ul-group (universal-launcher--title group)))

(defun universal-launcher--engine (name)
  (assoc name universal-launcher-search-engines))

(defun universal-launcher--dynamic (input)
  "Candidates derived from INPUT, as (TOP . BOTTOM)."
  (let ((s (string-trim input)) top bottom)
    (unless (string-empty-p s)
      (when-let* ((r (universal-launcher--calc s)))
        (push (universal-launcher--dyn
               s 'calc "Calculate" r
               (concat s (propertize " = " 'face 'universal-launcher-dim)
                       (propertize r 'face 'universal-launcher-result)))
              top))
      (when-let* ((r (universal-launcher--convert s)))
        (push (universal-launcher--dyn
               s 'calc "Calculate" (car r)
               (concat s (propertize " = " 'face 'universal-launcher-dim)
                       (propertize (car r) 'face 'universal-launcher-result)
                       " " (cdr r)))
              top))
      (cond
       ((string-match-p universal-launcher--url-re s)
        (push (universal-launcher--dyn
               s 'url "Search" (if (string-prefix-p "www." s) (concat "https://" s) s)
               (concat (propertize "Open: " 'face 'universal-launcher-dim) s))
              top))
       ((and (string-match "\\`!\\(\\S-+\\)\\s-+\\(.+\\)" s)
             (cl-find (match-string 1 s) universal-launcher-search-engines
                      :key #'cadr :test #'string=))
        (let* ((e (cl-find (match-string 1 s) universal-launcher-search-engines
                           :key #'cadr :test #'string=))
               (q (match-string 2 s)))
          (push (universal-launcher--dyn
                 s 'search "Search" (cons (car e) q)
                 (concat (propertize (format "Search %s: " (car e))
                                     'face 'universal-launcher-dim)
                         q))
                top)))
       (t
        (when (string-match-p universal-launcher--domain-re s)
          (push (universal-launcher--dyn
                 s 'url "Search" (concat "https://" s)
                 (concat (propertize "Open: " 'face 'universal-launcher-dim) "https://" s))
                bottom))
        (push (universal-launcher--dyn
               s 'search "Search" (cons universal-launcher-default-search-engine s)
               (concat (propertize (format "Search %s: " universal-launcher-default-search-engine)
                                   'face 'universal-launcher-dim)
                       s))
              bottom)
        (push (universal-launcher--dyn
               s 'pick "Search" s
               (concat (propertize "Search with…: " 'face 'universal-launcher-dim) s))
              bottom))))
    (cons (nreverse top) (nreverse bottom))))

;;;; Completion style
;; Static candidates go through the user's `completion-styles'; dynamic
;; ones are spliced around the result, unfiltered.  Frecency reorders.

(defvar universal-launcher--static nil "Static candidates of the active popup.")
(defvar universal-launcher--live nil "Dynamic candidates for the current input.")
(defvar universal-launcher--score-table nil "KEY -> score, snapshotted per popup.")
(defvar universal-launcher--frequent-cache nil)

(defun universal-launcher--rank (cands &optional input)
  "Order CANDS by (TIER, -FRECENCY, LENGTH), stably.
TIER compares the first token of INPUT with the candidate's name (the text
after `Prefix: '): 0 prefix, 1 word start, 2 elsewhere.  Without INPUT,
frecency alone decides.  Orderless filters; this decides what RET hits."
  (let* ((tok (car (split-string (or input "") nil t)))
         (n (length tok))
         (re (and tok (concat "[^[:alnum:]]" (regexp-quote tok))))
         (case-fold-search t)
         (keyed
          (mapcar
           (lambda (c)
             (let* ((i (string-search ": " c))
                    (start (if i (+ i 2) 0))
                    (tier (cond ((null tok) 0)
                                ((eq t (compare-strings tok nil nil c start (+ start n) t)) 0)
                                ((string-match-p re c start) 1)
                                (t 2))))
               (list tier (- (gethash c universal-launcher--score-table 0))
                     (- (length c) start) c)))
           cands)))
    (mapcar #'cadddr
            (sort keyed (lambda (a b)
                          (cond ((/= (car a) (car b)) (< (car a) (car b)))
                                ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
                                (t (< (caddr a) (caddr b)))))))))

(defun universal-launcher--frequent ()
  (with-memoization universal-launcher--frequent-cache
    (let ((title (universal-launcher--title "Frequent")))
      (mapcar (lambda (c)
                (setq c (copy-sequence c))
                (put-text-property 0 (length c) 'ul-group title c)
                c)
              (take universal-launcher-frequent-count
                    (universal-launcher--rank
                     (cl-remove-if-not
                      (lambda (c) (gethash c universal-launcher--score-table))
                      universal-launcher--static)))))))

(defun universal-launcher--style-try (string _table pred point)
  (completion-try-completion string universal-launcher--static pred point))

(defun universal-launcher--style-all (string _table pred point)
  (let ((res
         (if (string-empty-p string)
             (progn (setq universal-launcher--live nil)
                    (append (universal-launcher--frequent) universal-launcher--static 0))
           (let* ((dyn (universal-launcher--dynamic string))
                  (all (completion-all-completions
                        string universal-launcher--static pred point))
                  (last (last all)))
             (when last (setcdr last nil))   ; strip base-size; ours is 0
             (setq universal-launcher--live (append (car dyn) (cdr dyn)))
             (nconc (car dyn) (universal-launcher--rank all string) (cdr dyn) 0)))))
    (and (consp res) res)))                  ; (nconc nil ... 0) => 0

(add-to-list 'completion-styles-alist
             '(universal-launcher universal-launcher--style-try universal-launcher--style-all
               "User styles for static candidates, plus input-derived ones."))

;;;; Completion table

(defun universal-launcher--group (cand transform)
  (if transform cand (get-text-property 0 'ul-group cand)))

(defun universal-launcher--affix (cands)
  "Called by Vertico for visible rows only, so icon cost is O(screen)."
  (mapcar (lambda (c)
            (let ((type (get-text-property 0 'ul-type c)))
              (list c
                    (concat (if (eq type 'file)
                                (nerd-icons-icon-for-file (get-text-property 0 'ul-payload c)
                                                          :face 'universal-launcher-file)
                              (alist-get type universal-launcher--type-icons ""))
                            " ")
                    "")))
          cands))

(defun universal-launcher--table (string pred action)
  (if (eq action 'metadata)
      '(metadata (category . universal-launcher)
                 (group-function . universal-launcher--group)
                 (affixation-function . universal-launcher--affix)
                 (display-sort-function . identity)
                 (cycle-sort-function . identity))
    (complete-with-action action universal-launcher--static string pred)))

;;;; Web search

(defvar universal-launcher--last-search-engine nil)

(defun universal-launcher--search (engine query)
  "Open QUERY on ENGINE (a name in `universal-launcher-search-engines')."
  (setq universal-launcher--last-search-engine engine)
  (browse-url (concat (nth 2 (universal-launcher--engine engine))
                      (url-hexify-string query))))

(defun universal-launcher--web-search (query)
  "Pick an engine, then search QUERY.  URLs open directly."
  (interactive
   (list (if (use-region-p)
             (buffer-substring-no-properties (region-beginning) (region-end))
           (read-string "Search: " (thing-at-point 'symbol t)))))
  (if (string-match-p universal-launcher--url-re query)
      (browse-url (if (string-prefix-p "www." query) (concat "https://" query) query))
    (let ((def (or universal-launcher--last-search-engine
                   universal-launcher-default-search-engine)))
      (universal-launcher--search
       (completing-read (format-prompt "Search engine" def)
                        (mapcar #'car universal-launcher-search-engines)
                        nil t nil nil def)
       query))))

;;;; Dispatch

(defun universal-launcher--execute (cand)
  (let ((payload (get-text-property 0 'ul-payload cand)))
    (pcase (get-text-property 0 'ul-type cand)
      ('buffer   (when (buffer-live-p payload) (switch-to-buffer payload)))
      ('window   (universal-launcher--sway (format "[con_id=%d] focus" payload)))
      ((or 'app 'command) (universal-launcher--spawn payload))
      ('file     (find-file payload))
      ('bookmark (browse-url payload))
      ('url      (browse-url payload))
      ('search   (universal-launcher--search (car payload) (cdr payload)))
      ('pick     (universal-launcher--web-search payload))
      ('calc     (kill-new payload)
                 (message "%s  %s" cand (propertize "(copied)" 'face 'universal-launcher-dim)))
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

;;;###autoload
(defun universal-launcher-popup ()
  "Launch anything.  The selected row is what RET does: calculator,
conversion, URL and search rows appear as you type.  `!bang query'
targets an engine.  M-RET submits raw input (calc, else default search)."
  (interactive)
  (universal-launcher--stats-load)
  (let* ((universal-launcher--static (universal-launcher--collect))
         (universal-launcher--score-table (universal-launcher--scores))
         (universal-launcher--frequent-cache nil)
         (universal-launcher--live nil)
         (sel (minibuffer-with-setup-hook
                  (lambda ()
                    (setq-local completion-ignore-case t)
                    (setq-local completion-category-overrides
                                (cons '(universal-launcher (styles universal-launcher))
                                      completion-category-overrides)))
                (completing-read "Launch: " #'universal-launcher--table
                                 nil nil nil 'universal-launcher-history)))
         (cand (and (not (string-empty-p sel))
                    (or (car (member sel universal-launcher--live))
                        (car (member sel universal-launcher--static))
                        ;; M-RET: raw input, which matches no row.
                        (let ((d (universal-launcher--dynamic sel)))
                          (car (append (car d) (cdr d))))))))
    (when cand
      (if-let* ((input (get-text-property 0 'ul-input cand)))
          ;; Dynamic: M-p should recall what you typed, not "2+2 = 4".
          (when (equal (car universal-launcher-history) sel)
            (setcar universal-launcher-history input))
        (universal-launcher--record cand))
      (universal-launcher--execute cand))))

(defun universal-launcher--ssh-connect (host)
  "Connect to SSH HOST using best available terminal."
  (cond
   ((fboundp 'vterm)
    (let* ((buffer-name (format "*ssh-%s*" host))
           (existing-buffer (get-buffer buffer-name)))
      (if existing-buffer
          (progn (switch-to-buffer existing-buffer) (delete-other-windows))
        (let ((buf (vterm buffer-name)))
          (with-current-buffer buf
            (vterm-send-string (format "ssh %s" host))
            (vterm-send-return))
          (switch-to-buffer buf)
          (delete-other-windows)))))
   ((fboundp 'eshell)
    (let ((buffer (generate-new-buffer (format "*ssh-%s*" host))))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (eshell-mode)
      (insert (format "ssh %s" host))
      (eshell-send-input)))
   (t
    (let ((buffer (get-buffer-create (format "*ssh-%s*" host))))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (unless (comint-check-proc buffer)
        (shell buffer))
      (goto-char (point-max))
      (insert (format "ssh %s" host))
      (comint-send-input)))))

;; Pay every cold cost once, while idle: sources, calc, the units table.
(run-with-idle-timer
 2 nil
 (lambda ()
   (let ((inhibit-message t))
     (universal-launcher--stats-load)
     (universal-launcher--collect)
     (calc-eval "1+1")
     (require 'calc-units)
     (math-build-units-table))))

(provide 'universal-launcher)
;;; universal-launcher.el ends here
