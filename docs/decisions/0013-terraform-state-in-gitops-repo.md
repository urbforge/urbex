# ADR-0013: Terraform state, SOPS-encrypted, committed to the GitOps repo

## Status

Accepted

## Context

Terraform/OpenTofu (see
[ADR-0003](0003-terraform-ansible-provisioning.md)) needs a place to
store its state. Standard options are a remote backend (S3-compatible
object storage, Terraform Cloud, etc.) or a local/committed state file.
Urbex v1 targets a single Proxmox server with no separate object storage
service in scope, and is operated by a single person (no concurrent
`apply` runs to guard against with state locking).

## Decision

Terraform state is stored **locally as a file, encrypted with SOPS
(age), and committed to the GitOps repo**, under
`state/<scope>/terraform.tfstate` (one state file per bootstrap scope and
per project/environment). The `urbex plan`/`urbex apply` commands
orchestrate this automatically:

1. Pull the latest GitOps repo, decrypt the relevant state file into a
   local temp path (or initialize an empty one if it doesn't exist yet).
2. Run `terraform plan`/`apply` against that local state with the local
   backend.
3. Re-encrypt the resulting state file with SOPS and commit/push it back
   to the GitOps repo.

## Rationale

- Introducing a remote backend would mean provisioning *yet another*
  service before Terraform can run at all, worsening the
  chicken-and-egg problem already addressed for Gitea in
  [ADR-0006](0006-bootstrap-command.md).
- Terraform state can contain sensitive values (e.g. generated
  passwords), so it must be encrypted at rest just like other secrets
  (see [ADR-0011](0011-secrets-sops-age.md)) — reusing the same SOPS+age
  mechanism avoids introducing a second secrets-handling pattern.
- Single-operator usage means state locking (the main reason to prefer a
  remote backend) is not a pressing concern for v1; the CLI-orchestrated
  pull/decrypt → apply → encrypt/push cycle gives basic protection against
  the common case of forgetting to push updated state.

## Consequences

- `urbex plan`/`apply` must never run concurrently against the same
  scope from two different machines without pulling first — the CLI
  should detect a stale local state (GitOps repo has moved on) and
  refuse to apply until it's reconciled.
- Diffing encrypted state files in Git history is not meaningful; state
  changes will show as opaque blobs in `git log`. This is an accepted
  trade-off of the encryption requirement.
- This decision is scoped to the v1 Proxmox target. A cloud provider
  target in v2+ (see [`roadmap.md`](../roadmap.md)) may justify
  revisiting this in favor of that provider's native remote backend
  (e.g. S3 for AWS), since object storage would already be available
  there without extra bootstrapping.
