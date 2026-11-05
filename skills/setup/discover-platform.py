#!/usr/bin/env python3
"""Find what urbex.platform.yaml needs from Proxmox and Cloudflare, with the
tokens the user has stored, without ever printing them.

    discover-platform.py --workspace <dir> --proxmox https://<host>:8006 [--cloudflare]

The tokens come from URBEX_PROXMOX_TOKEN and URBEX_CLOUDFLARE_TOKEN if
set, else from <dir>/home/.urbex/credentials.yaml (where `urbex-op set`
puts them), else from ~/.urbex/credentials.yaml. Only GET requests.
Prints, as JSON, the values found and what to check; the token's secret
part never appears in the output.
"""
import argparse
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


def credential(key, env, workspace):
    if os.environ.get(env):
        return os.environ[env]
    paths = []
    if workspace:
        paths.append(os.path.join(os.path.expanduser(workspace), "home", ".urbex", "credentials.yaml"))
    paths.append(os.path.expanduser("~/.urbex/credentials.yaml"))
    for path in paths:
        try:
            text = open(path).read()
        except OSError:
            continue
        try:
            import yaml  # noqa: PLC0415 - optional
            value = (yaml.safe_load(text) or {}).get(key)
        except ImportError:
            m = re.search(r"^%s:\s*(.+?)\s*$" % re.escape(key), text, re.M)
            value = m.group(1).strip("'\"") if m else None
        if value:
            return str(value)
    return None


class Api:
    def __init__(self, base, headers, insecure=False):
        self.base, self.headers = base.rstrip("/"), headers
        self.ctx = ssl._create_unverified_context() if insecure else ssl.create_default_context()

    def get(self, path, **params):
        url = self.base + path + ("?" + urllib.parse.urlencode(params) if params else "")
        req = urllib.request.Request(url, headers=self.headers)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=10) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as e:
            return e.code, None


def proxmox(url, token, out):
    url = re.sub(r"/api2/json/?$", "", url.rstrip("/")) + "/api2/json"
    out["apiUrl"] = url
    tokenid = token.split("=", 1)[0]
    out["tokenId"] = tokenid  # user@realm!name: not secret
    out["keyctl"] = tokenid.startswith("root@pam")
    headers = {"Authorization": "PVEAPIToken=" + token}

    api = Api(url, headers)
    try:
        api.get("/version")
        out["insecure"] = False
    except (urllib.error.URLError, ssl.SSLError):
        api = Api(url, headers, insecure=True)
        out["insecure"] = True
    try:
        code, v = api.get("/version")
    except urllib.error.URLError as e:
        out["errors"].append(f"Proxmox doesn't answer at {url}: {e.reason}")
        return
    if code == 401:
        out["errors"].append("Proxmox refuses the token (401): check it was stored whole, as user@realm!name=value")
        return
    out["proxmoxVersion"] = (v or {}).get("data", {}).get("version")
    if out["proxmoxVersion"] and not out["proxmoxVersion"].startswith("9"):
        out["warnings"].append(f"Proxmox VE {out['proxmoxVersion']}: Urbex is validated on 9")

    _, perms = api.get("/access/permissions")
    paths = sorted((perms or {}).get("data", {}).keys())
    out["permissionPaths"] = paths
    pools = [p.split("/")[2] for p in paths if p.startswith("/pool/")]
    bridges = [p.rsplit("/", 1)[1] for p in paths if p.startswith("/sdn/zones/") and p.count("/") == 4]
    out["pool"] = pools[0] if pools else None
    if "/" not in paths and not pools:
        out["warnings"].append("the token has no permission on a pool: follow the Proxmox preparation")
    if "/" not in paths and not bridges:
        out["warnings"].append("the token has no SDN.Use on a bridge: LXCs can't get a network (the PVESDNUser line of the preparation)")

    _, nodes = api.get("/nodes")
    names = [n["node"] for n in (nodes or {}).get("data", []) if n.get("status", "online") == "online"]
    out["nodes"] = names
    if not names:
        out["errors"].append("the token sees no node")
        return
    node = names[0]
    out["node"] = node
    if len(names) > 1:
        out["warnings"].append(f"several nodes: {', '.join(names)} - the user picks one; the values below are {node}'s")

    _, net = api.get(f"/nodes/{node}/network", type="any_bridge")
    seen = [i["iface"] for i in (net or {}).get("data", [])]
    out["bridge"] = (bridges or seen or ["vmbr0"])[0]

    _, st = api.get(f"/nodes/{node}/storage", content="rootdir", enabled=1)
    rootdir = [s for s in (st or {}).get("data", []) if s.get("active")]
    # Thin, snapshot-capable storage first: what Proxmox installs (local-zfs, local-lvm).
    rank = {"zfspool": 0, "lvmthin": 1, "rbd": 2, "btrfs": 3, "dir": 5}
    rootdir.sort(key=lambda s: (rank.get(s.get("type"), 4), -s.get("avail", 0)))
    out["storages"] = [f"{s['storage']} ({s.get('type')}, {s.get('avail', 0) // 2**30} GiB free)" for s in rootdir]
    out["storagePool"] = rootdir[0]["storage"] if rootdir else None
    if not rootdir:
        out["errors"].append("no storage for LXC disks the token can use: add one to the pool (pveum pool modify urbex --storage <name>)")

    _, st = api.get(f"/nodes/{node}/storage", content="vztmpl", enabled=1)
    templates = []
    for s in (st or {}).get("data", []):
        _, content = api.get(f"/nodes/{node}/storage/{s['storage']}/content", content="vztmpl")
        templates += [c["volid"] for c in (content or {}).get("data", []) if "debian-13-standard" in c.get("volid", "")]
    templates.sort(key=lambda t: [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", t)])
    # Proxmox nodes are amd64, bar the odd arm64 port: never pick another architecture's template when ours is there.
    native = [t for t in templates if "_amd64" in t]
    out["lxcTemplate"] = (native or templates)[-1] if templates else None
    if not templates:
        out["errors"].append("no Debian 13 template the token can see: the user downloads it as root (the pveam line of the preparation)")

    # VMIDs: the platform takes vmIdBase..+5, projects from +100. nextid answers 400 for a taken one.
    taken = []
    for vmid in list(range(9000, 9006)) + [9100]:
        code, _ = api.get("/cluster/nextid", vmid=vmid)
        if code != 200:
            taken.append(vmid)
    out["vmIdBase"] = 9000
    if taken:
        out["warnings"].append(f"VMIDs taken: {taken} - an existing Urbex platform, or another vmIdBase is needed")
    if out["pool"]:
        _, pool = api.get(f"/pools/{out['pool']}")
        members = (pool or {}).get("data", {}).get("members", [])
        out["poolMembers"] = sorted(f"{m.get('vmid')} {m.get('name')}" for m in members if m.get("type") in ("lxc", "qemu"))
        if any(m.get("name") == "urbex-gitea" for m in members):
            out["warnings"].append("an Urbex platform already exists in this pool: use its GitOps repo and urbex.platform.yaml instead of a new one")


def cloudflare(token, out):
    api = Api("https://api.cloudflare.com/client/v4", {"Authorization": "Bearer " + token})
    code, zones = api.get("/zones", per_page=50)
    if code != 200:
        out["errors"].append(f"Cloudflare refuses the token on /zones (HTTP {code}): it needs Zone Read on the zone")
        return
    zs = (zones or {}).get("result", [])
    out["cloudflareZones"] = [{"domain": z["name"], "zoneId": z["id"], "accountId": z["account"]["id"]} for z in zs]
    for account in sorted({z["account"]["id"] for z in zs}):
        code, v = api.get(f"/accounts/{account}/tokens/verify")
        status = (v or {}).get("result", {}).get("status") if code == 200 else None
        if status != "active":
            out["warnings"].append(f"the Cloudflare token isn't verified as an account token of {account} (HTTP {code}, {status}): create it under Account API tokens")
    if len(zs) == 1:
        z = zs[0]
        out["domain"], out["zoneId"], out["accountId"] = z["name"], z["id"], z["account"]["id"]
    elif not zs:
        out["errors"].append("the Cloudflare token sees no zone")
    else:
        out["warnings"].append("several zones: the user picks the platform's domain")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workspace", default=os.environ.get("URBEX_WORKSPACE"))
    ap.add_argument("--proxmox", help="https://<host>:8006")
    ap.add_argument("--cloudflare", action="store_true")
    args = ap.parse_args()
    out = {"errors": [], "warnings": []}
    if args.proxmox:
        token = credential("proxmoxToken", "URBEX_PROXMOX_TOKEN", args.workspace)
        if not token:
            out["errors"].append("no Proxmox token: the user runs 'urbex-op set proxmoxToken'")
        else:
            proxmox(args.proxmox, token, out)
    if args.cloudflare:
        token = credential("cloudflareToken", "URBEX_CLOUDFLARE_TOKEN", args.workspace)
        if not token:
            out["errors"].append("no Cloudflare token: the user runs 'urbex-op set cloudflareToken'")
        else:
            cloudflare(token, out)
    print(json.dumps(out, indent=2))
    sys.exit(1 if out["errors"] else 0)


if __name__ == "__main__":
    main()
