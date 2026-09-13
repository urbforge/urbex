# Urbex

Urbex is a project to automate the creation and management of the
infrastructure needed to build, deploy, and publish (staging/production)
personal apps and projects, so that whoever develops them — manually or
through an LLM agent (Claude Code, Codex) — can focus solely on the
application itself.

Given a project with a frontend part (mobile → Firebase, web → Cloudflare
Pages) and/or a services part (Java, Python, Go, or any Docker image with a
ready Dockerfile), Urbex automatically creates and maintains the necessary
infrastructure in every environment.

## Status

🚧 Early scaffold. All 8 `urbex` CLI subcommands (`init`, `bootstrap`,
`plan`, `apply`, `deploy`, `status`, `promote`, `destroy`) have a real
implementation in [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli),
but several pieces of the v1 vision below aren't wired up yet (image
build/push, DNS/ingress, Komodo integration). See
[`docs/status.md`](docs/status.md) for the full supported/not-supported
breakdown and implementation priorities, and `docs/` more generally for
architecture, decisions, and roadmap.

## v1 — goal

- Infrastructure target: an already-running **Proxmox** server.
- Every project service runs in a dedicated **LXC**, with its own
  `docker compose`, cloned from a Git repo.
- Platform services (created on-demand if missing):
  - **Gitea** — self-hosted Git server (app repos + GitOps repo).
  - **Komodo** — build/update pipeline and LXC management.
  - **Technitium DNS** — internal name resolution between services.
  - **Keycloak** — identity provider (SSO for admin tools and OIDC for
    apps).
  - **Prometheus + Grafana + Loki** — metrics, logs, and observability.
- All infrastructure is declared and versioned in a **GitOps repo**.
- Main interface: a **CLI** (`urbex`), designed to be driven by an LLM in a
  terminal, but also usable by a human.
- The public domain is **configurable**, not hardcoded: Urbex must be
  usable by anyone with their own Proxmox and their own domain.
- Optional transactional email via a managed provider (**Brevo** in v1,
  more planned) — no self-hosted mail server.

## Future evolutions (v2+)

- Cloud providers beyond Proxmox: Azure, GCP, AWS.
- Git servers beyond Gitea: GitHub, GitLab.
- Secrets management: optional HashiCorp Vault support alongside SOPS+age.

## Repositories

- [`urbforge/urbex`](https://github.com/urbforge/urbex) (this repo) —
  architecture, ADRs, manifest spec/schema, roadmap.
- [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli) — the
  `urbex` CLI implementation (Go). See
  [ADR-0016](docs/decisions/0016-cli-repo-split.md).

## Documentation

- [`docs/status.md`](docs/status.md) — what's supported today vs. not
  yet, and priorities for what to implement next.
- [`docs/guide.md`](docs/guide.md) — real-world, step-by-step walkthrough
  (bootstrap → deploy → test → promote → iterate → fleet status) using
  the actual CLI, with known gaps called out inline.
- [`docs/credentials.md`](docs/credentials.md) — every credential Urbex
  reads, what it's for, and exactly how to get it.
- [`docs/architecture.md`](docs/architecture.md) — components, flows, CLI.
- [`docs/manifest-spec.md`](docs/manifest-spec.md) — schema of the app
  manifest (`urbex.yaml`); formal schema in
  [`schemas/urbex.schema.json`](schemas/urbex.schema.json).
- [`docs/roadmap.md`](docs/roadmap.md) — v1 vs v2+ scope.
- [`docs/decisions/`](docs/decisions/) — Architecture Decision Records.
