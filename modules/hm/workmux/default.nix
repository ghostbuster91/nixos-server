{ pkgs, lib, inputs, ... }:
# workmux: one git worktree + one tmux window per task, so several agents can
# work in parallel without branch switching or stashing. `workmux add <name>`
# creates the worktree, opens the window and starts the agent in it; `workmux
# merge` rebases, merges and tears the whole thing down again.
#
# Needs tmux (../tmux), plus agy (default agent) and/or claude-code (`-a claude`)
# for the status icons and skills — all imported alongside this module on beast.
let
  workmux =
    (inputs.workmux.packages.${pkgs.stdenv.hostPlatform.system}.default).overrideAttrs
      (old: {
        # One of the 2301 unit tests is a stopwatch race and fails on beast.
        # `conditional_consumption_preserves_atomic_replacement` writes an agent
        # state file, snapshots its revision, then rewrites it with a changed
        # payload and asserts the revision guard refuses to delete it. But
        # `write_raw_agent` uses `fs::write`, which truncates in place (same
        # dev/ino), both payloads are the same byte length, and the revision is
        # dev/ino/len/mtime/ctime — so the two writes are distinguishable only by
        # timestamp. Inode timestamps come from the coarse clock (CONFIG_HZ=1000
        # here, so 1 ms), which both writes comfortably fit inside. Nothing to do
        # with our rustc: it is a function of how fast the machine is.
        checkFlags = (old.checkFlags or [ ]) ++ [
          "--skip=state::store::tests::conditional_consumption_preserves_atomic_replacement"
        ];
      });

  # Upstream's repo root *is* the Claude Code plugin: `.claude-plugin/` sits
  # next to `src/`, `docs/`, `tests/`… Since `programs.claude-code.plugins`
  # hands each entry to `--plugin-dir`, pass a tree with only the two things
  # Claude reads — the hook manifest and the skills — instead of the whole
  # checkout.
  claude-plugin = pkgs.runCommand "workmux-claude-plugin" { } ''
    mkdir -p $out
    cp -r ${inputs.workmux}/.claude-plugin ${inputs.workmux}/skills $out/
  '';

  # Status hooks for Antigravity (`agy`), matching upstream's
  # `src/agent_setup/antigravity.rs` so `workmux` sees them as already installed
  # and drives the 🤖/✅ icons + sidebar registration. Each command ends with
  # `printf '{}\n'` because Antigravity hooks must return a JSON object on stdout.
  agy-hooks = (pkgs.formats.json { }).generate "workmux-agy-hooks.json" {
    workmux-status = {
      PreInvocation = [
        {
          type = "command";
          command = "workmux register-agent >/dev/null 2>&1 || true; printf '{}\\n'";
        }
        {
          type = "command";
          command = "workmux set-window-status working >/dev/null 2>&1 || true; printf '{}\\n'";
        }
      ];
      Stop = [
        {
          type = "command";
          command = "workmux set-window-status done >/dev/null 2>&1 || true; printf '{}\\n'";
        }
      ];
    };
  };

  # Expose workmux's bundled skills (/merge /rebase /worktree /coordinator
  # /open-pr /workmux) to Antigravity globally as un-namespaced skills so
  # `dashboard.merge = "/merge"` works identically in agy and Claude.
  agy-skills = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".gemini/config/skills/${name}" {
        source = "${inputs.workmux}/skills/${name}";
      })
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${inputs.workmux}/skills"));

  settings = {
    # Alacritty and tmux render JetBrains Mono Nerd Font (see ../alacritty), so
    # the glyph window prefix resolves instead of showing tofu. Setting it
    # explicitly also stops the first-run wizard from asking.
    nerdfont = true;
    agent = "agy";

    # Named agent overrides. Carrying Claude's `--ide` flag here instead of on
    # `<agent> --ide` below lets `agy` (which has no `--ide` flag) be the
    # default while `workmux add -a claude <name>` still launches `claude --ide`
    # with Claude's native profile and claudecode.nvim bridge intact.
    agents = {
      claude = "claude --ide";
    };

    merge_strategy = "merge";

    # Upstream puts worktrees in a `<project>__worktrees` sibling of the repo,
    # which would add a second visible entry per project to ~/workspace (~40
    # repos) and make z/fzf match worktrees as if they were top-level checkouts
    # — hence the hidden `.worktrees/` parent. The `__worktrees` suffix stays,
    # though, because it is a sentinel and not just a convention: the dashboard,
    # the sidebar and the project picker all label agents through
    # `extract_project_name` (src/agent_display.rs), which only understands
    # `<project>__worktrees/<branch>` and `<repo>/.worktrees/<branch>` (the
    # latter by finding a `.git` *directory*, which a linked worktree never
    # has). A plain `.worktrees/{project}/<branch>` matches neither and falls
    # through to the last resort — the leaf directory name — so every agent gets
    # labelled with its branch instead of its project.
    worktree_dir = "~/workspace/.worktrees/{project}__worktrees";

    # Neovim down the left half, the agent top right (focused), a plain shell
    # for git/nix commands bottom right. `split: horizontal` is tmux's `-h`
    # (left/right), `vertical` is `-v` (top/bottom); each pane splits the one
    # before it, so the shell halves the agent's pane and nvim keeps full
    # height. Pane commands are typed into an interactive shell (workmux uses
    # send-keys), which is what lets direnv load the devshell before the
    # commands run.
    #
    # nvim is listed *first* on purpose, and the editor bridges depend on it:
    # ../nvim-mcp's plugin opens the per-repo RPC socket when Neovim starts and
    # `nvim-mcp --connect auto` resolves it by git root, while ../claudecode's
    # plugin writes a ~/.claude/ide/<port>.lock that `claude --ide` (resolved
    # via `agents.claude` when `-a claude` is passed) connects to the same way —
    # so the editor has to be up before the agent.
    panes = [
      { command = "nvim"; }
      { command = "<agent>"; split = "horizontal"; percentage = 50; focus = true; }
      { split = "vertical"; percentage = 50; }
    ];

    files.symlink = [
      # A worktree is a separate project directory to Claude Code, so granted
      # tool permissions would otherwise start from zero in every one of them.
      # Skipped silently in repos that have no such file.
      ".claude/settings.local.json"
    ];

    post_create = [
      # Nearly every repo here is a flake behind direnv. `direnv allow` only
      # marks the (fresh, and therefore untrusted) .envrc path trusted; the
      # shell in each pane does the actual loading.
      "test -f .envrc && direnv allow || true"
    ];

    # The /merge skill below, bound to `m` in `workmux dashboard`. It commits
    # with the agent's context, rebases with conflict resolution, then runs
    # `workmux merge` — more than the bare merge the key does by default.
    dashboard.merge = "/merge";
  };
in
{
  # Carries its own bash/zsh/fish completions, so deliberately no
  # `eval "$(workmux completions zsh)"` in ../zsh.
  home.packages = [ workmux ];

  # Lives here rather than in ../zsh so the alias only exists on hosts that
  # actually have the binary. Spelled as the bare command, not a store path like
  # the `lsd` alias: COMPLETE_ALIASES is off, so zsh expands the alias before
  # completing and `wm <TAB>` inherits the package's own `_workmux` completions.
  programs.zsh.shellAliases.wm = "workmux";

  # A read-only store symlink, which costs the two places workmux writes back to
  # its own config: `workmux config edit`, and persisting a dashboard colour
  # scheme with `T`. Set `theme` here instead.
  xdg.configFile."workmux/config.yaml".source =
    (pkgs.formats.yaml { }).generate "workmux-config.yaml" settings;

  # Antigravity status hooks (matching workmux's `antigravity.rs` check) +
  # workmux's bundled skills under ~/.gemini/config/skills/<name>. Unlike
  # Claude's settings.json, agy keeps its own settings under
  # ~/.gemini/antigravity-cli/settings.json, so managing hooks.json here does
  # not interfere with agy's runtime settings.
  home.file = {
    ".gemini/config/hooks.json".source = agy-hooks;
  } // agy-skills;

  programs.claude-code = {
    # Already enabled by ../nvim-mcp on the host that imports both; repeated so
    # this module stands on its own, since `plugins` is silently dropped when
    # claude-code is disabled.
    enable = true;

    # Gives Claude the status hooks (SessionStart → `workmux register-agent`,
    # then working/waiting/done via `workmux set-window-status`) that drive the
    # 🤖/💬/✅ icons in the tmux window name, plus workmux's six skills
    # (/workmux /merge /rebase /worktree /coordinator /open-pr). ~256 tokens
    # always-on per session; `claude plugin details workmux-status@inline`
    # breaks the cost down.
    #
    # Going through `--plugin-dir` keeps ~/.claude/settings.json hand-managed —
    # but it also means `workmux` can't see the hooks (it looks for them in
    # settings.json) and will offer to install them on first run. Decline it;
    # the answer is remembered in ~/.local/state/workmux.
    plugins = [ claude-plugin ];
  };

  # mkAfter so this lands at the end of tmux.conf. ../tmux is a separate option
  # definition and is emitted ~100 lines earlier, and tmux keeps the *last*
  # binding for a key — without this, any key both modules touch silently
  # resolves to ../tmux's version on every `prefix+r`.
  programs.tmux.extraConfig = lib.mkAfter ''
    # workmux: Tab toggles between the two agents last visited, l cycles the
    # ones that finished or are waiting for input. 
    bind Tab run-shell "${workmux}/bin/workmux last-agent"
    unbind l
    bind l run-shell "${workmux}/bin/workmux last-done"

    # Show/hide the agent sidebar. The bare command is itself a toggle, so one
    # key does both; it pins the sidebar into every window of every session
    # (add `--session` to scope it to this one). Shadows tmux's mark-pane.
    unbind m
    bind m run-shell "${workmux}/bin/workmux sidebar"

    # The dashboard is a full-screen TUI, so unlike the three above it cannot go
    # through run-shell: that gives the command no tty and it exits 1 with
    # "No such device or address (os error 6)". -E closes the popup again when
    # the dashboard exits.
    unbind t
    bind t display-popup -w 90% -h 90% -E "${workmux}/bin/workmux dashboard"

    # prefix+A asks for a name and spawns a worktree for it. command-prompt does
    # the asking; the popup is what gives `add` a terminal, so its output — and
    # the one-time status-hook wizard — is visible rather than swallowed, and -d
    # pins it to the repo of the pane you pressed it from. The window `add`
    # creates at the end still becomes the client's active one from inside the
    # overlay.
    unbind a
    bind a command-prompt -p "workmux add:" "display-popup -E -d \"#{pane_current_path}\" -w 80% -h 60% \"${workmux}/bin/workmux add '%%'\""
  '';
}
