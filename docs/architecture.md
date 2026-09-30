# Architecture

## Overview

```mermaid
flowchart TB
    subgraph LLM["Dev / LLM agent (Claude Code, Codex)"]
        CLI[urbex CLI]
    end

    subgraph AppRepo["App repo (on Gitea)"]
        Manifest[urbex.yaml]
        Code[App code]
    end

    subgraph GitOpsRepo["GitOps repo (on Gitea)"]
        TF[Terraform/OpenTofu]
        ANS[Ansible]
        SEC[Encrypted secrets - SOPS+age]
    end

    subgraph Proxmox["Proxmox server"]
        subgraph Base["Base services LXCs"]
            Gitea
            Komodo
            Technitium[Technitium DNS]
            Keycloak
            Prom[Prometheus + Grafana + Loki]
        end
        subgraph Staging["Per-project LXC - staging"]
            SvcS[service container + Periphery]
        end
        subgraph Prod["Per-project LXC - production"]
            SvcP[service container + Periphery]
        end
    end

    subgraph Edge["Public ingress"]
        CF[Cloudflare Tunnel]
    end

    subgraph Frontend["Frontend"]
        Pages[Cloudflare Pages - web]
        FB[Firebase - mobile]
    end

    CLI -->|reads/writes| Manifest
    CLI -->|bootstrap / plan / apply| TF
    CLI -->|declares builds, deployments, webhooks| Komodo
    Code -->|merge into staging / main: webhook| Komodo
    TF -->|provisions| Base
    TF -->|provisions| Staging
    TF -->|provisions| Prod
    ANS -->|configures| Base
    ANS -->|configures| Staging
    ANS -->|configures| Prod
    Gitea -->|GitOps repo + app repo| GitOpsRepo
    Komodo -->|builds staging branch, deploys| SvcS
    Komodo -->|builds main branch, deploys| SvcP
    Technitium -->|resolves internal names| Base
    Technitium -->|resolves internal names| Staging
    Technitium -->|resolves internal names| Prod
    Keycloak -->|SSO| Base
    Keycloak -->|OIDC + roles| SvcS
    Keycloak -->|OIDC + roles| SvcP
    CF -->|routes without exposed ports| Staging
    CF -->|routes without exposed ports| Prod
    Code -->|build| Pages
    Code -->|build| FB
```

## Components

### urbex CLI

The project's main interface (see
[ADR-0001](decisions/0001-cli-first-interface.md)). Portable: works with
any agent that has shell access (Claude Code, Codex, or a human). Main
commands (draft, to be refined during technical design):

| Command | Purpose |
|---|---|
| `urbex bootstrap` | Provisions the base services on a fresh Proxmox (Gitea, Komodo, Technitium, Keycloak, Prometheus/Grafana/Loki) and initializes the GitOps repo. See [ADR-0006](decisions/0006-bootstrap-command.md). |
| `urbex init` | Generates/validates `urbex.yaml` in the app repo, typically run by the LLM after analyzing the project code. |
| `urbex plan <env>` | Computes the infrastructure changes needed (Terraform diff + Ansible config) for an environment, without applying them. |
| `urbex apply <env>` | Applies the planned changes: creates/updates LXCs, connects them to Komodo, declares the environment's builds/deployments and its Gitea webhook, and runs a first deploy. Still to come: DNS, ingress, Keycloak/Grafana registration. |
| `urbex deploy <env>` | Re-syncs the environment's Komodo resources from `urbex.yaml` and has Komodo build and deploy its branch now. |
| `urbex promote` | Opens the `staging` → `main` pull request on Gitea (`--merge` to merge it), which deploys production. |
| `urbex status` | Current status of a project/environment (LXCs, what Komodo is running; later DNS and certificates). |
| `urbex destroy <env>` | Removes an environment's infrastructure. |

### App manifest (`urbex.yaml`)

Lives in the app repo, not in the GitOps repo: it declares what the app
needs, maintained by the same LLM that writes the app's code. See
[ADR-0002](decisions/0002-app-manifest-in-app-repo.md) and the full schema
in [`manifest-spec.md`](manifest-spec.md).

### Provisioning: Terraform/OpenTofu + Ansible

Terraform/OpenTofu creates/destroys LXCs on Proxmox (resources, network,
storage) with tracked state; Ansible configures the inside of the LXCs
(Docker, the Komodo Periphery agent, later hardening and joining
Technitium/Keycloak). LXCs run Debian 13. See
[ADR-0003](decisions/0003-terraform-ansible-provisioning.md).

### GitOps: repo on Gitea + Komodo

All infrastructure (Terraform definitions, Ansible playbooks, encrypted
secrets, base service manifests, and the Komodo resources declared for
each project) is versioned in a GitOps repo hosted on a self-hosted Gitea
instance on the same Proxmox. App repos live on the same Gitea.

Komodo is the build and rollout engine: it builds each service's image
from the app repo, pushes it to Gitea's container registry, and runs it
on the service's LXC through the Periphery agent installed there. See
[ADR-0004](decisions/0004-gitops-gitea-komodo.md),
[ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md), and
[ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md).

### Ingress: Cloudflare Tunnel

No ports are publicly exposed on the Proxmox server: traffic to
staging/prod goes through a Cloudflare tunnel to the internal LXCs.
Consistent with using Cloudflare Pages for the web frontend. See
[ADR-0005](decisions/0005-cloudflare-tunnel-ingress.md).

### Internal DNS: Technitium

A dedicated LXC running Technitium DNS resolves names between services on
the Proxmox network (e.g. `api.staging.<project>.internal`). The public
domain used for exposed endpoints is **configurable per deployment**, not
hardcoded in the Urbex project. See
[ADR-0007](decisions/0007-technitium-configurable-domain.md).

### Identity: Keycloak

A single Keycloak, three uses:

1. SSO for admin UIs (Komodo, Grafana, Gitea, Technitium).
2. OIDC provider for dev apps (apps register as clients).
3. Service APIs are protected by roles defined in Keycloak.

Each project gets its own Keycloak realm, separate from the `platform`
realm used for admin SSO. See
[ADR-0008](decisions/0008-keycloak-scope.md) and
[ADR-0014](decisions/0014-keycloak-realm-per-project.md).

### Observability: Prometheus + Grafana + Loki

Prometheus/Grafana cover the explicitly requested metrics. **Loki +
Promtail** complete the stack for the explicitly requested "logging",
running on the same base-services LXC. See
[ADR-0004](decisions/0004-gitops-gitea-komodo.md#logging-note).

### Environment topology

One LXC per service per environment (staging and production are always
isolated on separate LXCs). See
[ADR-0009](decisions/0009-one-lxc-per-service-per-env.md).

### Staging → production promotion

One branch per environment: merging a pull request into `staging` deploys
staging, merging into `main` deploys production - a Gitea webhook has
Komodo build and roll out the branch. Promotion is a pull request from
`staging` into `main`. See
[ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md).

### Secrets

SOPS + age to encrypt secrets committed to the GitOps repo in v1; optional
HashiCorp Vault support planned for v2+. See
[ADR-0011](decisions/0011-secrets-sops-age.md).

### Platform configuration and credentials

Non-sensitive platform settings (base domain, Cloudflare zone, Proxmox
connection details, DNS/Keycloak endpoints) live in a versioned
`urbex.platform.yaml` at the root of the GitOps repo. Credentials (API
tokens, the age private key) never enter Git — they live in a local
`~/.urbex/credentials.yaml` (or environment variables) on whichever
machine runs the CLI. See
[ADR-0012](decisions/0012-platform-config-and-credentials.md).

### Transactional email

Apps declare transactional email needs (signup confirmation, password
reset, notifications) via a managed provider — **Brevo** in v1, with the
manifest designed to add more providers later without a breaking change.
The provider API key is handled as a secret (SOPS+age), never written in
the manifest. See
[ADR-0015](decisions/0015-transactional-email-brevo.md).

### Terraform state

State is kept as a local file, encrypted with SOPS+age, and committed to
the GitOps repo under `state/<scope>/terraform.tfstate`. `urbex
plan`/`apply` pull, decrypt, run Terraform, then re-encrypt and push the
result. See
[ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md).

## Bootstrap vs steady-state

Urbex operates in two distinct modes, to solve the chicken-and-egg problem
(the GitOps repo that is supposed to manage Gitea cannot exist before
Gitea exists):

1. **Bootstrap** (`urbex bootstrap`): runs Terraform+Ansible directly
   against the Proxmox API to create the base services and the first
   Gitea repo, then pushes the initial state to it as the GitOps repo.
2. **Steady-state**: from that point on, every change (new project, new
   environment, base service update) goes through a commit to the GitOps
   repo + reconciliation via Komodo/CLI.

See [ADR-0006](decisions/0006-bootstrap-command.md).

The Terraform modules and Ansible playbooks for the base services are
embedded in the `urbex` CLI binary and materialized into the GitOps repo
the first time `urbex bootstrap` runs; a Proxmox pre-flight check aborts
bootstrap if a base-service hostname already exists outside of Terraform's
knowledge, instead of silently adopting or duplicating it. See
[ADR-0017](decisions/0017-embedded-base-infra-assets.md).
