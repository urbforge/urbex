# ADR-0011: SOPS + age for secrets, Vault as a future extension

## Status

Accepted

## Context

The GitOps repo contains infrastructure definitions that often require
secrets (DB passwords, API keys, tokens) — these cannot live in plaintext
on Git. Options evaluated: SOPS+age, HashiCorp Vault, Ansible Vault.

## Decision

- v1: **SOPS + age**. Secret files are encrypted with age and committed
  encrypted to the GitOps repo; they are decrypted only at deploy time on
  the target LXC.
- v2+: **optional** HashiCorp Vault support for those who want rotation,
  auditing, and dynamic secrets, without replacing SOPS+age as the
  default.

## Rationale

- SOPS+age requires no additional server to bootstrap and maintain,
  unlike Vault: more suitable as a default for a personal project and for
  the initial bootstrap phase (see
  [ADR-0006](0006-bootstrap-command.md)), when the base infrastructure
  does not exist yet.
- It is the de-facto standard in the GitOps world for exactly this use
  case (encrypted secrets versioned alongside infrastructure).
- Ansible Vault was discarded as the default because it is less suited to
  secrets read at runtime by heterogeneous services compared to SOPS,
  which integrates well with both Terraform and generic manifests.

## Consequences

- Every LXC/service that needs to read secrets requires the age private
  key (or access to the decryption mechanism) at deploy time: securely
  distributing this key is a detail to be closed during technical design
  (e.g. injected by Ansible during provisioning, kept outside the Git
  repo).
- The future introduction of Vault must be optional and non-blocking:
  those who don't configure it keep using SOPS+age without any change to
  their workflow.
