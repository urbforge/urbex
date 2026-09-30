# Project status

A snapshot of what Urbex actually does today versus the v1 vision in
[`architecture.md`](architecture.md), and a prioritized list of what to
build next. Where [`guide.md`](guide.md) documents gaps from the
perspective of *using* the CLI, this document takes stock of the whole
project at once, for planning purposes. Update it whenever a priority
item below gets implemented, or a new gap is discovered.

As of this writing: 19 ADRs, all 8 `urbex` CLI subcommands implemented,
89 unit tests across 14 Go packages in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli). The real
`urbex` binary has been run end to end - bootstrap through
merge-triggered deploys - against Debian 13 machines standing in for
LXCs, with only Terraform and the Proxmox API faked. It has not yet run
against a real Proxmox server - see
[What has been validated](#what-has-been-validated) below.

## Supported today

| Area | State |
|---|---|
| App manifest (`urbex.yaml`) | Formal JSON Schema, typed Go decoding, `urbex init` scaffolds and validates |
| Platform config (`urbex.platform.yaml`) | Scaffolded and validated by `urbex bootstrap` |
| Credentials | Env vars, falling back to `~/.urbex/credentials.yaml`; never written to the GitOps repo |
| Base-service provisioning | Terraform (5 fixed Debian 13 LXCs: Gitea, Komodo, Technitium, Keycloak, observability; optional resource pool) + Ansible (Docker + each service's compose); idempotent, with a pre-flight check that aborts instead of adopting/duplicating an untracked container |
| Platform setup (`urbex bootstrap`) | Generates admin passwords/secrets into `~/.urbex/credentials.yaml`; creates a Gitea token, org, and `gitops` repo; a Komodo API key, the onboarding key project LXCs join with, and Komodo's Gitea git/registry accounts; pushes the GitOps repo to Gitea |
| Image build & push | Komodo builds each service from its environment's branch of the app repo on Gitea (own Dockerfile, or Urbex's for go/java/python) and pushes it to Gitea's registry as `<version>-<env>` ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)) |
| **Deploy on merge** | Merging into `staging` deploys staging, merging into `main` deploys prod: a Gitea webhook triggers a Komodo Procedure that builds every service of the environment and rolls it out on its LXC through the Periphery agent ([ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md)) |
| `urbex apply` | Terraform, Docker + Periphery on the LXCs (Ansible), then the environment's Komodo Builds/Deployments/Procedure and Gitea webhook, a first deploy, and a push of the GitOps repo (which records the declared Komodo resources) |
| Project-service provisioning | Generic `for_each` Terraform module (any number of manifest services); static VMID/IP allocation shared across all projects in one GitOps repo, so they never collide |
| `urbex deploy` | Re-syncs the environment's Komodo resources from `urbex.yaml` and has Komodo build and deploy its branch now - the manual trigger, and how manifest changes reach Komodo |
| `urbex promote` | Opens (or finds) the `staging` → `main` pull request on Gitea; `--merge` merges it, deploying prod. Refuses when there is nothing to promote |
| `urbex destroy` | Removes the environment's webhook and Komodo resources, `terraform destroy`, then clears the allocation-ledger entries and syncs the GitOps repo |
| `urbex status` | Cross-references Proxmox container presence with the allocation ledger and, per service, the container state and image Komodo reports |
| Transactional email | Manifest field only (`email.provider: brevo`); no code path uses it yet - see [Not supported yet](#not-supported-yet) |

## Not supported yet

| Area | Gap | ADR(s) |
|---|---|---|
| Manifest changes on merge | A merge deploys code, but `urbex.yaml` changes (env vars, port, resources, new services) only take effect on `urbex apply`/`deploy` | [0019](decisions/0019-branch-environments-komodo-rollouts.md) |
| Komodo resources as GitOps | Urbex declares Komodo resources through its API and records them in the GitOps repo; Komodo doesn't reconcile from that repo (no ResourceSync) | [0004](decisions/0004-gitops-gitea-komodo.md) |
| Pinned base-service images | Technitium, Prometheus, Loki, and Grafana still use `latest` | - |
| DNS registration | Technitium LXC exists; nothing registers a record in it | [0007](decisions/0007-technitium-configurable-domain.md) |
| Ingress (Cloudflare Tunnel) | Services are reachable only via their private LXC IP | [0005](decisions/0005-cloudflare-tunnel-ingress.md) |
| Keycloak realm/client provisioning | Keycloak LXC exists; nothing creates the `platform` realm, per-project realms, or app OIDC clients/roles | [0008](decisions/0008-keycloak-scope.md), [0014](decisions/0014-keycloak-realm-per-project.md) |
| Secret encryption (SOPS+age) | `urbex.yaml`'s `env` only carries non-secret values; there is no encrypted-secret mechanism wired into the CLI despite `URBEX_AGE_KEY` being a required credential | [0011](decisions/0011-secrets-sops-age.md) |
| Terraform state encryption | State is plain JSON on disk, not SOPS-encrypted as designed | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Observability wiring | Prometheus/Grafana/Loki LXC exists; no project service is actually scraped or ships logs to it, despite `observability.metrics`/`logs` in the manifest | - |
| Frontend deploy | `frontend` in the manifest is documentation only; no command builds/deploys to Cloudflare Pages or Firebase | - |
| Rollback | `urbex status` shows the running image, but there is no `urbex rollback`: revert the commit on the branch, or pin an older version on the Deployment in Komodo | [0019](decisions/0019-branch-environments-komodo-rollouts.md) |
| Fleet-wide status | `urbex status` is scoped to one project+environment at a time; no cross-project view | - |
| Cross-machine concurrency guard | Two machines applying against copies of the same GitOps repo can silently conflict | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Cloud providers beyond Proxmox (Azure, GCP, AWS) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Git servers beyond Gitea (GitHub, GitLab) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Vault secrets backend | Not started - v2+ by design | [0011](decisions/0011-secrets-sops-age.md) |

## What has been validated

Beyond unit tests (fakes for Proxmox, Gitea, Komodo, and command
execution), the **real `urbex` binary** ran this whole sequence against
Debian 13 systemd machines reachable over SSH at the static IPs Urbex
allocates - the same thing an LXC is to Ansible. Only `terraform` (a
stub) and the Proxmox API (a stub listing the machines) were faked.

1. `urbex bootstrap`: all five base-service roles (Gitea, Komodo with
   Postgres/FerretDB/Core/Periphery, Technitium, Keycloak,
   Prometheus/Loki/Grafana), then the platform setup and the GitOps repo
   push. A second run changes nothing.
2. `urbex apply staging` and `urbex apply prod`: Docker and Periphery on
   the project machines, Komodo resources, webhooks, first deploy - the
   service answers, healthy.
3. A pull request merged into `staging` on Gitea: the new version is
   live about 10 seconds later, with no command run.
4. `urbex promote --merge`: opens and merges `staging` → `main`; prod
   serves the new version about 10 seconds later.
5. `urbex deploy staging` after changing an env var in `urbex.yaml`;
   `urbex status`; `urbex destroy staging` (prod untouched); `urbex
   apply staging` again on a recreated machine.

Separately, `terraform validate` passes on the base and project modules
with the real `bpg/proxmox` provider, and the `python` and `java`
runtime Dockerfiles were built and run on their own.

Running things for real found and fixed: a missing `required_providers`
in the LXC module, a Komodo compose without its database, Prometheus
unable to read its config, roles that never restarted a service after a
failed run, Ansible conditionals and modules rejected by current
ansible-core, and a recreated machine unable to rejoin Komodo.

**Not yet validated:** `terraform apply` against a real Proxmox - LXC
creation from the Debian 13 template, pool placement, and the `keyctl`
feature with a non-root token (see [`credentials.md`](credentials.md)).

## Priorities

Roughly in the order that makes each subsequent item worth doing - no
point wiring DNS to a service that was never really deployed because its
image doesn't exist.

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

3. ~~**Push the GitOps repo to Gitea.**~~ Done: bootstrap and every
   apply/deploy/destroy push it.
4. ~~**Komodo-driven rollouts.**~~ Done: merging into `staging`/`main`
   builds and deploys through Komodo
   ([ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md)).
5. **DNS registration in Technitium.** Removes the "find the IP in
   `state/allocations.json`" step from every other workflow.
6. **Cloudflare Tunnel ingress**, once there's a domain/DNS story to
   attach it to.

### P2 - identity, secrets, observability

7. **Keycloak realm/client provisioning** - unblocks `auth.keycloak`/
   `auth.roles` in the manifest, currently inert.
8. **Secret encryption (SOPS+age)** - real secrets (DB passwords, API
   keys), not just the non-sensitive `env` block that works today.
9. **Observability wiring** - connect project services to
   Prometheus/Loki so `observability.metrics`/`logs` in the manifest do
   something.

### P3 - operability polish

10. **`urbex rollback`**, and applying `urbex.yaml` changes on merge
    (Komodo ResourceSync from the GitOps repo).
11. **Fleet-wide status** across projects/environments.
12. **Cross-machine concurrency guard** on the shared Terraform state
    and allocation ledger.

### P4 - v2+ scope (deliberately deferred)

13. Cloud providers beyond Proxmox, Git servers beyond Gitea (and
    ghcr.io as registry), CI/CD beyond Komodo (GitHub Actions, ArgoCD),
    Kubernetes as orchestrator, Vault -
    already scoped for later in [`roadmap.md`](roadmap.md); no urgency
    while v1 itself is incomplete.
