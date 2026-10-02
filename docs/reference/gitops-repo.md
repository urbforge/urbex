# GitOps repo reference

The GitOps repo (`<org>/gitops` on Gitea) is the platform's single
source of truth: how the infrastructure is built, and what every
environment of every project runs. Komodo deploys from it; `urbex`
writes to it; people can too - every change is a commit.

- [Layout](#layout)
- [A service's folder](#a-services-folder)
  - [`version.env`](#versionenv)
  - [`config.env`](#configenv)
  - [`secrets.sops.env`](#secretssopsenv)
  - [`compose.yaml`](#composeyaml)
- [How a change is deployed](#how-a-change-is-deployed)
- [Who writes what](#who-writes-what)
- [Infrastructure files](#infrastructure-files)

## Layout

```
gitops/
├── urbex.platform.yaml            platform config (reference/platform-config.md)
├── .sops.yaml                     which key secrets are encrypted for
├── environments/
│   ├── staging/
│   │   └── acme-app/
│   │       ├── api/
│   │       │   ├── version.env        what runs
│   │       │   ├── config.env         configuration
│   │       │   ├── secrets.sops.env   secrets, encrypted
│   │       │   └── compose.yaml       how it runs (generated)
│   │       └── worker/ ...
│   └── prod/
│       └── acme-app/ ...
├── state/allocations.json         VMID/IP of every project LXC
├── state/known_hosts              SSH host keys of the LXCs
├── terraform/
│   ├── base/                      the base services' LXCs, and their state
│   ├── modules/lxc/               the LXC module everything uses
│   ├── project/                   template of a project environment
│   └── projects/<project>/<env>/  each project environment's LXCs, and their state
└── ansible/
    ├── playbook.yml, inventory.yml        base services
    ├── project-playbook.yml               project LXCs
    ├── projects/<project>/<env>/          their inventories
    └── roles/                             gitea, komodo, periphery, ...
```

Only `environments/` is meant to be edited by hand. `terraform/` and
`ansible/` are written by `urbex` from files embedded in the CLI, so a
newer CLI updates them on its next `bootstrap`, `plan` or `apply`.

## A service's folder

`environments/<env>/<project>/<service>/` describes one service in one
environment. It is created by `urbex apply <env>`, removed by `urbex
destroy <env>`, and deployed by the Komodo Stack
`<project>-<service>-<env>` onto the LXC of the same name.

### `version.env`

What the service runs here.

```sh
VERSION=1.4.2
```

```sh
VERSION=8d41b07
TRACK=main
```

| Key | Meaning |
|---|---|
| `VERSION` | The image tag to run: a release (`1.4.2`, from the git tag `v1.4.2`) or a commit of `main` (its 7-12 character short hash). Absent: the service isn't deployed. |
| `TRACK` | Only value: `main`. After every build of `main`, the `urbex-release` Action sets `VERSION` to the new commit in every `version.env` that has it, in a single commit (`urbex: <project> main@<hash> to staging`). Without it, `VERSION` only changes when someone changes it. |

Staging's files are created with `TRACK=main`, prod's without - see
[ADR-0021](../decisions/0021-staging-follows-main.md). `urbex deploy
--version` removes `TRACK`, `urbex deploy --follow-main` adds it, and so
can you. Lines starting with `#` are comments; key order doesn't matter.

### `config.env`

The service's configuration in this environment: `KEY=value` lines,
passed to the container as environment variables.

```sh
LOG_LEVEL=info
FEATURE_CHECKOUT=on
```

Created from `urbex.yaml`'s `env.<env>` block on the first `apply`, then
yours: `urbex` never rewrites it. Values are taken literally, docker
compose `env_file` style: no quotes needed, no variable expansion. No
secrets here - the file is plain text in Git.

### `secrets.sops.env`

The service's secrets in this environment: a dotenv file encrypted with
[SOPS](https://github.com/getsops/sops) for the platform's age key.
Values are encrypted, names are not:

```sh
STRIPE_KEY=ENC[AES256_GCM,data:...,type:str]
sops_age__list_0__map_recipient=age1...
sops_lastmodified=2026-10-01T10:00:00Z
sops_mac=ENC[AES256_GCM,data:...,type:str]
sops_version=3.10.2
```

Manage it with `urbex secret` or `sops` (see the
[cookbook](../cookbook.md#edit-secrets-with-sops-directly)). Without
secrets it holds a placeholder comment; keep the file, the Stack
expects it.

On deploy, Komodo runs compose through `/opt/urbex/bin/urbex-compose`
on the LXC, which decrypts the file with the age key the LXC's agent
holds (`sops exec-file`) and hands the plaintext to compose without
writing it to disk. Secrets and configuration with the same name: the
secret wins.

`.sops.yaml` at the root of the repo sets the recipient for every
`secrets.sops.env`, so `sops` encrypts new files correctly:

```yaml
creation_rules:
  - path_regex: (^|/)secrets\.sops\.env$
    age: age1...
```

### `compose.yaml`

How the service runs: a Docker Compose file generated from `urbex.yaml`
by `urbex apply` and `urbex deploy`, overwritten each time - don't edit
it.

```yaml
services:
  app:
    image: 192.168.1.200:3000/urbex/acme-app-api:${VERSION}
    restart: unless-stopped
    env_file:
      - config.env
      - path: ${URBEX_SECRETS_FILE:-secrets.env}
        required: false
    environment:
      PORT: "8080"
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
```

`VERSION` comes from `version.env`; the image is
`<gitea>/<org>/<project>-<service>`.

## How a change is deployed

1. A commit lands on `main` of the GitOps repo (a push, a merged pull
   request, `urbex`, or the `urbex-release` Action).
2. Gitea calls Komodo's webhook for the `urbex-gitops` Procedure, which
   runs *deploy if changed* on every Urbex Stack.
3. Each Stack compares its folder with what it last deployed. Only a
   Stack whose `compose.yaml`, `version.env`, `config.env` or
   `secrets.sops.env` changed is redeployed (`docker compose pull` and
   `up -d` on its LXC); an unrelated commit restarts nothing.
4. The same Procedure also runs every 15 minutes, which catches anything
   a webhook missed.

Komodo caches the repo for a few seconds after reading it: a commit
pushed within ~5 seconds of the previous one can wait for the next run.
`urbex` commands account for this.

Only `main` is deployed: other branches are for pull requests.

## Who writes what

| Path | Written by | When |
|---|---|---|
| `urbex.platform.yaml` | you | Once, then when the platform changes. |
| `.sops.yaml` | `urbex bootstrap` | Every run (from the age key). |
| `…/version.env` | `urbex apply` (new staging), `urbex deploy`, `urbex promote`, the `urbex-release` Action (when `TRACK=main`), you | Each deploy. |
| `…/config.env` | `urbex apply` (first time), you | When configuration changes. |
| `…/secrets.sops.env` | `urbex apply` (placeholder), `urbex secret`, `sops` | When secrets change. |
| `…/compose.yaml` | `urbex apply`, `urbex deploy` | When `urbex.yaml` changes. |
| `state/allocations.json` | `urbex plan`, `apply`, `destroy` | New and removed LXCs. |
| `state/known_hosts` | Ansible (through `bootstrap`, `apply`), `urbex` | New and removed LXCs. |
| `terraform/`, `ansible/` | `urbex bootstrap`, `plan`, `apply`, `destroy` | Every run. |

Since `urbex` and Komodo both push, pull before you edit by hand
(`git pull --rebase`). `urbex` itself pulls, rebasing its own commits,
before every change.

## Infrastructure files

- **`terraform/base/`** - the base-service LXCs.
  **`terraform/projects/<project>/<env>/`** - one environment's LXCs.
  Each has its `terraform.tfstate` committed next to it
  ([ADR-0013](../decisions/0013-terraform-state-in-gitops-repo.md)),
  and a `terraform.auto.tfvars.json` with the inputs. The Proxmox token
  is passed through the environment, never written.
- **`ansible/`** - playbooks and roles that configure the LXCs.
  Generated passwords reach them through Ansible's environment, never
  files in the repo.
- **`state/allocations.json`** - the ledger of project LXC addresses:

  ```json
  {
    "entries": {
      "acme-app-api-staging": { "vmid": 9100, "ip": "192.168.1.210" }
    },
    "nextVmid": 9101,
    "nextIpOffset": 211
  }
  ```

- **`state/known_hosts`** - the SSH host keys of the LXCs, which Ansible
  connects to with this file only. An LXC seen for the first time is
  trusted and recorded; one whose key changes is refused. When `urbex`
  creates an LXC that wasn't there (`bootstrap`, `apply`) or destroys one
  (`destroy`, `teardown`), it forgets the key recorded for its address
  first - the address may have belonged to another LXC. Being in the
  repo, the trust is the same on every machine that runs `urbex`. Host
  keys are public: nothing secret here.

The Terraform state and inputs hold no secrets: the LXCs get only the
SSH public key from Terraform; passwords are set by Ansible.
