# AGENTS.md

Guidance for AI agents (Claude Code, Copilot, Cursor, …) and humans working in
this repository. This is the single canonical instructions file.

## Two repositories, two roles

This repo is **`homelab-config`** — the *source of truth for how the system is
configured* (NixOS modules, host definitions, nginx, oauth2-proxy, Kanidm, Home
Assistant, compose, …). It answers **"how is the system configured?"**

Documentation lives in a **sibling repo**:

```
../homelab-docs
```

It is the *source of knowledge* — Markdown answering **why / how / when / what to
do when**. It is self-describing; browse or `ripgrep` the tree to find the right
page, and follow whatever structure/conventions the repo itself documents.

## Before changing a service

1. **Read the documentation** in `../homelab-docs` for that service (and any
   related architecture/decision notes).
2. **Inspect the configuration** here — the code is authoritative for the current
   state.
3. **If documentation disagrees with configuration, the configuration wins.** The
   docs may be stale; never "fix" working config to match a doc without checking.
4. **Propose a documentation update** when your change makes a doc inaccurate, or
   when you discover something non-obvious that isn't written down.

## Source-of-truth hierarchy

When sources conflict, trust them in this order:

```
homelab-config   (this repo — configuration)
      ↓
homelab-docs     (the "why" and operational knowledge)
```

Configuration always wins.

## Common commands (in-repo)

All workflows assume you're inside the devshell (`nix develop`, or via `direnv` which is wired up through `.envrc`). The devshell sets `NIX_CONFIG` so `nix-plugins` provides the `extraBuiltins.ageImportEncrypted` builtin — without it, `flake.nix` evaluation fails on `meta.nix.age` decryption (you'll be prompted for the age passphrase the first time it runs in a session; results are cached under `/var/tmp/nix-import-encrypted/$UID/`).

Build/eval/format commands you run *here* on the flake:

- Format the tree: `nix fmt` (treefmt runs `nixpkgs-fmt` + `deadnix`; configured in `treefmt.nix`).
- Eval a host without building (cheap check): `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
- Build a host's toplevel: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`. Shortcut for deckard: `nix-build-deckard` (devshell command). Hosts are auto-discovered from `hosts/<arch>/<name>/`.
- Build the installer ISO: `nix build .#live-iso`. Flash it to USB (interactive fzf disk picker): `flash-deckard-iso` (devshell command). Boot the USB, then run `sudo install-system` to format with disko and `nixos-install`. The installer is currently wired to deckard's `disko-config.nix`.
- Render network topology: `nix build .#topology.x86_64-linux.config.output` (defined in `topology.nix` via `nix-topology`).

**Operational procedures live in the docs' runbooks** (`../homelab-docs/runbooks/`), not here — deploy, roll back, restore from Borg, and edit/rekey secrets each have a page. This file keeps only the flake mechanics an agent needs in-repo.

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

The fleet (which hosts exist, roles, build kinds) is single-sourced in the docs — see `../homelab-docs/inventory/hosts.md`; the per-service map (host · domain · port · auth · config) is in `../homelab-docs/services/index.md`. Don't restate them here. (deckard is decommissioned but its `hosts/x86_64-linux/deckard/` config is kept as the canonical reference example.)

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
8. **Verify** — `git add` new files first (flakes only see git-tracked files), `nix fmt`, then eval without a full build: `nix eval .#nixosConfigurations.<H>.config.system.build.toplevel.drvPath`. Eval both the app host and thunder if you touched kanidm/dns/dashy. Deploy thunder before H so DNS/kanidm land first. If this service added a new `/persist` directory (step 6), H's **first** activation needs a reboot — see "First deploy of a new persisted directory" below; a plain `deploy .#<H>` will fail and roll back.

### Secrets and `homelab.*` options

`modules/nixos/meta.nix` declares the `homelab.*` option tree (hostname, `ext-domain`, `sec-domain`, `vpnCidr`, per-host VLAN IPs, VPS interfaces). The *values* live in `secrets/meta.nix.age` and are read at flake-eval time via the custom `extraBuiltins.ageImportEncrypted` from `nix/extra-builtins.nix` (which calls `nix/age-decrypt-and-cache.sh`). This is why the devshell is required — outside it, the builtin is missing and `meta.nix` throws.

Other agenix secrets are referenced through `config.age.secrets.<name>.path` inside individual modules (e.g. `modules/nixos/backup.nix`, `modules/nixos/proxy.nix`). Recipients per file are in `secrets/secrets.nix`; the master identity is `~/.ssh/id_ed25519`.

### Impermanence, backup & binary cache

The *conceptual* model — impermanence (`/persist` backed up, `/state` not, root rolled back to blank each boot), the ZFS-snapshot → BorgBase backup convention (no per-app jobs), and the attic binary cache — is single-sourced in the docs: `../homelab-docs/architecture/overview.md` (with the restore procedure in `../homelab-docs/runbooks/restore-from-borg.md`). Only the in-repo config hooks belong here:

- Impermanence: `modules/nixos/impermanence.nix`; declare kept paths with `environment.persistence."/persist".directories`. `zfs-diff` (system command) surfaces files that survived a reboot but aren't declared.
- Backup: `modules/nixos/backup.nix` snapshots `rpool1/safe/persist` (beast also `dpool/safe/persist`); per-host set `backup.name` and `backup.repoId` (defaults: daily, keep 3 daily / 2 weekly / 3 monthly).
- Cache: `malina5` runs `atticd`; `malina5` + `beast` run `attic-watch-store` to auto-push to `malina5:system`. atticd data is on `/state` (not backed up — losing it means re-pushing NARs and rotating the pubkey in `flake.nix`). `nix-remote-builder` on `malina5` accepts aarch64 builds from `root@focus`.

#### First deploy of a *new* persisted directory needs a reboot (not a live switch)

Adding a new `environment.persistence."/persist".directories` entry creates a new bind mount (e.g. `var-lib-<svc>.mount`, `/persist/var/lib/<svc>` → `/var/lib/<svc>`). That mount only establishes cleanly at **boot** — impermanence mounts it `Before=local-fs.target` (before `systemd-tmpfiles-setup` and before the service), so tmpfiles creates the service's subdirs *inside* the mount and the unit starts against a populated `/persist`.

On a **live `nixos-rebuild switch` / `deploy`**, the brand-new mount races: systemd starts the service before the mount has finished mounting, and `RequiresMountsFor` does **not** gate it (when `/var/lib/<svc>` isn't yet a mountpoint the dependency resolves to `/`, not the new bind mount). tmpfiles then writes the skeleton to the ephemeral root fs, and any unit that sandboxes on the new path (`ReadWritePaths=`, `StateDirectory=`) dies at namespace setup with `226/NAMESPACE … No such file or directory`. This is the "boot vs. live switch" race already documented in `hosts/x86_64-linux/beast/paperless.nix`.

With **deploy-rs this is fatal**: `autoRollback`/`magicRollback` see the failed unit and roll the whole generation back, so the mount is torn down before you can reboot — the deploy can never converge. Two ways through, for the first activation only:

- **Preferred — stage then boot** (no live switch runs at all):
  ```
  nixos-rebuild boot --flake .#<H> --target-host <H> --use-remote-sudo
  ssh <H> sudo reboot
  ```
- **Or — live switch then reboot** (leaves the new unit failed until the reboot; use plain `nixos-rebuild`, *not* `deploy`, so nothing auto-rolls-back):
  ```
  nixos-rebuild switch --flake .#<H> --target-host <H> --use-remote-sudo   # new unit fails this round — expected
  ssh <H> sudo reboot
  ```

After that one boot the mount persists across subsequent live switches, so ordinary `deploy .#<H>` works from then on — the reboot is a one-time cost of introducing the persist dir, not a per-change requirement. No config change fixes this; it's inherent to adding the mount. (A stray skeleton left on the root fs by a failed switch is harmless — it vanishes on the next boot's root rollback.)
