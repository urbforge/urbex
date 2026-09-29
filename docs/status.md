# Project status

A snapshot of what Urbex actually does today versus the v1 vision in
[`architecture.md`](architecture.md), and a prioritized list of what to
build next. Where [`guide.md`](guide.md) documents gaps from the
perspective of *using* the CLI, this document takes stock of the whole
project at once, for planning purposes. Update it whenever a priority
item below gets implemented, or a new gap is discovered.

As of this writing: 18 ADRs, all 8 `urbex` CLI subcommands implemented,
85 unit tests across 16 Go packages in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli). The
pipeline from base services to a running app has been validated with
real Gitea, Komodo, Docker, Terraform, and Ansible binaries, but not yet
against a real Proxmox server - see
[What has been validated](#what-has-been-validated) below.

## Supported today

| Area | State |
|---|---|
| App manifest (`urbex.yaml`) | Formal JSON Schema, typed Go decoding, `urbex init` scaffolds and validates |
| Platform config (`urbex.platform.yaml`) | Scaffolded and validated by `urbex bootstrap` |
| Credentials | Env vars, falling back to `~/.urbex/credentials.yaml`; never written to the GitOps repo |
| Base-service provisioning | Terraform (5 fixed LXCs: Gitea, Komodo, Technitium, Keycloak, observability; optional resource pool) + Ansible (Docker + each service's compose); idempotent, with a pre-flight check that aborts instead of adopting/duplicating an untracked container |
| Platform setup (`urbex bootstrap`) | Generates admin passwords/secrets into `~/.urbex/credentials.yaml`; creates Gitea tokens, org, and `gitops` repo; a Komodo API key and Komodo's Gitea git/registry accounts; pushes the GitOps repo to Gitea |
| Image build & push | Komodo builds each service at the exact commit from the app's repo on Gitea (own Dockerfile, or Urbex's for go/java/python) and pushes it to Gitea's registry, tagged by commit; existing images are reused ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)) |
| `urbex apply` | Terraform, then build + deploy of the app repo's HEAD commit, then commits and pushes the GitOps repo (the inventory pins the deployed image) |
| Project-service provisioning | Generic `for_each` Terraform module (any number of manifest services); static VMID/IP allocation shared across all projects in one GitOps repo, so they never collide |
| `urbex deploy` | Builds (or reuses) the HEAD commit's images and rolls them out to already-applied LXCs with Ansible; syncs the GitOps repo |
| `urbex promote` | Real `git tag` + push (auto-incrementing semver, to `origin` and Gitea), then deploys the same commit to prod, reusing staging's image |
| `urbex destroy` | `terraform destroy` for applied services, then clears their allocation-ledger entries and syncs the GitOps repo |
| `urbex status` | Cross-references Proxmox container presence with the allocation ledger, per base services or per project+environment |
| Transactional email | Manifest field only (`email.provider: brevo`); no code path uses it yet - see [Not supported yet](#not-supported-yet) |

## Not supported yet

| Area | Gap | ADR(s) |
|---|---|---|
| Komodo-driven rollouts | Komodo builds images, but rollouts run as Ansible from the operator's machine; Komodo doesn't manage project LXCs (no Periphery/Stacks there) | [0004](decisions/0004-gitops-gitea-komodo.md), [0018](decisions/0018-image-build-komodo-gitea-registry.md) |
| Push-triggered staging deploy | A push to `main` is supposed to auto-deploy staging; nothing watches for it | [0010](decisions/0010-promotion-flow.md) |
| DNS registration | Technitium LXC exists; nothing registers a record in it | [0007](decisions/0007-technitium-configurable-domain.md) |
| Ingress (Cloudflare Tunnel) | Services are reachable only via their private LXC IP | [0005](decisions/0005-cloudflare-tunnel-ingress.md) |
| Keycloak realm/client provisioning | Keycloak LXC exists; nothing creates the `platform` realm, per-project realms, or app OIDC clients/roles | [0008](decisions/0008-keycloak-scope.md), [0014](decisions/0014-keycloak-realm-per-project.md) |
| Secret encryption (SOPS+age) | `urbex.yaml`'s `env` only carries non-secret values; there is no encrypted-secret mechanism wired into the CLI despite `URBEX_AGE_KEY` being a required credential | [0011](decisions/0011-secrets-sops-age.md) |
| Terraform state encryption | State is plain JSON on disk, not SOPS-encrypted as designed | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Observability wiring | Prometheus/Grafana/Loki LXC exists; no project service is actually scraped or ships logs to it, despite `observability.metrics`/`logs` in the manifest | - |
| Frontend deploy | `frontend` in the manifest is documentation only; no command builds/deploys to Cloudflare Pages or Firebase | - |
| Deployed-version tracking | The GitOps repo's inventories record each environment's image (commit), but no command summarizes it; no `urbex rollback` (redeploying an older commit works) | [0010](decisions/0010-promotion-flow.md) |
| Fleet-wide status | `urbex status` is scoped to one project+environment at a time; no cross-project view | - |
| Cross-machine concurrency guard | Two machines applying against copies of the same GitOps repo can silently conflict | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Cloud providers beyond Proxmox (Azure, GCP, AWS) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Git servers beyond Gitea (GitHub, GitLab) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Vault secrets backend | Not started - v2+ by design | [0011](decisions/0011-secrets-sops-age.md) |

## What has been validated

Beyond unit tests (fakes for Proxmox, Gitea, Komodo, and command
execution), the following ran for real, on containers standing in for
LXCs:

- `terraform validate` of the base and project modules with the real
  `bpg/proxmox` provider (this caught a missing `required_providers` in
  the shared LXC module).
- The Ansible `common`, `gitea`, `komodo`, and `service` roles on
  Debian 12 systemd containers: Docker install, Gitea with its admin
  user, the full Komodo stack (Postgres, FerretDB, Core, Periphery), and
  a service pulled from Gitea's registry and reported healthy. Second
  runs are idempotent (`changed=0`).
- The CLI's Gitea/Komodo code against those real instances: tokens, org,
  repos, Komodo API key and accounts, then Komodo building `go` and
  `docker` services from the app repo on Gitea and pushing them to the
  registry, and re-runs reusing the image.

**Not yet validated:** `terraform apply` against a real Proxmox (LXC
creation, pool placement, `keyctl` permissions with a non-root token),
and Ansible over SSH into real LXCs. The `technitium`, `keycloak`, and
`observability` roles haven't run either.

## Priorities

Roughly in the order that makes each subsequent item worth doing - no
point wiring DNS to a service that was never really deployed because its
image doesn't exist.

### P0 - prove the foundation

1. **Validate against a real Proxmox.** Run `urbex bootstrap` and
   `urbex apply` against the test node, and fix what's left (see
   [What has been validated](#what-has-been-validated)). Expect the
   `keyctl` feature to need a root-set workaround with a pool-scoped
   token.
2. ~~**Image build & push.**~~ Done: Komodo builds, Gitea's registry
   stores, images tagged by commit
   ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)).

### P1 - complete the v1 promise (in dependency order)

3. ~~**Push the GitOps repo to Gitea.**~~ Done: bootstrap and every
   apply/deploy/promote/destroy push it.
4. **Komodo-driven rollouts**, replacing the Ansible rollout in
   `deploy`/`promote` with Komodo Stacks on project LXCs (Periphery on
   each) - including push-triggered staging deploys and tag-triggered
   prod deploys.
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

10. **Deployed-version tracking and real rollback.**
11. **Fleet-wide status** across projects/environments.
12. **Cross-machine concurrency guard** on the shared Terraform state
    and allocation ledger.

### P4 - v2+ scope (deliberately deferred)

13. Cloud providers beyond Proxmox, Git servers beyond Gitea (and
    ghcr.io as registry), CI/CD beyond Komodo (GitHub Actions, ArgoCD),
    Kubernetes as orchestrator, Vault -
    already scoped for later in [`roadmap.md`](roadmap.md); no urgency
    while v1 itself is incomplete.
