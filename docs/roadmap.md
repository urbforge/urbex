# Roadmap

What Urbex covers (v1), what comes next, and later evolutions. For what
works today and its limits, see [`status.md`](status.md) and
[`known-limitations.md`](known-limitations.md).

## v1 — scope

- Infrastructure target: **Proxmox only** (an already-running server).
- Git server managed by Urbex: **Gitea only**.
- Container registry: **Gitea's built-in registry**
  ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)).
- CI/CD (image build + deploy): **Komodo**, triggered by Gitea webhooks
  ([ADR-0020](decisions/0020-trunk-releases-gitops-environments.md)).
- LXC operating system: **Debian 13**.
- Orchestrator: **Docker Compose** (one per LXC).
- Provisioning: **Terraform/OpenTofu + Ansible**.
- Frontend: **Cloudflare Workers** with static assets (web, the successor
  of Pages), **Firebase** (mobile).
- Services: **Java, Python, Go**, or any **Docker image** with a ready
  Dockerfile.
- Base services created on-demand: **Gitea, Komodo, Technitium, Keycloak,
  Prometheus + Grafana + Loki**.
- Ingress: **Cloudflare Tunnel**, with **Cloudflare Access** in front of
  the admin UIs ([ADR-0022](decisions/0022-cloudflare-tunnel-access-workers.md)).
- Secrets: **SOPS + age**.
- Topology: **one LXC per service per environment** (staging/prod
  separated).
- Development and promotion: **trunk-based** project repos, every push
  to `main` built and **deployed to staging**, **tagged releases**
  (`vX.Y.Z`) promoted to production, and **one folder per environment in
  the GitOps repo** deciding what it runs
  ([ADR-0021](decisions/0021-staging-follows-main.md)).
- Per-project isolation on Proxmox: creating a new project also creates
  - a dedicated **resource pool**, holding all of the project's LXCs;
  - a **group for the project's users**, with the minimum permissions
    needed to operate it, granted on that pool only;
  - the **technical users** (with their API tokens) that Urbex needs to
    work on the project, scoped the same way.

  Not implemented yet: today every LXC goes in the single pool set in
  `urbex.platform.yaml` (`proxmox.pool`), managed with the operator's
  token.
- Interface: **CLI** (`urbex`), usable by Claude Code, Codex, or a human.

## Milestones

The roadmap agreed in
[urbforge/redemptor#24](https://github.com/urbforge/redemptor/pull/24)
(`redemptor/docs/roadmap-proposal.md`): six milestones, each with its
epics. Every epic is an issue in `urbforge/redemptor`, its tasks are
sub-issues there or in `urbex` / `urbex-cli`, and the same milestones
exist in the three repos. A milestone opens when the previous one
closes, and closes when every task of its epics is done. No dates yet.

| Milestone | Goal | Epics |
| --- | --- | --- |
| M1 · v1.0 Platform conventions (done) | Every service operated the same way | E1 Service conventions ([redemptor#23](https://github.com/urbforge/redemptor/issues/23), [ADR-0027](decisions/0027-service-conventions.md)) |
| M2 · v1.1 Data | Projects that store data, safely - and a platform that runs without a homelab | E2 Databases ([redemptor#17](https://github.com/urbforge/redemptor/issues/17)) · E3 Backups and restore ([redemptor#31](https://github.com/urbforge/redemptor/issues/31)) · E3-bis VPS support ([redemptor#32](https://github.com/urbforge/redemptor/issues/32)) |
| M3 · v1.2 Production-ready | Run real apps and sleep at night | E4 Observability, next step ([redemptor#33](https://github.com/urbforge/redemptor/issues/33)) · E5 Security and isolation ([redemptor#34](https://github.com/urbforge/redemptor/issues/34)) · E6 Transactional email ([redemptor#13](https://github.com/urbforge/redemptor/issues/13)) |
| M4 · v1.3 Team operations | Several people on one platform | E7 Operators and identity ([redemptor#35](https://github.com/urbforge/redemptor/issues/35)) · E8 Bootstrap performance ([redemptor#18](https://github.com/urbforge/redemptor/issues/18)) |
| M5 · v1.4 Richer projects | More of what an app needs | E9 Frontends ([redemptor#36](https://github.com/urbforge/redemptor/issues/36)) · E10 Project lifecycle ([redemptor#37](https://github.com/urbforge/redemptor/issues/37)) |
| M6 · v2 Beyond the homelab | Other people, other stacks | E11 Modular architecture ([redemptor#16](https://github.com/urbforge/redemptor/issues/16)) · E12 End-user docs site ([redemptor#15](https://github.com/urbforge/redemptor/issues/15)) |

Alongside the milestones, **E13 First users**
([redemptor#38](https://github.com/urbforge/redemptor/issues/38)): a
demo of the full flow and the first ~20 self-hosters from homelab
communities, whose feedback reorders the milestones.

What the planned additions of v1 became:

- **Several frontends per project**, web and mobile together - E9 (M5).
- ~~**Frontends registered as Keycloak clients automatically**~~ - done,
  with a realm per environment, the services' roles and staging test
  users ([ADR-0024](decisions/0024-keycloak-realm-per-environment.md)).
- ~~**Service logs shipped to the observability stack automatically**~~
  - done, with the base services' logs and every LXC's resource metrics
  ([ADR-0023](decisions/0023-service-logs-to-loki.md)). The services'
  own metrics, alerting and Loki retention - E4 (M3).
- **Per-project Proxmox isolation** (pool, group, technical users - see
  v1 scope above) - E5 (M3).
- ~~**Internal DNS registration in Technitium**~~ - done, independent
  of Cloudflare being configured
  ([ADR-0026](decisions/0026-technitium-internal-dns-records.md)).
- Keycloak in production mode, a `platform` realm for admin SSO - E7
  (M4).
- **Hosts beyond Proxmox**: a server you bring over SSH, then Hetzner
  Cloud, then DigitalOcean (ADR in
  [urbex#24](https://github.com/urbforge/urbex/issues/24)) - E3-bis (M2).
- **Backups and restore** of Gitea, Komodo, Keycloak, databases and
  volumes - E3 (M2).

## v2+ — future evolutions

- **Cloud providers** beyond Proxmox: Azure, GCP, AWS (VPS hosts come
  first, in E3-bis).
- **Git servers** beyond Gitea: GitHub, GitLab.
- **Container registries** beyond Gitea: ghcr.io (paired with GitHub).
- **CI/CD** beyond Komodo: GitHub Actions, ArgoCD.
- **Orchestrators** beyond Docker Compose: Kubernetes.
- **Secrets**: optional HashiCorp Vault support.
- **Email providers**: additional transactional email providers beyond
  Brevo (e.g. Resend, Postmark, Amazon SES).
- **Promotion by pull request** on the GitOps repo, with protection on
  the production folder - planned in E10 (M5).
- **Applications from published images, stacks, declared requirements**
  ([ADR-0028](decisions/0028-application-model.md), proposed): images
  pinned by digest, linked applications (`uses`/`provides`), volumes
  and NAS shares, `access` exposure, OIDC clients, single-environment
  stacks, and one LXC per stack (`placement: stack`) for more
  resource-constrained hardware.
- Optional layers on top of the CLI: a dedicated Claude Code skill/plugin,
  an MCP server.
- **Schema sync automation**: a CI check (or codegen step) so the
  manifest schema vendored in `urbforge/urbex-cli` can't silently drift
  from `urbforge/urbex/schemas/urbex.schema.json` (see
  [ADR-0016](decisions/0016-cli-repo-split.md)).

## Design decisions status

All architectural points identified during initial planning have been
resolved as ADRs (see [`decisions/`](decisions/)):

| Area | Resolved by |
|---|---|
| Logging stack | [ADR-0004](decisions/0004-gitops-gitea-komodo.md#logging-note) |
| Terraform state location | [ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Platform config format & location | [ADR-0012](decisions/0012-platform-config-and-credentials.md) |
| Keycloak model per project | [ADR-0014](decisions/0014-keycloak-realm-per-project.md) |
| age key / credentials distribution | [ADR-0012](decisions/0012-platform-config-and-credentials.md) |
| Image build & registry | [ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md) |
| Rollout & promotion flow | [ADR-0020](decisions/0020-trunk-releases-gitops-environments.md), [ADR-0021](decisions/0021-staging-follows-main.md) |
| Formal manifest schema | [`schemas/urbex.schema.json`](../schemas/urbex.schema.json) |

No open architectural questions remain before starting implementation.
New ones that surface during CLI/Terraform/Ansible implementation should
be recorded here as they come up.
