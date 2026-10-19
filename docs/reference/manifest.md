# Manifest reference (`urbex.yaml`)

`urbex.yaml` lives at the root of a project's repo and describes the
project: its services, how they are built, the port and healthcheck of
each. It is validated by `urbex init` against
[`schemas/urbex.schema.json`](../../schemas/urbex.schema.json) and read by
`plan`, `apply`, `deploy`, `release`, `promote`, `secret`, and `status`
from the working copy they run in.

What differs **per environment** - which version runs, configuration,
secrets - is not here but in the [GitOps repo](gitops-repo.md).

- [Full example](#full-example)
- [Top level](#top-level)
- [`services[]`](#services)
- [Runtimes](#runtimes)
- [Applications from published images](#applications-from-published-images)
- [Volumes](#volumes)
- [`frontend`](#frontend)
- [`domain`, `observability.metrics`, `email`, `provides`, `uses`](#declared-not-yet-acted-on)
- [What changes take effect how](#what-changes-take-effect-how)

## Full example

```yaml
apiVersion: urbex/v1
project: acme-app

services:
  - name: api
    runtime: go
    port: 8080
    healthcheck: /healthz
    resources:
      cpu: 2
      memory: 2Gi
      disk: 10Gi
    env:
      staging:
        LOG_LEVEL: debug
      prod:
        LOG_LEVEL: info

  - name: web
    runtime: docker
    dockerfile: ./web/Dockerfile
    port: 3000
    healthcheck: /health

frontend:
  type: web
  provider: cloudflare-pages
  buildCommand: npm run build
  outputDir: dist
```

## Top level

| Field | Type | Required | Meaning |
|---|---|---|---|
| `apiVersion` | `urbex/v1` | yes | Manifest format version. |
| `project` | string | yes | The project's name on the platform: 3-40 characters, lowercase letters, digits, `-`, starting with a letter. It names the repo on Gitea, the LXCs, the images, and the folders in the GitOps repo, so changing it means a new project. |
| `services` | list | one of `services` or `frontend` | The services to build and run. At least one if present. |
| `environments` | `[staging, prod]` or `[prod]` | `[staging, prod]` | The environments of the stack. With `[prod]` the stack runs in production only: `urbex apply staging` is refused, and `urbex release` and `urbex promote` do not apply, since versions are set in production directly with `urbex deploy prod` ([ADR-0028](../decisions/0028-application-model.md)). |
| `frontend` | object | | See [`frontend`](#frontend). |
| `observability.logs` | boolean | `true` | Ship the services' logs to the platform's Loki ([ADR-0023](../decisions/0023-service-logs-to-loki.md)); `false` removes the log agent from the project's LXCs. |
| `domain`, `observability.metrics`, `email` | object | | Validated, [not acted on yet](#declared-not-yet-acted-on). |

Unknown fields are errors.

## `services[]`

Each service gets, per environment, its own LXC
(`<project>-<service>-<env>`), its own Komodo Build
(`<project>-<service>`, shared by the environments), its own image
(`<registry>/<org>/<project>-<service>`), and its own folder in the
GitOps repo. An application from a published image has neither a Build
nor an image of its own: its LXC pulls the image it declares (see
[applications from published images](#applications-from-published-images)).

| Field | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | required | 2-40 characters, lowercase letters, digits, `-`, starting with a letter. Unique in the project. |
| `runtime` | `go`, `java`, `python`, `docker` | required (without `image`) | How the image is built - see [runtimes](#runtimes). |
| `image` | image reference without tag | required (without `runtime`) | A published image to run instead of building one, such as `docker.io/library/postgres` or `ghcr.io/immich-app/immich-server`. A name without a registry refers to Docker Hub. Only public images are supported. |
| `version` | image tag | required with `image` | The tag to run, such as `17.6`. Each environment runs the digest this tag pointed to when it was resolved, recorded in its `version.env`, until `urbex deploy` resolves it again. |
| `dockerfile` | path | required with `docker` | Path of the Dockerfile from the repo root; its directory is the build context. Ignored for other runtimes. |
| `public` | boolean | `false` | Publish the service on the internet through the platform's Cloudflare Tunnel, at `<service>-<project>-urbex.<domain>` (prod) and `<service>-staging-<project>-urbex.<domain>` (staging). Its own auth is its gate. Needs Cloudflare in the [platform config](platform-config.md#public-hostnames). |
| `port` | 1-65535 | required with `runtime` | The port the service listens on. The container gets `PORT` set to it, and it is published on the LXC's IP at the same number. An application from a published image may omit it; if it declares one, the port is published in the same way, but `PORT` is not set, since such an image reads its own variables. `public` and `healthcheck` require a port. |
| `healthcheck` | HTTP path | none | Path probed every 30 s from inside the container (`wget -q --spider http://localhost:<port><path>`); three failures mark the container unhealthy, and `urbex` waits for healthy. Without it, a running container counts. |
| `volumes` | list | | What the application keeps: named volumes and shares, mounted in the container. See [volumes](#volumes). |
| `resources.cpu` | integer ≥ 1 | `1` | Cores of the LXC. |
| `resources.memory` | `<n>Mi` or `<n>Gi` | `1Gi` | Memory of the LXC. |
| `resources.disk` | `<n>Mi` or `<n>Gi` | `5Gi` | Root disk of the LXC, rounded up to whole GiB. |
| `env.staging`, `env.prod` | map of strings | | **Initial** configuration of the service in that environment: written to its `config.env` in the GitOps repo when the environment is first applied, and never again. Change `config.env` after that. Never put secrets here - use `urbex secret`. |
| `auth.keycloak` | boolean | `false` | The service authenticates users with Keycloak: it gets `KEYCLOAK_REALM`, `KEYCLOAK_ISSUER` and `KEYCLOAK_JWKS_URL` (its environment's realm, the issuer the tokens carry, the signing keys) to validate tokens ([ADR-0024](../decisions/0024-keycloak-realm-per-environment.md)). |
| `auth.roles` | list | | Realm roles the service checks: created in each environment's realm (`<project>-<env>`); in staging, a test user per role (`test-<role>`, see `urbex users`). |

## Runtimes

For `go`, `java`, and `python`, Urbex supplies the Dockerfile; the
project only follows a convention. Builds run on the Komodo LXC from the
project's repo at the pushed commit.

| Runtime | Build | Image | Start |
|---|---|---|---|
| `go` | `golang:1.26`: `go build ./cmd/<service>` if that directory exists, else `go build .` at the module root (`go.mod` at the repo root) | `alpine:3.22`, non-root | the binary |
| `python` | `python:3.12-slim`: `pip install -r requirements.txt` if present | same, with `wget`, non-root | `python main.py` |
| `java` | `maven:3.9-eclipse-temurin-21`: `./gradlew build -x test` if `gradlew` exists, else `./mvnw` or `mvn -DskipTests package` | `eclipse-temurin:21-jre`, with `wget`, non-root | `java -jar` on the built jar (from `target/` or `build/libs/`, excluding `-plain`, `-sources`, `-javadoc`) |
| `docker` | `docker build` of `dockerfile`, with its directory as context | yours | yours |

In every case:

- the service must listen on `$PORT`;
- the build gets `--build-arg SERVICE=<service name>`;
- with a `healthcheck`, the image must contain `wget` (Urbex's do);
- there is one image per commit of `main`, tagged with the commit's short
  hash, plus one tag per release (`1.4.2`) on the same image.

## Applications from published images

An application can run a published image, pulled as it is, instead of
an image built from the project's repository
([ADR-0028](../decisions/0028-application-model.md)):

```yaml
apiVersion: urbex/v1
project: acme-site
environments: [prod]

services:
  - name: web
    image: docker.io/library/nginx
    version: "1.29"
    port: 80
```

On the first `urbex apply` of an environment, the tag in `version` is
resolved, through the registry, to the digest of the image it refers to
at that moment. The environment records both in its `version.env`
(`VERSION=1.29@sha256:...`) and runs that digest. A new prod of a stack
with staging is the exception: it takes the tag and digest that staging
runs, if staging has them, so that production never runs a digest
staging has not run. The digest remains in
place when the tag is later moved by its publisher; it changes only
through `urbex deploy <env> --update`, which resolves the tag again,
through `urbex deploy <env> --app <name> --version <tag>`, which pins
another tag, and through `urbex promote`, which copies to production the
digest that staging runs. The [CLI reference](cli.md#urbex-deploy)
describes these forms.

Changing `version` in `urbex.yaml` therefore changes nothing by itself:
`urbex apply` reports the difference, and `urbex deploy <env> --app
<name> --update` applies it. In the opposite direction, `urbex deploy
<env> --app <name> --version <tag>` writes the new tag into `version`
when the environment is the first one of the stack, as the [CLI
reference](cli.md#urbex-deploy) describes.

An application from a published image is never built and never follows
`main`. A stack may combine such applications with services built from
source: `urbex release` and the builds concern the latter only, while
`urbex promote` moves both, the releases of the services built from
source and the digests of the applications from images.

The image must be reachable without credentials: a registry that
requires authentication is refused when the tag is resolved.

## Volumes

An application keeps data in volumes, mounted into its container at
`path` ([ADR-0028](../decisions/0028-application-model.md)):

```yaml
services:
  - name: jellyfin
    image: jellyfin/jellyfin
    version: "10.10.7"
    port: 8096
    volumes:
      - { name: config, path: /config, size: 5Gi }
      - { share: media, path: /media, readOnly: true }
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | one of `name` or `share` | A named volume: 2-40 characters, lowercase letters, digits, `-`. Unique in the application. |
| `share` | string | one of `name` or `share` | A share of the platform, declared in [`storage.shares`](platform-config.md#shares) of `urbex.platform.yaml`. |
| `path` | absolute path | required | Where the container sees it. Two volumes of an application can't have the same path. |
| `size` | `<n>Mi` or `<n>Gi` | `10Gi` | Size of a named volume, rounded up to whole GiB. Not for a share. |
| `readOnly` | boolean | `false` | Mounts the share read-only. Not for a named volume. |

A **named volume** is a mount point of the application's LXC on the
platform's storage (`proxmox.storagePool`). It is mounted on the LXC at
`/srv/volumes/<name>` and bound from there into the container. `urbex
apply` creates it with `backup=1`, so that Proxmox's backups (vzdump) of
the LXC include it, and grows it when `size` grows. It can't be shrunk:
`apply` refuses a smaller `size`. The data stays across redeploys,
updates, re-applies and changes of the LXC's `resources`, which are made
in place. A change that would make Terraform replace the LXC is refused
by `apply`, since Proxmox deletes an LXC's volumes with it (see [known
limitations](../known-limitations.md)). `urbex destroy` deletes the
volumes only with `--delete-data`. A volume removed from `urbex.yaml` is
no longer mounted in the container, but stays on the LXC until `urbex
destroy --delete-data`.

A **share** is a folder of the Proxmox node that exists outside Urbex,
such as a NAS's media library. The operator declares it once in
`urbex.platform.yaml`, and every application that names it mounts it, at
`/srv/shares/<share>` on its LXC. Binding a folder of the node into an
LXC needs `root@pam`, which an API token never has, so the operator
binds it. Until an application's LXC has its shares, `urbex apply`
prints the commands to run on the node, deploys the rest of the stack
without that application, and exits with an error:

```
Some applications need shares their LXC doesn't have yet. Binding a folder of the Proxmox node needs root@pam: on the node, as root, run
  pct set 9112 -mp1 /mnt/pve/nas/media,mp=/srv/shares/media,ro=1
then run 'urbex apply prod' again.
not deployed until their shares are mounted: jellyfin
```

`apply` restarts a running LXC that can't mount a new volume or share
at once. Urbex never deletes a share.

## `frontend`

```yaml
frontend:
  type: web                    # web | mobile
  provider: cloudflare-pages   # cloudflare-pages for web, firebase for mobile
  buildCommand: npm ci && npm run build
  outputDir: dist
```

All four fields are required; `web` must use `cloudflare-pages` and
`mobile` `firebase`.

Every frontend gets a public OIDC client in each environment's Keycloak
realm (`<project>-<env>`): `web` for a web frontend, redirecting to its
hostname; `mobile` for a mobile app, redirecting to `<project>://...`.
Use authorization code with PKCE; the issuer is printed by `urbex apply`
and `urbex users`.

A **web** frontend is deployed to Cloudflare Workers with static assets
([ADR-0022](../decisions/0022-cloudflare-tunnel-access-workers.md)),
alongside the services and with the same flow:

- every push to `main` builds it once: in a `node:22` container on the
  builder, at the repo root, `buildCommand` runs (install the
  dependencies there), and `outputDir` becomes the site;
- staging follows `main`, `urbex release` and `urbex promote` move the
  same build to prod, `urbex deploy --version` rolls back;
- each environment is a Worker, `urbex-<project>-web-<env>`, at
  `<project>-urbex.<domain>` (prod) and `staging-<project>-urbex.<domain>`;
  unknown paths serve `index.html` (single-page apps).

It needs Cloudflare configured in the platform, and at least one service
in the manifest (a frontend-only project isn't supported yet). In the
GitOps repo it appears as a service called `web`.

> ⚠️ `mobile` (Firebase) is validated, not acted on: deploy with
> Firebase's tooling.

## Declared, not yet acted on

These are validated, so a manifest can already state them, but no
command uses them yet (see [`status.md`](../status.md)). The fields of
`services[]` in this table are refused by `urbex plan`, `apply`,
`deploy` and `promote` rather than ignored, since an application that
expects a database would otherwise run without it.

| Field | Meaning, once implemented |
|---|---|
| `domain.subdomain` | A custom name for the project's public hostnames (today they are derived from the project's name). |
| `observability.metrics` | Scraping of the services' metrics by Prometheus. |
| `email.provider` (`brevo`), `email.fromAddress`, `email.fromName` | Transactional email; the provider key will be a secret. |
| `services[].provides: postgres`, `services[].uses` | A PostgreSQL in the stack - its own LXC per environment, its data on a named volume - and the applications that use it, each with its own role and schema on it, which get `DATABASE_URL` and `PG*` ([ADR-0030](../decisions/0030-postgresql-application.md)). A provider has exactly one volume, and no `port`, `public` or `healthcheck`. |

`provides` and `uses` are tracked in
[urbex-cli#43](https://github.com/urbforge/urbex-cli/issues/43).

## What changes take effect how

| Change | Takes effect with |
|---|---|
| Code | A push to `main` (staging); then `urbex release` and `urbex promote` (prod). |
| `port`, `healthcheck` | `urbex deploy <env>` (it regenerates the compose files). |
| `runtime`, `dockerfile` | `urbex apply <env>` (it updates the Build), then the next push to `main`. |
| `version` of an application from an image | `urbex deploy <env> --app <name> --update` in each environment, or `urbex deploy staging --app <name> --update` followed by `urbex promote`. |
| `environments` | `urbex apply <env>` for an environment added; an environment removed from the list is not destroyed: run `urbex destroy <env>` before removing it. |
| `resources` | `urbex plan <env>`, then `urbex apply <env>`. |
| `volumes` | `urbex apply <env>`, which adds a new named volume and grows a bigger one. A new share needs the operator's `pct set` first. |
| A new service | `urbex apply <env>` in each environment. |
| `public` | `urbex apply <env>` (it routes or unroutes the service). |
| `frontend` added | `urbex apply <env>` in each environment. |
| A removed service | Not handled: `urbex destroy <env>` and `apply` again, or remove its LXC, Stack, and folder by hand. |
| `env` | Nothing, once the environment exists: edit its `config.env` in the GitOps repo. |
| `observability.logs` | `urbex apply <env>` (it installs or removes the log agent). |
