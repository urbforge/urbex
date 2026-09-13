# ADR-0002: The app manifest lives in the app repo

## Status

Accepted

## Context

Urbex needs to know what an app requires (frontend type, services,
resources, environment variables) in order to generate the correct
infrastructure. Options evaluated: a manifest file in the app repo, an
interactive CLI wizard, or both.

## Decision

Every app declares its own needs in a `urbex.yaml` file **in the app's own
repo** (not in the GitOps repo). This file is generated and maintained by
the same LLM agent (Claude Code, Codex) that writes the app's code, not
through an interactive wizard.

## Rationale

- An LLM working in automation cannot answer an interactive wizard: a
  declarative file can be generated/edited directly.
- A manifest versioned alongside the code keeps infrastructure and app in
  sync: a PR that adds a service can modify `urbex.yaml` in the same
  commit.
- Separation of concerns: the GitOps repo describes the actual state of
  the infrastructure *derived* from project manifests, rather than
  containing them.

## Consequences

- A clear, versioned schema for `urbex.yaml` is needed (see
  [`manifest-spec.md`](../manifest-spec.md)), with explicit validation
  (`urbex init` / `urbex plan` must reject malformed manifests with
  errors an LLM can understand).
- Urbex must be able to read a manifest from an external repo
  (clone/fetch) to compute the infrastructure plan, without requiring the
  manifest to already be in the GitOps repo.
- An interactive wizard remains a possible future extension for direct
  human use, not part of the primary v1 path.
