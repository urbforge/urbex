# ADR-0027: Conventions every service follows

## Status

Accepted. Refines [ADR-0022](0022-cloudflare-tunnel-access-workers.md)
(more services behind Access, tunnel routes by name),
[ADR-0023](0023-service-logs-to-loki.md) (three kinds instead of two,
the agents' own logs, per-container resources) and
[ADR-0026](0026-technitium-internal-dns-records.md) (the platform's
subdomain as internal zone, base services registered, Technitium as the
LXCs' resolver). Tracked by
[urbforge/redemptor#23](https://github.com/urbforge/redemptor/issues/23).

## Context

Urbex runs two families of services: the platform's (Gitea, Komodo,
Technitium, Keycloak, the observability stack, the tunnel) and the
projects' (backends, frontends, and soon databases). Each grew its own
rules:

| Concern | Today |
|---|---|
| Deploy | Komodo deploys the projects' services as Stacks from the GitOps repo; the platform's are deployed by Ansible with `docker compose`. Komodo monitors every LXC through Periphery. |
| Names | Technitium has records for project services only, in a zone named after the platform's public domain (ADR-0026). The LXCs resolve through the router, not Technitium. Every reference between services is an IP: Gitea's and the registry's URLs (image names included), Komodo's address for Periphery, Loki's push and Prometheus' remote-write URLs, Keycloak's JWKS URL, the tunnel's routes. |
| Logs and resources | Every LXC ships its service's logs and its resources to Grafana (ADR-0023), labelled `platform` or `app`; Periphery's and Alloy's logs aren't shipped; resources are per LXC, not per container. |
| Exposure | Keycloak and Komodo's webhooks are public, Gitea and Komodo behind Access (ADR-0022); Grafana, Technitium's console, Prometheus and Loki are LAN-only; Keycloak's admin console (`/admin`) is public, with the realms. |
| Tags | Two kinds, `platform` and `app`; Periphery and Alloy take their host's. |

An IP changes when an LXC is recreated, and every place that holds one
has to be found and fixed. A LAN-only UI can't be used from outside, and
a public admin console is exposed to the internet. A service added
tomorrow (the databases of
[redemptor#17](https://github.com/urbforge/redemptor/issues/17)) would
have to pick a rule from each column.

Three choices are open:

1. **The internal zone.** Technitium serves a Primary zone named after
   the platform's public domain (`example.com`, say).
   Made the LXCs' resolver as it is, it would answer for the whole
   domain and hide every public record it doesn't hold: the platform's
   own public hostnames, and anything else the domain publishes.
2. **What Komodo can deploy.** Komodo reads Stacks from the GitOps
   repo on Gitea and reaches its servers through Periphery agents that
   connect to it: some services have to exist before it can deploy
   anything.
3. **The tag names**, the same on Komodo and Grafana.

## Decision

### The five conventions

Every service Urbex runs, platform or project, current or new:

1. **Is deployed and monitored by Komodo**: a Komodo Stack on a Server
   whose Periphery reports its containers, from the GitOps repo - or,
   for the bootstrap services, from files on their server (below).
2. **Has a name in the internal DNS**, and other services reach it only
   by that name, never by IP. The only addresses written anywhere are
   the LXCs' own (Terraform) and Technitium's, as their resolver.
3. **Sends its logs and resources to Grafana**, labelled with its kind.
4. **Is exposed by its kind of endpoint**:
   - public APIs and web UIs: through the platform's Cloudflare tunnel;
   - internal or admin APIs and UIs: through the tunnel, behind
     Cloudflare Access;
   - endpoints only other services use (databases, DNS on port 53,
     Gitea's SSH, the Loki and Prometheus write paths): by internal
     name only, with no public hostname.
5. **Is tagged with one of three kinds**, the same on Komodo and in
   Grafana: `platform`, `app` or `agent`.

They are part of the definition of done of any change that adds or
changes a service. The service catalog of
[urbex-cli#15](https://github.com/urbforge/urbex-cli/issues/15)
(`internal/platform/catalog.go` in `urbex-cli`) makes each service
declare its kind, where it runs, how Komodo deploys it, what it provides
and, for each endpoint, its internal name and exposure; internal names,
tunnel routes and Access applications are generated from it, and a test
fails when an entry - or a container in any compose file - lacks them.

### Internal DNS: the platform's subdomain, Technitium as resolver

- **Zone**: `<name>.<domain>` - the platform's name (`cloudflare.name`,
  default `urbex`) under its domain, so `urbex.example.com` - set with
  `dns.zone` in `urbex.platform.yaml`. Technitium is authoritative for
  that subtree only; the rest of the domain stays on Cloudflare. Two
  platforms on one domain get two zones. A subdomain of a domain the
  operator owns, rather than a private TLD (`.internal`, `home.arpa`):
  certificates for it can be issued through the DNS-01 challenge on
  Cloudflare if internal HTTPS is added later (Gitea's registry would
  stop being an insecure one).
- **Names are the nested form of ADR-0022's public hostnames**, whatever
  `cloudflare.hostnames` says:
  - platform services: `<label>.<zone>`, with the public labels where
    they exist: `auth` (Keycloak), `git` (Gitea), `komodo`, `hooks`, and
    `dns` (Technitium), `grafana`, `prometheus`, `loki`, `tunnel`;
  - project services: `<service>.<project>.<zone>` in prod,
    `<service>.staging.<project>.<zone>` in staging, e.g.
    `api.staging.hello.urbex.example.com`;
  - one A record per name, to the service's LXC; services sharing an
    LXC (Grafana, Prometheus and Loki) get one name each. The platform's
    labels are reserved: no project can be called `git`, `auth`, ...
- **With `nested` public hostnames, a service has one name inside and
  out**: Cloudflare answers it on the internet (through the tunnel),
  Technitium on the LAN (the LXC directly). Every name under the zone
  is Urbex's, so Technitium holds all of them - except the web
  frontends, which have no LXC: from the LXCs, their nested hostnames
  don't resolve. With `flat` public hostnames (`git-urbex.example.com`),
  public names sit outside the zone and resolve through the forwarders.
- **Everything else is forwarded**: Technitium forwards names outside
  its zone to `dns.forwarders`, by default `proxmox.network.dnsServers`,
  or the gateway when that is empty.
- **Every LXC resolves through Technitium**, then the forwarders as a
  fallback: if Technitium is down, public names keep working and
  internal ones fail, rather than every lookup. Bootstrap brings
  Technitium up before configuring the other LXCs.
- **The CLI checks before it trusts an address.** It runs on the
  operator's machine, outside the platform, and keeps taking the LXCs'
  addresses from the platform config and the allocation ledger. Before
  using one, it asks Technitium (its address is in the config) for the
  service's name and stops with an error naming both when they differ;
  when Technitium doesn't answer, it uses the configured address and
  warns. To use the internal names from the LAN, point the router's
  conditional forwarding for the zone at Technitium.

This replaces ADR-0026's zone named after the whole domain: the split
horizon is kept, but limited to the platform's own subdomain, and the
base services get records too. Records are still created and removed
with their services (bootstrap, `apply`, `destroy`, `teardown`).

### What Komodo deploys

Every service is a Komodo Stack, the platform's included. They differ in
where their compose files live and in who can repair them:

- **Bootstrap services** - Technitium, Gitea, Komodo (Core, its database,
  its Periphery and builder):
  - installed the first time by Ansible from `urbex bootstrap`, then
    adopted by Komodo as Stacks on their Servers, and from then on
    updated, redeployed and rolled back from Komodo;
  - their compose files are **files on the server**, written by
    Ansible, not read from the GitOps repo: a Stack that deploys Gitea
    can't depend on Gitea; copies are kept in the GitOps repo for
    review;
  - **`urbex bootstrap` stays their recovery path**: if a redeploy
    breaks Technitium, the Periphery agents can't resolve Komodo; if it
    breaks Gitea, Komodo can't read the GitOps repo; Komodo can't
    redeploy itself if its new version doesn't start. Re-running
    bootstrap reinstalls them with Ansible from the LXCs' addresses,
    without Komodo or DNS.
- **Periphery**, on every LXC, stays Ansible-only: it is the agent
  Komodo deploys through.
- **Everything else** comes from the GitOps repo, folder
  `platform/<service>/`, deployed like a project service
  ([ADR-0020](0020-trunk-releases-gitops-environments.md)): compose
  file, `config.env`, `secrets.sops.env` decrypted on the LXC.
  - Keycloak, the observability stack (Prometheus, Loki, Grafana), the
    tunnel (`cloudflared`);
  - the telemetry agent (Alloy): one Stack per Server,
    `urbex-telemetry-<host>`.
- Bootstrap order: Terraform creates the LXCs; Ansible installs
  Periphery and the bootstrap services; urbex configures Technitium
  (zone, records), Gitea and Komodo, has Komodo adopt the bootstrap
  services, pushes the GitOps repo, and has Komodo deploy the
  platform's Stacks.

### Kinds and tags

| Kind | What | Komodo tag | Grafana label |
|---|---|---|---|
| the platform's services, created by Urbex | Gitea, Komodo, Technitium, Keycloak, Prometheus, Loki, Grafana, the tunnel | `platform` | `kind="platform"` |
| the users' applications | a project's services, frontends and databases | `app` | `kind="app"` |
| technical agents running next to another service | Periphery, Alloy, the Quick Tunnel sidecar ([ADR-0025](0025-cloudflare-quick-tunnel.md)) | `agent` | `kind="agent"` |

- `platform` and `app` keep today's meaning, values and project and
  environment tags; `agent` is new.
- Every container carries Docker labels `urbex.kind` and
  `urbex.service`; Alloy takes the labels of logs and metrics from them,
  so an agent is told apart from the service it runs next to.
  Periphery's and Alloy's logs are shipped, as `agent`.
- Resources: the LXC's metrics keep the kind of its main service; Alloy
  also collects per-container CPU and memory (its cAdvisor exporter),
  labelled with each container's kind and service.
- On Komodo, a Server takes its main service's kind; Stacks, Builds,
  the builder and urbex's Action and Procedure take their own
  (`platform` for urbex's, `app` for a project's).

### Every current service

| Service | LXC | Internal name | Exposure | Kind |
|---|---|---|---|---|
| Technitium (DNS) | `urbex-technitium` | `dns.<zone>` | console behind Access; DNS internal | platform |
| Gitea (web, git, registry) | `urbex-gitea` | `git.<zone>` | web behind Access; git and registry internal | platform |
| Komodo | `urbex-komodo` | `komodo.<zone>` | UI behind Access; `/listener/` public (signed calls), also as `hooks.<zone>` | platform |
| Keycloak | `urbex-keycloak` | `auth.<zone>` | the projects' realms public; `/admin` and the `master` realm behind Access | platform |
| Grafana | `urbex-observability` | `grafana.<zone>` | behind Access | platform |
| Prometheus | `urbex-observability` | `prometheus.<zone>` | UI behind Access; remote write internal | platform |
| Loki | `urbex-observability` | `loki.<zone>` | API behind Access; push internal | platform |
| Tunnel (`cloudflared`) | `urbex-tunnel` | `tunnel.<zone>` | none (outbound only) | platform |
| Periphery | every LXC | - (connects out to Komodo) | internal | agent |
| Alloy | every LXC | - (pushes out) | internal | agent |
| Quick Tunnel sidecar | a project service's LXC | - | the service's public endpoint | agent |
| Project service | `<project>-<service>-<env>` | `<service>.<project>.<zone>` (prod), `<service>.staging.<project>.<zone>` | public with `public: true`, otherwise internal | app |
| Project web frontend | none (Cloudflare Worker, deployed by a Stack on the builder) | - (served by Cloudflare) | public | app |
| Project database ([redemptor#17](https://github.com/urbforge/redemptor/issues/17)) | its own LXC | `<database>.<project>.<zone>` (prod), `<database>.staging.<project>.<zone>` | internal | app |

Agents with no listener of their own (Periphery, Alloy) and services
that live on Cloudflare (web frontends) have no internal name.
On a platform named `urbex` under `example.com`, Gitea is
`git.urbex.example.com` and a project `hello`'s staging API
`api.staging.hello.urbex.example.com`. The new
public hostnames follow ADR-0022's scheme (`grafana-urbex.<domain>` flat,
`grafana.urbex.<domain>` nested, ...); Keycloak's admin console is an Access
application on the `/admin` path of Keycloak's hostname, and its admin
realm one on `/realms/master`: the admin login and token endpoints
aren't public either, only the projects' realms are (refined while
implementing [urbex-cli#13](https://github.com/urbforge/urbex-cli/issues/13)).

## Rationale

- One operating model: knowing a service's kind tells where it runs,
  how it is reached, where its logs are and how it is protected,
  whether it was written for the platform or for a project.
- Names instead of IPs make recreating an LXC a non-event for the
  services that use it, and the GitOps repo stops recording addresses.
- A zone limited to the platform's subdomain keeps the rest of the
  public domain where it is (Cloudflare) and lets Technitium be the only
  resolver the LXCs need; with nested hostnames, one name per service,
  inside and out.
- Every service gets Komodo's deploys, history and rollbacks; keeping
  Ansible as the bootstrap services' recovery path avoids a platform
  that can't repair itself.
- Docker labels carry the kind with the container, wherever it runs, so
  Alloy needs no per-host list.

## Consequences

- Implemented by
  [urbex-cli#10](https://github.com/urbforge/urbex-cli/issues/10) (zone
  and resolver), [#11](https://github.com/urbforge/urbex-cli/issues/11)
  (references by name), [#12](https://github.com/urbforge/urbex-cli/issues/12)
  (kinds), [#13](https://github.com/urbforge/urbex-cli/issues/13)
  (Access), [#14](https://github.com/urbforge/urbex-cli/issues/14)
  (Stacks) and [#15](https://github.com/urbforge/urbex-cli/issues/15)
  (catalog), in that order for the first two.
- Technitium becomes a dependency of every lookup inside the platform:
  its LXC is backed up and monitored like the other bootstrap services.
- Image references change from `<ip>:3000/...` to
  `git.<zone>:3000/...`: existing environments get new compose files
  on their next deploy, and Docker's insecure-registry entry follows the
  name.
- Existing platforms move to the new zone on the next `urbex bootstrap`;
  the old domain-named zone is deleted from Technitium.
- The platform's own subdomain belongs to Urbex: records under it on
  Cloudflare that Urbex didn't create are shadowed on the LAN.
- More Access applications (Grafana, Technitium, Prometheus, Loki,
  Keycloak's `/admin` and `master` realm): the e-mail list of `cloudflare.access.emails`
  applies to all of them. Without Cloudflare, these stay on the LAN.
- The platform's Stacks need their secrets (Keycloak's and Grafana's
  admin passwords, the tunnel's token) in the GitOps repo, encrypted
  with SOPS like the projects' ([ADR-0011](0011-secrets-sops-age.md)),
  instead of being passed by Ansible.
