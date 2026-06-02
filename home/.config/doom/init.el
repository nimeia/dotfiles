;;; init.el -*- lexical-binding: t; -*-

;; Run `doom sync` after changing this file.

(doom! :input
       ;; Use the system Fcitx5 IME for Chinese input.

       :completion
       (corfu +orderless)
       vertico

       :ui
       doom
       dashboard
       hl-todo
       indent-guides
       modeline
       ophints
       (popup +defaults)
       (vc-gutter +pretty)
       vi-tilde-fringe
       workspaces

       :editor
       (evil +everywhere)
       file-templates
       fold
       (format +onsave)
       snippets
       (whitespace +guess +trim)
       word-wrap

       :emacs
       dired
       electric
       ibuffer
       tramp
       undo
       vc

       :term
       vterm

       :checkers
       syntax
       (spell +flyspell)

       :tools
       direnv
       editorconfig
       (eval +overlay)
       lookup
       (lsp +eglot)
       magit
       make
       tree-sitter

       :os
       tty

       :lang
       (cc +lsp +tree-sitter)
       data
       emacs-lisp
       (json +lsp +tree-sitter)
       (javascript +lsp +tree-sitter)
       (lua +lsp +tree-sitter)
       markdown
       org
       (python +lsp +tree-sitter)
       (rust +lsp +tree-sitter)
       sh
       (web +lsp +tree-sitter)
       yaml

       :config
       (default +bindings +smartparens))
