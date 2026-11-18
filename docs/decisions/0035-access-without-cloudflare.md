# ADR-0035: Access without Cloudflare - the LAN or a VPN, or our own reverse proxy

## Status

Proposed. Extends [ADR-0022](0022-cloudflare-tunnel-access-workers.md)
and [ADR-0025](0025-cloudflare-quick-tunnel.md), which stay the
`cloudflare` mode, and puts [ADR-0008](0008-keycloak-scope.md)'s SSO for
the admin consoles in the order of implementation. Keycloak stays the
identity provider (urbforge/urbex#88).

## Context

Today a platform is reached in one of three ways:

- through **Cloudflare**: a tunnel publishes the public services on the
  operator's zone, and Cloudflare Access protects the admin consoles
  (Forgejo, Komodo, Technitium, Grafana, Prometheus, Loki, Keycloak's
  `/admin`) - ADR-0022;
- through a **Quick Tunnel**: public `*.trycloudflare.com` addresses
  without an account, and nothing protects the consoles beyond the LAN -
  ADR-0025;
- with **no Cloudflare**: everything on the LAN, by address or internal
  name (ADR-0026), and the consoles protected only by their own logins
  (`urbex-admin`).

The people Urbex is for mostly do it differently (selfh.st 2026,
urbforge/redemptor#49): 78% reach their services over a **VPN** (71% in
2025) and 66% run a **reverse proxy** - Traefik 27%, Caddy 27%, Nginx
Proxy Manager 25%, Cloudflare Tunnels 21%. 86% own a domain, 40% of
them at Cloudflare: the tunnel suits those, not everyone.

What Urbex needs from the access layer, whatever the mode: the projects'
public services and Keycloak's realms reachable by their users;
Komodo's webhook listener reachable by the forge (it is on the LAN);
the consoles reachable by the operator, and protected.

## Decision

1. **Three access modes**, chosen in `urbex.platform.yaml` as
   `access.mode`:
   - **`cloudflare`**: today's tunnel and Access, or a Quick Tunnel
     (ADR-0022, ADR-0025). The default when the file has a `cloudflare`
     section, so existing platforms don't change.
   - **`vpn`**: nothing is public. The consoles and the applications are
     reached on the LAN, or over the operator's VPN, by their internal
     names (Technitium, ADR-0026). The default without a `cloudflare`
     section: it is what "no Cloudflare" is today, named.
   - **`proxy`**: a reverse proxy on the platform publishes the public
     services, with TLS: **Caddy**, a platform service with its own LXC
     (`urbex-proxy`, ADR-0027), certificates from Let's Encrypt (HTTP-01
     through the operator's port forward of 80 and 443, or DNS-01 with
     the DNS provider's token for names not reachable from the
     internet). It publishes what the tunnel publishes in the
     `cloudflare` mode: the projects' `public: true` services, Keycloak's
     realms, Komodo's webhook listener. The consoles stay on the LAN and
     the VPN unless SSO protects them (point 2).

   The mode is a platform setting, like Cloudflare today: changing it is
   `urbex bootstrap` again on the same platform, then `urbex apply` of
   the environments with public services.

2. **Without Cloudflare Access, Keycloak protects the consoles**
   (ADR-0008), in the platform's realm (`keycloak.platformRealm`,
   `platform`), with the operators as its users:
   - **OIDC** where the tool has it: Forgejo, Grafana, Komodo;
   - **forward auth** - oauth2-proxy with Keycloak, in front of the
     tool - where it hasn't: Technitium's console, Prometheus, Loki.

   It applies to the `vpn` and `proxy` modes. The `cloudflare` mode
   keeps Access, and may add the same SSO behind it later. The tools'
   own `urbex-admin` logins stay, for when Keycloak is down.

3. **Urbex documents the VPN, it doesn't install it** - not yet. The
   operator's Tailscale (a subnet router on the LAN) or WireGuard gives
   the route to the LAN; what Urbex adds is the DNS: the VPN's clients
   use Technitium for the platform's zone (Tailscale's split DNS,
   WireGuard's `DNS =`), and the docs say how. A VPN on the platform (a
   Tailscale subnet router or a WireGuard LXC, managed by Urbex) may come
   later, as an option.

4. **`status`, `doctor` and the docs follow the mode**:
   - `urbex status` names the mode, and each endpoint's address in it:
     the public URL (`cloudflare`, `proxy`), or only the internal name
     and the LAN address (`vpn`), and whether a console is behind Access,
     behind SSO, or only on the LAN;
   - `urbex doctor` checks what the mode needs: the Cloudflare token and
     zone (`cloudflare`, as today); that this machine resolves the
     internal names (`vpn`: Technitium as its resolver, or the VPN's
     split DNS); the ACME settings, and that ports 80 and 443 reach the
     proxy (`proxy`);
   - getting started explains the three modes where it explains
     Cloudflare today; the reference documents `access.mode`.

5. **Order of implementation**, one issue each:
   1. `access.mode`, with `vpn` as today's no-Cloudflare platform and
      its defaults; `status` and `doctor` per mode; the VPN guide
      (Tailscale, WireGuard, the DNS).
   2. SSO for the consoles: the platform realm, OIDC for Forgejo,
      Grafana and Komodo, oauth2-proxy for Technitium, Prometheus and
      Loki.
   3. The `proxy` mode: Caddy, ACME (HTTP-01, then DNS-01), the public
      services; the consoles published only behind step 2's SSO.
   4. Later, if asked: a VPN installed by Urbex.

## Rationale

- `vpn` costs almost nothing: it is today's platform without Cloudflare,
  named and documented - and the way most homelabs already reach their
  services.
- Caddy: automatic TLS with no extra tool, one small configuration file
  that Urbex writes, and the share of proxy users it has. Traefik's
  label-driven routing fits one Docker host, not services spread over
  LXCs; Nginx Proxy Manager is configured through its UI, which Urbex
  can't keep in the GitOps repo.
- Keycloak is already there, and its realms are what projects use; using
  it for the consoles is ADR-0008's plan, not a new dependency. Forward
  auth covers the tools without OIDC with one more small container.
- Documenting the VPN first leaves the operator's existing VPN alone,
  which is what most of them have.

## Consequences

- The `vpn` mode keeps today's limits: the consoles' own logins until
  SSO (step 2), and Keycloak's issuer is its LAN address (see the known
  limitations). The `proxy` mode gives Keycloak a public issuer.
- A new platform service in the `proxy` mode: `urbex-proxy`, its LXC,
  Stack, internal name and Grafana labels, in the service catalog.
- The `proxy` mode needs the operator's router: a port forward of 80 and
  443 to the proxy, or a DNS provider token for DNS-01. `doctor` checks
  what it can.
- In the `vpn` mode a project's `public: true` publishes nothing: `apply`
  says so, so that no one expects a public URL.
