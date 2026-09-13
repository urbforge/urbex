# ADR-0012: Platform configuration file and credential handling

## Status

Accepted

## Context

Urbex needs platform-wide settings (base domain, Cloudflare zone, Proxmox
connection details, DNS/Keycloak endpoints) that are distinct from the
per-app manifest (`urbex.yaml`, see
[ADR-0002](0002-app-manifest-in-app-repo.md)). Some of this data is plain
configuration (safe to version), some is sensitive (API tokens, the age
private key) and must never be committed to Git, even encrypted with
SOPS+age, since age itself is one of the secrets involved.

## Decision

- A **`urbex.platform.yaml`** file lives at the root of the GitOps repo
  (created by `urbex bootstrap`, see
  [ADR-0006](0006-bootstrap-command.md)) and holds non-sensitive,
  versioned platform configuration:
  - `domain` (base domain used for all environments)
  - `git` (Gitea URL/org for app and GitOps repos)
  - `cloudflare` (account ID, zone ID, tunnel name — no tokens)
  - `proxmox` (API URL, node name, default storage pool — no tokens)
  - `dns` (Technitium API endpoint)
  - `keycloak` (platform realm name, base URL)
- **Credentials** (Proxmox API token, Cloudflare API token, Gitea admin
  token, the age private key used to decrypt SOPS secrets) live **outside
  Git entirely**, in a local `~/.urbex/credentials.yaml` file (or
  equivalent environment variables: `URBEX_PROXMOX_TOKEN`,
  `URBEX_CLOUDFLARE_TOKEN`, `URBEX_GITEA_TOKEN`, `URBEX_AGE_KEY`), read by
  the CLI at runtime on whatever machine executes `urbex` commands.
- The CLI locates the GitOps repo via `URBEX_GITOPS_REPO` (a local clone
  path or a Git URL) or an explicit `--gitops-repo` flag; it is never
  auto-discovered from the current directory, to avoid ambiguity when
  `urbex` is run from within an app repo.

## Rationale

- Keeps the "what" (platform topology/config) versioned and reviewable in
  Git, while keeping the "secret" (credentials, keys) out of Git
  entirely — no amount of encryption solves the bootstrapping problem of
  "the key that decrypts everything else must itself not be in the
  encrypted repo".
- A single, predictable local credentials file/env vars works whether
  `urbex` is run by a human, by an LLM agent in a sandboxed shell, or by
  Komodo/CI in an automated pipeline.
- Splitting config (`urbex.platform.yaml`) from credentials mirrors the
  same non-sensitive/sensitive separation already established for
  per-app manifests vs SOPS+age secrets (see
  [ADR-0011](0011-secrets-sops-age.md)).

## Consequences

- `urbex bootstrap` must generate `~/.urbex/credentials.yaml` (or prompt
  for the values) on first run, and must never write credentials into
  `urbex.platform.yaml` or any other file destined for Git.
- Documentation must clearly instruct users to back up
  `~/.urbex/credentials.yaml` (and the age private key in particular)
  outside of Urbex itself — Urbex has no way to recover a lost age key.
- Running `urbex` from a new machine requires provisioning that machine's
  local credentials file before any command that touches Proxmox,
  Cloudflare, Gitea, or encrypted secrets will work.
