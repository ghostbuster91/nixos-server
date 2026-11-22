{ pkgs, lib, inputs, ... }:
let
  leaderKey = "\\<Space>";
  # `with pkgs.vimPlugins` below does not shadow let bindings, so this name
  # wins over any nixpkgs package that may later use it.
  nvim-next = inputs.nvim-next.packages.${pkgs.stdenv.hostPlatform.system}.nvim-next;
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
    withRuby = false;
    withPython3 = false;
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
        type = "viml";
        config = ''
          packadd! ${plugin.pname}
          colorscheme kanagawa
        '';
      }
      # snacks.nvim is a bundle of small modules. It replaces telescope (+
      # telescope-fzf-native, telescope-ui-select, telescope-undo,
      # telescope-dap) with snacks.picker, indent-blankline with snacks.indent,
      # neoscroll with snacks.scroll and gitlinker with snacks.gitbrowse; it
      # also takes over vim.notify, vim.ui.input and vim.ui.select.
      # Configured in lua/local/snacks.lua.
      snacks-nvim
      which-key-nvim
      nvim-autopairs
      vim-sandwich
      gitsigns-nvim
      plenary-nvim

      # completions
      # blink.cmp replaces nvim-cmp + the cmp-* sources + lspkind: lsp, buffer,
      # path and luasnip are all built-in sources. The nixpkgs derivation ships
      # the prebuilt Rust fuzzy matcher, see lua/local/blink.lua.
      blink-cmp

      # lsp stuff
      nvim-lspconfig

      (nvim-treesitter.withPlugins (
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
      # The treesitter `main` branch dropped the integrated textobjects/refactor
      # modules, so nvim-treesitter-textobjects-legacy / nvim-treesitter-refactor
      # are gone; selection/highlight is reimplemented in lua/local/treesitter.lua.

      nvim-web-devicons
      lualine-nvim
      nvim-navic
      comment-nvim

      # snippets
      luasnip
      friendly-snippets

      nvim-neoclip-lua
      nvim-tree-lua
      vim-tmux-clipboard
      noice-nvim
      nui-nvim
      fidget-nvim
      nvim-lightbulb
      neogit
      undotree
      diffview-nvim
      goto-preview
      nvim-dap
      {
        plugin = nvim-dap-ui;
        type = "viml";
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
      trouble-nvim
      vim-repeat
      flash-nvim
      actions-preview-nvim
      {
        plugin = nvim-dap-virtual-text;
        type = "viml";
        config = ''
          lua <<EOF
            require("nvim-dap-virtual-text").setup()
          EOF
        '';
      }
      dial-nvim
      smart-splits-nvim
      # lazydev replaces neodev: neodev hooked lspconfig's lua_ls.setup{}, which
      # this config stopped using when it moved to vim.lsp.config.
      lazydev-nvim
      hydra-nvim
      substitute-nvim
      baleia-nvim
      hover-nvim
      ssr-nvim

      # Repeatable movements engine: `;` / `,` repeat the last next/prev move
      # (f/t, diagnostic, git hunk, merge conflict) regardless of which plugin
      # provided it. Built from its own flake, see lua/local/nvim-next.lua.
      nvim-next
    ];
  };
}
