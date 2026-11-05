#!/usr/bin/env python3
"""Prepare a Proxmox VE node for Urbex and store its API token, in one run.

    prepare-proxmox.py --host <node address> [--workspace ~/urbex-work]
                       [--user root@pam] [--node <name>]

Run it in your own terminal: it asks for the password of a Proxmox
administrator (root@pam by default) without echoing it, and for a TOTP
code if the account has one. It first reads the node and shows what it
will do; nothing changes until you answer yes. Then, through the Proxmox
API, it does what the "Prerequisites" root block of the getting started
does:

  - the pool `urbex`, with the disk storage and the template storage;
  - the group `urbex`, allowed only on that pool and on the LAN's bridge;
  - the user `urbex@pve` in that group, with no password;
  - the latest Debian 13 template for the node's architecture;
  - the API token `urbex@pve!cli`, stored straight into the workspace
    with `urbex-op set proxmoxToken`.

The password is used only to log in, for this run: it is not stored or
sent anywhere else. The token is never printed, unless urbex-op isn't
there to store it. Running it again is safe: what exists is kept, and
the token is replaced only if you say so.
Standard library only.
"""
import argparse
import getpass
import hashlib
import http.client
import json
import os
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.parse

POOL, GROUP, USER, TOKEN = "urbex", "urbex", "urbex@pve", "cli"
POOL_ROLES = "PVEVMAdmin,PVEDatastoreUser,PVEPoolUser"
RANK = {"zfspool": 0, "lvmthin": 1, "rbd": 2, "btrfs": 3, "dir": 9}


class ApiError(Exception):
    pass


class Proxmox:
    def __init__(self, host, port=8006):
        self.host, self.port = host, port
        self.pin = None  # sha256 of the certificate the user accepted
        self.cookie = self.csrf = None

    def _conn(self):
        if self.pin is None:
            return http.client.HTTPSConnection(self.host, self.port, timeout=30,
                                               context=ssl.create_default_context())
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        conn = http.client.HTTPSConnection(self.host, self.port, timeout=30, context=ctx)
        conn.connect()
        seen = hashlib.sha256(conn.sock.getpeercert(binary_form=True)).hexdigest()
        if seen != self.pin:
            conn.close()
            raise ApiError("the node's certificate changed during the run: stopping")
        return conn

    def call(self, method, path, params=None):
        body, headers = None, {}
        query = ""
        if params:
            encoded = urllib.parse.urlencode(params)
            if method == "GET":
                query = "?" + encoded
            else:
                body = encoded
                headers["Content-Type"] = "application/x-www-form-urlencoded"
        if self.cookie:
            headers["Cookie"] = "PVEAuthCookie=" + urllib.parse.quote(self.cookie, safe="")
            if method != "GET":
                headers["CSRFPreventionToken"] = self.csrf
        conn = self._conn()
        try:
            conn.request(method, "/api2/json" + path + query, body=body, headers=headers)
            resp = conn.getresponse()
            raw = resp.read().decode("utf-8", "replace")
        finally:
            conn.close()
        if resp.status >= 400:
            detail = resp.reason
            try:
                errors = json.loads(raw).get("errors")
                if errors:
                    detail += ": " + "; ".join(f"{k}: {v}" for k, v in errors.items())
            except ValueError:
                pass
            raise ApiError(f"{method} {path}: {resp.status} {detail.strip()}")
        return json.loads(raw).get("data") if raw else None


def ask(prompt, default=False):
    answer = input(prompt + (" [Y/n] " if default else " [y/N] ")).strip().lower()
    return default if not answer else answer in ("y", "yes", "s", "si", "sì")


def check_tls(api):
    """Verified TLS, or the user compares the certificate's fingerprint and we pin it."""
    try:
        api.call("GET", "/version")
        return
    except ssl.SSLError:
        pass
    except ApiError:
        return  # 401 means TLS worked
    pem = ssl.get_server_certificate((api.host, api.port))
    der = ssl.PEM_cert_to_DER_cert(pem)
    digest = hashlib.sha256(der).hexdigest()
    pretty = ":".join(digest[i:i + 2] for i in range(0, len(digest), 2)).upper()
    print(f"\nThe node's certificate isn't signed by an authority this machine trusts (Proxmox's own,\n"
          f"self-signed, is the default). Its SHA-256 fingerprint is:\n\n  {pretty}\n\n"
          f"Compare it with the node's: web UI → the node → System → Certificates → pve-ssl.pem →\n"
          f"View Certificate, or `openssl x509 -noout -fingerprint -sha256 -in /etc/pve/local/pve-ssl.pem`.")
    if not ask("Do they match?"):
        sys.exit("Stopped: the certificate wasn't confirmed.")
    api.pin = digest


def login(api, user):
    password = getpass.getpass(f"Password of {user} on {api.host}: ")
    try:
        data = api.call("POST", "/access/ticket", {"username": user, "password": password})
    except ApiError as e:
        sys.exit(f"Login failed ({e}). Check the user and the password; a user of the PVE realm is <name>@pve.")
    if data.get("NeedTFA"):
        code = getpass.getpass("Two-factor code (TOTP, or recovery:<key>): ").strip()
        response = code if ":" in code else "totp:" + code
        try:
            data = api.call("POST", "/access/ticket",
                            {"username": user, "tfa-challenge": data["ticket"], "password": response})
        except ApiError as e:
            sys.exit(f"Two-factor login failed ({e}).")
    del password
    api.cookie, api.csrf = data["ticket"], data["CSRFPreventionToken"]


def host_ip(host):
    try:
        return socket.gethostbyname(host)
    except OSError:
        return host


def pick_node(api, host, wanted):
    nodes = [n["node"] for n in api.call("GET", "/nodes") if n.get("status") == "online"]
    if wanted:
        if wanted not in nodes:
            sys.exit(f"No online node {wanted}: the nodes are {', '.join(nodes)}.")
        return wanted
    if len(nodes) == 1:
        return nodes[0]
    ip = host_ip(host)
    for entry in api.call("GET", "/cluster/status") or []:
        if entry.get("type") == "node" and entry.get("ip") == ip and entry.get("name") in nodes:
            return entry["name"]
    sys.exit(f"Several nodes ({', '.join(nodes)}): run again with --node <name>.")


def pick_storage(api, node, content):
    found = [s for s in api.call("GET", f"/nodes/{node}/storage", {"content": content, "enabled": 1})
             if s.get("active")]
    found.sort(key=lambda s: (RANK.get(s.get("type"), 5), -int(s.get("avail") or 0)))
    return found[0]["storage"] if found else None


def pick_bridge(api, node, host):
    nets = [n for n in api.call("GET", f"/nodes/{node}/network")
            if n.get("type") in ("bridge", "OVSBridge") and n.get("active", 1)]
    for n in nets:
        if n.get("gateway"):
            return n["iface"]
    names = [n["iface"] for n in nets]
    return "vmbr0" if "vmbr0" in names else (names[0] if names else None)


def pick_template(api, node):
    arch = "amd64"
    try:
        status = api.call("GET", f"/nodes/{node}/status")
        if "aarch64" in json.dumps(status).lower():
            arch = "arm64"
    except ApiError:
        pass
    candidates = [t["template"] for t in api.call("GET", f"/nodes/{node}/aplinfo")
                  if t.get("template", "").startswith("debian-13-standard_")
                  and t.get("architecture", arch) == arch]

    def version(name):
        return [int(p) if p.isdigit() else p for p in
                name.split("_")[1].replace("-", ".").split(".")]

    return (max(candidates, key=version) if candidates else None), arch


def wait_task(api, node, upid, what):
    path = f"/nodes/{node}/tasks/{urllib.parse.quote(upid, safe='')}/status"
    while True:
        status = api.call("GET", path)
        if status.get("status") == "stopped":
            if status.get("exitstatus") != "OK":
                raise ApiError(f"{what}: {status.get('exitstatus')}")
            return
        time.sleep(2)


def exists(fn):
    try:
        fn()
        return True
    except ApiError:
        return False


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--host", required=True, help="the node's address or name")
    ap.add_argument("--workspace", default=os.environ.get("URBEX_WORKSPACE", "~/urbex-work"))
    ap.add_argument("--user", default="root@pam", help="a Proxmox administrator (default root@pam)")
    ap.add_argument("--node", help="the node, when the cluster has several")
    args = ap.parse_args()
    if not sys.stdin.isatty():
        sys.exit("Run this in your own terminal: it asks for a password.")
    ws = os.path.expanduser(args.workspace)
    host = args.host.removeprefix("https://").split("/")[0]
    port = 8006
    if ":" in host:
        host, port = host.rsplit(":", 1)
        port = int(port)

    api = Proxmox(host, port)
    try:
        check_tls(api)
        login(api, args.user)

        # Read everything first: nothing changes before the user says yes.
        node = pick_node(api, host, args.node)
        disks = pick_storage(api, node, "rootdir")
        templates = pick_storage(api, node, "vztmpl")
        bridge = pick_bridge(api, node, host)
        template, arch = pick_template(api, node)
        missing = [n for n, v in (("a storage for disks", disks), ("a storage for templates", templates),
                                  ("a bridge", bridge), (f"a Debian 13 template for {arch}", template)) if not v]
        if missing:
            sys.exit(f"Node {node} has no {', '.join(missing)}: fix it in the web UI, then run again.")
        have_pool = exists(lambda: api.call("GET", f"/pools/{POOL}"))
        have_group = exists(lambda: api.call("GET", f"/access/groups/{GROUP}"))
        have_user = exists(lambda: api.call("GET", f"/access/users/{USER}"))
        have_token = have_user and exists(lambda: api.call("GET", f"/access/users/{USER}/token/{TOKEN}"))
        stored = [c.get("volid", "") for c in
                  api.call("GET", f"/nodes/{node}/storage/{templates}/content", {"content": "vztmpl"})]
        have_template = any(v.endswith("/" + template) for v in stored)
        urbex_op = shutil.which("urbex-op")
        can_store = bool(urbex_op) and os.path.isdir(os.path.join(ws, "home", ".urbex"))

        def state(done):
            return "exists, kept" if done else "create"

        print(f"""
On node {node} ({host}), this will:

  pool {POOL:<12} {state(have_pool)}; storages {disks} (disks) and {templates} (templates) added to it
  group {GROUP:<11} {state(have_group)}; roles {POOL_ROLES} on /pool/{POOL},
                     PVESDNUser on /sdn/zones/localnetwork/{bridge}: nothing else on the node
  user {USER:<12} {state(have_user)}; in group {GROUP}, no password (it can only use its token)
  template           {template} on {templates}: {"already there" if have_template else "download"}
  token {USER}!{TOKEN:<4} {"exists: you'll be asked whether to replace it" if have_token else "create"}, privilege separation off
                     (it has the group's rights, no more)
  then               {"store it with `urbex-op set proxmoxToken` in " + ws if can_store
                      else "print it once (no urbex-op workspace at " + ws + ")"}

It changes nothing else, and logs out when done.""")
        if not ask("Go ahead?"):
            sys.exit("Nothing changed.")

        if not have_pool:
            api.call("POST", "/pools", {"poolid": POOL, "comment": "Urbex"})
        try:
            api.call("PUT", f"/pools/{POOL}", {"storage": f"{disks},{templates}"})
        except ApiError:
            api.call("PUT", "/pools", {"poolid": POOL, "storage": f"{disks},{templates}"})
        print(f"✔ pool {POOL}")
        if not have_group:
            api.call("POST", "/access/groups", {"groupid": GROUP, "comment": "Urbex operators: pool urbex only"})
        api.call("PUT", "/access/acl", {"path": f"/pool/{POOL}", "groups": GROUP, "roles": POOL_ROLES})
        try:
            api.call("PUT", "/access/acl", {"path": f"/sdn/zones/localnetwork/{bridge}",
                                            "groups": GROUP, "roles": "PVESDNUser"})
        except ApiError as e:
            print(f"  ! the bridge permission wasn't set ({e}): Proxmox VE before 8 doesn't need it")
        print(f"✔ group {GROUP} and its permissions")
        if have_user:
            api.call("PUT", f"/access/users/{USER}", {"groups": GROUP, "append": 1})
        else:
            api.call("POST", "/access/users", {"userid": USER, "comment": "Urbex CLI", "groups": GROUP})
        print(f"✔ user {USER}")
        if not have_template:
            print(f"  downloading {template}...")
            upid = api.call("POST", f"/nodes/{node}/aplinfo", {"storage": templates, "template": template})
            wait_task(api, node, upid, "template download")
        print(f"✔ template {template}")

        if have_token:
            if not ask(f"Token {USER}!{TOKEN} exists. Replace it? Whatever uses the old one stops working"):
                print("Token kept. If you don't have its value any more, run again and replace it.")
                return
            api.call("DELETE", f"/access/users/{USER}/token/{TOKEN}")
        data = api.call("POST", f"/access/users/{USER}/token/{TOKEN}", {"privsep": 0, "comment": "urbex"})
        token = f"{data['full-tokenid']}={data['value']}"
        if can_store:
            done = subprocess.run([urbex_op, "-w", ws, "set", "proxmoxToken"], input=token, text=True)
            if done.returncode == 0:
                print(f"✔ token {USER}!{TOKEN}, stored in the workspace (not shown)")
            else:
                print(f"urbex-op couldn't store it. Here it is, once: keep it and run `urbex-op set proxmoxToken`:\n\n  {token}\n")
        else:
            print(f"\nThe token, shown once: keep it, and when the workspace exists run `urbex-op set proxmoxToken`.\n\n  {token}\n")
        del token
        print(f"\nDone. Node {node}: disks on {disks}, bridge {bridge}, template {template}, pool {POOL}.")
    except ApiError as e:
        sys.exit(f"Stopped: {e}")
    except (OSError, ssl.SSLError) as e:
        sys.exit(f"Can't reach https://{host}:{port}: {e}")
    except KeyboardInterrupt:
        sys.exit("\nInterrupted: run it again, what exists is kept.")
    finally:
        api.cookie = api.csrf = None


if __name__ == "__main__":
    main()
