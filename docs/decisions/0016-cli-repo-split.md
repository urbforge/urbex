# ADR-0016: The CLI implementation lives in a separate repo

## Status

Accepted

## Context

Urbex so far has been a planning/documentation repo (`urbforge/urbex`):
README, architecture, ADRs, the manifest JSON Schema. Implementation work
on the `urbex` CLI (see [ADR-0001](0001-cli-first-interface.md)) needs
somewhere to live: the same repo, or a dedicated one.

## Decision

- `urbforge/urbex` stays the **docs/spec repo**: architecture, ADRs, the
  manifest spec and its JSON Schema, roadmap.
- `urbforge/urbex-cli` is a **new, separate repo** holding the Go
  implementation of the `urbex` CLI (Cobra-based, module
  `github.com/urbforge/urbex-cli`).
- The manifest JSON Schema is **vendored** (copied) into
  `urbex-cli/internal/manifest/schema/urbex.schema.json` and embedded
  into the binary via `go:embed`, kept in sync with
  `urbforge/urbex/schemas/urbex.schema.json` **manually** for now.

## Rationale

- Keeps a stable, reviewable source of truth (docs + ADRs + schema)
  decoupled from fast-moving implementation code and its own release
  cadence, issue tracker noise, and language-specific tooling
  (go.mod, CI, etc.).
- Matches a common, easy-to-explain pattern (spec repo + implementation
  repo) that other future components (e.g. Terraform modules, Ansible
  roles, if they end up in their own repos) can follow consistently.
- Embedding a vendored schema copy into the CLI binary means `urbex init`
  works fully offline, with no dependency on `urbforge/urbex` being
  reachable at runtime.

## Consequences

- Manual schema sync is a known drift risk: a schema change merged in
  `urbforge/urbex` does not automatically reach `urbex-cli`. Tracked as a
  follow-up in [`roadmap.md`](../roadmap.md) — likely direction is a CI
  check in `urbex-cli` that fails if its vendored copy diverges from the
  docs repo's schema, fetched at CI time.
- Contributions that touch both the spec and the CLI (e.g. adding a new
  manifest field) require coordinated PRs across two repos rather than a
  single commit.
- `urbex-cli`'s own README points back to `urbforge/urbex` for
  architecture/ADR context rather than duplicating it.
