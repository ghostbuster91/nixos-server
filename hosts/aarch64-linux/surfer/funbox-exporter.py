#!/usr/bin/env python3
"""Poll the Orange FunBox (SoftAtHome) topology API and emit Prometheus
textfile metrics for node_exporter's textfile collector.

Config comes from the environment:
  FUNBOX_URL       ws endpoint            (default http://192.168.1.1/ws)
  FUNBOX_USER      admin username         (from the agenix EnvironmentFile)
  FUNBOX_PASSWORD  the credential the web UI SENDS in createContext -- the FunBox
                   JS transforms the typed password client-side with no server
                   nonce, so this static value is replayable and is what we store
                   (NOT the human password)   (from the agenix EnvironmentFile)
  TEXTFILE_DIR     node_exporter dir      (default /run/node-exporter-textfile)

Design notes (see ../../../AGENTS.md and the task write-up):
- The SAH session context is short-lived, so we log in via `createContext` each
  run and retry the login once if `buildTopology` is rejected (error 13).
- The context id must travel in BOTH the Authorization/X-Context headers AND the
  `sah/contextId` cookie -- header-only is rejected -- so cookies are tracked
  explicitly and the cookie is force-set from the context id if the server did
  not send it.
- Real client devices are the `edev`-tagged nodes nested under the interfaces;
  the HGW root and interface/bridge nodes are skipped by recursing Children and
  filtering on the `edev` tag, so interfaces are never counted as devices.
- The MAC (PhysAddress) is the only per-device key label; timestamps are emitted
  as metric *values*, never labels, to keep cardinality bounded.
- Health (scrape_success/duration) lives in a SEPARATE file that is always
  rewritten, so the device metrics in funbox.prom survive a transient outage
  (keeping their last-good values + timestamps) without ever producing duplicate
  series across the two files.
- Credentials and the session token are never written to stdout/stderr.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

URL = os.environ.get("FUNBOX_URL", "http://192.168.1.1/ws")
USER = os.environ.get("FUNBOX_USER", "")
PASSWORD = os.environ.get("FUNBOX_PASSWORD", "")
TEXTFILE_DIR = os.environ.get("TEXTFILE_DIR", "/run/node-exporter-textfile")
TIMEOUT = 15
CONTENT_TYPE = "application/x-sah-ws-4-call+json"


def _post(body, headers):
    data = json.dumps(body).encode()
    req = urllib.request.Request(URL, data=data, method="POST")
    req.add_header("Content-Type", CONTENT_TYPE)
    req.add_header("Accept", "*/*")
    for key, value in headers.items():
        req.add_header(key, value)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read(), (resp.headers.get_all("Set-Cookie") or [])


def login():
    """Authenticate and return (context_id, cookies_dict)."""
    body = {
        "service": "sah.Device.Information",
        "method": "createContext",
        "parameters": {
            "applicationName": "webui",
            "username": USER,
            "password": PASSWORD,
        },
    }
    raw, set_cookies = _post(body, {"Authorization": "X-Sah-Login"})
    obj = json.loads(raw)
    ctx = (obj.get("data") or {}).get("contextID")
    if not ctx:
        # Do not echo the response body -- it may carry session material.
        raise RuntimeError("login failed: no contextID returned")
    # Parse Set-Cookie manually: SAH uses a cookie name with a '/'
    # (e.g. "fc4718c6/sessid") which stdlib's SimpleCookie rejects.
    cookies = {}
    for header in set_cookies:
        pair = header.split(";", 1)[0].strip()
        if "=" in pair:
            name, value = pair.split("=", 1)
            cookies[name.strip()] = value.strip()
    # createContext only sets the sessid cookie; the webui sets sah/contextId
    # itself from the response body, so synthesize it the same way.
    cookies.setdefault("sah/contextId", urllib.parse.quote(ctx, safe=""))
    return ctx, cookies


def build_topology(ctx, cookies):
    headers = {
        "Authorization": "X-Sah " + ctx,
        "X-Context": ctx,
        "X-Sah-Request-Type": "idle",
        "Cookie": "; ".join(f"{k}={v}" for k, v in cookies.items()),
    }
    body = {
        "service": "TopologyDiagnostics",
        "method": "buildTopology",
        "parameters": {"SendXmlFile": False},
    }
    raw, _ = _post(body, headers)
    obj = json.loads(raw)
    if isinstance(obj, dict) and obj.get("errors"):
        codes = [e.get("error") for e in obj["errors"]]
        raise PermissionError(f"buildTopology rejected, error codes {codes}")
    return obj


def collect_devices(obj):
    """Recurse the topology tree and return the edev (client) nodes."""
    root = obj.get("status")
    if isinstance(root, list):
        root = root[0] if root else None
    devices = []

    def walk(node):
        if not isinstance(node, dict):
            return
        tags = node.get("Tags")
        if isinstance(tags, str) and "edev" in tags.split():
            devices.append(node)
        for child in node.get("Children") or []:
            walk(child)

    if root:
        walk(root)
    return devices


def epoch(value):
    if not value:
        return None
    try:
        dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return dt.replace(tzinfo=timezone.utc).timestamp()


def esc(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def mac_of(device):
    return esc(device.get("PhysAddress") or device.get("Key") or "")


def render(devices):
    out = []

    def family(name, typ, help_):
        out.append(f"# HELP {name} {help_}")
        out.append(f"# TYPE {name} {typ}")

    family(
        "funbox_device_info",
        "gauge",
        "Known device with identifying labels (value 1). "
        "interface_type is unreliable (the FunBox sees downstream Wi-Fi as wired); "
        "ip may change on DHCP renewal.",
    )
    for d in devices:
        reserved = "false"
        for addr in d.get("IPv4Address") or []:
            if addr.get("Reserved"):
                reserved = "true"
        out.append(
            'funbox_device_info{'
            f'mac="{mac_of(d)}",'
            f'name="{esc(d.get("Name") or "")}",'
            f'device_type="{esc(d.get("DeviceType") or "")}",'
            f'ip="{esc(d.get("IPAddress") or "")}",'
            f'interface_type="{esc(d.get("InterfaceType") or "")}",'
            f'reserved="{reserved}"'
            '} 1'
        )

    family(
        "funbox_device_active",
        "gauge",
        "1 if the FunBox currently considers the device connected.",
    )
    for d in devices:
        out.append(f'funbox_device_active{{mac="{mac_of(d)}"}} {1 if d.get("Active") else 0}')

    for metric, field, help_ in (
        ("funbox_device_first_seen_seconds", "FirstSeen",
         "Unix time the device was first ever seen."),
        ("funbox_device_last_connection_seconds", "LastConnection",
         "Unix time of the device's last connection."),
        ("funbox_device_last_changed_seconds", "LastChanged",
         "Unix time the device record last changed."),
    ):
        family(metric, "gauge", help_)
        for d in devices:
            ts = epoch(d.get(field))
            if ts is None:
                continue
            out.append(f'{metric}{{mac="{mac_of(d)}"}} {int(ts)}')

    family("funbox_online_devices", "gauge", "Number of edev devices currently active.")
    out.append(f"funbox_online_devices {sum(1 for d in devices if d.get('Active'))}")
    family("funbox_known_devices", "gauge", "Number of edev devices known to the FunBox.")
    out.append(f"funbox_known_devices {len(devices)}")

    return "\n".join(out) + "\n"


def write_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        handle.write(text)
    os.replace(tmp, path)
    os.chmod(path, 0o644)


def main():
    start = time.monotonic()
    success = 0
    try:
        ctx, cookies = login()
        try:
            obj = build_topology(ctx, cookies)
        except (PermissionError, urllib.error.HTTPError):
            # Session likely expired between runs -- re-authenticate once.
            ctx, cookies = login()
            obj = build_topology(ctx, cookies)
        devices = collect_devices(obj)
        write_atomic(os.path.join(TEXTFILE_DIR, "funbox.prom"), render(devices))
        success = 1
    except Exception as exc:  # noqa: BLE001 -- the timer must keep running
        # Generic message only; never surface credentials or the session token.
        print(f"funbox-exporter: scrape failed: {type(exc).__name__}: {exc}",
              file=sys.stderr)

    duration = time.monotonic() - start
    health = (
        "# HELP funbox_scrape_success 1 if the last FunBox scrape succeeded.\n"
        "# TYPE funbox_scrape_success gauge\n"
        f"funbox_scrape_success {success}\n"
        "# HELP funbox_scrape_duration_seconds Duration of the last FunBox scrape.\n"
        "# TYPE funbox_scrape_duration_seconds gauge\n"
        f"funbox_scrape_duration_seconds {duration:.3f}\n"
    )
    write_atomic(os.path.join(TEXTFILE_DIR, "funbox-health.prom"), health)


if __name__ == "__main__":
    main()
