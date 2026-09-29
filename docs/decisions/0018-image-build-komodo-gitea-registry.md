# ADR-0018: Images built by Komodo, pushed to Gitea's container registry

## Status

Accepted - implemented in `urbforge/urbex-cli` (image build; rollouts
still run through Ansible, see Consequences).

## Context

`urbex apply`/`deploy` rendered each service's `docker-compose.yml` with
a placeholder image reference (`<project>/<service>:<env>-latest`):
nothing built or pushed a real image. This was the biggest gap between
"an LXC exists" and "the promoted code is running" (see
[`status.md`](../status.md), P0.2).

Two choices were needed: **where images are built** and **which
registry they are pushed to**. The product backlog
([`urbforge/product-management`](https://github.com/urbforge/product-management),
`docs/features.md`) lists ghcr.io as the registry and ArgoCD / GitHub
Actions as CI/CD candidates. Those are treated as future provider
options, not as v1 targets: v1 keeps the self-hosted stack it already
provisions.

## Decision

- **Registry: Gitea's built-in container registry** (Gitea Packages,
  OCI-compatible). Urbex already runs Gitea
  ([ADR-0004](0004-gitops-gitea-komodo.md)), so no extra service is
  needed. Image references take the form
  `<gitea-host:port>/<org>/<project>-<service>:<tag>`, where `<org>` is
  `git.org` from `urbex.platform.yaml` (default `urbex`).
- **Build: Komodo.** Each project service gets a Komodo *Build*
  resource (`<project>-<service>`) that clones the app's repo from Gitea
  at an exact commit and builds on the **Komodo LXC itself**: its compose
  runs a Periphery agent next to Core, registered on first start as
  server and builder `urbex-komodo` (`KOMODO_FIRST_SERVER_NAME`).
  - `runtime: docker`: the service's own Dockerfile, with its directory
    as build context.
  - `runtime: go|java|python`: a Urbex Dockerfile, embedded in the CLI
    ([ADR-0017](0017-embedded-base-infra-assets.md)) and written into
    the clone as `Dockerfile.urbex` by the Build's pre-build command
    (Komodo ignores UI-defined Dockerfile contents when a repo is
    attached). Conventions: Go builds `./cmd/<service>` or the module
    root, Python runs `main.py` after installing `requirements.txt`,
    Java runs the jar built by the Gradle wrapper or Maven. Every
    service listens on `$PORT`.
- **App repos on Gitea.** Before building, the CLI pushes the app
  repo's HEAD to `<org>/<project>` on Gitea (branch `main`). The
  developer's own remote (GitHub, etc.) stays their canonical repo;
  Gitea holds what Urbex builds and deploys.
- **Tags: one immutable image per commit**, tagged with the commit's
  short SHA (Komodo's commit tag). Staging and production run the same
  image: `urbex promote` tags `vX.Y.Z` in Git (per
  [ADR-0010](0010-promotion-flow.md)) and deploys the same commit to
  prod, **reusing** the image built for staging instead of rebuilding
  it - prod runs exactly what was tested. Mutable tags (`latest`) are
  never pushed or referenced.
- **The deployed image is recorded in the GitOps repo**: the rendered
  Ansible inventory pins each service's image, and every
  apply/deploy/promote commits and pushes the GitOps repo to Gitea.
- The CLI never runs `docker build`/`docker push` itself: it creates or
  updates the Komodo Builds, runs them, and waits for the result.

## Rationale

- Zero new services: registry and CI both run on LXCs Urbex already
  creates.
- Keeps the whole v1 loop self-hosted on Proxmox, the same way Git and
  reconciliation are.
- Komodo Builds already implement "clone repo at commit → build →
  push", so Urbex does not need its own build runner.
- Build once, deploy everywhere: tagging by commit makes builds
  idempotent (an existing tag is reused) and makes promotion and
  rollback a redeploy of an existing image rather than a rebuild.

## Consequences

- `urbex bootstrap` additionally generates the Gitea/Komodo admin
  passwords and Komodo's internal secrets, creates two Gitea tokens (one
  read/write for the CLI and Komodo, one read-only for pulls), a Komodo
  API key, and Komodo's git provider and registry accounts for Gitea,
  all stored in `~/.urbex/credentials.yaml` (see
  [`credentials.md`](../credentials.md)); it also pushes the GitOps
  repo to Gitea.
- Until ingress/TLS exists ([ADR-0005](0005-cloudflare-tunnel-ingress.md)),
  Gitea (git and registry) is plain HTTP on the LAN: the Ansible
  `common` role lists it in Docker's `insecure-registries` on every LXC,
  and Komodo's accounts use `http`. This goes away once Gitea is served
  over HTTPS.
- Project LXCs log in to the registry with the read-only token, passed
  through Ansible's environment.
- **Rollouts are not yet Komodo-driven**: after the build, `urbex
  apply`/`deploy`/`promote` still roll the pinned image out with
  Ansible from the operator's machine. Push-triggered staging deploys
  and tag-triggered prod deploys ([ADR-0010](0010-promotion-flow.md))
  need Komodo to own the rollout too (Periphery on every project LXC,
  Stacks per service) - the next step of
  [ADR-0004](0004-gitops-gitea-komodo.md).
- Monorepos are supported per service (`./cmd/<service>` for Go, a
  per-service Dockerfile for `runtime: docker`); other language
  runtimes build from the repo root.

## Future evolutions

Registry and CI/CD become pluggable providers, alongside the Git server
(see [`roadmap.md`](../roadmap.md)):

- **Registry**: ghcr.io, paired with GitHub as Git server.
- **CI/CD**: GitHub Actions, ArgoCD, as alternatives to Komodo.
