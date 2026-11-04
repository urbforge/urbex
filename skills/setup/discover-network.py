#!/usr/bin/env python3
"""Find what urbex.platform.yaml needs from the LAN, from this machine.

    discover-network.py [--proxmox <host>] [--no-scan]

Prints, as JSON: this machine's address, the LAN's CIDR and gateway, its
DNS servers, the hosts answering on Proxmox's port 8006, the addresses in
use, and a proposed block of free addresses for Urbex (baseHostOffset).
It pings the LAN's addresses once (a /24 at most, around this machine)
unless --no-scan; it reads no credential and changes nothing.
Linux and macOS.
"""
import argparse
import ipaddress
import json
import platform
import re
import shutil
import socket
import subprocess
from concurrent.futures import ThreadPoolExecutor

NEEDED = 20  # the platform's 10, plus room for a first project's LXCs


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def route_to(target):
    """(source address, interface, gateway or None) towards target."""
    if platform.system() == "Darwin":
        out = run("route", "-n", "get", target)
        iface = re.search(r"interface: (\S+)", out)
        gw = re.search(r"gateway: (\S+)", out)
        iface = iface.group(1) if iface else None
        src = None
        if iface:
            m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", run("ifconfig", iface))
            src = m.group(1) if m else None
        return src, iface, gw.group(1) if gw else None
    out = run("ip", "-4", "route", "get", target)
    src = re.search(r"src (\S+)", out)
    dev = re.search(r"dev (\S+)", out)
    via = re.search(r"via (\S+)", out)
    return (src.group(1) if src else None, dev.group(1) if dev else None,
            via.group(1) if via else None)


def cidr_of(iface, src):
    if platform.system() == "Darwin":
        m = re.search(r"inet %s netmask (0x[0-9a-f]+)" % re.escape(src), run("ifconfig", iface))
        if not m:
            return None
        bits = bin(int(m.group(1), 16)).count("1")
    else:
        m = re.search(r"inet %s/(\d+)" % re.escape(src), run("ip", "-4", "-o", "addr", "show", "dev", iface))
        if not m:
            return None
        bits = int(m.group(1))
    return str(ipaddress.ip_interface(f"{src}/{bits}").network)


def default_gateway():
    if platform.system() == "Darwin":
        m = re.search(r"gateway: (\S+)", run("route", "-n", "get", "default"))
    else:
        m = re.search(r"default via (\S+)", run("ip", "-4", "route", "show", "default"))
    return m.group(1) if m else None


def dns_servers():
    servers = []
    if shutil.which("resolvectl"):
        servers += re.findall(r"(\d+\.\d+\.\d+\.\d+)", run("resolvectl", "dns"))
    if platform.system() == "Darwin":
        servers += re.findall(r"nameserver\[\d+\] : (\d+\.\d+\.\d+\.\d+)", run("scutil", "--dns"))
    try:
        servers += re.findall(r"^nameserver\s+(\d+\.\d+\.\d+\.\d+)", open("/etc/resolv.conf").read(), re.M)
    except OSError:
        pass
    # 127.0.0.53 and the like are local stubs, Tailscale's 100.100.100.100 isn't reachable from the LXCs.
    keep = []
    for s in servers:
        ip = ipaddress.ip_address(s)
        if ip.is_loopback or s == "100.100.100.100" or s in keep:
            continue
        keep.append(s)
    return keep


def alive(ip):
    if platform.system() == "Darwin":
        cmd = ["ping", "-c", "1", "-t", "1", ip]
    else:
        cmd = ["ping", "-c", "1", "-W", "1", ip]
    try:
        return subprocess.run(cmd, capture_output=True, timeout=3).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def port_open(ip, port=8006):
    try:
        with socket.create_connection((ip, port), timeout=0.7):
            return True
    except OSError:
        return False


def neighbours():
    out = run("ip", "-4", "neigh") if platform.system() != "Darwin" else run("arp", "-an")
    used = set()
    for line in out.splitlines():
        # Only entries with a MAC address: a pinged address nobody has shows as INCOMPLETE or FAILED.
        if "lladdr" not in line and not re.search(r" at [0-9a-f]{1,2}:", line):
            continue
        m = re.search(r"(\d+\.\d+\.\d+\.\d+)", line)
        if m:
            used.add(m.group(1))
    return used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proxmox", help="the Proxmox node's address, if known")
    ap.add_argument("--no-scan", action="store_true")
    args = ap.parse_args()

    target = args.proxmox or "1.1.1.1"
    src, iface, _ = route_to(target)
    out = {"thisMachine": src, "interface": iface, "warnings": []}
    cidr = cidr_of(iface, src) if iface and src else None
    out["cidr"] = cidr
    out["gateway"] = default_gateway()
    out["dnsServers"] = dns_servers() or ([out["gateway"]] if out["gateway"] else [])
    if not cidr:
        out["warnings"].append("couldn't read the LAN's CIDR: ask the user")
        print(json.dumps(out, indent=2))
        return
    net = ipaddress.ip_network(cidr)
    if args.proxmox:
        try:
            if ipaddress.ip_address(socket.gethostbyname(args.proxmox)) not in net:
                out["warnings"].append(f"{args.proxmox} is not on this machine's LAN {cidr}: the LXCs go on the node's LAN, ask the user for its CIDR and gateway")
        except OSError:
            out["warnings"].append(f"can't resolve {args.proxmox}")
    if args.no_scan:
        print(json.dumps(out, indent=2))
        return

    # Scan at most the /24 around this machine.
    scan = net if net.prefixlen >= 24 else ipaddress.ip_network(f"{src}/24", strict=False)
    hosts = [str(h) for h in scan.hosts()]
    with ThreadPoolExecutor(64) as pool:
        up = dict(zip(hosts, pool.map(alive, hosts)))
        pve = dict(zip(hosts, pool.map(port_open, hosts)))
    used = {h for h, a in up.items() if a} | (neighbours() & set(hosts)) | {src}
    if out["gateway"]:
        used.add(out["gateway"])
    out["proxmoxCandidates"] = [h for h in hosts if pve[h]]
    out["inUse"] = sorted(used, key=ipaddress.ip_address)

    # The free runs, and the proposed block: .200 if free, else the longest run in the upper half.
    runs, start = [], None
    for h in hosts + [None]:
        free = h is not None and h not in used
        if free and start is None:
            start = h
        if not free and start is not None:
            runs.append((start, prev))
            start = None
        prev = h
    offset = lambda ip: int(ipaddress.ip_address(ip)) - int(net.network_address)
    runs = [(a, b, offset(b) - offset(a) + 1) for a, b in runs]
    out["freeRuns"] = [f"{a}-{b} ({n})" for a, b, n in runs if n >= 5]
    pick = None
    for a, b, n in runs:
        if offset(a) <= 200 and offset(b) >= 200 + NEEDED - 1:
            pick = (200, a, b)
    if pick is None:
        big = [r for r in runs if r[2] >= NEEDED]
        if big:
            a, b, n = max(big, key=lambda r: (offset(r[0]) > len(hosts) // 2, r[2]))
            pick = (offset(a), a, b)
    if pick:
        base = pick[0]
        first = ipaddress.ip_address(int(net.network_address) + base)
        out["proposal"] = {
            "baseHostOffset": base,
            "platform": f"{first} - {first + 5}",
            "projectsFrom": str(first + 10),
            "freeUpTo": pick[2],
        }
    else:
        out["warnings"].append(f"no run of {NEEDED} free addresses: ask the user")
    out["warnings"].append("a host that is off, or doesn't answer ping, looks free: the user confirms the block is outside the DHCP range and unused")
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
