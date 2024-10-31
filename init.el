;;; init.el -*- lexical-binding: t; -*-

;; Install Elpaca
(defvar elpaca-installer-version 0.7)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (< emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                    (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (load "./elpaca-autoloads")))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))
;; End of Elpaca installation snippet

(elpaca elpaca-use-package
  (elpaca-use-package-mode))

(defun c/generate-config ()
  "This function will write all source blocks from =config.org= into =config.el= that:
- Are not marked as `tangle: no'
- Don't have the TODO state `DISABLED'
- Have a source-code of `emacs-lisp'"
  (require 'org)
  (let* ((body-list ())
         (output-file (concat user-emacs-directory "config.el"))
         (org-babel-default-header-args (org-babel-merge-params org-babel-default-header-args
                                                                (list (cons :tangle output-file)))))
    (let ((inhibit-message t)) (message "Generating %s" output-file))
    (save-restriction
      (save-excursion
        (org-babel-map-src-blocks (concat user-emacs-directory "config.org")
          (let* ((org_block_info (org-babel-get-src-block-info 'light))
                 (tfile (cdr (assq :tangle (nth 2 org_block_info))))
                 (todo-keyword-match))
            (save-excursion
              (catch 'exit
                (org-back-to-heading t)
                (when (looking-at org-outline-regexp)
                  (goto-char (1- (match-end 0))))
                (when (looking-at (concat " +" org-todo-regexp "\\( +\\|[ \t]*$\\)"))
                  (setq todo-keyword-match (match-string 1)))))
            (unless (or (string= "no" tfile)
                        (string= "DISABLED" todo-keyword-match)
                        (not (string= "emacs-lisp" lang)))
              (add-to-list 'body-list (concat "\n\n;; #############################################################\n"
                                              ";; " (org-get-heading) "\n"
                                              ";; #############################################################\n\n"))
              (add-to-list 'body-list body)))))

      (with-temp-file output-file
        (insert ";;; config.el -*- lexical-binding: t; -*-\n")
        (insert ";; =============================================================\n")
        (insert ";; Don't edit this file, edit config.org instead.\n")
        (insert ";; Generated at " (format-time-string "%a %b %d %Y-%m-%dT%H:%M:%S " (current-time)) "on host " system-name "\n")
        (insert ";; =============================================================\n")
        (insert (apply 'concat (reverse body-list))))

      (let ((inhibit-message t)) (message "Wrote %s" output-file)))))

(let ((org-file (concat user-emacs-directory "config.org"))
      (el-file (concat user-emacs-directory "config.el")))
  (when (or (not (file-exists-p el-file))
            (file-newer-than-file-p org-file el-file))
    (c/generate-config)))

(defvar c/config-file (concat user-emacs-directory "config.el")
    "File containing main Emacs configuration.
This file is loaded by init.el.")

(unwind-protect
    ;; Load the main Emacs configuration code. Disable
    ;; `file-name-handler-alist' to improve load time.
    (let ((file-name-handler-alist nil)
          (load-prefer-newer t))
      (load c/config-file nil 'nomessage 'nosuffix)))

;; Prevent Custom from modifying this file.
(setq custom-file (expand-file-name
                   (format "custom-%d-%d.el" (emacs-pid) (random))
                   temporary-file-directory))
