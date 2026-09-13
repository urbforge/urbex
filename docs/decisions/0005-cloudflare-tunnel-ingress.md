# ADR-0005: Ingress via Cloudflare Tunnel

## Status

Accepted

## Context

Backend services on staging/prod must be reachable publicly in a secure
way. Options evaluated: Traefik, Nginx Proxy Manager, Caddy, Cloudflare
Tunnel.

## Decision

Use **Cloudflare Tunnel** to expose services: no ports are publicly opened
on the Proxmox server, traffic reaches the internal LXCs through the
tunnel.

## Rationale

- Security: the Proxmox server (often behind a home NAT) requires no port
  forwarding and no static public IP.
- Consistency: the web frontend already uses Cloudflare Pages, so the
  domain is already managed on Cloudflare anyway.
- Reduces the attack surface compared to a reverse proxy with directly
  exposed ports.

## Consequences

- The domain used for the environments must be managed on Cloudflare
  (Cloudflare DNS zone) in order to configure the tunnels — a constraint
  to communicate clearly in `urbex.yaml`/user documentation.
- A `cloudflared` (or equivalent service) configured per LXC/project/
  environment is needed, with automated provisioning of the tunnel and
  public routes by Urbex.
- This choice is specific to the "Proxmox + Cloudflare" v1 deployment
  target; future cloud providers (Azure/GCP/AWS, see
  [`roadmap.md`](../roadmap.md)) may require different ingress strategies
  (e.g. native load balancers) to be evaluated when that work is tackled.
