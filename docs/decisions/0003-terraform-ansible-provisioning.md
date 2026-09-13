# ADR-0003: Terraform/OpenTofu for provisioning, Ansible for configuration

## Status

Accepted

## Context

A way is needed to create/update/destroy LXCs on Proxmox and to configure
their contents (Docker, users, hardening, joining base services).
Options evaluated: Terraform/OpenTofu only, Ansible only, custom scripts
against the Proxmox API, Terraform+Ansible combined.

## Decision

- **Terraform/OpenTofu** (Proxmox provider, e.g. `bpg/proxmox`) for
  provisioning: existence, resources (CPU/RAM/disk), network, and storage
  of LXCs. Tracked state, native drift detection.
- **Ansible** for the internal configuration of LXCs after boot: Docker,
  users, hardening, registration with Technitium/Keycloak, initial docker
  compose deploy.

## Rationale

- Clean separation between "what exists" (Terraform, declarative, state)
  and "how it's configured" (Ansible, idempotent, no state to manage).
- Standard pattern in the IaC world, well documented, easy to explain to
  an LLM that generates configurations.
- Avoids reinventing state management and drift detection by writing
  custom scripts against the Proxmox API.

## Consequences

- Two tools to maintain and orchestrate in sequence inside `urbex
  plan`/`urbex apply` (Terraform first, then Ansible on its output).
- Terraform state must be versioned/backed up consistently with the
  GitOps repo (remote backend or encrypted committed state — to be
  defined during technical design).
- Terraform modules for base LXCs (Gitea, Komodo, Technitium, Keycloak,
  Prometheus/Grafana) and for project LXCs must be parameterized and
  reusable.
