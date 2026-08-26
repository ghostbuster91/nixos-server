{ pkgs, lib, ... }:
let
  leaderKey = "\\<Space>";
in
{
  # Vendored lua config, sourced from the store (immutable). Editing requires a
  # rebuild — this diverges from dot-files' out-of-store symlink on purpose.
  xdg.configFile."nvim/lua".source = ./lua;

  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    viAlias = true;
    vimAlias = true;
    # EDITOR is already set to nvim in modules/hm/base.nix; leave defaultEditor
    # off so the two don't clash on home.sessionVariables.EDITOR.
    defaultEditor = false;
    extraConfig = ''
      	let mapleader = "${leaderKey}"
    '' +
    "${builtins.readFile ./init.vim}" +
    ''
      lua << EOF
        local binaries = {
          tsserver_path = "${pkgs.typescript-language-server}/bin/typescript-language-server",
          lua_language_server = "${pkgs.lua-language-server}/bin/lua-language-server",
          nodejs = "${lib.getExe pkgs.nodejs}", -- required for copilot
          nix_fmt = "${lib.getExe pkgs.nixpkgs-fmt}",
          nix = "${lib.getExe pkgs.nix}"
        }

        ${builtins.readFile ./init.lua}
      EOF
    '';
    extraPackages = with pkgs; [
      bash-language-server
      vim-language-server
      yaml-language-server
      nil
      lua-language-server
      stylua
      shfmt
      eslint
      prettier
      cspell
      rust-analyzer
      rustfmt
      gopls
      go # for gopls
    ];
    plugins = with pkgs.vimPlugins; [
      rec {
        plugin = kanagawa-nvim;
        config = ''
          packadd! ${plugin.pname}
          colorscheme kanagawa
        '';
      }
      telescope-nvim
      telescope-fzf-native-nvim
      which-key-nvim
      nvim-autopairs
      vim-sandwich
      gitsigns-nvim
      plenary-nvim

      # completions
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp_luasnip

      # lsp stuff
      nvim-lspconfig

      (nvim-treesitter-legacy.withPlugins (
        # https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/development/tools/parsing/tree-sitter/grammars
        plugins:
          with plugins; [
            tree-sitter-lua
            tree-sitter-vim
            tree-sitter-vimdoc
            tree-sitter-html
            tree-sitter-yaml
            tree-sitter-json
            tree-sitter-markdown
            tree-sitter-markdown-inline
            tree-sitter-comment
            tree-sitter-bash
            tree-sitter-javascript
            tree-sitter-nix
            tree-sitter-typescript
            tree-sitter-tsx
            tree-sitter-c
            tree-sitter-java
            tree-sitter-kotlin
            tree-sitter-query # for the tree-sitter itself
            tree-sitter-python
            tree-sitter-go
            tree-sitter-hocon
            tree-sitter-sql
            tree-sitter-graphql
            tree-sitter-dockerfile
            tree-sitter-scheme
            tree-sitter-rust
          ]
      ))
      nvim-treesitter-textobjects-legacy
      nvim-treesitter-refactor

      nvim-web-devicons
      lualine-nvim
      nvim-navic
      comment-nvim

      # snippets
      luasnip
      lspkind-nvim
      friendly-snippets

      nvim-neoclip-lua
      indent-blankline-nvim
      nvim-tree-lua
      vim-tmux-clipboard
      telescope-ui-select-nvim
      noice-nvim
      nui-nvim
      fidget-nvim
      nvim-lightbulb
      neoscroll-nvim
      neogit
      undotree
      diffview-nvim
      goto-preview
      nvim-dap
      {
        plugin = nvim-dap-ui;
        config = ''
          lua << EOF
            require("dapui").setup()
            local dap, dapui = require("dap"), require("dapui")
            dap.listeners.before.event_terminated["dapui_config"] = function()
              dapui.close()
            end
            dap.listeners.before.event_exited["dapui_config"] = function()
              dapui.close()
            end
          EOF
        '';
      }
      telescope-dap-nvim
      trouble-nvim
      vim-repeat
      flash-nvim
      gitlinker-nvim
      actions-preview-nvim
      {
        plugin = nvim-dap-virtual-text;
        config = ''
          lua <<EOF
            require("nvim-dap-virtual-text").setup()
          EOF
        '';
      }
      telescope-undo-nvim
      dial-nvim
      smart-splits-nvim
      neodev-nvim
      hydra-nvim
      substitute-nvim
      baleia-nvim
      hover-nvim
      ssr-nvim
    ];
  };
}
