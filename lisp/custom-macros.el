;; -*- lexical-binding: t; -*-

(defalias 'title-find
  (kmacro
   "/ A D D R E S S <return> <up> <up> C-SPC t * d C-e <backspace> i SPC C-y C-x ) <escape>"))(defalias 'cleanup-lines (kmacro "<down> C-a i <backspace> SPC C-x ) <escape>"))

(defalias 'address-format
  (kmacro "/ A D D R E <return> C-SPC t * d <right> i * SPC C-y <return> <escape>"))

(defalias 'sources-format
  (kmacro
   "/ S O U R C E S S-SPC O F S-SPC I N C O M E : <return> C-SPC t : <right> d <right> i * SPC C-y <return> <escape>"))

(defalias 'cleanup-lines (kmacro "<down> C-a i <backspace> SPC C-x ) <escape>"))

(defalias 'web-format
  (kmacro "/ W E B <return> C-SPC t * d <right> i * SPC C-y <return> <escape>"))

(defalias 'rf-format
  (kmacro "/ R E M A R K S <return> C-SPC t * d <right> i * SPC C-y <return> <escape>"))

(defalias 'time-format
  (kmacro "/ T I M E <return> C-SPC t * d <right> i * SPC C-y <return> <escape>"))

(defalias 'fields-format
  (kmacro
   "C-s F I E L <return> M-b C-SPC t : <right> C-w i * * SPC C-y C-k <return> C-y C-a - C-s * <return> C-k <return> C-y <escape>"))

(defalias 'region-format
  (kmacro
   "C-s R E G I O <return> M-b C-SPC t ( t * d <right> i * SPC C-y <return> <escape>"))

(defalias 'application-format
  (kmacro
   "C-s A P P L I C A T <return> M-b C-SPC t * C-w <right> i * SPC C-y <return> <escape>"))

(defalias 'phone-format
  (kmacro
   "/ P H O N <return> C-SPC t * d <right> i * SPC C-y C-e <backspace> <backspace> <escape>"))

(defalias 'email-format
  (kmacro
   "C-s | <return> i <return> <delete> * * <right> SPC C-e <backspace> <escape>"))

(defalias 'remark-format
  (kmacro
   "C-s R E M A <return> M-b C-SPC t * d <right> i * SPC C-y <return> <escape>"))

(defalias 'aid-format
  (kmacro
   "/ T Y P <return> C-SPC t * d i * <right> SPC C-y <return> <escape> C-SPC t / <right> d O - SPC C-y <return> * * * * SPC A I D S-SPC R E M A R K S : <escape> O <backspace> <backspace> * * * * SPC A M O U N T : <escape>"))

(defalias 'comma-clean
  (kmacro "/ , C-g C-s , <return> <backspace> <return> i <return> - <escape>"))

(defun format-funder ()
  "Format a funder"
  (interactive)
  (title-find)
  (address-format)
  (email-format)
  (phone-format)
  (aid-format)
  (web-format)
  (sources-format)
  (fields-format)
  (region-format)
  (application-format)
  (time-format)
  (remark-format))


(defun format-all-entries ()
  "Run `format-entry' from the top of the buffer until a macro fails."
  (interactive)
  (goto-char (point-min))
  (condition-case nil
      (while t (format-entry))
    (error nil)))
