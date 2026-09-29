# ADR-0018: Images built by Komodo, pushed to Gitea's container registry

## Status

Accepted

## Context

`urbex apply`/`deploy` currently render each service's
`docker-compose.yml` with a placeholder image reference
(`<project>/<service>:<env>-latest`): nothing builds or pushes a real
image. This is the biggest gap between "an LXC exists" and "the promoted
code is running" (see [`status.md`](../status.md), P0.2).

Two choices are needed: **where images are built** and **which registry
they are pushed to**. The product backlog
([`urbforge/product-management`](https://github.com/urbforge/product-management),
`docs/features.md`) lists ghcr.io as the registry and ArgoCD / GitHub
Actions as CI/CD candidates. Those are treated as future provider
options, not as v1 targets: v1 keeps the self-hosted stack it already
provisions.

## Decision

- **Registry: Gitea's built-in container registry** (Gitea Packages,
  OCI-compatible, enabled by default). Urbex already runs Gitea
  ([ADR-0004](0004-gitops-gitea-komodo.md)), so no extra service is
  needed. Image references take the form
  `<gitea-host>/<owner>/<project>-<service>:<tag>`, where `<owner>` is
  the Gitea org/user that owns the app repo.
- **Build: Komodo.** Each project service gets a Komodo *Build* resource
  pointing at the app repo on Gitea, building either the service's own
  `Dockerfile` (`runtime: docker`) or a Urbex-provided Dockerfile per
  language runtime (`go`, `java`, `python`), and pushing to the Gitea
  registry with a Gitea account configured in Komodo.
- **Tags** follow the promotion flow
  ([ADR-0010](0010-promotion-flow.md)):
  - push to `main` → image tagged with the short commit SHA, deployed
    to **staging**;
  - Git tag `vX.Y.Z` → image tagged `vX.Y.Z`, deployed to
    **production**.
  Mutable tags (`latest`, `staging`) are never what a deployment
  references: the compose file always pins an immutable tag, so what is
  running can be read back from the GitOps repo.
- The CLI does **not** run `docker build`/`docker push` itself: building
  is Komodo's job, consistent with the GitOps model. The CLI's role is to
  create/update the Komodo Build resources and write the pinned image
  reference into the GitOps repo.

## Rationale

- Zero new services: registry and CI both run on LXCs Urbex already
  creates.
- Keeps the whole v1 loop self-hosted on Proxmox, the same way Git and
  reconciliation are.
- Komodo Builds already implement "clone repo at ref → build → push",
  so Urbex does not need its own build runner.

## Consequences

- **Priority order changes**: image build now depends on Komodo
  integration and on repos being on Gitea, so status.md P1.3 (push the
  GitOps repo to Gitea) and P1.4 (Komodo integration) move ahead of,
  or merge into, P0.2.
- `urbex bootstrap` must additionally: create a Gitea account/token for
  Komodo with `write:package` scope, register it as a registry account
  in Komodo, and install Komodo Periphery (plus Docker) on the LXC
  used as builder - the Komodo LXC itself in v1.
- Until ingress/TLS exists ([ADR-0005](0005-cloudflare-tunnel-ingress.md)),
  Gitea's registry is plain HTTP on the LAN: the Docker daemon on the
  builder and on every project LXC must list it in
  `insecure-registries`, configured by the Ansible `common` role. This
  goes away once Gitea is served over HTTPS.
- Project LXCs need pull credentials for the registry (a read-only Gitea
  token), distributed by Ansible.
- Per-runtime Dockerfiles for `go`, `java`, `python` become Urbex
  assets, embedded in the CLI like the other platform assets
  ([ADR-0017](0017-embedded-base-infra-assets.md)).

## Future evolutions

Registry and CI/CD become pluggable providers, alongside the Git server
(see [`roadmap.md`](../roadmap.md)):

- **Registry**: ghcr.io, paired with GitHub as Git server.
- **CI/CD**: GitHub Actions, ArgoCD, as alternatives to Komodo.
