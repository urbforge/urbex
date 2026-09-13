# ADR-0006: `urbex bootstrap` solves the chicken-and-egg problem

## Status

Accepted

## Context

Infrastructure is managed via GitOps on a repo hosted on Gitea — but Gitea
itself is a base service that must be created *by Urbex*. On a fresh
Proxmox there is neither Gitea nor a GitOps repo yet to drive
reconciliation from. Options evaluated: a dedicated bootstrap command that
acts directly on Proxmox, or routing even the first bootstrap through a
GitOps flow (with a local/temporary repo before Gitea exists).

## Decision

Urbex operates in two explicit modes:

1. **`urbex bootstrap`**: runs Terraform/OpenTofu + Ansible directly
   against the Proxmox API to create the base services (Gitea, Komodo,
   Technitium, Keycloak, Prometheus/Grafana/Loki) and the first Gitea
   repo, then pushes the initial state to it as the GitOps repo.
2. **Steady-state**: from that point on, every change goes through a
   commit to the GitOps repo + reconciliation via Komodo/CLI.

## Rationale

- A "everything via GitOps from the start" flow would require inventing a
  temporary pre-Gitea Git repo and then migrating the remote: conceptually
  purer but much more complex to implement and explain correctly, for a
  marginal benefit at Urbex's target scale (a single operator managing
  personal-app infrastructure).
- Having two explicit, documented modes (bootstrap vs steady-state) is
  easier to reason about, test, and explain to an LLM that needs to
  understand which phase a given Proxmox is in.

## Consequences

- `urbex bootstrap` must be idempotent: re-running it on an already
  bootstrapped Proxmox must not duplicate resources (it must detect base
  services already present, as required: "created **if not already
  present**").
- Bootstrap requires direct credentials to the Proxmox API (token), while
  steady-state can operate mainly through Git commits + Komodo.
- A way for the user/LLM to check what state a Proxmox is in is needed
  (`urbex status` at the platform level, not just at the project level).
