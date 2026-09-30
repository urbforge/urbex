# Roadmap

## v1 — scope

- Infrastructure target: **Proxmox only** (an already-running server).
- Git server managed by Urbex: **Gitea only**.
- Container registry: **Gitea's built-in registry**
  ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)).
- CI/CD (image build + deploy): **Komodo**, triggered by Gitea webhooks
  ([ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md)).
- LXC operating system: **Debian 13**.
- Orchestrator: **Docker Compose** (one per LXC).
- Provisioning: **Terraform/OpenTofu + Ansible**.
- Frontend: **Cloudflare Pages** (web), **Firebase** (mobile).
- Services: **Java, Python, Go**, or any **Docker image** with a ready
  Dockerfile.
- Base services created on-demand: **Gitea, Komodo, Technitium, Keycloak,
  Prometheus + Grafana + Loki**.
- Ingress: **Cloudflare Tunnel**.
- Secrets: **SOPS + age**.
- Topology: **one LXC per service per environment** (staging/prod
  separated).
- Promotion: **one branch per environment** - merge into `staging` →
  staging, merge into `main` → prod.
- Interface: **CLI** (`urbex`), usable by Claude Code, Codex, or a human.

## v2+ — future evolutions

- **Cloud providers** beyond Proxmox: Azure, GCP, AWS.
- **Git servers** beyond Gitea: GitHub, GitLab.
- **Container registries** beyond Gitea: ghcr.io (paired with GitHub).
- **CI/CD** beyond Komodo: GitHub Actions, ArgoCD.
- **Orchestrators** beyond Docker Compose: Kubernetes.
- **Secrets**: optional HashiCorp Vault support.
- **Email providers**: additional transactional email providers beyond
  Brevo (e.g. Resend, Postmark, Amazon SES).
- **Topology**: a "lightweight" profile with multiple services sharing a
  single LXC, for more resource-constrained hardware.
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
| Rollout & promotion flow | [ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md) |
| Formal manifest schema | [`schemas/urbex.schema.json`](../schemas/urbex.schema.json) |

No open architectural questions remain before starting implementation.
New ones that surface during CLI/Terraform/Ansible implementation should
be recorded here as they come up.
