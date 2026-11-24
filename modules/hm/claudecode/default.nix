{ pkgs, inputs, ... }:
# Pushes a Neovim selection into Claude: claudecode.nvim runs a WebSocket server
# inside the editor speaking the VS Code extension protocol, and the Claude CLI
# connects to it as a client (`claude --ide`, wired up in ../workmux).
#
# The opposite direction to ../nvim-mcp, and the reason both exist. There, Claude
# spawns the MCP server, which connects *out* to the editor's RPC socket, so
# Neovim is the leaf of two client→server hops: it can answer "what is the user
# pointing at" when asked, but it can never start a turn. Here the editor holds
# the server, so a keymap can put a file reference in Claude's prompt.
#
# Opt-in per host — see beast.
let
  plugin = inputs.claudecode-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  programs.neovim.plugins = [
    {
      inherit plugin;
      type = "lua";
      config = ''
        -- Each editor writes a ~/.claude/ide/<port>.lock, and `claude --ide`
        -- connects only "if exactly one valid IDE is available" — so every extra
        -- lockfile is a way for it to quietly connect to nothing at all. Register
        -- only where there is a project to offer: an nvim opened to read a file
        -- outside any repo (`nvim ~/.claude/CLAUDE.md`, cwd ~) would otherwise
        -- advertise the home directory as a workspace and count against that
        -- "exactly one" for every session below it. workmux always starts nvim
        -- inside the worktree, where `.git` is a file rather than a directory —
        -- `vim.fs.root` finds it either way.
        ${builtins.readFile ../lib/transient-nvim.lua}
        if not _G.ClaudeNvimTransient() and vim.fs.root(vim.fn.getcwd(), ".git") then
          require("claudecode").setup({
            -- Claude already has a pane of its own (../workmux), so the plugin
            -- manages no terminal here. The server and the tools still run.
            terminal = { provider = "none" },
            -- Answer Claude's edits as accepted unchanged instead of opening
            -- each one as a diff to review: an agent working unattended in the
            -- next pane would otherwise stall until someone accepts it. Our
            -- fork carries this option; upstream always reviews.
            diff_opts = { review = false },
          })

          -- Both of these send an `@file#Lx-y` reference rather than the text,
          -- so Claude reads the file as it is when it looks, and a long
          -- selection costs a line of prompt instead of its own length.
          vim.keymap.set("v", "<leader>as", "<Cmd>ClaudeCodeSend<CR>", {
            desc = "Send selection to Claude",
          })
          vim.keymap.set("n", "<leader>aa", "<Cmd>ClaudeCodeAdd %<CR>", {
            desc = "Send this file to Claude",
          })

          -- A send lands in a pane that does not have focus, so follow it over.
          -- tmux resolves {right-of} against the active pane, which is this
          -- editor while the keymap runs — the agent pane in ../workmux's
          -- layout. The plugin's own `focus_after_send` cannot do this: it only
          -- knows terminals it opened inside Neovim.
          vim.api.nvim_create_autocmd("User", {
            pattern = "ClaudeCodeSendComplete",
            desc = "Focus the Claude pane after sending to it",
            callback = function()
              if vim.env.TMUX then
                vim.system({ "tmux", "select-pane", "-t", "{right-of}" })
              end
            end,
          })
        end
      '';
    }
  ];
}
