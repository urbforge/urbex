---
name: manifest
description: >
  Create, change and validate urbex.yaml, the manifest that tells Urbex
  what a project runs: its services (Go, Java, Python, a Dockerfile, or a
  published image), ports and healthchecks, resources, staging and
  production, databases and the applications that use them, volumes and
  NAS shares, public services, Keycloak roles, a web frontend. Use when
  the user says "write the urbex.yaml", "add a service", "add a
  PostgreSQL database", "make the API public", "keep this app's data",
  "give it more memory", "deploy this Docker image with Urbex", or edits
  or asks about urbex.yaml.
---

# urbex.yaml

`urbex.yaml` is at the root of the project's repository. Every field is
in the [manifest reference](${CLAUDE_PLUGIN_ROOT}/docs/reference/manifest.md),
and the schema it's validated against is
`${CLAUDE_PLUGIN_ROOT}/schemas/urbex.schema.json`. Read the reference's
section for each field you write: unknown fields are errors, and several
fields depend on each other.

What differs per environment (the version that runs, configuration,
secrets) is not in `urbex.yaml` but in the GitOps repo; see the `cli`
skill.

## Writing a new one

1. **Read the repository** before asking anything: the language and
   build files (`go.mod` and `cmd/<name>/`, `pom.xml`, `build.gradle`,
   `gradlew`, `requirements.txt` and `main.py`, `Dockerfile`s,
   `compose.yaml`, `package.json`), the port the code listens on and how
   it reads it, a health endpoint, the database it connects to and the
   variables it reads for it, what it writes to disk.
2. **Map each deployable part to a service**:

   | What you find | Service |
   |---|---|
   | Go module, `go build ./cmd/<service>` or `.` | `runtime: go` |
   | Maven or Gradle project, one runnable jar | `runtime: java` |
   | `requirements.txt` and `main.py` | `runtime: python` |
   | Anything else with a Dockerfile | `runtime: docker`, `dockerfile: <path>` |
   | A published image to run as it is (PostgreSQL, Redis, a CMS) | `image: <registry/name>` and `version: "<tag>"` (quoted) |
   | A static site or SPA built with npm | `frontend` (`type: web`, `provider: cloudflare-pages`); needs Cloudflare and at least one service |

   `compose.yaml` services map one to one: `build:` becomes a `docker`
   runtime, `image:` an application from a published image, named volumes
   become `volumes`, `depends_on` becomes `uses`.
3. **Check the conventions** of the runtimes in the reference
   (*Runtimes*): the service must listen on `$PORT`; with a `healthcheck`
   the image needs `wget` (Urbex's images have it). If the code listens on
   a fixed port, say so and propose reading `PORT`, or use that port.
4. **Propose, don't ask.** Decide every value from the code and these
   defaults, and let the user correct them in step 6: the project name
   from the repository's name (3-40 characters, lowercase, digits, `-`;
   it names everything on the platform and can't change later), staging
   and prod (`environments: [prod]` only for an app with production only,
   such as a self-hosted tool from a published image), nothing `public`
   unless the app is meant for the internet and Cloudflare is
   configured, the default resources unless the code clearly needs more
   (a JVM: `memory: 2Gi`), `10Gi` per named volume. Ask only when the
   code leaves two real choices open.
5. **Write it**, then validate:
   ```sh
   urbex-op 'cd /work/projects/<project> && urbex init'     # or: urbex init, natively
   ```
   It lists every error. With no `urbex.yaml`, `urbex init --project
   <name>` writes a starter one; you can also write the file directly.
6. **Show it** to the user with a line per value you chose and why, ask
   for one confirmation, and commit it when they agree.

A minimal service:

```yaml
apiVersion: urbex/v1
project: acme-app
services:
  - name: api
    runtime: go
    port: 8080
    healthcheck: /healthz
```

## Patterns

Read the reference's section before using each.

- **A database and its users** ([linked applications](${CLAUDE_PLUGIN_ROOT}/docs/reference/manifest.md#linked-applications)):
  a `postgres` provider has `provides: postgres`, exactly one named
  volume, and no `port`, `public` or `healthcheck`. Each application
  that uses it lists it in `uses` and gets `DATABASE_URL`, `PGHOST`,
  `PGPORT`, `PGDATABASE`, `PGUSER` and `PGPASSWORD`. If the code reads
  other names, map them in `env` with references such as
  `${db.url}`. Check [known limitations](${CLAUDE_PLUGIN_ROOT}/docs/known-limitations.md#projects-and-deploys)
  for what Urbex doesn't create yet on the database, and tell the user.
- **Order between applications**: `uses` also makes an application
  wait until what it uses is healthy. An application used by others needs
  a `port` and a `healthcheck`, or an interface; `ready_within` (default
  `60s`) is how long it may take to be healthy.
- **Data**: a named volume (`{ name: data, path: /data, size: 10Gi }`)
  survives redeploys and updates, is in Proxmox's backups, can grow but
  never shrink. A share (`{ share: media, path: /media, readOnly: true }`)
  must be declared in the platform's `storage.shares` first, and the
  operator runs a `pct set` as root on the node that `apply` prints.
- **Public on the internet**: `public: true` on a service with a `port`,
  through the platform's Cloudflare Tunnel. Its own authentication is its
  only gate: say so. Without Cloudflare in the platform it can't be
  public.
- **Login**: `auth.keycloak: true` and `auth.roles: [...]`. The service
  gets the realm and issuer; staging gets a test user per role (`urbex
  users staging`).
- **Initial configuration**: `env.staging` and `env.prod` are written
  once, when the environment is first applied, never again. Never put
  secrets there: use `urbex secret` (see the `cli` skill).
- **Resources**: `resources.cpu`, `memory` (`1Gi` default), `disk`
  (`5Gi` default) of the service's LXC.

## Changing one

After editing, run `urbex init` to validate it, then tell the user which
command makes the change take effect, from the reference's table
[What changes take effect how](${CLAUDE_PLUGIN_ROOT}/docs/reference/manifest.md#what-changes-take-effect-how).
The ones that surprise:

- `port` or `healthcheck`: `urbex deploy <env>`, no `apply`.
- `version` of an application from an image: nothing by itself; `urbex
  deploy <env> --app <name> --update`, staging first, then `urbex
  promote`.
- `env`: nothing, once the environment exists: edit its `config.env` in
  the GitOps repo instead.
- A removed service or application: `apply` refuses to delete an LXC with
  data unless `--delete-data`, and deletes the data with it. Ask the user
  first.
- A smaller volume `size`, or a change that would replace an LXC with
  volumes: refused. Don't try to work around it.
- `project`: a different project, not a rename. Don't change it on a
  deployed project.

Never edit the generated files in the GitOps repo (`compose.yaml`,
`version.env`) to change what `urbex.yaml` says: change `urbex.yaml` and
run the command.
