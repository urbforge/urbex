# ADR-0021: Staging follows main

## Status

Accepted. Extends [ADR-0020](0020-trunk-releases-gitops-environments.md),
replacing its "nothing is deployed by a push to `main`" consequence and
its build trigger (a build per release tag).

## Context

With ADR-0020, staging only moved when someone released and deployed. On
a trunk-based project the useful default is the opposite: every push to
`main` should be running on staging within minutes, so that what gets
released is what has already been seen working there. The GitOps repo
must stay the single source of truth for what runs where, and a release
must still be a tag.

## Decision

- **Every push to `main` is built.** The `urbex-release` Komodo Action,
  already called by the project repo's webhook on every push, builds the
  pushed commit: one image per service, tagged with the commit's short
  hash (`<project>-<service>:a1b2c3d`).
- **An environment follows `main` when its version file says so.**
  `version.env` gets a second line, `TRACK=main`. After a build of
  `main`, the Action rewrites `VERSION` in every version file that has
  it, in one commit to the GitOps repo (through Gitea's API), and asks
  Komodo to reconcile. The deploy is then the ordinary GitOps one.
- **Staging follows `main` by default, production never does.** `urbex
  apply staging` creates staging's version files with `TRACK=main` and
  builds `main`'s head right away; prod's start empty.
- **A release reuses the image `main` built.** Tagging `vX.Y.Z` makes
  the Action copy the commit's image manifest to the tag `X.Y.Z` in the
  registry - no rebuild. Only a commit `main` never built (a tag on an
  older commit) is built first.
- **`urbex release` releases what staging runs** by default: the commit
  in staging's version file, if staging follows `main`; otherwise
  `main`'s head; `--ref` picks anything else.
- **Production only runs releases.** `urbex promote` resolves the commit
  staging runs to the release tagged on it, and refuses an unreleased
  commit.
- **Pinning.** `urbex deploy <env> --version X` (a release or a commit)
  writes the version without `TRACK`, so `main` stops moving the
  environment; `urbex deploy <env> --follow-main` puts `TRACK` back and
  deploys `main`'s head. Editing the line by hand does the same.
- **The Action reaches Gitea** with Komodo variables that `urbex
  bootstrap` sets: `URBEX_GITEA_URL`, `URBEX_GITEA_USER`, `URBEX_ORG`,
  and `URBEX_GITEA_TOKEN` (a secret variable).

## Rationale

- `TRACK=main` keeps "what follows what" in the GitOps repo, next to the
  version it governs, visible and revertable like everything else.
- Retagging makes releases cheap and exact: the bytes promoted to
  production are the bytes staging ran, by construction.
- Releasing the commit staging runs, rather than whatever `main` is by
  then, removes the race between testing and tagging.

## Consequences

- The GitOps repo now has two writers besides people: `urbex` and the
  Action. The CLI pulls (rebasing its own commits) before changing it
  and before pushing; a person editing it by hand should do the same.
- Every push to `main` costs a build on the Komodo LXC, including pushes
  that only touch documentation.
- A version is either a release (`1.4.2`) or a commit (`a1b2c3d`);
  `urbex deploy --version` accepts both, prod is only ever promoted to
  releases.
- Builds of `main` can overlap. The Action waits for a busy Build, skips
  a commit whose image exists, and only moves environments to `main`'s
  current head, so pushes finishing out of order never move staging
  backwards.
- Staging's history in the GitOps repo is a commit per build of `main`
  (`urbex: <project> main@a1b2c3d to staging`).
