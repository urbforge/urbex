# Project status

A snapshot of what Urbex actually does today versus the v1 vision in
[`architecture.md`](architecture.md), and a prioritized list of what to
build next. Where [`guide.md`](guide.md) documents gaps from the
perspective of *using* the CLI, this document takes stock of the whole
project at once, for planning purposes. Update it whenever a priority
item below gets implemented, or a new gap is discovered.

As of this writing: 20 ADRs, 10 `urbex` CLI commands, 111 unit tests
across 17 Go packages, and an end-to-end test (`e2e/run.sh`) in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli) that runs
the real binary through a whole project lifecycle against Debian 13
machines standing in for LXCs, with only Terraform and the Proxmox API
stubbed. It has not yet run against a real Proxmox server - see
[What has been validated](#what-has-been-validated) below.

## Supported today

| Area | State |
|---|---|
| App manifest (`urbex.yaml`) | Formal JSON Schema, typed Go decoding, `urbex init` scaffolds and validates |
| Platform config (`urbex.platform.yaml`) | Scaffolded and validated by `urbex bootstrap` |
| Credentials | Env vars, falling back to `~/.urbex/credentials.yaml`; never written to the GitOps repo |
| Base-service provisioning | Terraform (5 fixed Debian 13 LXCs: Gitea, Komodo, Technitium, Keycloak, observability; optional resource pool) + Ansible (Docker + each service's compose); idempotent, with a pre-flight check that aborts instead of adopting/duplicating an untracked container |
| Platform setup (`urbex bootstrap`) | Generates admin passwords/secrets into `~/.urbex/credentials.yaml`; creates a Gitea token, org, and `gitops` repo; a Komodo API key, the onboarding key project LXCs join with, and Komodo's Gitea git/registry accounts; the release Action, the GitOps Procedure and its webhook; `.sops.yaml`; pushes the GitOps repo to Gitea |
| Project-service provisioning | Generic `for_each` Terraform module (any number of manifest services); static VMID/IP allocation shared across all projects in one GitOps repo, so they never collide; Docker + Komodo Periphery + sops on each LXC |
| **Releases** | A `vX.Y.Z` tag on a project's `main` (pushed by hand or by `urbex release`) makes Komodo build every service once and push `<project>-<service>:X.Y.Z` to Gitea's registry ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md), [ADR-0020](decisions/0020-trunk-releases-gitops-environments.md)) |
| **Environments in the GitOps repo** | `environments/<env>/<project>/<service>/` holds the compose file, `version.env`, `config.env`, and `secrets.sops.env`; Komodo deploys each folder as a Stack on the service's LXC whenever it changes (webhook), and reconciles every 15 minutes |
| **Secrets** | SOPS + age, per service and environment, in the GitOps repo; decrypted only on the LXC, at deploy time; `urbex secret set/unset/list` |
| `urbex apply` | Terraform, Ansible, the project's Builds and release webhook, the environment's folder and Stacks; redeploys an environment that already has a version |
| `urbex release` | Tags the next release on `main` and waits for its images |
| `urbex deploy` | Sets an environment's version in the GitOps repo (latest release, or `--version`, which is also how to roll back), pushes, waits for Komodo to run it |
| `urbex promote` | Sets prod's versions to staging's: prod runs the very images staging ran |
| `urbex destroy` | Takes the environment's Stacks down, removes its folder, `terraform destroy`, clears the allocation ledger; the project's Builds go with its last environment |
| `urbex status` | Proxmox container presence, allocation ledger and, per service, the version the GitOps repo asks for against what Komodo runs |
| Transactional email | Manifest field only (`email.provider: brevo`); no code path uses it yet - see [Not supported yet](#not-supported-yet) |

## Not supported yet

| Area | Gap | ADR(s) |
|---|---|---|
| Continuous deployment to staging | Nothing is deployed by a push to `main`; staging runs a release only once its version is set | [0020](decisions/0020-trunk-releases-gitops-environments.md) |
| Promotion by pull request | `urbex promote` commits to the GitOps repo directly; a PR-gated production folder is a Gitea setting Urbex doesn't manage | [0020](decisions/0020-trunk-releases-gitops-environments.md) |
| Pre-releases | Only `vX.Y.Z` tags are releases; `-rc.1` and the like are ignored | [0020](decisions/0020-trunk-releases-gitops-environments.md) |
| Pinned base-service images | Technitium, Prometheus, Loki, and Grafana still use `latest` | - |
| DNS registration | Technitium LXC exists; nothing registers a record in it | [0007](decisions/0007-technitium-configurable-domain.md) |
| Ingress (Cloudflare Tunnel) | Services are reachable only via their private LXC IP; Gitea and its registry are plain HTTP | [0005](decisions/0005-cloudflare-tunnel-ingress.md) |
| Keycloak realm/client provisioning | Keycloak LXC exists; nothing creates the `platform` realm, per-project realms, or app OIDC clients/roles | [0008](decisions/0008-keycloak-scope.md), [0014](decisions/0014-keycloak-realm-per-project.md) |
| Terraform state encryption | State is plain JSON in the (private) GitOps repo, not SOPS-encrypted as designed | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Observability wiring | Prometheus/Grafana/Loki LXC exists; no project service is actually scraped or ships logs to it, despite `observability.metrics`/`logs` in the manifest | - |
| Frontend deploy | `frontend` in the manifest is documentation only; no command builds/deploys to Cloudflare Pages or Firebase | - |
| Fleet-wide status | `urbex status` is scoped to one project+environment at a time; Komodo's UI is the cross-project view | - |
| Cross-machine concurrency guard | Two machines applying against copies of the same GitOps repo can silently conflict | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Cloud providers beyond Proxmox (Azure, GCP, AWS) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Git servers beyond Gitea (GitHub, GitLab) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Vault secrets backend | Not started - v2+ by design | [0011](decisions/0011-secrets-sops-age.md) |

## What has been validated

`e2e/run.sh` in `urbex-cli` runs the **real `urbex` binary** against
Debian 13 systemd machines reachable over SSH at the static IPs Urbex
allocates - the same thing an LXC is to Ansible - and checks every step.
Only `terraform` (a stub) and the Proxmox API (a stub listing the
machines) are faked; Ansible, Docker, Gitea, Komodo, sops, and the other
base services are real. It covers:

1. `urbex bootstrap`: all five base-service roles, the platform setup,
   the GitOps repo push; a second run changes nothing.
2. `urbex apply staging`: an environment that exists and is empty.
3. `urbex release` and `urbex deploy staging`: a tag, built by Komodo,
   deployed from the GitOps repo.
4. Trunk development: a push to `main` deploys nothing; a tag pushed by
   hand is a release.
5. `urbex apply prod` and `urbex promote`: prod runs staging's image,
   nothing is rebuilt.
6. Secrets: set, delivered to the service, absent in plaintext from the
   repo, unset.
7. Configuration edited by hand in the GitOps repo and pushed with
   plain git; an unrelated commit restarts nothing.
8. Rollback by deploying an older version; a version that was never
   built is refused.
9. `urbex destroy staging` (prod untouched), then `urbex apply` onto a
   brand-new machine.

Separately, `terraform validate` passes on the base and project modules
with the real `bpg/proxmox` provider, and the `python` and `java`
runtime Dockerfiles were built and run on their own.

**Not yet validated:** `terraform apply` against a real Proxmox - LXC
creation from the Debian 13 template, pool placement, and the `keyctl`
feature with a non-root token (see [`credentials.md`](credentials.md)).

## Priorities

Roughly in the order that makes each subsequent item worth doing.

### P0 - prove the foundation

1. **Validate against a real Proxmox.** Run `urbex bootstrap` and
   `urbex apply` against the test node: the only layer still unproven
   is Terraform creating the LXCs (see
   [What has been validated](#what-has-been-validated)). Expect the
   `keyctl` feature to need a root-set workaround with a pool-scoped
   token.
2. ~~**Image build & push.**~~ Done: Komodo builds, Gitea's registry
   stores ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)).

### P1 - complete the v1 promise (in dependency order)

3. ~~**Push the GitOps repo to Gitea.**~~ Done.
4. ~~**Komodo-driven rollouts, from the GitOps repo.**~~ Done
   ([ADR-0020](decisions/0020-trunk-releases-gitops-environments.md)).
5. **DNS registration in Technitium.** Removes the "find the IP" step
   from every other workflow.
6. **Cloudflare Tunnel ingress**, once there's a domain/DNS story to
   attach it to.

### P2 - identity, secrets, observability

7. **Keycloak realm/client provisioning** - unblocks `auth.keycloak`/
   `auth.roles` in the manifest, currently inert.
8. ~~**Secret encryption (SOPS+age)**~~ Done for application secrets
   ([ADR-0020](decisions/0020-trunk-releases-gitops-environments.md));
   Terraform state is still stored unencrypted.
9. **Observability wiring** - connect project services to
   Prometheus/Loki so `observability.metrics`/`logs` in the manifest do
   something.

### P3 - operability polish

10. **Continuous deployment to staging** (bump staging's version for
    every commit or release on `main`) and **promotion by pull request**
    on the GitOps repo.
11. **Fleet-wide status** across projects/environments.
12. **Cross-machine concurrency guard** on the shared Terraform state
    and allocation ledger.

### P4 - v2+ scope (deliberately deferred)

13. Cloud providers beyond Proxmox, Git servers beyond Gitea (and
    ghcr.io as registry), CI/CD beyond Komodo (GitHub Actions, ArgoCD),
    Kubernetes as orchestrator, Vault -
    already scoped for later in [`roadmap.md`](roadmap.md); no urgency
    while v1 itself is incomplete.
