{
  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
      "https://attic.typesafebrew.dev/system"
      "https://comfyui.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "system:WOAVhhRoFrTy1MfcJyEzHLOa737CJZOGZccwOiwhfoU="
      "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
    ];
    connect-timeout = 5;
  };
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs.follows = "nixpkgs-stable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    # flake-parts
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flake-root.url = "github:srid/flake-root";
    devshell.url = "github:numtide/devshell";

    # utilities
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs.url = "github:serokell/deploy-rs";

    nix-topology = {
      url = "github:oddlama/nix-topology";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostbuster91-blog = {
      url = "github:ghostbuster91/blogposts";
    };

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };

    nixos-sbc = {
      url = "github:ghostbuster91/nixos-sbc/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP server + Neovim plugin that lets Claude Code talk to a running
    # Neovim (LSP diagnostics, hover, code actions). Deliberately not
    # following our nixpkgs: upstream builds the Rust server with its own
    # fenix toolchain pinned against nixpkgs-unstable.
    # Fork, for one fix: upstream's injected autocmds notify `rpcnotify(0, ...)`,
    # which broadcasts to every channel — including nvim 0.12's TUI, which runs as
    # a separate process over RPC and answers an unknown method with a visible
    # `Invalid method: NVIM_MCP_LspAttach` on every LSP attach.
    nvim-mcp = {
      url = "github:ghostbuster91/nvim-mcp";
    };

    # Repeatable-movements engine for Neovim: `;` / `,` repeat whatever
    # next/prev motion was used last (diagnostic, git hunk, merge conflict,
    # f/t), instead of every plugin stealing `;` for itself. Upstream's flake
    # only uses nixpkgs for `vimUtils.buildVimPlugin`, so it can follow ours.
    nvim-next = {
      url = "github:ghostbuster91/nvim-next";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Parallel development: one git worktree + tmux window per task, with the
    # agent's status rendered into the window name. Upstream's flake tracks
    # nixos-unstable, but the package is a plain `rustPlatform.buildRustPackage`
    # with no toolchain pinning, so following our nixpkgs keeps one rustc in the
    # closure instead of two.
    workmux = {
      url = "github:raine/workmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imports = [
        ./nix
        ./modules
        inputs.treefmt-nix.flakeModule
        inputs.devshell.flakeModule
        inputs.flake-root.flakeModule
        inputs.nix-topology.flakeModule
      ];
      perSystem.treefmt = {
        imports = [ ./treefmt.nix ];
      };
      perSystem.topology = {
        modules = [ ./topology.nix ];
      };
    };
}

