# ADR-0004: GitOps on Gitea, reconciliation via Komodo

## Status

Accepted

## Context

The infrastructure must be "documented and managed in a GitOps repo", and
each LXC "manages its own docker compose by cloning a git repo". A
self-hosted Git server is needed, as well as an engine that keeps the LXCs
in sync with the state declared in the repos.

## Decision

- **Gitea**, on a dedicated LXC on Proxmox, as the self-hosted Git server
  for the GitOps repo and for the app repos created/managed in v1.
- **Komodo**, on a dedicated LXC, watches (poll/webhook) the repos and
  applies updates to the `docker compose` files on the LXCs — it is the
  system's reconciliation/redeploy engine, for both base services and
  project services.

## Rationale

- Explicitly requested: self-hosted Git repo + pipeline/update management
  via Komodo.
- Gitea is lightweight, suitable for running in an LXC on home-lab
  hardware.
- Komodo already provides the "clone repo → update docker compose on the
  host" logic, avoiding the need to write a custom reconciliation loop.

## Consequences

- v1 only supports Gitea as the Git server for repos managed by Urbex
  (GitHub/GitLab planned for v2+, see [`roadmap.md`](../roadmap.md)).
- The initial bootstrap must create Gitea *before* the GitOps repo can
  exist on it (see
  [ADR-0006](0006-bootstrap-command.md)).
- Komodo must have access (credentials/deploy key) to every repo it
  manages: managing these credentials is part of the bootstrap and of
  provisioning each new project.

## Logging note

The original request mentions "logging and metrics" as a base service
responsibility, but only the Prometheus+Grafana stack (metrics) was
explicitly chosen. Proposed design assumption: add **Loki + Promtail** as
the natural logging complement in the same Grafana stack. This point
remains open and must be confirmed during technical design (see Open
Questions in [`roadmap.md`](../roadmap.md)).
