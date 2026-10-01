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
- [`frontend`](#frontend)
- [`domain`, `observability`, `email`, `auth`](#declared-not-yet-acted-on)
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
| `frontend` | object | | See [`frontend`](#frontend). |
| `domain`, `observability`, `email` | object | | Validated, [not acted on yet](#declared-not-yet-acted-on). |

Unknown fields are errors.

## `services[]`

Each service gets, per environment, its own LXC
(`<project>-<service>-<env>`), its own Komodo Build
(`<project>-<service>`, shared by the environments), its own image
(`<registry>/<org>/<project>-<service>`), and its own folder in the
GitOps repo.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | required | 2-40 characters, lowercase letters, digits, `-`, starting with a letter. Unique in the project. |
| `runtime` | `go`, `java`, `python`, `docker` | required | How the image is built - see [runtimes](#runtimes). |
| `dockerfile` | path | required with `docker` | Path of the Dockerfile from the repo root; its directory is the build context. Ignored for other runtimes. |
| `port` | 1-65535 | required | The port the service listens on. The container gets `PORT` set to it, and it is published on the LXC's IP at the same number. |
| `healthcheck` | HTTP path | none | Path probed every 30 s from inside the container (`wget -q --spider http://localhost:<port><path>`); three failures mark the container unhealthy, and `urbex` waits for healthy. Without it, a running container counts. |
| `resources.cpu` | integer ≥ 1 | `1` | Cores of the LXC. |
| `resources.memory` | `<n>Mi` or `<n>Gi` | `1Gi` | Memory of the LXC. |
| `resources.disk` | `<n>Mi` or `<n>Gi` | `5Gi` | Root disk of the LXC, rounded up to whole GiB. |
| `env.staging`, `env.prod` | map of strings | | **Initial** configuration of the service in that environment: written to its `config.env` in the GitOps repo when the environment is first applied, and never again. Change `config.env` after that. Never put secrets here - use `urbex secret`. |
| `auth.keycloak`, `auth.roles` | | | Validated, [not acted on yet](#declared-not-yet-acted-on). |

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

## `frontend`

```yaml
frontend:
  type: web                    # web | mobile
  provider: cloudflare-pages   # cloudflare-pages for web, firebase for mobile
  buildCommand: npm run build
  outputDir: dist
```

All four fields are required; `web` must use `cloudflare-pages` and
`mobile` `firebase`.

> ⚠️ Validated, not acted on: Urbex doesn't build or deploy frontends
> yet. Deploy them with the provider's own tooling.

## Declared, not yet acted on

These are validated, so a manifest can already state them, but no
command uses them yet - see [`status.md`](../status.md):

| Field | Meaning, once implemented |
|---|---|
| `domain.subdomain` | DNS name under the platform's domain, and ingress through Cloudflare Tunnel. |
| `observability.metrics`, `observability.logs` | Scraping by Prometheus, log shipping to Loki. |
| `email.provider` (`brevo`), `email.fromAddress`, `email.fromName` | Transactional email; the provider key will be a secret. |
| `services[].auth.keycloak`, `services[].auth.roles` | A Keycloak client for the service, and the roles it checks. |

## What changes take effect how

| Change | Takes effect with |
|---|---|
| Code | A push to `main` (staging); then `urbex release` and `urbex promote` (prod). |
| `port`, `healthcheck` | `urbex deploy <env>` (it regenerates the compose files). |
| `runtime`, `dockerfile` | `urbex apply <env>` (it updates the Build), then the next push to `main`. |
| `resources` | `urbex plan <env>`, then `urbex apply <env>`. |
| A new service | `urbex apply <env>` in each environment. |
| A removed service | Not handled: `urbex destroy <env>` and `apply` again, or remove its LXC, Stack, and folder by hand. |
| `env` | Nothing, once the environment exists: edit its `config.env` in the GitOps repo. |
