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
- Browse a host's backup: `explore-backup-<host>` (devshell command, available for deckard, malina5, thunder, beast) — mounts the BorgBase repo and drops into a subshell.
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
- aarch64 (malina5): `inputs.nixos-raspberrypi.lib.nixosSystemFull` (provides the Pi kernel & firmware).
- aarch64 (surfer): `inputs.nixos-sbc.inputs.nixpkgs.lib.nixosSystem` (Banana Pi R3 SBC board via nixos-sbc).

Both factories pass `nodes = config.nixosConfigurations` so any host can refer to siblings via `nodes.<other-host>`. To add a new host, create `hosts/<arch>/<name>/default.nix` — it's discovered automatically and gets a corresponding `deploy.nodes.<name>` entry.

### How a host is composed

A host `default.nix` (see `hosts/x86_64-linux/deckard/default.nix` for the canonical example — note deckard is decommissioned but its config is kept for reference) does three things:

1. Imports `inputs.self.nixosModules.<feature>` for the features it wants from `modules/nixos/`.
2. Imports host-local files (`hardware-configuration.nix`, `disko-config.nix`, `impermanence.nix`, `topology.nix`, plus any host-specific service files like `linkwarden.nix`, `headscale.nix`, `mattermost.nix`).
3. Sets `config.homelab.hostname = "<name>"` and wires home-manager for the `kghost` user from `inputs.self.homeModules.*`.

Hosts in service today: `thunder` (VPS — headscale, blog, mattermost, DNS, cloudflare tunnel, kanidm), `beast` (workstation x86_64 with nvidia), `malina5` (Raspberry Pi 5 — Home Assistant, Zigbee2MQTT, Mosquitto, atticd binary cache), and `surfer` (Banana Pi R3 — hostapd WiFi AP, monitoring). `deckard` (formerly the main x86_64 homelab — Grafana/Prometheus/Loki, kanidm, linkwarden, ESPHome) is **decommissioned**; its `hosts/x86_64-linux/deckard/` config is retained only as a reference example and is not deployed.

### Adding a new web service (runbook)

Most new services follow the same shape. Copy the closest existing example rather than starting blank — the three canonical templates are:

- **Native OIDC client** (app speaks OIDC itself): `hosts/aarch64-linux/malina5/mealie.nix` + its `systems.oauth2.mealie` block in `modules/nixos/kanidm.nix`. Also: `paperless.nix` (beast), grafana, linkwarden.
- **oauth2-proxy gated** (app has no/weak auth): `hosts/x86_64-linux/beast/comfyui.nix` — sets `services.nginx.virtualHosts.<d>.oauth2 = { enable = true; allowedGroups = [ ... ]; };`.
- **Own auth, VPN-only** (kept independent of the IdP): `hosts/x86_64-linux/thunder/vaultwarden.nix`.

Steps (a service on host H reachable at `svc.<ext-domain>`):

1. **Service file** — create `hosts/<arch>/<H>/<svc>.nix` and add it to that host's `default.nix` `imports`. Bind the app to loopback (`127.0.0.1:<port>`).
2. **nginx vhost** (in the service file): `forceSSL = true; useACMEHost = config.homelab.ext-domain;` (wildcard cert comes from `modules/nixos/proxy.nix`), a loopback `proxyPass` with `recommendedProxySettings`, `proxyWebsockets = true` if it needs live updates, and `client_max_body_size` if it takes uploads.
3. **DNS** — add `''"svc.${ext-domain}. IN A ${<H>Ip}"''` to `hosts/x86_64-linux/thunder/dns.nix` (`<H>Ip` from `config.homelab.<H>.vlan.ip`). All homelab DNS is VPN-only via thunder's unbound; there is no public record, so a beast/malina5 vhost needs no extra allow/deny block (thunder's public-facing vhosts like vaultwarden add one as defense-in-depth).
4. **Auth**:
   - *Native OIDC*: in `modules/nixos/kanidm.nix` add `groups."<svc>.access" = { }` and `systems.oauth2.<svc>` with `basicSecretFile`, `scopeMaps."<svc>.access" = [ "openid" "email" "profile" ]`, `originUrl` = the app's **exact** callback path, `preferShortUsername = true`. Grant access by adding `<svc>.access` to the relevant `persons`. Some clients need `enableLegacyCrypto = true` (RS256) — Mealie/Linkwarden do, Grafana doesn't; symptom is a token signature/alg error on first login.
   - *oauth2-proxy gate*: the `allowedGroups` values are the **claim values** emitted by the `web-sentinel` client's `claimMaps.groups` in `kanidm.nix` — add a `web-sentinel.<svc>` group and a `valuesByGroup."web-sentinel.<svc>" = [ "access_<svc>" ]` there, then reference `access_<svc>` in the vhost. The login portal lives on thunder; other hosts run oauth2-proxy only for local validation (`meta.oauth2-proxy.servePortal = false`).
5. **Secrets** (see the Secrets section below for mechanics):
   - A kanidm OIDC client secret must be decryptable on **both** the kanidm host (thunder) *and* the app host. Either one age file listing both host pubkeys, or — when the app needs it in a different shape — two files holding the same value (the Mealie/Paperless pattern: `kanidm-oauth2-<svc>.age` on thunder + a host-shaped file on H). Register in `secrets/secrets.nix` and create with `age -r <pubkey> -o <file>.age` (host pubkeys are the `let` bindings at the top of `secrets.nix`).
   - **Never put a secret in a module's `settings`/`environment`** — most NixOS service modules bake those into the world-readable Nix store. Prefer the module's own secret option (`environmentFile`, `credentialsFile`, `passwordFile`); if there is none, render an `EnvironmentFile` at runtime from a oneshot (see `paperless.nix`). Always check the module source for how `settings` reach the unit before trusting it.
6. **Storage & backup** — persist the app's data dir with `environment.persistence."/persist".directories = [ { directory = "/var/lib/<svc>"; user/group/mode; } ]` (use standard `/var/lib` paths + impermanence, not raw `/persist/...`). That dataset (`rpool1/safe/persist`; on beast also `/data/persist` = `dpool/safe/persist`) is snapshotted and borg'd by `modules/nixos/backup.nix` — **do not add a per-app backup job**. Reproducible caches go on `/state` or (beast) `/data/local`, which are not backed up.
7. **Dashy tile** — add an item to `hosts/x86_64-linux/thunder/dashy.nix`; gate visibility with `// gate "<value>"` and add `"<svc>.access" = [ "<value>" ]` to the **dashy** client's `claimMaps.groups.valuesByGroup` in `kanidm.nix` (not the `groups` scope).
8. **Verify** — `git add` new files first (flakes only see git-tracked files), `nix fmt`, then eval without a full build: `nix eval .#nixosConfigurations.<H>.config.system.build.toplevel.drvPath`. Eval both the app host and thunder if you touched kanidm/dns/dashy. Deploy thunder before H so DNS/kanidm land first.

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

### Binary cache (attic)

`malina5` runs `atticd` (served at `attic.<ext-domain>`) as the homelab's Nix binary cache. Both `malina5` and `beast` run the `attic-watch-store` module which auto-pushes new store paths to the `malina5:system` cache. The atticd data lives on `/state` (not backed up — losing it means re-pushing NARs and rotating the pubkey in `flake.nix`). The `nix-remote-builder` module on `malina5` also accepts aarch64 remote builds from `root@focus` over SSH, letting x86_64 hosts cross-compile for aarch64.

### nixpkgs channels

`nixpkgs-stable` is `nixos-25.11` and is the default (`nixpkgs.follows = "nixpkgs-stable"`). `nixpkgs-unstable` and `linkwardenPkgs` (nixpkgs master) are both passed to hosts via `specialArgs` for selective use.
