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
;;          what RET does.
;;
;; Ranking: learned choice for this exact input, then match quality (name
;; prefix > word start or initials > infix), then frecency, then length.
;; An empty prompt opens on a "Frequent" group.
;;
;; Two entry points:
;;   `universal-launcher-popup'  in the selected frame (bind it in Emacs).
;;   `universal-launcher-float'  a persistent hidden minibuffer-only frame,
;;                               shown floating on whatever workspace you are
;;                               on; outside actions (apps, URLs, copies)
;;                               happen there, Emacs actions focus Emacs.
;;   `universal-launcher-tabs'   the floating frame with browser tabs only;
;;                               `universal-launcher-tabs-bookmark' bookmarks.
;; Sway (Emacs draws the border, so sway draws none):
;;   for_window [title="^ul-launcher$"] floating enable, sticky enable, border none, move position center
;;   bindsym $mod+space exec emacsclient -n -e '(universal-launcher-float)'
;;   bindsym $mod+Shift+b exec emacsclient -n -e '(universal-launcher-tabs)'
;;   bindsym Ctrl+Shift+b exec emacsclient -n -e '(universal-launcher-tabs-bookmark)'
;; Tabs need Chromium started with --remote-debugging-port, matching
;; `universal-launcher-browser-debug-port'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'recentf)
(require 'nerd-icons)
(recentf-mode 1)

(autoload 'url-hexify-string "url-util")
(defvar org-agenda-files)
(defvar org-capture-templates)
(defvar orderless-matching-styles)
(defvar vertico-count)
(defvar math-standard-units)
(defvar embark-transformer-alist)
(defvar embark-keymap-alist)
(defvar embark-pre-action-hooks)
(defvar embark-general-map)
(defvar embark-url-map)
(declare-function org-agenda-files "org")
(declare-function org-map-entries "org")
(declare-function org-get-heading "org")
(declare-function org-get-todo-state "org")
(declare-function org-fold-show-context "org-fold")
(declare-function org-capture "org-capture")
(declare-function org-find-olp "org")
(declare-function org-current-level "org")
(declare-function org-get-outline-path "org")
(declare-function org-link-make-string "ol")
(declare-function outline-next-heading "outline")
(declare-function org-end-of-subtree "org")
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
(defface universal-launcher-pass    '((t :foreground "#d4ccb4")) "Password icon.")
(defface universal-launcher-power   '((t :foreground "#cdacac")) "Power icon.")
(defface universal-launcher-script  '((t :foreground "#b8c4b8")) "Script icon.")
(defface universal-launcher-capture '((t :foreground "#b4c4bc")) "Capture icon.")
(defface universal-launcher-tab     '((t :foreground "#b4c0c8")) "Browser tab icon.")
(defface universal-launcher-border  '((t :background "#515761"))
  "Border of the floating launcher; only the background is used.")

;;;; Configuration

(defvar universal-launcher-sources
  '(("Context"      universal-launcher--actions)
    ("Capture"      universal-launcher--captures  universal-launcher--captures-key)
    ("Active"       universal-launcher--buffers)
    ("Active"       universal-launcher--windows)
    ("Tasks"        universal-launcher--tasks     universal-launcher--tasks-key)
    ("Files & Apps" universal-launcher--files     universal-launcher--files-key)
    ("Files & Apps" universal-launcher--apps      universal-launcher--apps-key)
    ("Web"          universal-launcher--bookmarks universal-launcher--bookmarks-key)
    ("Passwords"    universal-launcher--passwords universal-launcher--passwords-key)
    ("System"       universal-launcher--scripts   universal-launcher--scripts-key)
    ("System"       universal-launcher--ssh-hosts universal-launcher--ssh-key)
    ("System"       universal-launcher--commands  universal-launcher--commands-key)
    ("Power"        universal-launcher--power     universal-launcher--power-key)
    ("Clipboard"    universal-launcher--cliphist  universal-launcher--cliphist-key)
    ("Clipboard"    universal-launcher--kill-ring)
    ("Tools"        universal-launcher--emojis    ignore))
  "List of (GROUP FETCH KEY).  `ignore' as KEY means compute once.")

(defcustom universal-launcher-bookmarks-file "~/org/bookmarks.org"
  "Org file scanned for URLs." :type 'file)

(defcustom universal-launcher-browser-debug-port 9222
  "Port of a Chromium-family browser started with --remote-debugging-port.
Tabs are read from its DevTools HTTP endpoint; nil disables the source."
  :type '(choice (const nil) natnum))

(defcustom universal-launcher-browser-app-ids
  '("chromium" "Chromium" "chromium-browser" "google-chrome" "brave-browser")
  "Sway app_ids the browser window may have, for raising it after a switch."
  :type '(repeat string))

(defcustom universal-launcher-scripts-directory "~/.config/scripts"
  "Every executable here becomes a `Script:' row." :type 'directory)

(defcustom universal-launcher-pass-command "pass -c %s"
  "Shell command copying a pass entry; %s is the shell-quoted entry."
  :type 'string)

(defcustom universal-launcher-pass-username-fields '("username" "user" "login" "email")
  "Fields of a pass entry tried, in order, for its username." :type '(repeat string))

(defcustom universal-launcher-pass-url-fields '("url" "website")
  "Fields of a pass entry tried, in order, for its URL.  Without one, the
first path component that looks like a domain is used (web/github.com)."
  :type '(repeat string))

(defcustom universal-launcher-cliphist-limit 100
  "Newest cliphist entries offered." :type 'natnum)

(defcustom universal-launcher-power-actions
  '(("Lock"              "swaylock -f -c 1a1d21" nil)
    ("Suspend"           "loginctl suspend" nil)
    ("Log out"           "swaymsg exit" t)
    ("Reboot"            "loginctl reboot" t)
    ("Power off"         "loginctl poweroff" t)
    ("Screenshot region" "grim -g \"$(slurp)\" - | wl-copy -t image/png" nil)
    ("Screenshot screen"
     "mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/$(date +%F_%H-%M-%S).png"
     nil))
  "Entries (NAME SHELL-COMMAND CONFIRM).  `loginctl' works under both
systemd and elogind (Guix)."
  :type '(repeat (list string string boolean)))

(defcustom universal-launcher-command-exclude
  '("reboot" "poweroff" "halt" "shutdown" "suspend" "hibernate")
  "PATH names never offered as `Run:' rows.  The Power group covers them,
with confirmation; one stray RET on a raw `reboot' must not be possible."
  :type '(repeat string))

(defcustom universal-launcher-frecency-half-life (* 7 86400)
  "Seconds for a launch's weight to halve." :type 'number)

(defcustom universal-launcher-frequent-count 8
  "Rows in the Frequent group shown on an empty prompt.  0 disables."
  :type 'natnum)

(defcustom universal-launcher-frecency-file
  (locate-user-emacs-file "universal-launcher-frecency.eld")
  "Where launch statistics persist." :type 'file)

(defcustom universal-launcher-frame-parameters
  '((name . "ul-launcher") (title . "ul-launcher") (minibuffer . only)
    (width . 100) (undecorated . t) (vertical-scroll-bars)
    (menu-bar-lines . 0) (tool-bar-lines . 0) (tab-bar-lines . 0)
    (unsplittable . t) (no-other-frame . t) (skip-taskbar . t)
    (background-color . "#1a1d21") (foreground-color . "#f0efeb"))
  "Parameters of the floating launcher frame.  Height follows `vertico-count';
border and padding come from `universal-launcher-border-width' and
`universal-launcher-padding'.  The title is what the sway rule matches."
  :type '(alist :key-type symbol :value-type sexp))

(defcustom universal-launcher-border-width 1
  "Pixels of border around the floating launcher, colored by the
`universal-launcher-border' face.  Emacs draws it (as the frame's internal
border), so set the sway rule to `border none'.  0 for no border."
  :type 'natnum)

(defcustom universal-launcher-padding 14
  "Pixels between the border and the text.  Left and right are fringes;
the top is a spacer line above the prompt."
  :type 'natnum)

(defcustom universal-launcher-hide-on-blur t
  "Close the floating launcher when it loses focus." :type 'boolean)

(defcustom universal-launcher-mode-actions
  '((org-mode nil "Org"
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
is (NAME . COMMAND) or (NAME . SHELL-STRING).  Unbound commands are hidden.
Context is the buffer of the main frame, also when launched floating."
  :type 'sexp)

(defcustom universal-launcher-custom-actions nil
  "Global actions: (NAME . COMMAND), (NAME . SHELL-STRING),
or the old form (NAME . (TYPE . ACTION))."
  :type 'sexp)

(defcustom universal-launcher-default-search-engine "4get"
  "Engine used by the plain \"Search\" candidate."
  :type 'string)

(defcustom universal-launcher-search-engines
  '(("DuckDuckGo"        "d"     "https://duckduckgo.com/?q=")
    ("Google"            "g"     "https://www.google.com/search?q=")
    ("Claude" "c"  "https://claude.ai/new?q=")
    ("Gemini" "ge" "https://gemini.google.com/app?q=")
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
      (tab      . ,(i #'nerd-icons-mdicon  "nf-md-tab"            'universal-launcher-tab))
      (app      . ,(i #'nerd-icons-faicon  "nf-fa-cube"           'universal-launcher-app))
      (command  . ,(i #'nerd-icons-octicon "nf-oct-terminal"      'universal-launcher-command))
      (script   . ,(i #'nerd-icons-mdicon  "nf-md-script_text"    'universal-launcher-script))
      (bookmark . ,(i #'nerd-icons-octicon "nf-oct-bookmark"      'universal-launcher-bookmark))
      (ssh      . ,(i #'nerd-icons-faicon  "nf-fa-server"         'universal-launcher-ssh))
      (task     . ,(i #'nerd-icons-octicon "nf-oct-checklist"     'universal-launcher-task))
      (capture  . ,(i #'nerd-icons-mdicon  "nf-md-note_plus"      'universal-launcher-capture))
      (kill     . ,(i #'nerd-icons-faicon  "nf-fa-clipboard"      'universal-launcher-kill))
      (clip     . ,(i #'nerd-icons-mdicon  "nf-md-clipboard_text" 'universal-launcher-kill))
      (pass     . ,(i #'nerd-icons-mdicon  "nf-md-key"            'universal-launcher-pass))
      (power    . ,(i #'nerd-icons-mdicon  "nf-md-power"          'universal-launcher-power))
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
          (g #'nerd-icons-mdicon  "nf-md-note_plus"      'universal-launcher-capture  "Capture")
          (g #'nerd-icons-mdicon  "nf-md-view_dashboard" 'universal-launcher-buffer   "Active")
          (g #'nerd-icons-octicon "nf-oct-checklist"     'universal-launcher-task     "Tasks")
          (g #'nerd-icons-mdicon  "nf-md-apps"           'universal-launcher-app      "Files & Apps")
          (g #'nerd-icons-mdicon  "nf-md-web"            'universal-launcher-bookmark "Web")
          (g #'nerd-icons-mdicon  "nf-md-lock"           'universal-launcher-pass     "Passwords")
          (g #'nerd-icons-mdicon  "nf-md-cog"            'universal-launcher-command  "System")
          (g #'nerd-icons-mdicon  "nf-md-power"          'universal-launcher-power    "Power")
          (g #'nerd-icons-mdicon  "nf-md-clipboard_text" 'universal-launcher-kill     "Clipboard")
          (g #'nerd-icons-mdicon  "nf-md-hammer_wrench"  'universal-launcher-emoji    "Tools")
          (g #'nerd-icons-octicon "nf-oct-search"        'universal-launcher-search   "Search")
          (g #'nerd-icons-mdicon  "nf-md-tab"            'universal-launcher-tab      "Tabs"))))

(defun universal-launcher--title (group)
  (or (cdr (assoc group universal-launcher--group-titles))
      (propertize group 'face 'universal-launcher-group)))

;;;; Primitives

(defvar universal-launcher--floating nil "Non-nil while a floating session runs.")
(defvar universal-launcher--main nil "The Emacs frame Emacs-side actions target.")
(defvar universal-launcher--frame nil "The floating launcher frame, once created.")
(defvar universal-launcher--prompt "Launch: " "Prompt of the current popup.")
(defvar universal-launcher--dynamic-rows t
  "Nil in scoped popups (tabs only): no calculator, URL or search rows.")
(defvar universal-launcher--shown nil
  "Whether the launcher frame is shown, by our own account.  Not
`frame-visible-p': on pgtk a hide completes asynchronously, so it still
answers t right after `make-frame-invisible'.")
(defvar universal-launcher--content-height nil
  "Largest measured pixel height of the launcher's content, spacer included.
Lines holding icons are taller than `frame-char-height' (icon fonts have
their own metrics), so the height is measured, not computed.")

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

(defun universal-launcher--tree-stamp (dir)
  "Mtimes of DIR and every directory below it (an entry added anywhere
changes its parent's mtime).  Dotted directories are skipped."
  (let ((file-name-handler-alist nil) acc)
    (when (file-directory-p dir)
      (cl-labels ((walk (d)
                    (push (file-attribute-modification-time (file-attributes d)) acc)
                    (dolist (f (directory-files d t "\\`[^.]" t))
                      (when (file-directory-p f) (walk f)))))
        (walk dir)))
    acc))

(defun universal-launcher--sway (cmd)
  (call-process "swaymsg" nil 0 nil cmd))

(defun universal-launcher--sh (cmd)
  "Run shell CMD detached, without a window manager in between."
  (call-process "sh" nil 0 nil "-c" cmd))

(defun universal-launcher--spawn (cmd)
  "Run shell CMD detached.  Under sway, sway is the parent, so its first
window lands on the workspace focused now."
  (if (getenv "SWAYSOCK")
      (universal-launcher--sway (concat "exec " cmd))
    (call-process "setsid" nil 0 nil "-f" "sh" "-c" cmd)))

(defun universal-launcher--copy (s)
  "Put S on the kill ring and the system clipboard.
On Wayland a client may set the selection only while focused; wl-copy
owns it independently, so this works after the launcher has hidden."
  (if (and (getenv "WAYLAND_DISPLAY") (executable-find "wl-copy"))
      (let ((interprogram-cut-function nil))
        (kill-new s)
        (let ((p (make-process :name "wl-copy" :command '("wl-copy")
                               :connection-type 'pipe :noquery t)))
          (process-send-string p s)
          (process-send-eof p)))
    (kill-new s)))

;;;; Volatile sources (every popup; all cheap)

(defun universal-launcher--buffers ()
  (cl-loop for b in (buffer-list)
           for name = (buffer-name b)
           unless (string-prefix-p " " name)
           collect (universal-launcher--cand "Buffer" name 'buffer b)))

(defun universal-launcher--sway-views ()
  "Every sway view as (:id ID :app APP :name TITLE :pid PID), one get_tree."
  (when (getenv "SWAYSOCK")
    (with-temp-buffer
      (when (eq 0 (call-process "swaymsg" nil t nil "-r" "-t" "get_tree"))
        (goto-char (point-min))
        (let (acc)
          (cl-labels
              ((walk (n)
                 (when (plist-get n :pid)
                   (push (list :id (plist-get n :id) :pid (plist-get n :pid)
                               :name (or (plist-get n :name) "")
                               :app (or (plist-get n :app_id)
                                        (plist-get (plist-get n :window_properties) :class)
                                        "?"))
                         acc))
                 (mapc #'walk (plist-get n :nodes))
                 (mapc #'walk (plist-get n :floating_nodes))))
            (walk (json-parse-buffer :object-type 'plist :null-object nil)))
          (nreverse acc))))))

(defun universal-launcher--windows ()
  (cl-loop for v in (universal-launcher--sway-views)
           for app = (plist-get v :app)
           unless (string-match-p "\\`[Ee]macs\\b" app)   ; emacs, emacs-pgtk
           collect (universal-launcher--cand
                    "Window"
                    (format "%s  %s %s" app (plist-get v :name)
                            (propertize (format "#%d" (plist-get v :id))
                                        'face 'universal-launcher-dim))
                    'window (plist-get v :id))))

;;;; Browser tabs (Chrome DevTools HTTP endpoint, spoken directly)

(defvar universal-launcher--tabs-cache nil
  "Tabs from the last fetch, as plists (:id :title :url ...).")

(defun universal-launcher--cdp (method path)
  "Send METHOD PATH to the DevTools HTTP endpoint; return the body or nil.
Raw HTTP over a socket: no curl process.  HTTP/1.1, because Chromium's
DevTools server closes HTTP/1.0 connections without answering.  Refused (no
browser) fails at once; a stalled endpoint gives up after half a second."
  (when universal-launcher-browser-debug-port
    (let ((buf (generate-new-buffer " *ul-cdp*")) proc)
      (unwind-protect
          (condition-case nil
              (progn
                (setq proc (make-network-process
                            :name "ul-cdp" :buffer buf :host "127.0.0.1"
                            :service universal-launcher-browser-debug-port
                            :noquery t
                            ;; The default sentinel writes "connection broken"
                            ;; into the buffer, after the body.
                            :sentinel #'ignore
                            ;; -unix: plain utf-8 decodes as -dos here and
                            ;; eats the CRs that delimit the HTTP headers.
                            :coding '(utf-8-unix . utf-8-unix)))
                ;; DevTools only answers Host: localhost or an IP.
                (process-send-string
                 proc (format (concat "%s %s HTTP/1.1\r\nHost: localhost\r\n"
                                      "Connection: close\r\nContent-Length: 0\r\n\r\n")
                              method path))
                (let ((deadline (+ (float-time) 0.5)) body)
                  (while (and (not body) (< (float-time) deadline))
                    (accept-process-output proc 0.02)
                    (with-current-buffer buf
                      (goto-char (point-min))
                      (when (re-search-forward "\r\n\r\n" nil t)
                        (let* ((start (point))
                               (len (save-excursion
                                     (goto-char (point-min))
                                     (and (re-search-forward
                                           "^content-length: *\\([0-9]+\\)" start t)
                                          (string-to-number (match-string 1))))))
                          ;; Done when Content-Length bytes arrived, or the
                          ;; server closed: keep-alive must not cost the deadline.
                          (when (or (and len (>= (- (position-bytes (point-max))
                                                    (position-bytes start))
                                                 len))
                                    (not (process-live-p proc)))
                            (setq body (buffer-substring-no-properties
                                        start
                                        (if len
                                            (or (byte-to-position (+ (position-bytes start) len))
                                                (point-max))
                                          (point-max)))))))))
                  body))
            (error nil))
        (when proc (delete-process proc))
        (kill-buffer buf)))))

(defun universal-launcher--tabs ()
  "Open browser pages, fetched fresh each time (about a millisecond).
Only in the tabs popups: the main launcher never touches the browser."
  (let ((tabs (when-let* ((body (universal-launcher--cdp "GET" "/json/list")))
                (cl-loop for tab in (ignore-errors
                                      (json-parse-string body :object-type 'plist
                                                         :array-type 'list))
                         when (and (equal (plist-get tab :type) "page")
                                   (not (string-match-p "\\`\\(devtools\\|chrome-extension\\)://"
                                                        (or (plist-get tab :url) ""))))
                         collect tab))))
    (setq universal-launcher--tabs-cache tabs)
    (mapcar (lambda (tab)
              (let ((url (plist-get tab :url)))
                (universal-launcher--cand
                 "Tab"
                 (concat (let ((title (plist-get tab :title)))
                           (if (string-empty-p title) url title))
                         "  "
                         (propertize (truncate-string-to-width
                                      (replace-regexp-in-string "\\`https?://\\(www\\.\\)?" "" url)
                                      60 nil nil "…")
                                     'face 'universal-launcher-dim))
                 'tab tab)))
            tabs)))

(defun universal-launcher--tab-by-url (url)
  (seq-find (lambda (tab) (equal (plist-get tab :url) url)) universal-launcher--tabs-cache))

(defun universal-launcher--focus-browser (title &optional tries)
  "Raise the browser window now showing TITLE.  The window title follows
the active tab a moment after activation, so poll briefly; failing that,
raise any browser window."
  (let* ((ids universal-launcher-browser-app-ids)
         (view (seq-find (lambda (v) (and (member (plist-get v :app) ids)
                                          (string-prefix-p title (plist-get v :name))))
                         (universal-launcher--sway-views))))
    (cond
     (view (universal-launcher--sway (format "[con_id=%d] focus" (plist-get view :id))))
     ((< (or tries 0) 6)
      (run-at-time 0.05 nil #'universal-launcher--focus-browser title (1+ (or tries 0))))
     (t (universal-launcher--sway
         (format "[app_id=\"^(%s)$\"] focus"
                 (mapconcat #'universal-launcher--pcre-quote ids "|")))))))

(defun universal-launcher--tab-switch (tab)
  (universal-launcher--cdp "POST" (concat "/json/activate/" (plist-get tab :id)))
  (when (getenv "SWAYSOCK")
    (universal-launcher--focus-browser (plist-get tab :title))))

(defun universal-launcher--kill-ring ()
  "Kill ring, inserted at point.  Only inside Emacs: floating, there is
no point to insert at, and cliphist already holds what Emacs copied."
  (unless universal-launcher--floating
    (cl-loop for item in kill-ring
             for i from 1 to 15
             when (and (stringp item) (string-match-p "[^[:space:]]" item))
             collect (universal-launcher--cand
                      (format "Kill %d" i)
                      (truncate-string-to-width
                       (string-replace "\n" " ↩ " (substring-no-properties item))
                       60 nil nil "…")
                      'kill item))))

(defun universal-launcher--mode-match-p (modes)
  (or (eq modes t)
      (cl-some (lambda (m) (provided-mode-derived-p major-mode m))
               (ensure-list modes))))

(defun universal-launcher--actions ()
  "Mode actions for the main frame's buffer, plus custom actions."
  (with-current-buffer (if (frame-live-p universal-launcher--main)
                           (window-buffer (frame-selected-window universal-launcher--main))
                         (current-buffer))
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
      (nreverse acc))))

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

(defun universal-launcher--captures-key ()
  (and (boundp 'org-capture-templates) org-capture-templates))

(defun universal-launcher--captures ()
  "One row per capture template; nested keys show their group's name."
  (let* ((tpls (universal-launcher--captures-key))
         (headers (cl-loop for tp in tpls
                           when (and (consp tp) (stringp (car tp)) (null (nthcdr 2 tp)))
                           collect (cons (car tp) (nth 1 tp)))))
    (cl-loop for tp in tpls
             when (and (consp tp) (stringp (car tp)) (nthcdr 2 tp))
             collect (let* ((key (car tp))
                            (group (and (> (length key) 1)
                                        (cdr (assoc (substring key 0 -1) headers)))))
                       (universal-launcher--cand
                        "Capture" (if group (format "%s › %s" group (nth 1 tp)) (nth 1 tp))
                        'capture key)))))

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

(defun universal-launcher--desktop-keys (beg end)
  "KEY=VALUE pairs between BEG and END; first occurrence wins."
  (save-excursion
    (goto-char beg)
    (let (acc)
      (while (re-search-forward "^\\([A-Za-z0-9-]+\\)[ \t]*=[ \t]*\\(.*\\)$" end t)
        (unless (assoc (match-string 1) acc)
          (push (cons (match-string 1) (match-string 2)) acc)))
      acc)))

(defun universal-launcher--clean-exec (exec)
  "Desktop-spec Exec to a shell command: unescape `\\\\', drop field codes."
  (string-trim (string-replace "%%" "%" (replace-regexp-in-string
                                         "%[fFuUdDnNickvm]" ""
                                         (string-replace "\\\\" "\\" exec) t t))))

(defun universal-launcher--parse-desktop ()
  "Parse the current buffer to ((NAME . EXEC) ...): the entry, then its
Desktop Actions (only those listed in Actions=, per the spec)."
  (goto-char (point-min))
  (let (heads)
    (while (re-search-forward "^\\[\\([^]\n]+\\)\\][ \t]*$" nil t)
      (push (list (match-string 1) (match-end 0) (match-beginning 0)) heads))
    (setq heads (nreverse heads))
    (let ((sections (cl-loop for (title body) in heads
                             for rest on (cdr (append heads '(nil)))
                             collect (cons title (universal-launcher--desktop-keys
                                                  body (if (car rest) (nth 2 (car rest))
                                                         (point-max)))))))
      (let* ((main (cdr (assoc "Desktop Entry" sections)))
             (name (cdr (assoc "Name" main)))
             (exec (cdr (assoc "Exec" main))))
        (when (and name exec
                   (equal (cdr (assoc "Type" main)) "Application")
                   (not (equal (cdr (assoc "NoDisplay" main)) "true"))
                   (not (equal (cdr (assoc "Hidden" main)) "true")))
          (cons (cons name (universal-launcher--clean-exec exec))
                (cl-loop for id in (split-string (or (cdr (assoc "Actions" main)) "") ";" t)
                         for act = (cdr (assoc (concat "Desktop Action " id) sections))
                         for an = (cdr (assoc "Name" act))
                         for ae = (cdr (assoc "Exec" act))
                         when (and an ae)
                         collect (cons (format "%s › %s" name an)
                                       (universal-launcher--clean-exec ae)))))))))

(defun universal-launcher--apps ()
  "Desktop entries and their actions.  First desktop-file ID wins, per
the XDG spec, so a user override (including Hidden=true) shadows it."
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
              (pcase-dolist (`(,name . ,exec) (universal-launcher--parse-desktop))
                (push (universal-launcher--cand "App" name 'app exec) acc)))))))
    (sort acc #'string<)))

(defun universal-launcher--pass-dir ()
  (expand-file-name (or (getenv "PASSWORD_STORE_DIR") "~/.password-store")))

(defun universal-launcher--passwords-key ()
  (universal-launcher--tree-stamp (universal-launcher--pass-dir)))

(defun universal-launcher--passwords ()
  (let ((dir (universal-launcher--pass-dir)) (file-name-handler-alist nil))
    (when (file-directory-p dir)
      (sort (mapcar (lambda (f)
                      (let ((entry (file-name-sans-extension (file-relative-name f dir))))
                        (universal-launcher--cand "Pass" entry 'pass entry)))
                    (directory-files-recursively
                     dir "\\.gpg\\'" nil
                     (lambda (d) (not (string-prefix-p "." (file-name-nondirectory d))))))
            #'string<))))

(defun universal-launcher--scripts-key ()
  (let ((dir (expand-file-name universal-launcher-scripts-directory)))
    (and (file-directory-p dir) (universal-launcher--stamp dir))))

(defun universal-launcher--scripts ()
  (let ((dir (expand-file-name universal-launcher-scripts-directory))
        (file-name-handler-alist nil))
    (when (file-directory-p dir)
      (cl-loop for f in (directory-files dir t "\\`[^.]" )
               when (and (file-regular-p f) (file-executable-p f))
               collect (universal-launcher--cand
                        "Script" (file-name-nondirectory f) 'script
                        (shell-quote-argument f))))))

(defun universal-launcher--power-key () universal-launcher-power-actions)

(defun universal-launcher--power ()
  (mapcar (pcase-lambda (`(,name ,cmd ,confirm))
            (universal-launcher--cand "Power" name 'power (cons cmd confirm)))
          universal-launcher-power-actions))

(defun universal-launcher--cliphist-db ()
  (expand-file-name "cliphist/db" (or (getenv "XDG_CACHE_HOME") "~/.cache")))

(defun universal-launcher--cliphist-key ()
  (and (executable-find "cliphist")
       (universal-launcher--stamp (universal-launcher--cliphist-db))))

(defun universal-launcher--cliphist ()
  "Newest cliphist entries.  The payload is the raw `ID<TAB>preview' line,
which is what `cliphist decode' and `cliphist delete' read."
  (when (executable-find "cliphist")
    (cl-loop for line in (ignore-errors (process-lines "cliphist" "list"))
             for i from 1 to universal-launcher-cliphist-limit
             for tab = (string-search "\t" line)
             when tab
             collect (universal-launcher--cand
                      "Clip"
                      (truncate-string-to-width
                       (string-trim (substring line (1+ tab))) 70 nil nil "…")
                      'clip line))))

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
          (unless (or (gethash name seen) (member name universal-launcher-command-exclude))
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
          ;; Org's grammar: a description runs to the first "]]", so it may
          ;; itself hold brackets ("Vertico [VERTical] docs").
          (while (re-search-forward
                  "\\[\\[\\(https?://[^]]+\\)\\]\\(?:\\[\\(.*?\\)\\]\\)?\\]" nil t)
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

;;;; Frecency and learned choices

(defvar universal-launcher--stats nil
  "KEY -> (SCORE . TIME).  SCORE is decayed to TIME; KEY is candidate text.")

(defvar universal-launcher--learned nil
  "QUERY -> ((KEY SCORE . TIME) ...): what was chosen after typing QUERY.
Every prefix of the typed input is a QUERY, so choosing Firefox after
\"fire\" also teaches \"f\".")

(defvar universal-launcher--save-timer nil)

(defun universal-launcher--decay (entry now)
  (* (car entry) (expt 2.0 (/ (- (cdr entry) now) universal-launcher-frecency-half-life))))

(defun universal-launcher--norm (s)
  (downcase (string-join (split-string s) " ")))

(defun universal-launcher--stats-load ()
  (unless universal-launcher--stats
    (setq universal-launcher--stats (make-hash-table :test #'equal)
          universal-launcher--learned (make-hash-table :test #'equal))
    (when (file-readable-p universal-launcher-frecency-file)
      (with-temp-buffer
        (insert-file-contents universal-launcher-frecency-file)
        (let* ((data (ignore-errors (read (current-buffer))))
               (plist-p (keywordp (car-safe data))))
          (pcase-dolist (`(,k ,s . ,tm) (if plist-p (plist-get data :stats) data))
            (puthash k (cons s tm) universal-launcher--stats))
          (when plist-p
            (pcase-dolist (`(,q . ,entries) (plist-get data :learned))
              (puthash q entries universal-launcher--learned))))))))

(defun universal-launcher--stats-save ()
  "Persist, dropping everything decayed below relevance."
  (when universal-launcher--stats
    (let ((now (float-time)) stats learned)
      (maphash (lambda (k e)
                 (if (< (universal-launcher--decay e now) 0.05)
                     (remhash k universal-launcher--stats)
                   (push (cons k e) stats)))
               universal-launcher--stats)
      (maphash (lambda (q entries)
                 (let ((live (cl-remove-if (lambda (e) (< (universal-launcher--decay (cdr e) now) 0.05))
                                           entries)))
                   (if live
                       (progn (puthash q live universal-launcher--learned)
                              (push (cons q live) learned))
                     (remhash q universal-launcher--learned))))
               universal-launcher--learned)
      (with-temp-file universal-launcher-frecency-file
        (let ((print-length nil) (print-level nil))
          (prin1 (list :stats stats :learned learned) (current-buffer)))))))

(add-hook 'kill-emacs-hook #'universal-launcher--stats-save)

(defun universal-launcher--bump (entry now)
  (cons (1+ (if entry (universal-launcher--decay entry now) 0)) now))

(defun universal-launcher--record (cand input)
  "Count a launch of CAND, chosen after typing INPUT."
  (unless (memq (get-text-property 0 'ul-type cand) '(kill window clip tab))
    (let ((k (substring-no-properties cand))
          (q (universal-launcher--norm (or input "")))
          (now (float-time)))
      (puthash k (universal-launcher--bump (gethash k universal-launcher--stats) now)
               universal-launcher--stats)
      (dotimes (i (min (length q) 24))
        (let* ((p (substring q 0 (1+ i)))
               (entries (gethash p universal-launcher--learned))
               (e (assoc k entries)))
          (if e
              (setcdr e (universal-launcher--bump (cdr e) now))
            (push (cons k (universal-launcher--bump nil now)) entries))
          (puthash p entries universal-launcher--learned))))
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

(defun universal-launcher--learned-for (input)
  "KEY -> score of choices made after typing INPUT, or nil."
  (when-let* ((entries (and universal-launcher--learned
                            (gethash (universal-launcher--norm input)
                                     universal-launcher--learned))))
    (let ((now (float-time)) (h (make-hash-table :test #'equal)))
      (pcase-dolist (`(,k . ,e) entries)
        (puthash k (universal-launcher--decay e now) h))
      h)))

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
;; Static candidates go through the user's `completion-styles' (plus
;; initialism, for orderless); dynamic ones are spliced around the result,
;; unfiltered.  Ranking reorders.

(defvar universal-launcher--static nil "Static candidates of the active popup.")
(defvar universal-launcher--live nil "Dynamic candidates for the current input.")
(defvar universal-launcher--input "" "Input the current candidate list was computed for.")
(defvar universal-launcher--score-table nil "KEY -> score, snapshotted per popup.")
(defvar universal-launcher--frequent-cache nil)

(defun universal-launcher--rank (cands &optional input)
  "Order CANDS by (-LEARNED, TIER, RAW, -FRECENCY, LENGTH), stably.
LEARNED is how often a candidate was chosen after typing exactly INPUT.
TIER compares INPUT with the candidate's name (the text after `Prefix: '):
0 whole input is a prefix, 1 first token is a prefix, 2 word start or
initials, 3 elsewhere.  So \"power off\" ranks `Power: Power off' above
`Run: poweroff'.  RAW is 1 for bare PATH commands, the least curated
source: at equal tier an app, script or power row wins.
Orderless filters; this decides what RET hits."
  (let* ((words (split-string (or input "") nil t))
         (tok (car words))
         (n (length tok))
         (phrase (and (cdr words) (string-join words " ")))
         (word-re (and tok (concat "[^[:alnum:]]" (regexp-quote tok))))
         (init-re (and tok (> n 1)
                       (mapconcat (lambda (ch) (concat "\\<" (regexp-quote (string ch))))
                                  tok "[^z-a]*")))
         (learned (and tok (universal-launcher--learned-for input)))
         (case-fold-search t)
         (keyed
          (mapcar
           (lambda (c)
             (let* ((i (string-search ": " c))
                    (start (if i (+ i 2) 0))
                    (tier (cond ((null tok) 0)
                                ((and phrase
                                      (eq t (compare-strings phrase nil nil c start
                                                             (+ start (length phrase)) t)))
                                 0)
                                ((eq t (compare-strings tok nil nil c start (+ start n) t)) 1)
                                ((string-match-p word-re c start) 2)
                                ((and init-re (string-match-p init-re c start)) 2)
                                (t 3))))
               (vector (- (if learned (gethash c learned 0) 0))
                       tier
                       (if (eq (get-text-property 0 'ul-type c) 'command) 1 0)
                       (- (gethash c universal-launcher--score-table 0))
                       (- (length c) start)
                       c)))
           cands)))
    (mapcar (lambda (v) (aref v 5))
            (sort keyed (lambda (a b)
                          (cl-loop for i below 5
                                   for x = (aref a i) for y = (aref b i)
                                   unless (= x y) return (< x y)))))))

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
  (setq universal-launcher--input string)
  (let ((res
         (if (string-empty-p string)
             (progn (setq universal-launcher--live nil)
                    (append (universal-launcher--frequent) universal-launcher--static 0))
           (let* ((dyn (if universal-launcher--dynamic-rows
                           (universal-launcher--dynamic string)
                         (cons nil nil)))
                  (orderless-matching-styles
                   (if (boundp 'orderless-matching-styles)
                       (cl-adjoin 'orderless-initialism orderless-matching-styles)
                     nil))
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

(defun universal-launcher--resolve (s)
  "The candidate object whose text is S, if any."
  (or (car (member s universal-launcher--live))
      (car (member s universal-launcher--static))))

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
       (universal-launcher--ask
        (lambda ()
          (completing-read (format-prompt "Search engine" def)
                           (mapcar #'car universal-launcher-search-engines)
                           nil t nil nil def)))
       query))))

;;;; Dispatch

(defconst universal-launcher--emacs-types '(buffer file task action ssh capture kill)
  "Types whose action happens inside Emacs; floating, they focus Emacs.")

(defconst universal-launcher--asking-types '(pick)
  "Types whose action asks a further question; floating, it is asked in the
launcher before it hides, not in an Emacs frame on another workspace.")

(defun universal-launcher--pcre-quote (s)
  (replace-regexp-in-string "[][\\\\^$.|?*+(){}\"]" "\\\\\\&" s))

(defun universal-launcher--ensure-main ()
  "A visible graphical frame for Emacs-side actions.  A daemon with none
open gets a new one, which sway maps on the current workspace."
  (unless (and (frame-live-p universal-launcher--main)
               (display-graphic-p universal-launcher--main)
               (frame-visible-p universal-launcher--main))
    (setq universal-launcher--main
          (make-frame-on-display (or (and (frame-live-p universal-launcher--frame)
                                          (frame-parameter universal-launcher--frame 'display))
                                     (getenv "WAYLAND_DISPLAY")))))
  universal-launcher--main)

(defun universal-launcher--focus-main ()
  "Select the main frame in Emacs and in sway (whatever workspace it is on).
Sway matches it by pid and its current title; the launcher frame is
unmapped by now, so it cannot match."
  (let ((main (universal-launcher--ensure-main)))
    (when (frame-live-p main)
      (select-frame-set-input-focus main)
      (when (getenv "SWAYSOCK")
        (universal-launcher--sway
         (format "[pid=%d title=\"^%s$\"] focus" (emacs-pid)
                 (universal-launcher--pcre-quote
                  (or (frame-parameter main 'name) ""))))))))

(defun universal-launcher--confirm (cand)
  "Ask before destructive actions.  Runs while the launcher is visible."
  (let ((payload (get-text-property 0 'ul-payload cand)))
    (or (not (and (eq (get-text-property 0 'ul-type cand) 'power) (cdr payload)))
        (y-or-n-p (format "%s? " (substring-no-properties cand))))))

(defun universal-launcher--execute (cand)
  (let ((payload (get-text-property 0 'ul-payload cand)))
    (pcase (get-text-property 0 'ul-type cand)
      ('buffer   (when (buffer-live-p payload) (switch-to-buffer payload)))
      ('window   (universal-launcher--sway (format "[con_id=%d] focus" payload)))
      ('tab      (universal-launcher--tab-switch payload))
      ((or 'app 'command 'script) (universal-launcher--spawn payload))
      ('file     (find-file payload))
      ('bookmark (browse-url payload))
      ('url      (browse-url payload))
      ('search   (universal-launcher--search (car payload) (cdr payload)))
      ('pick     (universal-launcher--web-search payload))
      ('calc     (universal-launcher--copy payload)
                 (message "%s  %s" cand (propertize "(copied)" 'face 'universal-launcher-dim)))
      ('pass     (universal-launcher--sh (format universal-launcher-pass-command
                                                 (shell-quote-argument payload))))
      ('clip     (universal-launcher--sh (format "printf '%%s' %s | cliphist decode | wl-copy"
                                                 (shell-quote-argument payload))))
      ('power    (universal-launcher--sh (car payload)))
      ('capture  (require 'org-capture) (org-capture nil payload))
      ('ssh      (universal-launcher--ssh-connect payload))
      ('task     (pop-to-buffer-same-window (car payload))
                 (goto-char (cdr payload))
                 (org-fold-show-context)
                 (recenter))
      ('kill     (if buffer-read-only (kill-new payload) (insert payload)))
      ('emoji    (universal-launcher--copy payload) (message "Copied %s" payload))
      ('action   (let ((default-directory (car payload)))
                   (if (stringp (cdr payload))
                       (async-shell-command (cdr payload))
                     (call-interactively (cdr payload))))))))

(defvar universal-launcher-history nil)

(defun universal-launcher--setup ()
  (setq-local completion-ignore-case t)
  (setq-local completion-category-overrides
              (cons '(universal-launcher (styles universal-launcher))
                    completion-category-overrides))
  (when universal-launcher--floating
    (universal-launcher--floating-setup)))

(defun universal-launcher--floating-setup ()
  "Minibuffer chrome of the floating frame: ESC closes, padding above."
    ;; A launcher closes on a single ESC.  Vertico composes its map on top.
    (use-local-map (make-composed-keymap
                    (define-keymap "<escape>" #'abort-recursive-edit)
                    (current-local-map)))
    (when (> universal-launcher-padding 0)
      ;; Top padding: a short blank line before everything, Vertico's count
      ;; included (its overlay has priority 1; lower priority draws first).
      ;; The newline's face height sets the line's pixel height.
      (let ((ov (make-overlay (point-min) (point-min) nil t t)))
        (overlay-put ov 'priority -10)
        (overlay-put ov 'before-string
                     (propertize "\n" 'face `(:height ,(/ (float universal-launcher-padding)
                                                            (frame-char-height)))))
        ;; The minibuffer buffer is shared; leave nothing behind.
        (add-hook 'minibuffer-exit-hook (lambda () (delete-overlay ov)) nil t)))
    ;; After the first redisplay, measure what was actually drawn.
    (run-at-time 0 nil #'universal-launcher--fit))

(defun universal-launcher--ask (fn)
  "Call FN, which reads from the minibuffer.  Floating, read in the launcher
frame on the current workspace (shown again if an action hid it), never in
an Emacs frame on some other workspace."
  (let ((f universal-launcher--frame))
    (if (not (and universal-launcher--floating (frame-live-p f)))
        (funcall fn)
      (let ((shown universal-launcher--shown))
        (if shown (select-frame-set-input-focus f) (universal-launcher--show f))
        (unwind-protect
            (minibuffer-with-setup-hook #'universal-launcher--floating-setup
              (funcall fn))
          (unless shown (universal-launcher--hide f)))))))

(defun universal-launcher--read ()
  "Prompt; return the chosen candidate (after recording it), or nil."
  (universal-launcher--stats-load)
  (let* ((universal-launcher--static (universal-launcher--collect))
         (universal-launcher--score-table (universal-launcher--scores))
         (universal-launcher--frequent-cache nil)
         (universal-launcher--live nil)
         (universal-launcher--input "")
         (sel (minibuffer-with-setup-hook #'universal-launcher--setup
                (completing-read universal-launcher--prompt #'universal-launcher--table
                                 nil nil nil 'universal-launcher-history)))
         (cand (and (not (string-empty-p sel))
                    (or (universal-launcher--resolve sel)
                        ;; M-RET: raw input, which matches no row.
                        (and universal-launcher--dynamic-rows
                             (let ((d (universal-launcher--dynamic sel)))
                               (car (append (car d) (cdr d)))))))))
    (when cand
      (if-let* ((input (get-text-property 0 'ul-input cand)))
          ;; Dynamic: M-p should recall what you typed, not "2+2 = 4".
          (when (equal (car universal-launcher-history) sel)
            (setcar universal-launcher-history input))
        (universal-launcher--record cand universal-launcher--input)))
    cand))

;;;###autoload
(defun universal-launcher-popup ()
  "Launch anything, in the selected frame.  The selected row is what RET
does: calculator, conversion, URL and search rows appear as you type.
`!bang query' targets an engine.  M-RET submits raw input."
  (interactive)
  (setq universal-launcher--floating nil
        universal-launcher--main (selected-frame))
  (when-let* ((cand (universal-launcher--read)))
    (when (universal-launcher--confirm cand)
      (universal-launcher--execute cand))))

;;;; Floating frame

(defvar universal-launcher--had-focus nil)

(defun universal-launcher--frame ()
  "The launcher frame, created hidden on first use and reused forever."
  (unless (frame-live-p universal-launcher--frame)
    (let* ((params `((visibility . nil)
                     (height . ,(+ (if (boundp 'vertico-count) vertico-count 10) 2))
                     ,@universal-launcher-frame-parameters))
           (gui (seq-find #'display-graphic-p (frame-list))))
      (setq universal-launcher--frame
            (if gui
                (with-selected-frame gui (make-frame params))
              (make-frame-on-display (getenv "WAYLAND_DISPLAY") params)))))
  universal-launcher--frame)

(defun universal-launcher--style-frame (f)
  "Border and padding for F.  Faces are set for F alone, and reapplied on
every show, so a later `load-theme' cannot undo them."
  (modify-frame-parameters
   f `((internal-border-width . ,universal-launcher-border-width)
       (left-fringe . ,universal-launcher-padding)
       (right-fringe . ,universal-launcher-padding)))
  (set-face-background 'internal-border
                       (face-background 'universal-launcher-border nil t) f)
  (set-face-background 'fringe (frame-parameter f 'background-color) f)
  (universal-launcher--set-height
   f (or universal-launcher--content-height
         ;; First show: estimate the prompt plus `vertico-count' rows, and
         ;; the spacer.  `universal-launcher--fit' then measures.
         (+ (* (1+ (if (boundp 'vertico-count) vertico-count 10)) (frame-char-height f))
            universal-launcher-padding))))

(defun universal-launcher--set-height (f content)
  "Make F's text area CONTENT pixels plus the bottom padding.
Pixelwise, or Emacs rounds the height to whole lines."
  (let ((frame-resize-pixelwise t))
    (set-frame-height f (+ content universal-launcher-padding) nil t)))

(defun universal-launcher--fit ()
  "Measure the drawn content and grow the frame to hold it.  Grow-only and
remembered, so later shows open at the right size."
  (let ((f universal-launcher--frame))
    (when (and (frame-live-p f) universal-launcher--shown)
      (let ((h (cdr (window-text-pixel-size (frame-root-window f) nil nil nil nil t))))
        (when (> h (or universal-launcher--content-height 0))
          (setq universal-launcher--content-height h)
          (universal-launcher--set-height f h))))))

(defun universal-launcher--main-frame (launcher)
  (let ((sel (selected-frame)))
    (if (and (display-graphic-p sel) (not (eq sel launcher)))
        sel
      (seq-find (lambda (f) (and (display-graphic-p f) (frame-visible-p f)
                                 (not (eq f launcher))))
                (frame-list)))))

(defun universal-launcher--focused-p (f)
  "Whether F has keyboard focus.  Under sway, ask sway: GTK's focus state
flickers on keymap changes (virtual keyboards, layout switches)."
  (if (getenv "SWAYSOCK")
      (with-temp-buffer
        (and (eq 0 (call-process "swaymsg" nil t nil "-r" "-t" "get_tree"))
             (progn
               (goto-char (point-min))
               (let ((title (frame-parameter f 'title)) found)
                 (cl-labels ((walk (n)
                               (if (and (eql (plist-get n :pid) (emacs-pid))
                                        (equal (plist-get n :name) title))
                                   (setq found (eq (plist-get n :focused) t))
                                 (mapc #'walk (plist-get n :nodes))
                                 (mapc #'walk (plist-get n :floating_nodes)))))
                   (walk (json-parse-buffer :object-type 'plist :array-type 'list
                                            :false-object nil :null-object nil)))
                 found))))
    (frame-focus-state f)))

(defun universal-launcher--blur-watch ()
  "Abort the floating prompt once it has had focus and lost it."
  (let ((f universal-launcher--frame))
    (when (and universal-launcher-hide-on-blur (frame-live-p f) universal-launcher--shown)
      (run-at-time 0.15 nil
                   (lambda ()
                     (when (and universal-launcher--shown (active-minibuffer-window))
                       (if (universal-launcher--focused-p f)
                           (setq universal-launcher--had-focus t)
                         (when universal-launcher--had-focus
                           (abort-recursive-edit)))))))))

(add-function :after after-focus-change-function #'universal-launcher--blur-watch)

(defun universal-launcher--show (f)
  (universal-launcher--style-frame f)
  (make-frame-visible f)
  (setq universal-launcher--shown t)
  (select-frame-set-input-focus f))

(defun universal-launcher--hide (f)
  (setq universal-launcher--shown nil)
  (make-frame-invisible f t)
  (when (frame-live-p universal-launcher--main)
    (select-frame universal-launcher--main)))

(defconst universal-launcher--tab-sources '(("Tabs" universal-launcher--tabs))
  "Sources of the tabs-only popups.")

(defun universal-launcher--float (&optional sources prompt action)
  "Show the floating launcher.  SOURCES, PROMPT and ACTION scope it: only
those sources, no calculator or search rows, and ACTION called with the
chosen candidate in place of the usual dispatch."
  (let ((f (universal-launcher--frame)))
    (if universal-launcher--shown
        (when (active-minibuffer-window) (abort-recursive-edit))   ; toggle
      (let ((universal-launcher-sources (or sources universal-launcher-sources))
            (universal-launcher--prompt (or prompt "Launch: "))
            (universal-launcher--dynamic-rows (null sources))
            (main (universal-launcher--main-frame f))
            cand)
        (setq universal-launcher--floating t
              universal-launcher--main main
              universal-launcher--had-focus nil)
        (if (and sources (null (universal-launcher--collect)))
            ;; An empty scoped popup only says "nothing here"; say why instead.
            (message "%s"
                     (if (eq sources universal-launcher--tab-sources)
                         (format "No browser tabs on port %s: is Chromium running with --remote-debugging-port=%s?"
                                 universal-launcher-browser-debug-port
                                 universal-launcher-browser-debug-port)
                       (format "Nothing to show from %s" (mapconcat #'car sources ", "))))
          (universal-launcher--show f)
          (unwind-protect
              (progn
                (setq cand (universal-launcher--read))
                ;; Whatever asks a follow-up question (an ACTION such as
                ;; bookmarking, the engine picker, a confirmation) runs here,
                ;; while the launcher is still up on this workspace.
                (cond
                 ((null cand))
                 (action (funcall action cand) (setq cand nil))
                 ((not (universal-launcher--confirm cand)) (setq cand nil))
                 ((memq (get-text-property 0 'ul-type cand) universal-launcher--asking-types)
                  (universal-launcher--execute cand)
                  (setq cand nil))))
            (universal-launcher--hide f))
          (when cand
            (when (memq (get-text-property 0 'ul-type cand) universal-launcher--emacs-types)
              (universal-launcher--focus-main))
            (universal-launcher--execute cand)))))))

;;;###autoload
(defun universal-launcher-float (&optional sources prompt action)
  "Show the launcher floating on the current workspace.  Toggles.
Returns at once, so `emacsclient -e' never blocks on the prompt.
SOURCES, PROMPT and ACTION scope it; see `universal-launcher--float'."
  (interactive)
  (run-at-time 0 nil #'universal-launcher--float sources prompt action)
  t)

;;;###autoload
(defun universal-launcher-tabs ()
  "Floating popup of open browser tabs only; RET switches to one.
Embark actions still apply (`b' bookmark, `k' close)."
  (interactive)
  (universal-launcher-float universal-launcher--tab-sources "Tab: "))

;;;###autoload
(defun universal-launcher-tabs-bookmark ()
  "Floating popup of open browser tabs only; RET bookmarks one."
  (interactive)
  (universal-launcher-float
   universal-launcher--tab-sources "Bookmark tab: "
   (lambda (cand)
     (universal-launcher-tab-bookmark
      (plist-get (get-text-property 0 'ul-payload cand) :url)))))

;;;; Embark
;; One transformer turns a launcher row into its native target (file,
;; buffer, url, text), so every Embark action you already have applies.
;; Kinds with no native category get small keymaps of their own.

(defun universal-launcher--embark-transform (_type target)
  (let* ((c (or (universal-launcher--resolve target) target))
         (p (get-text-property 0 'ul-payload c)))
    (pcase (get-text-property 0 'ul-type c)
      ('file   (cons 'file p))
      ('buffer (cons 'buffer (if (buffer-live-p p) (buffer-name p) target)))
      ((or 'bookmark 'url) (cons 'url p))
      ((or 'app 'command 'script) (cons 'ul-exec p))
      ((or 'calc 'emoji 'kill) (cons 'general p))
      ('pass   (cons 'ul-pass p))
      ('clip   (cons 'ul-clip p))
      ('window (cons 'ul-window (number-to-string p)))
      ('tab    (cons 'ul-tab (plist-get p :url)))
      ('ssh    (cons 'ul-ssh p))
      ('search (cons 'ul-search (cdr p)))
      ('pick   (cons 'ul-search p))
      (_       (cons 'universal-launcher target)))))

(defun universal-launcher-exec (cmd)
  "Run CMD detached."
  (interactive "sCommand: ")
  (universal-launcher--spawn cmd))

(defun universal-launcher-exec-output (cmd)
  "Run CMD in a buffer, to see its output."
  (interactive "sCommand: ")
  (async-shell-command cmd))

(defun universal-launcher-pass-copy (entry)
  (interactive "sEntry: ")
  (universal-launcher--sh (format universal-launcher-pass-command (shell-quote-argument entry))))

(defun universal-launcher--pass-parse ()
  "Fields of the decrypted entry in the current buffer, as ((FIELD . VALUE) ...).
FIELD is downcased.  Line 1 is the password and is never read."
  (goto-char (point-min))
  (forward-line 1)
  (let (acc)
    (while (re-search-forward "^[ \t]*\\([^:\n]+?\\)[ \t]*:[ \t]*\\(.*?\\)[ \t]*$" nil t)
      (push (cons (downcase (match-string-no-properties 1)) (match-string-no-properties 2)) acc))
    (nreverse acc)))

(defun universal-launcher--pass-field (fields names)
  (cl-some (lambda (n) (let ((v (cdr (assoc n fields))))
                         (and v (not (string-empty-p v)) v)))
           names))

(defun universal-launcher--pass-url (entry fields)
  "URL for ENTRY: a URL field, else a domain-looking path component."
  (when-let* ((u (or (universal-launcher--pass-field fields universal-launcher-pass-url-fields)
                     (seq-find (lambda (c) (string-match-p universal-launcher--domain-re c))
                               (split-string entry "/" t)))))
    (if (string-match-p "\\`[a-z][a-z0-9+.-]*://" u) u (concat "https://" u))))

(defun universal-launcher--pass-show (entry k)
  "Decrypt ENTRY with `pass show' asynchronously and call K with its fields.
Async, so a pinentry prompt never freezes Emacs.  The output buffer, which
holds the password, is parsed in place and killed."
  (let ((out (generate-new-buffer " *ul-pass*"))
        (err (generate-new-buffer " *ul-pass-err*")))
    (make-process
     :name "ul-pass" :buffer out :stderr err :noquery t
     :connection-type 'pipe :command (list "pass" "show" entry)
     :sentinel
     (lambda (p _)
       (unless (process-live-p p)
         (unwind-protect
             (if (zerop (process-exit-status p))
                 (funcall k (with-current-buffer out (universal-launcher--pass-parse)))
               (message "pass: %s" (string-trim (with-current-buffer err (buffer-string)))))
           (with-current-buffer out (erase-buffer))
           (kill-buffer out)
           (when (buffer-live-p err) (kill-buffer err))))))))

(defun universal-launcher-pass-username (entry)
  "Copy ENTRY's username field."
  (interactive "sEntry: ")
  (universal-launcher--pass-show
   entry (lambda (fields)
           (if-let* ((u (universal-launcher--pass-field
                         fields universal-launcher-pass-username-fields)))
               (progn (universal-launcher--copy u) (message "Copied username for %s" entry))
             (message "%s has no %s field" entry
                      (string-join universal-launcher-pass-username-fields "/"))))))

(defun universal-launcher-pass-browse (entry)
  "Open ENTRY's URL: its URL field, else the domain in its path."
  (interactive "sEntry: ")
  (universal-launcher--pass-show
   entry (lambda (fields)
           (if-let* ((u (universal-launcher--pass-url entry fields)))
               (browse-url u)
             (message "%s has no URL" entry)))))

(defun universal-launcher-pass-otp (entry)
  (interactive "sEntry: ")
  (universal-launcher--sh (format "pass otp -c %s" (shell-quote-argument entry))))

(defun universal-launcher-clip-copy (line)
  (interactive "sEntry: ")
  (universal-launcher--sh (format "printf '%%s' %s | cliphist decode | wl-copy"
                                  (shell-quote-argument line))))

(defun universal-launcher-clip-delete (line)
  (interactive "sEntry: ")
  (universal-launcher--sh (format "printf '%%s' %s | cliphist delete" (shell-quote-argument line))))

(defun universal-launcher-window-focus (id)
  (interactive "sCon id: ")
  (universal-launcher--sway (format "[con_id=%s] focus" id)))

(defun universal-launcher-window-kill (id)
  (interactive "sCon id: ")
  (universal-launcher--sway (format "[con_id=%s] kill" id)))

(defun universal-launcher-window-here (id)
  "Move window ID to the focused workspace and focus it."
  (interactive "sCon id: ")
  (when-let* ((ws (with-temp-buffer
                    (call-process "swaymsg" nil t nil "-r" "-t" "get_workspaces")
                    (goto-char (point-min))
                    (seq-find (lambda (w) (eq (plist-get w :focused) t))
                              (json-parse-buffer :object-type 'plist :array-type 'list)))))
    (universal-launcher--sway (format "[con_id=%s] move container to workspace \"%s\", focus"
                                      id (plist-get ws :name)))))

(defmacro universal-launcher--wide (&rest body)
  "BODY with the whole buffer visible; point and narrowing restored."
  `(save-excursion (save-restriction (widen) ,@body)))

(defun universal-launcher--org-paths (file)
  "Outline paths of FILE's headings, as \"A/B/C\"."
  (require 'org)
  (with-current-buffer (find-file-noselect file)
    (universal-launcher--wide
     (org-map-entries (lambda () (string-join (org-get-outline-path t) "/"))))))

(defun universal-launcher--org-append (file path line)
  "Append LINE to the body of heading PATH (a list) in FILE, creating any
missing headings.  The line goes after the heading's own body, before its
first child, so it belongs to that heading and not to its last subtree."
  (require 'org)
  (with-current-buffer (find-file-noselect file)
    (universal-launcher--wide
     (let* ((k (length path)) m)
       (while (and (> k 0)
                   (not (setq m (ignore-errors (org-find-olp (take k path) t)))))
         (setq k (1- k)))
       (let ((level (if m (save-excursion (goto-char m) (org-current-level)) 0)))
         (if (null m)
             (goto-char (point-max))
           (goto-char m)
           (if (< k (length path))
               (org-end-of-subtree t t)       ; new children go after existing ones
             (outline-next-heading)           ; own body ends where next heading starts
             (skip-chars-backward " \t\n")
             (end-of-line)))
         (unless (bolp) (insert "\n"))
         (cl-loop for name in (nthcdr k path)
                  for lvl from (1+ level)
                  do (insert (make-string lvl ?*) " " name "\n"))
         (insert line)
         (when (or (eobp) (not (eolp))) (insert "\n"))))
     (let ((save-silently t)) (save-buffer)))))

(defun universal-launcher-tab-switch (url)
  "Activate the tab showing URL and raise its window."
  (interactive "sURL: ")
  (if-let* ((tab (universal-launcher--tab-by-url url)))
      (universal-launcher--tab-switch tab)
    (message "No open tab for %s" url)))

(defun universal-launcher-tab-close (url)
  (interactive "sURL: ")
  (when-let* ((tab (universal-launcher--tab-by-url url)))
    (universal-launcher--cdp "GET" (concat "/json/close/" (plist-get tab :id)))))

(defun universal-launcher-tab-bookmark (url)
  "Bookmark the tab showing URL under a heading of the bookmarks file,
chosen or typed as a new path (\"Dev/Emacs\").  It is a launcher row on
the next popup."
  (interactive "sURL: ")
  (require 'ol)
  (let* ((tab (universal-launcher--tab-by-url url))
         (title (or (and tab (plist-get tab :title)) url))
         (file (expand-file-name universal-launcher-bookmarks-file))
         (choice (universal-launcher--ask
                  (lambda ()
                    (completing-read (format "Bookmark \"%s\" under: "
                                             (truncate-string-to-width title 40 nil nil "…"))
                                     (universal-launcher--org-paths file))))))
    (unless (string-blank-p choice)
      (universal-launcher--org-append
       file (split-string choice "/" t " +")
       (format "- %s %s" (org-link-make-string url title) (format-time-string "[%Y-%m-%d]")))
      (message "Bookmarked \"%s\" under %s" title choice))))

(defun universal-launcher-ssh-dired (host)
  (interactive "sHost: ")
  (dired (format "/ssh:%s:~/" host)))

(defvar universal-launcher--no-focus-actions
  '(embark-copy-as-kill embark-save embark-insert kill-new)
  "Embark actions on Emacs-side targets that should not raise Emacs.")

(cl-defun universal-launcher--embark-pre (&key orig-type type action &allow-other-keys)
  "Floating: act in the main frame, never the launcher's minibuffer window,
and raise Emacs when the action happens there."
  (when (and (eq orig-type 'universal-launcher) universal-launcher--floating)
    (let ((emacs-side (and (memq type '(file buffer ul-ssh))
                           (not (memq action universal-launcher--no-focus-actions)))))
      (when emacs-side (universal-launcher--focus-main))
      (when (frame-live-p universal-launcher--main)
        (select-window (frame-selected-window universal-launcher--main))))))

(with-eval-after-load 'embark
  (defvar-keymap universal-launcher-exec-map
    :doc "Actions on launcher commands." :parent embark-general-map
    "RET" #'universal-launcher-exec
    "o"   #'universal-launcher-exec-output)
  (defvar-keymap universal-launcher-pass-map
    :doc "Actions on pass entries." :parent embark-general-map
    "RET" #'universal-launcher-pass-copy
    "o"   #'universal-launcher-pass-otp
    "b"   #'universal-launcher-pass-username
    "U"   #'universal-launcher-pass-browse)
  (defvar-keymap universal-launcher-clip-map
    :doc "Actions on cliphist entries." :parent embark-general-map
    "RET" #'universal-launcher-clip-copy
    "d"   #'universal-launcher-clip-delete)
  (defvar-keymap universal-launcher-window-map
    :doc "Actions on sway windows." :parent embark-general-map
    "RET" #'universal-launcher-window-focus
    "k"   #'universal-launcher-window-kill
    "h"   #'universal-launcher-window-here)
  (defvar-keymap universal-launcher-tab-map
    :doc "Actions on browser tabs.  Inherits the URL actions." :parent embark-url-map
    "RET" #'universal-launcher-tab-switch
    "b"   #'universal-launcher-tab-bookmark
    "k"   #'universal-launcher-tab-close)
  (defvar-keymap universal-launcher-ssh-map
    :doc "Actions on SSH hosts." :parent embark-general-map
    "RET" #'universal-launcher--ssh-connect
    "d"   #'universal-launcher-ssh-dired)
  (defvar-keymap universal-launcher-search-map
    :doc "Actions on search queries." :parent embark-general-map
    "RET" #'universal-launcher--web-search
    "e"   #'universal-launcher--web-search)
  (setf (alist-get 'universal-launcher embark-transformer-alist)
        #'universal-launcher--embark-transform)
  (dolist (m '((ul-exec . universal-launcher-exec-map)
               (ul-pass . universal-launcher-pass-map)
               (ul-clip . universal-launcher-clip-map)
               (ul-window . universal-launcher-window-map)
               (ul-tab . universal-launcher-tab-map)
               (ul-ssh . universal-launcher-ssh-map)
               (ul-search . universal-launcher-search-map)))
    (setf (alist-get (car m) embark-keymap-alist) (list (cdr m))))
  (cl-pushnew #'universal-launcher--embark-pre
              (alist-get :always embark-pre-action-hooks)))

;;;; SSH

(defun universal-launcher--ssh-connect (host)
  "Connect to SSH HOST using best available terminal."
  (interactive "sHost: ")
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

;; Pay every cold cost once, while idle: sources, calc, the units table,
;; and the floating frame itself when a graphical display exists.
(run-with-idle-timer
 2 nil
 (lambda ()
   (let ((inhibit-message t))
     (universal-launcher--stats-load)
     (universal-launcher--collect)
     (calc-eval "1+1")
     (require 'calc-units)
     (math-build-units-table)
     (when (seq-find #'display-graphic-p (frame-list))
       (universal-launcher--frame)))))

(provide 'universal-launcher)
;;; universal-launcher.el ends here
