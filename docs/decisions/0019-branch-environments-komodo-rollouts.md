# ADR-0019: One branch per environment, built and rolled out by Komodo

## Status

Accepted. Supersedes [ADR-0010](0010-promotion-flow.md) (push → staging,
tag → prod) and the "Tags" and rollout parts of
[ADR-0018](0018-image-build-komodo-gitea-registry.md).

## Context

ADR-0018 had Komodo build images, but the rollout was still Ansible run
from the operator's machine, and ADR-0010's triggers (push to `main` →
staging, Git tag → prod) were never wired up. The requirement is now
explicit: **Komodo builds and deploys automatically when a pull request
is merged** - into `staging` for the staging environment, into `main`
for production.

## Decision

- **The app repo lives on Gitea** (`<org>/<project>`), the v1 Git
  provider. Pull requests are opened and merged there.
- **One long-lived branch per environment**: `staging` → staging,
  `main` → prod. Any push to the branch - in practice, merging a PR -
  deploys that environment. Promoting to production is a PR from
  `staging` into `main`.
- **Komodo owns build and rollout.** For each project and environment,
  Urbex maintains in Komodo:
  - a **Build** per service, `<project>-<service>-<env>`, tracking the
    environment's branch and pushing
    `<registry>/<org>/<project>-<service>:<version>-<env>` to Gitea's
    registry (version auto-incremented by Komodo on every build, plus a
    `<commit>-<env>` tag);
  - a **Deployment** per service, `<project>-<service>-<env>`, running
    that Build's image on the service's LXC with the port, environment
    variables, and healthcheck from `urbex.yaml`;
  - a **Procedure** `<project>-<env>` that runs every Build of the
    environment, then every Deployment.
- **A Gitea webhook per environment** (push events, filtered to the
  branch) calls the Procedure's listener on Komodo, signed with Komodo's
  webhook secret. Komodo's GitHub-style listener handles Gitea as-is.
- **Every project LXC runs Komodo Periphery**, registered in Komodo as a
  Server named after the LXC (`<project>-<service>-<env>`) through an
  onboarding key created by `urbex bootstrap`. Ansible's job on a project
  LXC shrinks to Docker + Periphery; it no longer knows about the app.
- **CLI roles:**
  - `urbex apply <env>`: infrastructure, Periphery, the Komodo resources
    and the webhook, then a first run of the Procedure. If the
    environment's branch doesn't exist on Gitea yet, it is created from
    the local HEAD.
  - `urbex deploy <env>`: re-syncs the Komodo resources from `urbex.yaml`
    and runs the Procedure - the manual trigger, and how manifest changes
    (env vars, port, healthcheck) reach Komodo.
  - `urbex promote`: opens (or finds) the `staging` → `main` pull request
    on Gitea; `--merge` merges it, which deploys prod.
  - `urbex destroy <env>`: removes the webhook and the Komodo resources
    before destroying the LXCs.

## Rationale

- A Procedure, rather than Komodo's "redeploy on build" flag, because
  that flag only redeploys containers that are currently running: a
  service that crashed would never pick up the fix that was just merged.
  A Procedure always deploys, and needs one webhook per environment
  instead of one per service.
- Branch-per-environment makes "what is deployed" readable in Git (the
  branch head) and makes promotion a reviewable pull request.
- Komodo already has every piece (Builds, Deployments, Procedures,
  webhooks, agents); Urbex only declares them.

## Consequences

- **Production images are rebuilt from `main`**, not reused from
  staging: a merge commit is a different commit. "Build once, deploy
  everywhere" (ADR-0018) is traded for the simpler branch model; the
  per-commit tags keep every image traceable to its source.
- Git tags are no longer the production trigger; `urbex promote` no
  longer creates them.
- Deploying no longer needs the operator's machine, SSH access, or the
  CLI at all - only a merge.
- **Manifest changes are not applied by a merge.** Komodo resources
  mirror `urbex.yaml` as of the last `urbex apply`/`deploy`; changing a
  port, an env var, or resources still needs one of those commands, run
  from a checkout of the environment's branch.
- The rendered Komodo resources are written to the GitOps repo
  (`komodo/<project>/<env>.json`) on every apply/deploy, as the record
  of what Urbex asked Komodo to run.
- Komodo Core must be reachable from Gitea (webhooks) and from every
  project LXC (Periphery connects out to it). Gitea must allow webhooks
  to private addresses (`webhook.ALLOWED_HOST_LIST`).
- Komodo only treats an image's first path segment as a registry if it
  contains a dot, so the registry must be addressed by IP or by a dotted
  hostname - which the static-IP allocation already guarantees.
- A Deployment healthcheck is a `docker run --health-cmd`, so images
  must still ship `wget`.
- When an LXC is recreated (destroyed and re-applied, or replaced by
  Terraform), its Periphery comes back with a new identity under the
  same Server name. `urbex apply`/`deploy` accept the new key - only a
  holder of the onboarding key can present one - and say so. For the
  same reason `destroy` deletes a Server only after its LXC is gone.
- Version numbers belong to the Build: destroying and re-applying an
  environment restarts them at 0.0.1, overwriting the old tags. The
  `<commit>-<env>` tag is what identifies an image unambiguously.
