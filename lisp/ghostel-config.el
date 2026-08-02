;;; ghostel-config.el --- Description -*- lexical-binding: t; -*-

(use-package ghostel
  :ensure t
  :bind (:map ghostel-mode-map
              ("C-<left>"  . windmove-left)
              ("C-<right>" . windmove-right)
              ("C-<up>"    . windmove-up)
              ("C-<down>"  . windmove-down)))

(defun jb/ghostel ()
  "Open ghostel buffer as a bottom popup at 30% height."
  (interactive)
  (require 'ghostel)
  (let ((buf (or (get-buffer "*ghostel*")
                 ;; Let `ghostel' spawn the process + buffer, but don't let it
                 ;; steal the window — capture the buffer and display it ourselves.
                 (save-window-excursion
                   (ghostel "*ghostel*")
                   (get-buffer "*ghostel*")))))
    (select-window
     (display-buffer
      buf
      '((display-buffer-reuse-window
         display-buffer-in-side-window)
        (side . bottom)
        (slot . 0)
        (window-height . 0.3)
        (window-parameters . ((no-delete-other-windows . t))))))))

;; Explicitly spawn a new frame with ghostel
(defun my/new-frame-with-ghostel ()
  "Create a new frame and immediately open ghostel in it."
  (interactive)
  (require 'ghostel)
  (let ((new-frame (make-frame '((explicit-ghostel . t)))))
    (select-frame new-frame)
    (delete-other-windows)
    (let ((ghostel-buffer (ghostel (format "*ghostel-%s*" (frame-parameter new-frame 'name)))))
      (switch-to-buffer ghostel-buffer)
      (delete-other-windows))))

(provide 'ghostel-config)
