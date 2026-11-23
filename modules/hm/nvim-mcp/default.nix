{ pkgs, lib, inputs, ... }:
# Bridges Claude Code and a running Neovim: the plugin opens a per-repo RPC
# socket, the Rust MCP server connects to it and exposes LSP diagnostics,
# hover and code actions as MCP tools.
#
# Opt-in per host (it builds the Rust server from source) — see beast.
let
  server = inputs.nvim-mcp.packages.${pkgs.stdenv.hostPlatform.system}.default;

  plugin = pkgs.vimUtils.buildVimPlugin {
    pname = "nvim-mcp";
    version = inputs.nvim-mcp.shortRev or "unstable";
    src = inputs.nvim-mcp;
  };
in
{
  programs.neovim.plugins = [
    {
      inherit plugin;
      type = "lua";
      config = ''
        -- git spawns throwaway Neovim instances to edit commit/merge/rebase
        -- messages. Those load this config too, and every setup() call
        -- registers another socket for the same git root — which makes
        -- `--connect auto` pick an editor that is about to exit. Skip them.
        local transient = false
        for _, arg in ipairs(vim.fn.argv()) do
          if arg:match("COMMIT_EDITMSG$") or arg:match("MERGE_MSG$")
            or arg:match("git%-rebase%-todo$") or arg:match("TAG_EDITMSG$") then
            transient = true
          end
        end
        if not transient then
          require("nvim-mcp").setup({})
          -- Keeps whatever Claude resolves "this line" / "ten fragment" to
          -- visible once focus moves to its pane; see pointer.lua.
          ${builtins.readFile ./pointer.lua}
        end
      '';
    }
  ];

  # The server CLI, for debugging a connection by hand
  # (`nvim-mcp --connect auto --log-level debug`).
  home.packages = [ server ];

  programs.claude-code = {
    enable = true;
    # Deliberately no `settings` / `context`: the MCP server is injected by
    # wrapping the claude binary with `--plugin-dir`, so the only thing this
    # adds under ~/.claude is the skill below — settings.json, CLAUDE.md and
    # the memory dir stay hand-managed as they are today.

    # Teaches Claude that "this line" / "ten fragment" means the cursor or the
    # visual selection in the running Neovim, not something to grep for.
    skills.nvim-cursor-context = ./skills/nvim-cursor-context/SKILL.md;
    mcpServers.nvim = {
      type = "stdio";
      command = lib.getExe server;
      args = [ "--connect" "auto" ];
    };
  };
}
