;;; ghostel-config.el --- Description -*- lexical-binding: t; -*-

(use-package ghostel
  :ensure t)

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

(provide 'ghostel-config)
