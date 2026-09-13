# Roadmap

## v1 — scope

- Infrastructure target: **Proxmox only** (an already-running server).
- Git server managed by Urbex: **Gitea only**.
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
- Promotion: **push → staging auto, tag/release → prod**.
- Interface: **CLI** (`urbex`), usable by Claude Code, Codex, or a human.

## v2+ — future evolutions

- **Cloud providers** beyond Proxmox: Azure, GCP, AWS.
- **Git servers** beyond Gitea: GitHub, GitLab.
- **Secrets**: optional HashiCorp Vault support.
- **Topology**: a "lightweight" profile with multiple services sharing a
  single LXC, for more resource-constrained hardware.
- Optional layers on top of the CLI: a dedicated Claude Code skill/plugin,
  an MCP server.

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
| Formal manifest schema | [`schemas/urbex.schema.json`](../schemas/urbex.schema.json) |

No open architectural questions remain before starting implementation.
New ones that surface during CLI/Terraform/Ansible implementation should
be recorded here as they come up.
