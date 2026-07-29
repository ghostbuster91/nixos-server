# Builds a bounded DNS-readiness gate, used as an ExecStartPre for services that
# resolve a VPN-only name (thunder's MagicDNS) at startup. Without the gate a
# transient lookup miss during a deploy makes the service exit non-zero, marks
# the unit failed, and trips deploy-rs autoRollback — reverting the whole node.
#
# Ordering the service `after = [ "tailscaled.service" ]` is not enough: the
# daemon reaching "active" does not mean the tailnet is connected and MagicDNS
# answers yet — that converges asynchronously afterwards. This probe waits for
# the name to actually resolve. Used as an ExecStartPre it re-runs on every
# start of the service, including the restart a `switch-to-configuration` does.
{ pkgs, lib }:
# host: the name to wait for. Waits up to tries*2s, then fails (which lets a
# genuinely-down resolver still surface rather than blocking forever).
host:
pkgs.writeShellScript "wait-for-dns-${host}" ''
  set -eu
  tries=150
  i=0
  while [ "$i" -lt "$tries" ]; do
    if ${pkgs.getent}/bin/getent ahosts ${lib.escapeShellArg host} >/dev/null 2>&1; then
      exit 0
    fi
    i=$((i + 1))
    sleep 2
  done
  echo "wait-for-dns: ${host} did not resolve after $((tries * 2))s" >&2
  exit 1
''
