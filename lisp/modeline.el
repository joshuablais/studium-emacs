;;; modeline.el -*- lexical-binding: t; -*-

(defvar nerd-icons-font-family)   ; defined by nerd-icons; declared here for the compiler
(setq nerd-icons-font-family "GeistMono Nerd Font")

(use-package nerd-icons :demand t)

;;;; Helpers

(defun studium-modeline--glyph (char &optional face)
  "CHAR from the icon font, in FACE (default `shadow')."
  (propertize (string char)
              'face `(:family ,nerd-icons-font-family :inherit ,(or face 'shadow))))

;;;; Left side

(defvar-local studium-modeline--icon nil
  "Cached (KEY ACTIVE DIMMED) for this buffer.")

(defun studium-modeline--icon ()
  "Icon for the buffer's file type or major mode; dimmed in unfocused windows."
  (when (fboundp 'nerd-icons-icon-for-buffer)
    (let ((key (cons major-mode buffer-file-name)))
      (unless (equal key (car studium-modeline--icon))
        (let ((icon (nerd-icons-icon-for-buffer)))
          (setq studium-modeline--icon
                (if (stringp icon)
                    (list key icon
                          (propertize
                           (substring-no-properties icon)
                           'face `(:family ,nerd-icons-font-family :inherit shadow)
                           'display (get-text-property 0 'display icon)))
                  (list key nil nil)))))
      (nth (if (mode-line-window-selected-p) 1 2) studium-modeline--icon))))

(defun studium-modeline--name ()
  "Buffer name. Bold and coloured when modified; lock when read-only."
  (let ((active (mode-line-window-selected-p))
        (modified (and buffer-file-name (buffer-modified-p))))
    (concat
     (propertize "%b" 'face (cond ((not active) nil)
                                  (modified '(:inherit warning :weight bold))
                                  (t 'mode-line-buffer-id)))
     (when (and buffer-file-name buffer-read-only)
       (concat " " (studium-modeline--glyph ?\uf023))))))

(defun studium-modeline--branch ()
  "Current branch, from the string VC already maintains."
  (when-let* ((file buffer-file-name)
              (vc vc-mode)
              (backend (vc-backend file))
              (name (substring-no-properties
                     vc (+ 2 (length (symbol-name backend))))))
    (concat "  " (studium-modeline--glyph ?\ue0a0) " "
            (propertize (string-replace "%" "%%" name) 'face 'shadow))))

;;;; Right side

(defun studium-modeline--unread-mail-p ()
  "Non-nil when mu4e's favourite bookmark has unread messages."
  (when (and (featurep 'mu4e) (fboundp 'mu4e-query-items))
    (ignore-errors
      (when-let* ((fav (seq-find (lambda (item) (plist-get item :favorite))
                                 (mu4e-query-items 'bookmarks)))
                  (n (plist-get fav :unread)))
        (> n 0)))))

(defun studium-modeline--unread-chat-p ()
  "Non-nil when ERC has channels with unseen activity."
  (bound-and-true-p erc-modified-channels-alist))

(defun studium-modeline--alerts ()
  "Mail and chat icons when mu4e or ERC have something unread."
  (let ((face (if (mode-line-window-selected-p) 'warning 'shadow)))
    (concat
     (when (studium-modeline--unread-mail-p)
       (concat (studium-modeline--glyph ?\uf0e0 face) "  "))
     (when (studium-modeline--unread-chat-p)
       (concat (studium-modeline--glyph ?\uf075 face) "  ")))))

(defun studium-modeline--misc ()
  "`global-mode-string' without ERC's own channel list."
  (if (listp global-mode-string)
      (remq 'erc-modified-channels-object global-mode-string)
    global-mode-string))

;; Redraw when mu4e's counts change.
(add-hook 'mu4e-query-items-updated-hook
          (lambda () (force-mode-line-update t)))

;;;; Format

(setq-default mode-line-format
              '("%e"
                " "
                (:eval (studium-modeline--icon))
                " "
                (:eval (studium-modeline--name))
                mode-line-process
                (:eval (studium-modeline--branch))
                (defining-kbd-macro (:propertize "  REC" face error))
                mode-line-format-right-align
                (:eval (studium-modeline--alerts))
                (:eval (studium-modeline--misc))
                "  %l:%c  %p "))

;;;; Keep the branch current

(defvar studium-modeline--heads (make-hash-table :test #'equal)
  "Last seen HEAD per repository root.")

(defun studium-modeline--refresh-branch ()
  "After a Magit refresh, update VC state if the repository's HEAD moved."
  (when-let* ((root (magit-toplevel))
              (head (or (magit-get-current-branch)
                        (magit-rev-parse "--short" "HEAD"))))
    (unless (equal head (gethash root studium-modeline--heads))
      (puthash root head studium-modeline--heads)
      (dolist (buf (buffer-list))
        (with-current-buffer buf
          (when (and buffer-file-name vc-mode
                     (file-in-directory-p buffer-file-name root))
            (vc-refresh-state)))))))

(with-eval-after-load 'magit
  (add-hook 'magit-post-refresh-hook #'studium-modeline--refresh-branch))

;;;; Padding

;; Vertical padding; re-applied because themes reset the box.
(defun studium-modeline--pad (&rest _)
  (dolist (face '(mode-line mode-line-inactive))
    (set-face-attribute face nil :box '(:line-width (1 . 5) :style flat-button))))
(add-hook 'enable-theme-functions #'studium-modeline--pad)
(studium-modeline--pad)

(provide 'modeline)
