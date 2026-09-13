# ADR-0017: Base infrastructure assets are embedded in the CLI

## Status

Accepted

## Context

[ADR-0006](0006-bootstrap-command.md) established that `urbex bootstrap`
runs Terraform/Ansible directly against Proxmox to create the base
services and the first GitOps repo. But the Terraform module and Ansible
playbook *source files* for those base services (Gitea, Komodo,
Technitium, Keycloak, Prometheus/Grafana/Loki) have to come from
somewhere — and at the moment `bootstrap` runs, no GitOps repo exists yet
to hold them.

## Decision

- The reference Terraform modules and Ansible playbooks/roles for the
  base services live **inside the `urbforge/urbex-cli` repo**, under
  `platform/terraform/` and `platform/ansible/`, embedded into the
  `urbex` binary via `go:embed` (same pattern as the manifest schema,
  see [ADR-0016](0016-cli-repo-split.md)).
- `urbex bootstrap` **materializes** (writes out) these embedded assets
  into the target GitOps repo working directory before running
  `terraform`/`ansible-playbook` against them. From that point on, the
  materialized copies are regular files in the GitOps repo, versioned
  and editable like anything else.
- Before provisioning, `urbex bootstrap` queries the Proxmox API for
  existing containers whose hostnames match the expected base-service
  names. If one exists but isn't already tracked in the local Terraform
  state, bootstrap **aborts with an error** instead of silently adopting
  or duplicating it — this is the concrete mechanism behind "created if
  not already present" from the original requirement.

## Rationale

- Mirrors the schema-embedding pattern already established for the app
  manifest: works fully offline, no dependency on `urbforge/urbex` (or
  network access) at bootstrap time.
- Materializing into the GitOps repo (rather than running Terraform
  straight from the CLI's embedded files) means the *result* of bootstrap
  is immediately a normal, inspectable, versioned GitOps repo — nothing
  stays hidden inside the binary after the first run.
- An explicit existence check before provisioning gives a safe, clear
  failure mode on a Proxmox that isn't as "vergine" (fresh) as assumed,
  rather than Terraform failing later with a less actionable error, or
  silently importing an unrelated resource.

## Consequences

- Upgrading `urbex-cli` to a new version with updated base-service
  modules does **not** retroactively update an already-bootstrapped
  GitOps repo's materialized copies — they diverge intentionally at
  materialization time and are then user-owned. Picking up platform
  updates is a separate, explicit action (out of scope for this ADR;
  likely a future `urbex platform upgrade` command).
- The CLI needs a minimal Proxmox API client (just enough to list
  existing containers by node) purely for this pre-flight check; it does
  not need to replicate anything Terraform's provider already does.
- Base-service Terraform/Ansible content is authored and reviewed inside
  `urbex-cli`'s own repo and test suite, not this docs repo.
