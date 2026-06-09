# malina5

Raspberry Pi 5 homelab node.

## atticd persistence model

atticd state lives at `/var/lib/private/atticd/` (DynamicUser indirection — see `attic.nix`). The persistence config bind-mounts it from `/state`:

- `/state` survives reboots (root rolls back to `@blank` on each boot).
- `/state` is **not** backed up by borg — deliberate, so binary cache chunks don't bloat backups.

This means losing `/state` (disk failure, dataset destroy) loses the cache. What that actually costs:

| Item | Recovery |
|---|---|
| NAR chunks + metadata (`server.db`) | Re-push from builders — slow but mechanical |
| Cache definitions | `attic cache create system` |
| **Cache signing keypair** | Regenerated → new pubkey, must update `flake.nix` `extra-trusted-public-keys` and any host pinning it |
| JWT signing secret | Survives — lives in agenix (`secrets/atticd-env.age`), so existing tokens stay valid |

Treat the cache as a performance optimization, not a source of truth. The only meaningful pain on `/state` loss is rotating the cache pubkey in `flake.nix`.

## Pushing to the cache

`attic watch-store` runs on builders (`malina5`, `beast`) via the `attic-watch-store` module. It pushes new store paths automatically — no `post-build-hook` needed. Credentials live in `secrets/attic-pusher-config.age`.
