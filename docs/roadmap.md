# Roadmap

## v1 — scope

- Infrastructure target: **Proxmox only** (an already-running server).
- Git server managed by Urbex: **Gitea only**.
- Provisioning: **Terraform/OpenTofu + Ansible**.
- Frontend: **Cloudflare Pages** (web), **Firebase** (mobile).
- Services: **Java, Python, Go**, or any **Docker image** with a ready
  Dockerfile.
- Base services created on-demand: **Gitea, Komodo, Technitium, Keycloak,
  Prometheus + Grafana (+ Loki, to be confirmed)**.
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

## Open questions

Architectural points where a reasonable assumption was made during
planning but that still need to be confirmed/refined during technical
design:

- **Logging**: confirm Loki + Promtail as the logging stack alongside
  Prometheus/Grafana (see note in
  [ADR-0004](decisions/0004-gitops-gitea-komodo.md#logging-note)).
- **Terraform state**: define where/how state is stored (remote backend
  vs encrypted state committed to the GitOps repo) consistently with the
  rest of the GitOps flow.
- **Platform config**: define the format and location of the global
  configuration file (domain, Proxmox credentials, Cloudflare zone — see
  [ADR-0007](decisions/0007-technitium-configurable-domain.md)), distinct
  from the per-app `urbex.yaml` manifest.
- **Keycloak model per project**: one realm per project vs multiple
  clients in a shared realm (see
  [ADR-0008](decisions/0008-keycloak-scope.md)).
- **age key distribution**: how it is securely made available to every
  LXC that needs to decrypt secrets at deploy time (see
  [ADR-0011](decisions/0011-secrets-sops-age.md)).
- **Formal manifest schema**: JSON Schema validation for
  [`urbex.yaml`](manifest-spec.md) and default values for `resources`.
