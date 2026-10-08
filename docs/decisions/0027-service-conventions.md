# ADR-0027: Conventions every service follows

## Status

Proposed. Refines [ADR-0022](0022-cloudflare-tunnel-access-workers.md)
(more services behind Access, tunnel routes by name),
[ADR-0023](0023-service-logs-to-loki.md) (three kinds instead of two,
the agents' own logs, per-container resources) and
[ADR-0026](0026-technitium-internal-dns-records.md) (a dedicated
internal zone, base services registered, Technitium as the LXCs'
resolver). Tracked by
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

1. **Is deployed and monitored by Komodo**: a Komodo Stack from the
   GitOps repo, on a Server whose Periphery reports its containers. The
   exceptions are the bootstrap services below.
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
   Grafana: `infra`, `app` or `support`.

They are part of the definition of done of any change that adds or
changes a service. The service catalog of
[urbex-cli#15](https://github.com/urbforge/urbex-cli/issues/15) makes
each service declare its kind, name and exposure, and a test fails when
one is missing.

### Internal DNS: a dedicated zone, Technitium as resolver

- **Zone**: `int.<domain>` by default (`int.example.com`), set with
  `dns.zone` in `urbex.platform.yaml`. A subdomain of a domain the
  operator owns, rather than a private TLD (`.internal`, `home.arpa`):
  nobody else can claim it, and certificates for it can be issued
  through the DNS-01 challenge on Cloudflare if internal HTTPS is added
  later (Gitea's registry would stop being an insecure one). The public
  zone never delegates it, so these names don't resolve on the internet.
- **Names**:
  - platform services: `<service>.<zone>`, e.g. `gitea.int.example.com`;
  - project services: `<service>.<env>.<project>.<zone>`, e.g.
    `api.staging.hello.int.example.com`. Hierarchical, since the
    internal zone has no certificate constraint (unlike ADR-0022's flat
    public names). The platform services' names are reserved: no project
    can be called `gitea`, `komodo`, ...
  - one record per service, A to its LXC; services sharing an LXC
    (Grafana, Prometheus and Loki) get one name each.
- **Everything else is forwarded**: Technitium forwards names outside
  its zone to `dns.forwarders`, by default `proxmox.network.dnsServers`,
  or the gateway when that is empty. Public names, the platform's
  included, resolve as they do on the internet.
- **Every LXC resolves through Technitium**, then the forwarders as a
  fallback: if Technitium is down, public names keep working and
  internal ones fail, rather than every lookup. Technitium's own LXC
  uses the forwarders. Bootstrap brings Technitium up before configuring
  the other LXCs.
- The operator's machine is outside the platform: the CLI keeps using
  the LXCs' addresses from the platform config. To use the internal
  names from the LAN, point the router's conditional forwarding for the
  zone at Technitium.

This replaces ADR-0026's split horizon (internal and public names being
the same FQDN): internal names live in their own zone, public ones only
on Cloudflare. Records are still created and removed with their
services (bootstrap, `apply`, `destroy`, `teardown`).

### What Komodo deploys

- **Bootstrap services**, installed by Ansible from `urbex bootstrap`,
  because Komodo can't deploy anything without them:
  - **Technitium**: every other name resolves through it, Periphery's
    connection to Komodo included;
  - **Gitea**: holds the GitOps repo Komodo reads Stacks from;
  - **Komodo** itself (Core, its database, its Periphery and builder);
  - **Periphery** on every LXC: the agent Komodo deploys through.

  Komodo monitors them (their LXCs are Servers, as today), and their
  compose files are kept in the GitOps repo with the others; upgrading
  them is a `urbex bootstrap` re-run. Moving Gitea or Technitium to
  Komodo after bootstrap was rejected: a failed redeploy would cut
  Komodo off from the repo or the names it needs to repair it.
- **Everything else is a Komodo Stack** from the GitOps repo, folder
  `platform/<service>/`, deployed like a project service
  ([ADR-0020](0020-trunk-releases-gitops-environments.md)): compose
  file, `config.env`, `secrets.sops.env` decrypted on the LXC.
  - Keycloak, the observability stack (Prometheus, Loki, Grafana), the
    tunnel (`cloudflared`);
  - the telemetry agent (Alloy): one Stack per Server,
    `urbex-telemetry-<host>`.
- Bootstrap order: Terraform creates the LXCs; Ansible installs the
  bootstrap services; urbex configures Technitium (zone, records),
  Gitea and Komodo, pushes the GitOps repo and has Komodo deploy the
  platform's Stacks.

### Kinds and tags

| Kind | What | Komodo tag | Grafana label |
|---|---|---|---|
| infrastructure | the platform's services: Gitea, Komodo, Technitium, Keycloak, Prometheus, Loki, Grafana, the tunnel | `infra` | `kind="infra"` |
| application | a project's services, frontends and databases | `app` | `kind="app"` |
| support | agents running next to another service: Periphery, Alloy, the Quick Tunnel sidecar ([ADR-0025](0025-cloudflare-quick-tunnel.md)) | `support` | `kind="support"` |

- `infra` replaces `platform` (Komodo tag and Grafana label); `app` is
  unchanged, with its project and environment.
- Every container carries Docker labels `urbex.kind` and
  `urbex.service`; Alloy takes the labels of logs and metrics from them,
  so a support container is told apart from the service it runs next
  to. Periphery's and Alloy's logs are shipped, as `support`.
- Resources: the LXC's metrics keep the kind of its main service; Alloy
  also collects per-container CPU and memory (its cAdvisor exporter),
  labelled with each container's kind and service.
- On Komodo, a Server takes its main service's kind; Stacks, Builds,
  the builder and urbex's Action and Procedure take their own (`infra`
  for urbex's, `app` for a project's).

### Every current service

| Service | LXC | Internal name | Exposure | Kind |
|---|---|---|---|---|
| Technitium (DNS) | `urbex-technitium` | `technitium.<zone>` | console behind Access; DNS internal | infra |
| Gitea (web, git, registry) | `urbex-gitea` | `gitea.<zone>` | web behind Access; git and registry internal | infra |
| Komodo | `urbex-komodo` | `komodo.<zone>` | UI behind Access; `/listener/` public (signed calls) | infra |
| Keycloak | `urbex-keycloak` | `keycloak.<zone>` | realms public; `/admin` behind Access | infra |
| Grafana | `urbex-observability` | `grafana.<zone>` | behind Access | infra |
| Prometheus | `urbex-observability` | `prometheus.<zone>` | UI behind Access; remote write internal | infra |
| Loki | `urbex-observability` | `loki.<zone>` | API behind Access; push internal | infra |
| Tunnel (`cloudflared`) | `urbex-tunnel` | `tunnel.<zone>` | none (outbound only) | infra |
| Periphery | every LXC | - (connects out to Komodo) | internal | support |
| Alloy | every LXC | - (pushes out) | internal | support |
| Quick Tunnel sidecar | a project service's LXC | - | the service's public endpoint | support |
| Project service | `<project>-<service>-<env>` | `<service>.<env>.<project>.<zone>` | public with `public: true`, otherwise internal | app |
| Project web frontend | none (Cloudflare Worker, deployed by a Stack on the builder) | - (served by Cloudflare) | public | app |
| Project database ([redemptor#17](https://github.com/urbforge/redemptor/issues/17)) | its own LXC | `<database>.<env>.<project>.<zone>` | internal | app |

Agents with no listener of their own (Periphery, Alloy) and services
that live on Cloudflare (web frontends) have no internal name. The new
public hostnames follow ADR-0022's scheme (`grafana-urbex.<domain>`,
`dns-urbex.<domain>`, ...); Keycloak's admin console is an Access
application on the `/admin` path of Keycloak's hostname.

## Rationale

- One operating model: knowing a service's kind tells where it runs,
  how it is reached, where its logs are and how it is protected,
  whether it was written for the platform or for a project.
- Names instead of IPs make recreating an LXC a non-event for the
  services that use it, and the GitOps repo stops recording addresses.
- A dedicated zone keeps the public domain's records where they are
  (Cloudflare) and lets Technitium be the only resolver the LXCs need.
- Keeping the bootstrap services out of Komodo avoids a platform that
  can't repair itself; everything after them gets Komodo's deploys,
  history and rollbacks.
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
  `gitea.<zone>:3000/...`: existing environments get new compose files
  on their next deploy, and Docker's insecure-registry entry follows the
  name.
- Existing platforms move to the new zone on the next `urbex bootstrap`;
  the old records in the domain-named zone are removed. Grafana keeps
  the old `kind="platform"` series until they age out; the dashboards
  filter on the new values.
- More Access applications (Grafana, Technitium, Prometheus, Loki,
  Keycloak's `/admin`): the e-mail list of `cloudflare.access.emails`
  applies to all of them. Without Cloudflare, these stay on the LAN.
- The platform's Stacks need their secrets (Keycloak's and Grafana's
  admin passwords, the tunnel's token) in the GitOps repo, encrypted
  with SOPS like the projects' ([ADR-0011](0011-secrets-sops-age.md)),
  instead of being passed by Ansible.
