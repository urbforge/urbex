# ADR-0035: Access without Cloudflare - Pangolin, a VPN, or our own reverse proxy

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
them at Cloudflare: the tunnel suits those, not everyone. Many homelabs
are behind CGNAT, with no public IP to forward ports to.

What Urbex needs from the access layer, whatever the mode: the projects'
public services and Keycloak's realms reachable by their users;
Komodo's webhook listener reachable by the forge (it is on the LAN);
the consoles reachable by the operator, and protected. A reverse proxy
alone publishes services but protects nothing: what Cloudflare Access
does - a login in front of a service, and some defence against abuse -
has to come from somewhere else.

**[Pangolin](https://github.com/fosrl/pangolin)** is a self-hosted
tunnelled reverse proxy with identity-aware access, the closest
self-hosted equivalent of Cloudflare's tunnel and Access together
([its docs](https://docs.pangolin.net)):

- a **Pangolin server** on a host with a public IP (a small VPS): its
  control plane, Traefik (TLS, HTTP ingress), Gerbil (WireGuard) and
  Badger (Traefik's forward auth). It needs TCP 80 and 443, UDP 51820
  for the sites' tunnels (UDP 21820 for client relays), and a wildcard
  DNS record;
- a **site connector, Newt**, on the network it publishes: a container
  or a binary, configured with a site ID, a secret and the server's
  address. It connects out - a WebSocket to the control plane, a
  WireGuard tunnel to Gerbil - and **needs no open port or public IP**;
- **resources**: an HTTP service published on a name, with TLS, behind
  Pangolin's login or not; raw TCP and UDP resources too (no TLS or
  login, opt-in);
- **identity**: an external OIDC provider as the global identity
  provider - Keycloak among the documented examples - in the Community
  Edition; roles granted per resource (one role per user in the
  Community Edition; several is the Enterprise Edition's);
- an **Integration API** (`/v1`, a bearer API key with per-action
  permissions, an OpenAPI description at `/v1/docs`), enabled with
  `flags.enable_integration_api`, to create sites, resources, targets
  and roles. It isn't in the user docs yet: it is described by its
  OpenAPI document and its code;
- **CrowdSec**, offered by Pangolin's installer as an option ("a minimal
  viable deployment"), in front of Traefik;
- licence: the Community Edition is **AGPL-3**; the Enterprise Edition
  is a commercial licence, free for personal use and small businesses
  with a key.

## Decision

1. **Four access modes**, chosen in `urbex.platform.yaml` as
   `access.mode`:

   | Mode | Public services | How | For |
   |---|---|---|---|
   | **`cloudflare`** | yes | Cloudflare's tunnel and Access, or a Quick Tunnel (ADR-0022, ADR-0025) | a domain on Cloudflare; the default with a `cloudflare` section, so existing platforms don't change |
   | **`pangolin`** | yes | a tunnel, no open ports, to the operator's Pangolin server; Keycloak's login in front | **the main self-hosted mode**, behind CGNAT too |
   | **`vpn`** | no | nothing public: the LAN, or a VPN (NetBird, Tailscale) | the default without a `cloudflare` section: today's "no Cloudflare", named |
   | **`proxy`** | yes | Caddy on the platform, with oauth2-proxy and CrowdSec | an option only: a public IP and a wish to open ports 80 and 443 |

   The mode is a platform setting, like Cloudflare today: changing it is
   `urbex bootstrap` again on the same platform, then `urbex apply` of
   the environments with public services.

2. **`pangolin`**:
   - **The Pangolin server runs on the operator's VPS**, not on the
     platform: it has to be reachable from the internet, which the
     platform isn't. The operator installs it with Pangolin's installer,
     enables its Integration API, and gives urbex its address, an API
     key and the organisation (`access.pangolin` in
     `urbex.platform.yaml`, the key in `credentials.yaml` as
     `pangolinApiKey`). Installing it from urbex comes later, with
     E3-bis: the VPS urbex will manage for a platform can host it.
   - **Newt runs on the platform** as a Stack on the edge LXC - the LXC
     that runs `cloudflared` in the `cloudflare` mode (`urbex-tunnel`,
     ADR-0027), deployed and monitored by Komodo like every service. Its
     site ID and secret are created by urbex through the API and kept
     as a SOPS secret of the Stack.
   - **urbex registers the resources through the Integration API**, as
     it does Cloudflare's routes today: on bootstrap the site, the
     platform's resources (Keycloak's realms, Komodo's webhook listener,
     the consoles) and their roles; on apply each `public: true`
     service, with its target on the LAN; on destroy their removal.
     urbex pins the Pangolin version it is tested with, since the API is
     described only by its OpenAPI document.
   - **Keycloak is Pangolin's identity provider** (a global OIDC
     provider, in the platform's realm): the consoles are Pangolin
     resources behind its login, with the operators' role - the same
     login as the consoles' own SSO (point 4). A project's public
     service is published without Pangolin's login by default, since it
     has its own users in its environment's realm (ADR-0024);
     `access: platform` on a service puts it behind the operators' login.
   - **CrowdSec**: recommended, through Pangolin's installer; it is on
     the Pangolin server, so it's the operator's to manage. urbex
     documents it, and doesn't depend on it.
   - **Licence**: urbex deploys Pangolin's Community Edition unmodified
     and talks to it over HTTP; it doesn't link or ship its code, so the
     AGPL asks nothing of urbex. Nothing urbex needs is Enterprise-only.
   - **No DDoS protection**: the edge is the operator's VPS, protected
     only by what its provider offers. Say so in the docs; who needs
     more stays on the `cloudflare` mode.

3. **`vpn`** - nothing public:
   - the operator's **NetBird, self-hosted, with Keycloak as its
     identity provider** (the same login), or their **Tailscale**; a
     route to the LAN, and the VPN's DNS pointing at Technitium for the
     platform's zone;
   - **urbex documents it, and doesn't install it** - not yet. A NetBird
     management server on the platform or the VPS may come later, as an
     option.

4. **The consoles are protected by Keycloak** (ADR-0008), in the
   platform's realm (`keycloak.platformRealm`), with the operators as
   its users, in every mode without Cloudflare Access:
   - **OIDC** where the tool has it: Forgejo, Grafana, Komodo;
   - **forward auth** where it hasn't - Technitium's console, Prometheus,
     Loki: Pangolin's login in the `pangolin` mode, oauth2-proxy with
     Keycloak otherwise.

   The tools' own `urbex-admin` logins stay, for when Keycloak is down.
   The `cloudflare` mode keeps Access, and may add the same SSO behind
   it later.

5. **`proxy`** - an option, not a main mode: Caddy on the platform
   (`urbex-proxy`, its own LXC), certificates from Let's Encrypt
   (HTTP-01 through the operator's port forward of 80 and 443, or DNS-01
   with the DNS provider's token), **oauth2-proxy with Keycloak in front
   of every console and of `access: platform` services, and CrowdSec**.
   Caddy alone would publish and protect nothing; with the two it is for
   operators with a public IP who prefer their own edge to a VPS.

6. **`status`, `doctor` and the docs follow the mode**:
   - `urbex status` names the mode, and each endpoint's address in it -
     the public URL, or only the internal name and the LAN address - and
     what protects a console (Access, Pangolin's login, oauth2-proxy, or
     only the LAN);
   - `urbex doctor` checks what the mode needs: the Cloudflare token and
     zone (`cloudflare`); the Pangolin server's API, the key's
     permissions and Newt's connection (`pangolin`); that this machine
     resolves the internal names (`vpn`); the ACME settings, and that
     ports 80 and 443 reach the proxy (`proxy`);
   - getting started explains the modes where it explains Cloudflare
     today; the reference documents `access.*`.

7. **Order of implementation**, one issue each:
   1. `access.mode`, with `vpn` as today's no-Cloudflare platform and its
      defaults; `status` and `doctor` per mode; the VPN guide (NetBird
      with Keycloak, Tailscale, the DNS).
   2. SSO for the consoles: the platform realm, OIDC for Forgejo,
      Grafana and Komodo.
   3. The `pangolin` mode: Newt on the edge LXC, the site and resources
      through the API, Keycloak as Pangolin's identity provider, the
      consoles behind it; the Pangolin server guide.
   4. The `proxy` option: Caddy, oauth2-proxy, CrowdSec.
   5. Later, with E3-bis: the Pangolin server installed by urbex on a
      VPS; a NetBird server, if asked.

## Rationale

- Pangolin gives a homelab what Cloudflare gives it - a public name
  without open ports, behind CGNAT too, and a login in front of a
  service - with the edge on a VPS the operator owns. It is the mode
  closest to `cloudflare`, so it should be the main self-hosted one.
- Its tunnel connects out, like `cloudflared`: the platform's edge LXC
  only changes what it runs, and the services stay reached by internal
  name (ADR-0027).
- Keycloak is already there, and its realms are what projects use: as
  Pangolin's, NetBird's and the consoles' identity provider, it gives
  one login everywhere, without a new identity system.
- `vpn` costs almost nothing: it is today's platform without Cloudflare,
  named and documented - the way most homelabs already reach their
  services.
- Caddy stays as an option for those who want no third host, but only
  with oauth2-proxy and CrowdSec: a bare reverse proxy isn't a safe
  edge.

## Consequences

- The `pangolin` mode needs a VPS with a public IP, run by the operator
  (until E3-bis), and a domain with a wildcard record pointing at it.
- The edge has no DDoS protection beyond the VPS provider's.
- urbex depends on Pangolin's Integration API, described only by its
  OpenAPI document: urbex pins a version and tests against it, and an
  upgrade of the Pangolin server is checked against urbex's.
- The Community Edition allows one role per user: operators and
  `access: platform` users are roles in Keycloak mapped to one Pangolin
  role each.
- New: `access.*` in `urbex.platform.yaml`, `pangolinApiKey` in the
  credentials, a Newt Stack on the edge LXC, `access: platform` on a
  service; in the `proxy` option `urbex-proxy` with Caddy, oauth2-proxy
  and CrowdSec, in the service catalog.
- In the `vpn` mode a project's `public: true` publishes nothing:
  `apply` says so, so that no one expects a public URL.
