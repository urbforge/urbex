# ADR-0010: Staging → production promotion via push and Git tags

## Status

Accepted

## Context

A flow is needed to move a release from staging to production. Options
evaluated: fully manual via an Urbex command, fully automatic on push,
automatic on staging with an explicit approval step for prod (without
using Git tags as the mechanism).

## Decision

- **Push to the main branch** of the app repo → **automatic deploy to
  staging** (Komodo detects the new commit and updates the staging LXC).
- **Git tag or release** on the app repo → Komodo applies the **redeploy
  to the production LXC** with that specific version.

## Rationale

A flow familiar to anyone already working with Git (branch = work in
progress, tag/release = stable version), requires no extra command to
remember to run in order to promote, and integrates naturally with the
polling/webhook mechanism already planned for Komodo.

## Consequences

- The app repo must follow a tagging convention recognized by Urbex (e.g.
  semver `vX.Y.Z`), to be clearly documented for the LLMs generating
  releases.
- Komodo must be configured to watch branches and tags separately for
  different environments on the same repo.
- An `urbex promote` command remains useful as a shortcut to create the
  tag and trigger the promotion in one step, but the underlying mechanism
  is always Git-based (no "silent" deploy outside of Git).
