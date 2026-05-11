# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common commands

All workflows assume you're inside the devshell (`nix develop`, or via `direnv` which is wired up through `.envrc`). The devshell sets `NIX_CONFIG` so `nix-plugins` provides the `extraBuiltins.ageImportEncrypted` builtin — without it, `flake.nix` evaluation fails on `meta.nix.age` decryption (you'll be prompted for the age passphrase the first time it runs in a session; results are cached under `/var/tmp/nix-import-encrypted/$UID/`).

- Format the tree: `nix fmt` (treefmt runs `nixpkgs-fmt` + `deadnix`; configured in `treefmt.nix`).
- Build a host's toplevel: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`. Shortcut for deckard: `nix-build-deckard` (devshell command). Hosts are auto-discovered from `hosts/<arch>/<name>/`.
- Rebuild a host remotely: `nixos-rebuild switch --flake .#<host> --target-host <host>.local --use-remote-sudo`.
- Deploy via deploy-rs: `deploy .#<host>` (configured in `nix/deployment.nix`; `autoRollback` and `magicRollback` are on).
- Build the installer ISO: `nix build .#live-iso`. Flash it to USB (interactive fzf disk picker): `flash-deckard-iso` (devshell command). Boot the USB, then run `sudo install-system` to format with disko and `nixos-install`. The installer is currently wired to deckard's `disko-config.nix`.
- Edit secrets: `agenix -e <file>.age` from `secrets/`. Recipient keys are listed per file in `secrets/secrets.nix`; rekey after changing them.
- Render network topology: `nix build .#topology.x86_64-linux.config.output` (defined in `topology.nix` via `nix-topology`).

## Architecture

### Flake structure

`flake.nix` uses `flake-parts`. `./nix/default.nix` imports four flake modules:

- `nix/hosts.nix` — auto-discovers hosts and produces `nixosConfigurations`.
- `nix/deployment.nix` — generates `deploy.nodes` for deploy-rs mirroring those hosts.
- `nix/devshell.nix` — the development shell (agenix, deploy-rs, age, cloudflared) plus the `NIX_CONFIG` env for `nix-plugins`.
- `nix/iso.nix` — builds `packages.live-iso` containing disko helpers and `install-system`.

`./modules/default.nix` re-exports two module sets via flake outputs:

- `flake.nixosModules.*` from `modules/nixos/` (e.g. `grafana`, `kanidm`, `proxy`, `backup`, `impermanence`, `meta`, `zfs`, `oauth2`, `oauth2-proxy`, ...).
- `flake.homeModules.*` from `modules/hm/` (`base`, `nvim`, `git`, `zsh`).

### Host auto-discovery

`nix/hosts.nix` walks `hosts/`. Each top-level directory is a `system` (e.g. `x86_64-linux`, `aarch64-linux`); each subdirectory under it is a host. The per-system `hosts/<arch>/default.nix` is the host *factory* — it returns `{ name }:` that builds the right kind of system:

- x86_64: `inputs.nixpkgs.lib.nixosSystem` with `pkgs-stable`/`pkgs-unstable` passed as `specialArgs`.
- aarch64: `inputs.nixos-raspberrypi.lib.nixosSystemFull` (provides the Pi kernel & firmware).

Both factories pass `nodes = config.nixosConfigurations` so any host can refer to siblings via `nodes.<other-host>`. To add a new host, create `hosts/<arch>/<name>/default.nix` — it's discovered automatically and gets a corresponding `deploy.nodes.<name>` entry.

### How a host is composed

A host `default.nix` (see `hosts/x86_64-linux/deckard/default.nix` for the canonical example) does three things:

1. Imports `inputs.self.nixosModules.<feature>` for the features it wants from `modules/nixos/`.
2. Imports host-local files (`hardware-configuration.nix`, `disko-config.nix`, `impermanence.nix`, `topology.nix`, plus any host-specific service files like `linkwarden.nix`, `headscale.nix`, `mattermost.nix`).
3. Sets `config.homelab.hostname = "<name>"` and wires home-manager for the `kghost` user from `inputs.self.homeModules.*`.

Hosts in service today: `deckard` (main x86_64 homelab — Grafana/Prometheus/Loki, kanidm, linkwarden, ESPHome), `thunder` (VPS — headscale, blog, mattermost, DNS, cloudflare tunnel), `beast` (workstation x86_64 with nvidia), and `malina5` (Raspberry Pi 5 — Home Assistant, Zigbee2MQTT, Mosquitto).

### Secrets and `homelab.*` options

`modules/nixos/meta.nix` declares the `homelab.*` option tree (hostname, `ext-domain`, `sec-domain`, `vpnCidr`, per-host VLAN IPs, VPS interfaces). The *values* live in `secrets/meta.nix.age` and are read at flake-eval time via the custom `extraBuiltins.ageImportEncrypted` from `nix/extra-builtins.nix` (which calls `nix/age-decrypt-and-cache.sh`). This is why the devshell is required — outside it, the builtin is missing and `meta.nix` throws.

Other agenix secrets are referenced through `config.age.secrets.<name>.path` inside individual modules (e.g. `modules/nixos/backup.nix`, `modules/nixos/proxy.nix`). Recipients per file are in `secrets/secrets.nix`; the master identity is `~/.ssh/id_ed25519`.

### Impermanence + ZFS layout

Most hosts use `nixos-server`'s impermanence pattern (`modules/nixos/impermanence.nix`):

- `/persist` — kept forever, backed up.
- `/state` — kept across reboots, *not* backed up (logs, `/var/lib/nixos`, tailscale state).
- Root is rolled back to `rpool1/local/root@blank` on each boot.
- `zfs-diff` is installed as a system command to surface files that survived a reboot but aren't declared in `environment.persistence`.

`modules/nixos/backup.nix` snapshots `rpool1/safe/persist` to a BorgBase repo on a schedule (defaults: daily, keep 3 daily / 2 weekly / 3 monthly). Hosts set `backup.name` and `backup.repoId`.

### nixpkgs channels

`nixpkgs-stable` is `nixos-25.11` and is the default (`nixpkgs.follows = "nixpkgs-stable"`). `nixpkgs-unstable` and `linkwardenPkgs` (nixpkgs master) are both passed to hosts via `specialArgs` for selective use.
