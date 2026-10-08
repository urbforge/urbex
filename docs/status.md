# Project status

A snapshot of what Urbex actually does today versus the v1 vision in
[`architecture.md`](architecture.md), and a prioritized list of what to
build next. Where the [getting started](getting-started.md) and
[cookbook](cookbook.md) call out gaps from the perspective of *using*
the CLI, this document takes stock of the whole project at once, for
planning purposes. Every known limitation, with what to do meanwhile, is
in [`known-limitations.md`](known-limitations.md); the table below keeps
only the gaps that matter for planning. Update both whenever a priority
item gets implemented, or a new gap is discovered.

As of this writing: 27 ADRs, 12 `urbex` CLI commands, 156 unit tests
across 20 Go packages, and an end-to-end test (`e2e/run.sh`) in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli) that runs
the real binary through a whole project lifecycle against Debian 13
machines standing in for LXCs, with only Terraform and the Proxmox API
stubbed - and the whole flow has also been run by hand on a real
Proxmox VE 9.2 node, see [What has been validated](#what-has-been-validated).

## Supported today

| Area | State |
|---|---|
| App manifest (`urbex.yaml`) | Formal JSON Schema, typed Go decoding, `urbex init` scaffolds and validates |
| Platform config (`urbex.platform.yaml`) | Scaffolded and validated by `urbex bootstrap` |
| Credentials | Env vars, falling back to `~/.urbex/credentials.yaml`; never written to the GitOps repo |
| Base-service provisioning | Terraform (5 fixed Debian 13 LXCs: Gitea, Komodo, Technitium, Keycloak, observability; optional resource pool) + Ansible (Docker + each service's compose); idempotent, with a pre-flight check that aborts instead of adopting/duplicating an untracked container |
| Platform setup (`urbex bootstrap`) | Generates admin passwords/secrets into `~/.urbex/credentials.yaml`; creates a Gitea token, org, and `gitops` repo; a Komodo API key, the onboarding key project LXCs join with, Komodo's Gitea git/registry accounts and `URBEX_*` variables; the release Action, the GitOps Procedure and its webhook; `.sops.yaml`; pushes the GitOps repo to Gitea ([platform resources](reference/platform-resources.md)) |
| Project-service provisioning | Generic `for_each` Terraform module (any number of manifest services); static VMID/IP allocation shared across all projects in one GitOps repo, so they never collide; Docker + Komodo Periphery + sops on each LXC |
| **Builds** | Every push to a project's `main` makes Komodo build each service and push `<project>-<service>:<short hash>` to Gitea's registry ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md), [ADR-0021](decisions/0021-staging-follows-main.md)) |
| **Continuous deployment to staging** | Staging follows `main` (`TRACK=main` in its version files): after each build, Komodo commits the new version to the GitOps repo and deploys it ([ADR-0021](decisions/0021-staging-follows-main.md)) |
| **Releases** | A `vX.Y.Z` tag (pushed by hand or by `urbex release`, which tags the commit staging runs) gives that commit's images the tag `X.Y.Z` - no rebuild ([ADR-0020](decisions/0020-trunk-releases-gitops-environments.md), [ADR-0021](decisions/0021-staging-follows-main.md)) |
| **Environments in the GitOps repo** | `environments/<env>/<project>/<service>/` holds the compose file, `version.env`, `config.env`, and `secrets.sops.env`; Komodo deploys each folder as a Stack on the service's LXC whenever it changes (webhook), and reconciles every 15 minutes |
| **Secrets** | SOPS + age, per service and environment, in the GitOps repo; decrypted only on the LXC, at deploy time; `urbex secret set/unset/list` |
| `urbex apply` | Terraform, Ansible, the project's Builds and webhook, the environment's folder and Stacks; a new staging builds and runs `main`'s head; redeploys an environment that already runs something |
| `urbex release` | Tags the next release on the commit staging runs (or `main`, or `--ref`) and waits for its images |
| `urbex deploy` | Sets an environment's version in the GitOps repo (latest release, `--version` with a release or commit - also how to roll back - or `--follow-main`), pushes, waits for Komodo to run it |
| `urbex promote` | Sets prod to the release staging runs: prod runs the very images staging ran; refuses an unreleased commit |
| `urbex teardown` | Destroys the base-service LXCs (refusing while project environments exist), forgets the generated credentials, keeps the GitOps repo locally |
| `urbex destroy` | Takes the environment's Stacks down, removes its folder, `terraform destroy`, clears the allocation ledger; the project's Builds go with its last environment |
| `urbex status` | Proxmox container presence, allocation ledger and, per service, the version the GitOps repo asks for against what Komodo runs |
| **Public endpoints (Cloudflare)** | One tunnel for the platform, `cloudflared` on `urbex-tunnel`; Keycloak public, Gitea and Komodo behind Cloudflare Access (one-time PIN for listed e-mails), Komodo's webhook listener public; services with `public: true` published per environment; flat or nested hostnames ([ADR-0022](decisions/0022-cloudflare-tunnel-access-workers.md)) |
| **Cloudflare Quick Tunnel** | `cloudflare.quickTunnel: true`, without an account, exposes every `public: true` service on its own `https://*.trycloudflare.com` hostname: a `cloudflared` sidecar on the service's LXC, `urbex apply`/`urbex status` reading the hostname live from it. Not a production substitute for ADR-0022 ([ADR-0025](decisions/0025-cloudflare-quick-tunnel.md)) |
| **Logs and resource monitoring** | A Grafana Alloy agent on every LXC - base services and project services - sends its service's logs to Loki and the LXC's CPU, memory, disk and network to Prometheus, labelled `kind` (`platform`/`app`), `service`, `host`, and `project`/`env` for apps; Grafana comes with both data sources and the *Urbex logs* and *Urbex resources* dashboards; `observability.logs: false` stops a project's logs ([ADR-0023](decisions/0023-service-logs-to-loki.md)) |
| **Identity (Keycloak)** | A realm per project environment (`<project>-<env>`) with the services' roles and a public OIDC client per frontend; in staging a test user per role (`urbex users staging`) and a password-login client for tests; services with `auth.keycloak` get the issuer and keys ([ADR-0024](decisions/0024-keycloak-realm-per-environment.md)) |
| **Internal DNS (Technitium)** | A zone named after the platform's domain, created by `urbex bootstrap`; `urbex apply <env>` sets an A record per declared service at its LAN IP (the same hostname Cloudflare would publish), `urbex destroy <env>` removes them; independent of Cloudflare being configured ([ADR-0026](decisions/0026-technitium-internal-dns-records.md)) |
| **Komodo** | Every LXC is a Komodo Server - the base services' too, for monitoring their containers - and Komodo's resources are tagged like Grafana: `platform`, or `app` + project (+ environment) |
| **Endpoints** | `urbex status` lists every platform address (LAN and public) and where the logins are; `urbex status <env>` each service's |
| **Running from a container** | `tools/operator/urbex-op` in urbex-cli: an image with urbex and its tools, run against a workspace folder |
| **Web frontends** | Built once per commit of `main`, deployed to a Cloudflare Worker with static assets per environment by a Stack on the builder; staging follows `main`, release/promote/rollback as for services ([ADR-0022](decisions/0022-cloudflare-tunnel-access-workers.md)) |
| Transactional email | Manifest field only (`email.provider: brevo`); no code path uses it yet - see [Not supported yet](#not-supported-yet) |

## Not supported yet

| Area | Gap | ADR(s) |
|---|---|---|
| Promotion by pull request | `urbex promote` commits to the GitOps repo directly; a PR-gated production folder is a Gitea setting Urbex doesn't manage (see the [cookbook](cookbook.md#gate-production-behind-a-pull-request)) | [0020](decisions/0020-trunk-releases-gitops-environments.md) |
| Image cleanup | Every push to `main` leaves an image in the registry; nothing prunes them | [0021](decisions/0021-staging-follows-main.md) |
| Service conventions | Every service should be deployed by Komodo, reached by internal name, tagged by kind (`platform`/`app`/`agent`) and exposed by its kind of endpoint; today services reach each other by IP, the LXCs don't resolve through Technitium, base services have no DNS record, the platform's services are deployed by Ansible, Grafana/Technitium/Prometheus/Loki are LAN-only and Keycloak's `/admin` is public | [0027](decisions/0027-service-conventions.md) |
| Removing a service | Dropping a service from `urbex.yaml` leaves its LXC, Stack, folder and internal DNS record behind | - |
| Pre-releases | Only `vX.Y.Z` tags are releases; `-rc.1` and the like are ignored | [0020](decisions/0020-trunk-releases-gitops-environments.md) |
| Pinned base-service images | Technitium, Prometheus, Loki, and Grafana still use `latest` | - |
| Custom public names | Public hostnames are derived from the project's and services' names; `domain.subdomain` in the manifest isn't used, and `nested` names need ACM enabled by hand | [0022](decisions/0022-cloudflare-tunnel-access-workers.md) |
| Frontend-only projects | A web frontend needs at least one service in the manifest | [0022](decisions/0022-cloudflare-tunnel-access-workers.md) |
| Keycloak beyond projects | No `platform` realm (admin SSO), no confidential clients for service-to-service calls; Keycloak in development mode | [0008](decisions/0008-keycloak-scope.md), [0024](decisions/0024-keycloak-realm-per-environment.md) |
| Terraform state encryption | State is plain JSON in the (private) GitOps repo, not SOPS-encrypted as designed | [0013](decisions/0013-terraform-state-in-gitops-repo.md) |
| Service metrics, alerting | LXC resource metrics are collected, but not the services' own metrics (`observability.metrics` is ignored); no alerting; Loki has no retention | [0023](decisions/0023-service-logs-to-loki.md) |
| Mobile frontend deploy | `frontend.type: mobile` (Firebase) is validated, not deployed | - |
| Fleet-wide status | `urbex status` is scoped to one project+environment at a time; Komodo's UI is the cross-project view | - |
| Per-project Proxmox isolation | New projects should get their own resource pool, a group for their users with minimal permissions, and dedicated technical users; today every LXC goes in the platform-wide `proxmox.pool`, managed with the operator's token | [roadmap](roadmap.md) |
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
2. `urbex apply staging`: staging follows `main` and runs its head.
3. Continuous deployment: a push to `main` reaches staging with no
   command, through a commit to the GitOps repo.
4. `urbex release` tags the commit staging runs and publishes its image
   without a new build; a tag pushed by hand is a release too.
5. `urbex apply prod` (empty) and `urbex promote`: prod runs the release
   staging runs; an unreleased commit is refused.
6. Secrets: set, delivered to the service, absent in plaintext from the
   repo, unset.
7. Configuration edited by hand in the GitOps repo and pushed with
   plain git; an unrelated commit restarts nothing.
8. Pinning staging to a release (pushes to `main` no longer move it),
   then `--follow-main`.
9. Rollback by deploying an older release; a release that doesn't exist
   is refused.
10. `urbex destroy staging` (prod untouched), then `urbex apply` onto a
    brand-new machine.

Separately, `terraform validate` passes on the base and project modules
with the real `bpg/proxmox` provider, and the `python` and `java`
runtime Dockerfiles were built and run on their own.

**On a real Proxmox** (VE 9.2, test node, 2026-10-01): with a
pool-scoped, non-root token (the group setup in
[credentials](reference/credentials.md#proxmox-api-token)) and
`keyctl: false`, `urbex bootstrap` created and configured the five base
services from the Debian 13.6 template, and a re-run changed nothing;
then, for a sample Go service, `urbex apply staging` (built and ran
`main`'s head), a push to `main` deployed to staging in 45 seconds,
`urbex release` (no rebuild), `urbex apply prod`, `urbex promote`, a
secret delivered to the service, and `urbex destroy staging` followed by
`urbex apply staging` onto a new LXC. Docker runs in the unprivileged
LXCs without `keyctl`. Two things it surfaced, both fixed: LXCs copying
a Proxmox host's Tailscale DNS (now `proxmox.network.dnsServers`), and
a too-short timeout downloading `sops`. Not exercised there: rollback
and pinning (identical to the e2e, no Proxmox involvement).

Deleting the project (`urbex destroy staging`, `urbex destroy prod`) was
then checked against a snapshot of everything taken before: exactly the
project's LXCs, their ZFS volumes and pool membership, its Komodo
Servers, Stacks and Build, the project webhook, and its files in the
GitOps repo (environment folders, Terraform state and files, Ansible
inventories, ledger entries) were gone; the base services, the project
repo and its images on Gitea (kept by design) untouched. It surfaced
three bugs, fixed: `destroy` worked from a stale copy of the GitOps repo
and conflicted with the release Action's commits (now it refreshes, and
removes the folder last); a Build busy with a push made during `destroy`
couldn't be deleted (now waited for); and with a pool-scoped token,
Terraform fails on an LXC that no longer exists (403 instead of 404), so
a destroy interrupted halfway couldn't be resumed (now such LXCs are
dropped from the state first). A destroy with a push to `main` racing it,
and a destroy resumed after a failure, both ended clean.

Removing the platform (`urbex teardown --yes`, new) destroyed the five
base-service LXCs and their disks, left the resource pool with only its
storages, forgot the generated credentials, and kept the GitOps repo as
a local commit; `urbex bootstrap` then rebuilt the platform from that
working copy. Reusing the same addresses for new LXCs surfaced three
more problems, fixed: Ansible refused the new LXCs' host keys (host keys
now live in the GitOps repo's `state/known_hosts`, and urbex forgets an
address's key when it creates or destroys the LXC there); Proxmox's
storage lock timed out with five LXCs created at once right after five
were destroyed (Terraform now runs two operations at a time and retries
once); and SSH timed out while the network still had the old LXCs' MAC
addresses (longer timeout, retries).

**Cloudflare Quick Tunnel, on the same real Proxmox node** (2026-10-04),
without any Cloudflare account configured: with `cloudflare.quickTunnel:
true` and a service marked `public: true`, `urbex apply` ran the
`quicktunnel` role, printed a `https://*.trycloudflare.com` hostname,
and the deployed service (a Go API behind a small web UI) answered
through it from outside the LAN. A second, unmodified `urbex apply` run
immediately after was checked specifically for the hostname's stability:
the role's `docker compose up -d` reported no change, the sidecar
container was not recreated, and the same hostname kept answering - a
plain re-apply does not disrupt an already-running Quick Tunnel, unlike
what an initial reading of [ADR-0025](decisions/0025-cloudflare-quick-tunnel.md)
assumed (corrected there). Not exercised there: recovery after an actual
network interruption, and the hostname change expected from an LXC
reboot or a config change that recreates the sidecar.

**Internal DNS (Technitium), on the same real Proxmox node**
(2026-10-05): `urbex bootstrap` set `DNS_SERVER_ADMIN_PASSWORD`, minted
an API token with it, and created a zone named after the platform's
domain - confirmed independently with a direct `GET /api/zones/list`
call using the stored token. `urbex apply staging` then set an A record
for the sample service's hostname at its allocated LAN IP; querying
Technitium directly (`GET /api/zones/records/get`) returned exactly
that record, resolving to the right address, with no Cloudflare account
configured - confirming registration doesn't depend on it
([ADR-0026](decisions/0026-technitium-internal-dns-records.md)). The
one gap it surfaced isn't a code bug: the lab's Technitium instance had
already been configured (by a previous bootstrap, before this feature
existed) with a different admin password than the newly generated one,
so bootstrap's token minting needed that real password seeded into
`~/.urbex/credentials.yaml` by hand first - see
[known limitations](known-limitations.md#platform). Not exercised
there: `urbex destroy`'s record removal, and a from-scratch bootstrap
where Technitium has no prior configuration at all.

**On a real Cloudflare account** (Free plan zone, 2026-10-02), with a
pool-scoped Proxmox token: bootstrap published Keycloak
(`auth-urbex.<domain>`, issuer public), Gitea and Komodo behind Access
(redirect to the team's login, one-time PIN), and the webhook listener;
a project with a public API and a web frontend then ran on staging
(`api-staging-hello-urbex`, `staging-hello-urbex`), followed `main` -
the frontend served a new version 91 seconds after the push - and was
released and promoted to prod (`api-hello-urbex`, `hello-urbex`, the
same build). `destroy` of both environments and `teardown` left nothing
of urbex on the account - tunnel, routes, DNS records, Access objects,
Workers and their domains - and everything else untouched. It surfaced:
Access set up after routing (a failed Access setup left Gitea and Komodo
exposed for a few minutes; now Access comes first and nothing is
published without it), Access errors carried in a different field, and
a Workers API answering 200 with no body.

**Service logs** ([ADR-0023](decisions/0023-service-logs-to-loki.md)),
on the same Proxmox node after a fresh bootstrap: the sample service's
lines reached Loki as one stream labelled `project`, `service`, `env`,
`host`, `container` - its own container only, not Periphery's or the
agent's - and Grafana came up with the Loki and Prometheus data sources
and the *Urbex logs* dashboard, querying Loki. The e2e test checks the
same. It surfaced that Alloy ignored the filtering when given as
`relabel_rules`: the containers are now filtered at discovery. Then, with the agent on every LXC: logs of every
base service (`kind="platform"`, by service) and of the app
(`kind="app"`), resource metrics of all seven LXCs with each LXC's own
memory and CPU count, and both dashboards working through Grafana. The
CPU formula had to change: inside an LXC the idle counter undercounts
(`1 - idle` showed 60-80% on idle LXCs, Proxmox 1-6%), so CPU is the
busy time over the CPUs. The platform was run from `urbex-op` too. Keycloak wrote nothing after starting, so it
seemed missing from Loki: it now logs every HTTP request and user events
(logins, failed logins), which needed Keycloak 26.1+ (pinned to 26.7.5);
upgrading its development database from 26.0 failed on the database
credentials until urbex pinned them.

## Priorities

Roughly in the order that makes each subsequent item worth doing.

### P0 - prove the foundation

1. ~~**Validate against a real Proxmox.**~~ Done (see
   [What has been validated](#what-has-been-validated)).
2. ~~**Image build & push.**~~ Done: Komodo builds, Gitea's registry
   stores ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)).

### P1 - complete the v1 promise (in dependency order)

3. ~~**Push the GitOps repo to Gitea.**~~ Done.
4. ~~**Komodo-driven rollouts, from the GitOps repo.**~~ Done
   ([ADR-0020](decisions/0020-trunk-releases-gitops-environments.md)).
5. ~~**DNS registration in Technitium.**~~ Done
   ([ADR-0026](decisions/0026-technitium-internal-dns-records.md)):
   removes the "find the IP" step from every other workflow.
6. ~~**Cloudflare Tunnel ingress**~~ Done, with Access and web
   frontends on Workers
   ([ADR-0022](decisions/0022-cloudflare-tunnel-access-workers.md)).

7. **Service conventions**
   ([ADR-0027](decisions/0027-service-conventions.md)): internal DNS
   zone and Technitium as resolver, references by name, three kinds,
   admin UIs behind Access, platform services as Komodo Stacks, a
   service catalog that enforces them. New services (databases) wait
   for it.

### P2 - identity, secrets, observability

8. ~~**Keycloak realm/client provisioning**~~ Done for projects
   ([ADR-0024](decisions/0024-keycloak-realm-per-environment.md)); next:
   the `platform` realm for admin SSO, production mode.
9. ~~**Secret encryption (SOPS+age)**~~ Done for application secrets
   ([ADR-0020](decisions/0020-trunk-releases-gitops-environments.md));
   Terraform state is still stored unencrypted.
10. **Observability wiring** - ~~logs and resource metrics of every LXC~~
   done ([ADR-0023](decisions/0023-service-logs-to-loki.md)); next: the
   services' own metrics (`observability.metrics`), alerting, Loki
   retention.

### P3 - operability polish

11. ~~**Continuous deployment to staging.**~~ Done
    ([ADR-0021](decisions/0021-staging-follows-main.md)). Still open:
    **promotion by pull request** on the GitOps repo, and pruning old
    images.
12. **Fleet-wide status** across projects/environments.
13. **Cross-machine concurrency guard** on the shared Terraform state
    and allocation ledger.

### P4 - v2+ scope (deliberately deferred)

14. Cloud providers beyond Proxmox, Git servers beyond Gitea (and
    ghcr.io as registry), CI/CD beyond Komodo (GitHub Actions, ArgoCD),
    Kubernetes as orchestrator, Vault -
    already scoped for later in [`roadmap.md`](roadmap.md); no urgency
    while v1 itself is incomplete.
