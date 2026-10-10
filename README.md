# Urbex

**Urbex - a self-hosted app platform: everything your apps need, on infrastructure you own.**

Write the app; Urbex gives it everything else - repositories, builds, deploys, login, networking, logs, backups. On your server, not someone else's cloud.

Every environment, from a homelab to the cloud, should give applications the same fundamental services, the same way. Urbex is that platform.

## Why

Every serious application needs the same things: a repository, a CI
pipeline that builds its images, a CD pipeline that takes them to
staging and production, an identity provider, an address people can
reach, logs and monitoring, storage and backups, disaster recovery, high
availability. Today whoever writes the app wires each of them by hand,
and differently in every environment. Urbex is one standard ecosystem
you install once - on your homelab or your cloud - and from then on each
application declares what it needs in `urbex.yaml`, and gets it.

## An operating system for your apps

Think of it as an operating system for applications: what an OS gives a program, Urbex gives an application.

| An OS gives a program | Urbex gives an application | Today |
| --- | --- | --- |
| `exec` | build and deploy: CI builds the image, CD takes it to staging and production | available |
| processes | an isolated environment per service (LXC), staging and production | available |
| users and permissions | an identity provider (Keycloak): login, roles, a client per frontend | available |
| network and DNS | internal DNS, a public tunnel, protected access (Cloudflare) | available |
| filesystem | storage, databases, backups | roadmap |
| system logs and monitor | logs and resources in Grafana, every container in Komodo | available |
| package manager | the platform's standard services, the same in every environment | available |
| system restore | disaster recovery and high availability | roadmap |

In short: like Heroku or Vercel, but on your server and with everything
included; like Coolify or Dokploy, with identity, observability - and,
next, backups and disaster recovery - built in. And built to be driven
by an AI agent as well as by a person: its interface is a CLI an agent
like Claude Code or Codex can use
([ADR-0001](docs/decisions/0001-cli-first-interface.md)).

## How it works

Urbex runs on a server you already have - a Proxmox node today - and
installs the platform's services there: Gitea for the repositories,
Komodo for builds and deploys, Technitium for internal DNS, Keycloak for
identity, Prometheus, Loki and Grafana for monitoring, and Cloudflare for
public access. A project - web frontends deployed to Cloudflare Workers,
mobile apps registered with Keycloak, services in Java, Python, Go or any
Docker image - describes itself in `urbex.yaml`, and the `urbex` CLI
creates and keeps what it needs in every environment.

## Status

🚧 Early stage. The `urbex` CLI is implemented in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli): bootstrap
sets up Gitea and Komodo; projects are developed trunk-based, and every
push to `main` is built by Komodo and deployed to staging; releases are
tags, promoted to production; and each environment runs what its folder
in the GitOps repo says - version, configuration, SOPS-encrypted
secrets - deployed by Komodo on every change. With Cloudflare, public
APIs go out through a Cloudflare Tunnel, web frontends are deployed to
Cloudflare Workers, Keycloak is public, and Gitea and Komodo sit behind
Cloudflare Access; every service also gets an internal DNS name in
Technitium, independently of Cloudflare. Validated on a real Proxmox
VE 9.2 node and Cloudflare account - see
[`docs/known-limitations.md`](docs/known-limitations.md) for what's
still missing.
See [`docs/status.md`](docs/status.md) for the full
supported/not-supported breakdown and implementation priorities, and
`docs/` more generally for architecture, decisions, and roadmap.

## v1 — goal

- Infrastructure target: an already-running **Proxmox** server.
- Every project service runs in a dedicated **LXC** (Debian 13), as a
  container Komodo builds from the project's Git repo and rolls out.
- Platform services (created on-demand if missing):
  - **Gitea** — self-hosted Git server (app repos + GitOps repo).
  - **Komodo** — build/update pipeline and LXC management.
  - **Technitium DNS** — internal name resolution between services.
  - **Keycloak** — identity provider (SSO for admin tools and OIDC for
    apps).
  - **Prometheus + Grafana + Loki** — metrics, logs, and observability.
- All infrastructure is declared and versioned in a **GitOps repo**,
  which also says, per environment, what each project runs: version,
  configuration, secrets.
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

Start here:

- [**Getting started**](docs/getting-started.md) — from an empty Proxmox
  server to a service in production, every command and its output.
- [**Cookbook**](docs/cookbook.md) — recipes: releasing, rolling back,
  pinning staging, secrets, adding services, troubleshooting, driving
  Urbex from an LLM agent.

Reference ([index](docs/reference/)):

- [CLI](docs/reference/cli.md) — every command and flag.
- [Manifest](docs/reference/manifest.md) — `urbex.yaml`, field by field;
  formal schema in [`schemas/urbex.schema.json`](schemas/urbex.schema.json).
- [Platform config](docs/reference/platform-config.md) —
  `urbex.platform.yaml`.
- [GitOps repo](docs/reference/gitops-repo.md) — layout, version,
  configuration and secrets files, how a commit is deployed.
- [Credentials](docs/reference/credentials.md) — every credential and how
  to get it.
- [Platform resources](docs/reference/platform-resources.md) — what Urbex
  creates on Proxmox, Gitea, and Komodo.

Design and planning:

- [`docs/architecture.md`](docs/architecture.md) — components and flows.
- [`docs/decisions/`](docs/decisions/) — Architecture Decision Records.
- [`docs/status.md`](docs/status.md) — what's supported today vs. not
  yet, and priorities.
- [`docs/known-limitations.md`](docs/known-limitations.md) — every known
  limitation, with what to do meanwhile.
- [`docs/roadmap.md`](docs/roadmap.md) — v1 vs v2+ scope.
