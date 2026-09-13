# Project status

A snapshot of what Urbex actually does today versus the v1 vision in
[`architecture.md`](architecture.md), and a prioritized list of what to
build next. Where [`guide.md`](guide.md) documents gaps from the
perspective of *using* the CLI, this document takes stock of the whole
project at once, for planning purposes. Update it whenever a priority
item below gets implemented, or a new gap is discovered.

As of this writing: 17 ADRs, all 8 `urbex` CLI subcommands implemented,
65 unit tests across 16 Go packages in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli). Nothing
has been run against a real Proxmox server or real
`terraform`/`ansible-playbook` binaries yet - see
[Untested, not "not implemented"](#untested-not-not-implemented) below.

## Supported today

| Area | State |
|---|---|
| App manifest (`urbex.yaml`) | Formal JSON Schema, typed Go decoding, `urbex init` scaffolds and validates |
| Platform config (`urbex.platform.yaml`) | Scaffolded and validated by `urbex bootstrap` |
| Credentials | Env vars, falling back to `~/.urbex/credentials.yaml`; never written to the GitOps repo |
| Base-service provisioning | Terraform (5 fixed LXCs: Gitea, Komodo, Technitium, Keycloak, observability) + Ansible (Docker + compose skeleton); idempotent, with a pre-flight check that aborts instead of adopting/duplicating an untracked container |
| Project-service provisioning | Generic `for_each` Terraform module (any number of manifest services); static VMID/IP allocation shared across all projects in one GitOps repo, so they never collide |
| `urbex deploy` | Re-renders the Ansible inventory from the current manifest and redeploys already-applied LXCs directly (no Komodo involved) |
| `urbex promote` | Real `git tag` + `git push` (auto-incrementing semver), then calls the same direct-Ansible redeploy against prod |
| `urbex destroy` | `terraform destroy` for applied services, then clears their allocation-ledger entries |
| `urbex status` | Cross-references Proxmox container presence with the allocation ledger, per base services or per project+environment |
| Transactional email | Manifest field only (`email.provider: brevo`); no code path uses it yet - see [Not supported yet](#not-supported-yet) |

## Not supported yet

| Area | Gap | ADR(s) |
|---|---|---|
| Image build & push | `apply`/`deploy` render a compose file with a **placeholder** image reference; nothing builds or pushes a real image from a Dockerfile or from source | [0003](decisions/0003-terraform-ansible-provisioning.md) |
| GitOps repo → Gitea | `bootstrap` creates the Gitea LXC but never pushes anything to it; "the GitOps repo" is just a local directory | [0004](decisions/0004-gitops-gitea-komodo.md), [0006](decisions/0006-bootstrap-command.md) |
| Komodo integration | No code talks to Komodo at all; `deploy`/`promote` fake its job via direct Ansible | [0004](decisions/0004-gitops-gitea-komodo.md) |
| Push-triggered staging deploy | A push to `main` is supposed to auto-deploy staging; nothing watches for it | [0010](decisions/0010-promotion-flow.md) |
| DNS registration | Technitium LXC exists; nothing registers a record in it | [0007](decisions/0007-technitium-configurable-domain.md) |
| Ingress (Cloudflare Tunnel) | Services are reachable only via their private LXC IP | [0005](decisions/0005-cloudflare-tunnel-ingress.md) |
| Keycloak realm/client provisioning | Keycloak LXC exists; nothing creates the `platform` realm, per-project realms, or app OIDC clients/roles | [0008](decisions/0008-keycloak-scope.md), [0014](decisions/0014-keycloak-realm-per-project.md) |
| Secret encryption (SOPS+age) | `urbex.yaml`'s `env` only carries non-secret values; there is no encrypted-secret mechanism wired into the CLI despite `URBEX_AGE_KEY` being a required credential | [0011](decisions/0011-secrets-sops-age.md) |
| Terraform state encryption | State is plain JSON on disk, not SOPS-encrypted as designed | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Observability wiring | Prometheus/Grafana/Loki LXC exists; no project service is actually scraped or ships logs to it, despite `observability.metrics`/`logs` in the manifest | - |
| Frontend deploy | `frontend` in the manifest is documentation only; no command builds/deploys to Cloudflare Pages or Firebase | - |
| Deployed-version tracking | No record links a promoted tag to what's actually running; no `urbex rollback` | [0010](decisions/0010-promotion-flow.md) |
| Fleet-wide status | `urbex status` is scoped to one project+environment at a time; no cross-project view | - |
| Cross-machine concurrency guard | Two machines applying against copies of the same GitOps repo can silently conflict | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Cloud providers beyond Proxmox (Azure, GCP, AWS) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Git servers beyond Gitea (GitHub, GitLab) | Not started - v2+ by design | [roadmap](roadmap.md) |
| Vault secrets backend | Not started - v2+ by design | [0011](decisions/0011-secrets-sops-age.md) |

## Untested, not "not implemented"

Distinct from the gaps above: the embedded Terraform modules and Ansible
playbooks/roles (`platform/terraform/`, `platform/ansible/` in
`urbex-cli`) are real, written carefully, and covered by unit tests for
the Go orchestration logic around them (fakes for Proxmox and for
command execution) - but have never been run against a live Proxmox
server or real `terraform`/`ansible-playbook` binaries, because neither
was available while building this. They might just work; they haven't
been proven to. Treat this as the first thing to close, since every
priority below builds on top of this infrastructure layer.

## Priorities

Roughly in the order that makes each subsequent item worth doing - no
point wiring DNS to a service that was never really deployed because its
image doesn't exist.

### P0 - prove the foundation

1. **Validate against a real Proxmox.** Not new code: run `urbex
   bootstrap` and `urbex apply` against an actual server, fix whatever
   the Terraform/Ansible content gets wrong (image tags, provider
   syntax, resource attributes). Everything else compounds on top of
   this being trustworthy.
2. **Image build & push.** The single biggest blocker to a real
   zero-touch deploy - without it, `apply`/`deploy` never produce an
   app that's actually running the code that was promoted. Needs a
   design decision first: build in Komodo, in a Gitea Actions-style CI,
   or via the CLI itself calling `docker build`/`docker push`.

### P1 - complete the v1 promise (in dependency order)

3. **Push the GitOps repo to Gitea.** Prerequisite for Komodo to have
   anything to watch.
4. **Komodo integration**, replacing `deploy`/`promote`'s direct-Ansible
   shortcut with real GitOps reconciliation - including push-triggered
   staging deploys (item 3's payoff).
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

13. Cloud providers beyond Proxmox, Git servers beyond Gitea, Vault -
    already scoped for later in [`roadmap.md`](roadmap.md); no urgency
    while v1 itself is incomplete.
