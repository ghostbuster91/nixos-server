{ pkgs, lib, inputs, ... }:
# workmux: one git worktree + one tmux window per task, so several agents can
# work in parallel without branch switching or stashing. `workmux add <name>`
# creates the worktree, opens the window and starts the agent in it; `workmux
# merge` rebases, merges and tears the whole thing down again.
#
# Needs tmux (../tmux) and, for the status icons and skills, claude-code —
# both are imported alongside this module on beast.
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

  settings = {
    # Alacritty and tmux render JetBrains Mono Nerd Font (see ../alacritty), so
    # the glyph window prefix resolves instead of showing tofu. Setting it
    # explicitly also stops the first-run wizard from asking.
    nerdfont = true;
    agent = "claude";
    # This repo's history is linear and so is every other one here.
    merge_strategy = "rebase";

    # Upstream's default is a `<project>__worktrees` sibling, which would put a
    # second visible entry per project into ~/workspace (~40 repos) and make
    # z/fzf match worktrees as if they were top-level checkouts.
    worktree_dir = "~/workspace/.worktrees/{project}";

    # Neovim down the left half, the agent top right (focused), a plain shell
    # for git/nix commands bottom right. `split: horizontal` is tmux's `-h`
    # (left/right), `vertical` is `-v` (top/bottom); each pane splits the one
    # before it, so the shell halves the agent's pane and nvim keeps full
    # height. Pane commands are typed into an interactive shell (workmux uses
    # send-keys), which is what lets direnv load the devshell before the
    # commands run.
    #
    # nvim is listed *first* on purpose, and both bridges to Claude depend on it:
    # ../nvim-mcp's plugin opens the per-repo RPC socket when Neovim starts and
    # the agent's `nvim-mcp --connect auto` resolves it by git root, while
    # ../claudecode's plugin writes a ~/.claude/ide/<port>.lock that `--ide`
    # below resolves the same way — so the editor has to be up before the agent.
    #
    # `--ide` rides on the placeholder rather than replacing it with `claude`:
    # workmux appends whatever follows `<agent>` to the command it resolves
    # (`parse_agent_placeholder_with_args`), so the status tracking and the
    # native prompt-injection flag still apply.
    panes = [
      { command = "nvim"; }
      { command = "<agent> --ide"; split = "horizontal"; percentage = 50; focus = true; }
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
