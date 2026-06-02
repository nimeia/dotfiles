;;; config.el -*- lexical-binding: t; -*-

(setq user-full-name "sakura"
      user-mail-address "sakura@localhost")

(setq doom-font (font-spec :family "JetBrainsMono Nerd Font" :size 13)
      doom-big-font (font-spec :family "JetBrainsMono Nerd Font" :size 18)
      doom-variable-pitch-font (font-spec :family "Noto Sans CJK SC" :size 14)
      doom-symbol-font (font-spec :family "Noto Color Emoji" :size 13))

(setq catppuccin-flavor 'mocha
      doom-theme 'catppuccin
      display-line-numbers-type 'relative
      org-directory "~/org/"
      delete-by-moving-to-trash t
      confirm-kill-emacs nil
      evil-split-window-below t
      evil-vsplit-window-right t
      save-interprogram-paste-before-kill t
      doom-scratch-initial-major-mode 'org-mode)

(setq +format-on-save-enabled-modes
      '(not emacs-lisp-mode
            org-mode
            sql-mode
            tex-mode
            latex-mode))

(after! corfu
  (setq corfu-auto t
        corfu-auto-delay 0.15
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-preselect 'prompt))

(after! vertico
  (setq vertico-count 14
        vertico-resize nil))

(after! doom-themes
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t))

(after! vterm
  (setq vterm-shell (or (getenv "SHELL") "/bin/bash")
        vterm-max-scrollback 10000))

(after! eglot
  (setq eglot-autoshutdown t
        eglot-events-buffer-size 0))

(map! :leader
      :desc "Open vterm" "o t" #'+vterm/here
      :desc "Magit status" "g g" #'magit-status
      :desc "Format buffer" "c f" #'+format/buffer)
