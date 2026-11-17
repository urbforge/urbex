# ADR-0034: Forgejo LTS is the platform's forge

## Status

Accepted. Changes [ADR-0004](0004-gitops-gitea-komodo.md) and
[ADR-0018](0018-image-build-komodo-gitea-registry.md): where they say
Gitea, the forge is now Forgejo; everything else they decide stands.

## Context

The platform's Git forge holds the GitOps repo, the projects' repos and
their container images (ADR-0004, ADR-0018). Until urbex 0.1.0 it was
`gitea/gitea:1.24`, not pinned by digest, and out of support: Gitea
supports its last two majors (28 and 27). It had to move before the
first testers install a platform.

Two candidates, both Apache/MIT-licensed and close to each other
(Forgejo is a hard fork of Gitea):

- **Gitea 28**: maintained, and adds bot accounts and an audit log,
  useful for the operators' work of E7 (after M5).
- **Forgejo 15**: a long-term-support release, supported until
  15 July 2027, with a stable release every quarter besides.

Homelab users update rarely: 47% by hand (selfh.st survey 2026). Among
self-hosters Forgejo grew to 27% (15% in 2025), Gitea fell to 17% (21%)
(urbforge/redemptor#49).

Urbex uses little of the forge (`internal/forge` in urbex-cli): the REST
API `/api/v1` (version, tokens with basic auth, orgs, repos, branches,
commits, tags, webhooks, container packages), push webhooks to Komodo
(type `gitea`, signed with `X-Hub-Signature-256`, which Forgejo sends
too), and the container registry. Not Actions, OAuth or mirrors.

A spike (urbforge/urbex-cli#112) swapped the image for
`codeberg.org/forgejo/forgejo:15.0.11`, pinned by digest, with the
settings as `FORGEJO__*`, and nothing else:

- urbex-cli's end-to-end test passed whole (24 steps: bootstrap, apply
  with webhook, build, registry and deploy, release, promote, status,
  volumes, linked applications, the reconciler, destroy, teardown), as
  it does with Gitea 1.24. The forge container's memory over the run:
  median 106 MiB, peak 196 MiB with Forgejo; 101 and 181 MiB with Gitea.
- On the test Proxmox node, a platform bootstrapped from scratch with
  Forgejo, then a project in staging and production. The forge LXC:
  150-160 MiB for the forge, about 300 MiB for the whole LXC (Gitea:
  124 and 316 MiB on a platform weeks old), 1.8 GB of disk (2.2 GB).

## Decision

- **Forgejo LTS is the platform's forge**: today
  `codeberg.org/forgejo/forgejo:15.0.11`, pinned by digest, configured
  with `FORGEJO__*` variables.
- **Following its releases**: each urbex release pins the newest patch
  of the current LTS (15.0.x) by digest; an urbex release moves to the
  next LTS before the current one reaches its end of support. Forgejo's
  quarterly releases in between are not followed.
- **Names**: in the code, the messages and the docs, the generic word
  is *forge* (*Forgejo* when the product is meant): urbex-cli's package
  `internal/forge`; the credentials `forgeAdminPassword` and
  `forgeToken` (`URBEX_FORGE_*`); the platform config's `git.forgeUrl`.
  The old names - `giteaAdminPassword`, `giteaToken`, `URBEX_GITEA_*`,
  `git.giteaUrl` - are still read, so a workspace written by 0.1.0
  works unchanged; urbex writes the new ones.
- **What keeps its name**: what a platform already has on Proxmox and
  Komodo - the LXC `urbex-gitea`, the Stack `urbex-gitea`, its volume
  `gitea-data`, the service `gitea` in the catalog and in Grafana's
  labels, the webhook type `gitea`, and Komodo's variables
  `URBEX_GITEA_URL`, `URBEX_GITEA_USER` and `URBEX_GITEA_TOKEN`, which
  the Actions installed on a platform read. Renaming them would replace the LXC
  of every existing platform; a migration may do it later.
- **Gitea 28 is the fallback**: the API Urbex uses is the same, so going
  back is the image and the variables, as the spike was.

## Rationale

- A support window measured in years fits users who update twice a
  year; Gitea's two-major window doesn't.
- Forgejo is what more self-hosters now run, and it is a community
  project under Codeberg e.V.
- The spike changed no code: the risk of the switch is low, and so is
  the cost of going back.
- Generic names in the code keep the next change of forge, if any, as
  small as this one.

## Consequences

- We give up, for now, Gitea 28's bot accounts and audit log. E7 looks
  at what Forgejo offers when it starts.
- **A platform installed with urbex 0.1.0 runs Gitea 1.24 and isn't
  migrated in place**: Forgejo imports Gitea's database only up to Gitea
  1.22. Bootstrap the platform again, or push its repos to the new
  forge (see the known limitations).
- The image comes from codeberg.org instead of Docker Hub.
- Upgrading the forge is an urbex release; between releases nothing
  changes on a platform.
