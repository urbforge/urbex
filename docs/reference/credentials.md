# Credentials reference

Every value `urbex` reads from an environment variable, from
`~/.urbex/credentials.yaml`, or from `urbex.platform.yaml` - what it's
for, whether any command actually checks it yet, and exactly how to get
it. See [ADR-0012](../decisions/0012-platform-config-and-credentials.md)
for the design (non-sensitive config in `urbex.platform.yaml`, secrets
never in the GitOps repo).

## Required today

These are enforced - `urbex bootstrap`/`plan`/`apply`/`destroy` refuse
to run without them (`credentials.MissingForProvisioning()` in
`urbex-cli`). `urbex release`, `deploy`, `promote`, and `secret` don't
need the Proxmox token, since they only talk to Gitea and Komodo - but
they do need the
[generated platform credentials](#generated-by-urbex-bootstrap).

### Proxmox API token

- **Env var / credentials file key:** `URBEX_PROXMOX_TOKEN` /
  `proxmoxToken`
- **Used by:** Terraform's Proxmox provider (every command that
  provisions/destroys LXCs) and `urbex status`'s Proxmox query.
- **Format:** `user@realm!tokenid=secret`, e.g.
  `root@pam!urbex=1234abcd-5678-...`.
- **How to get one:** Proxmox web UI → *Datacenter* → *Permissions* →
  *API Tokens* → *Add*. Pick or create a user, give the token an ID
  (e.g. `urbex`), and decide on **Privilege Separation**: unchecked, the
  token inherits the user's full permissions (simplest for a personal,
  single-operator setup); checked, you must grant the token its own role
  separately. Copy the secret shown once - Proxmox never shows it again.
- **Least privilege:** give the permissions to a group, scope them to
  a resource pool, and put the users (whose tokens have privilege
  separation off, so they inherit them) in the group. As root on the
  Proxmox host:
  ```sh
  pveum group add urbex --comment "Urbex operators: pool urbex only"
  pveum pool add urbex                                  # if it doesn't exist
  pveum pool modify urbex --storage local-zfs,local     # root disks, templates
  pveum acl modify /pool/urbex --groups urbex --roles PVEVMAdmin,PVEDatastoreUser,PVEPoolUser
  pveum acl modify /sdn/zones/localnetwork/vmbr0 --groups urbex --roles PVESDNUser
  pveum user modify <user>@pve --groups urbex --append 1
  ```
  `PVEVMAdmin` manages the pool's LXCs, `PVEDatastoreUser` allocates
  disks and reads templates on the pool's storages, `PVEPoolUser` lets
  the token see the pool. `PVESDNUser` on the bridge is needed to attach
  an LXC's network interface - without it, Proxmox refuses with
  `Permission check failed (/sdn/zones/localnetwork/vmbr0, SDN.Use)`.
  Nothing else on the node is needed. Avoid using a `root@pam` token
  for anything beyond a quick personal test.
- **Pool-scoped tokens:** if the token's permissions are granted on a
  resource pool, set `proxmox.pool` in `urbex.platform.yaml` so every
  LXC is created in it - otherwise the token can't see or manage the
  containers it just created.
- **keyctl:** Docker inside an unprivileged LXC needs the `nesting` and,
  on most hosts, `keyctl` features. Proxmox only lets `root@pam` change
  features other than `nesting`, so with any other token set
  `proxmox.keyctl: false` and, if Docker then fails with overlayfs
  `permission denied` errors, have an administrator enable it once per
  container (`pct set <vmid> --features nesting=1,keyctl=1`).
- **Self-signed certificate:** set `proxmox.insecure: true` if the node
  still uses Proxmox's default certificate.

### SSH key

- **Where it's set:** `proxmox.sshPublicKey` in `urbex.platform.yaml`
  (the public key itself, not a credential file entry - only the
  matching private key needs to stay off the GitOps repo).
- **Used by:** the Terraform LXC module (installs it as the `root`
  user's authorized key at container creation) and Ansible (connects
  over SSH to configure every LXC - during `bootstrap` and `apply` only;
  deploying never needs SSH).
- **How to get one:** generate a dedicated keypair rather than reusing a
  personal one:
  ```sh
  ssh-keygen -t ed25519 -f ~/.ssh/urbex -C urbex
  ```
  Put the **public** key's contents in `urbex.platform.yaml`. Load the
  **private** key into an SSH agent on whichever machine runs `urbex`
  commands (`ssh-add ~/.ssh/urbex`) - neither Terraform's provider nor
  Ansible can prompt for a passphrase.

### age keypair

- **Env var / credentials file key:** `URBEX_AGE_KEY` / `ageKey`
- **Used by:** every secret in the GitOps repo. They are encrypted with
  SOPS for this key ([ADR-0011](../decisions/0011-secrets-sops-age.md)):
  `urbex bootstrap` writes its public half to `.sops.yaml`, `urbex
  secret` encrypts and decrypts with it, and `urbex apply` hands it to
  the Periphery agent on each project LXC, which decrypts a service's
  secrets when Komodo deploys it
  ([ADR-0020](../decisions/0020-trunk-releases-gitops-environments.md)).
  `bootstrap` rejects a value that isn't a valid age secret key.
- **How to get one:** install [age](https://github.com/FiloSottile/age)
  (`brew install age`, or your distro's package), then:
  ```sh
  age-keygen -o urbex.key
  ```
  The file's `AGE-SECRET-KEY-1...` line is `URBEX_AGE_KEY`. Keep the
  file itself somewhere durable outside the GitOps repo: Urbex has no
  way to recover a lost age key, and losing it means losing every secret
  encrypted to it.
- **Editing secrets without urbex:** with the key exported as
  `SOPS_AGE_KEY`, `sops environments/<env>/<project>/<service>/secrets.sops.env`
  opens the decrypted file in your editor.

### sops (only for `urbex secret`)

Not a credential, but the one extra tool: `urbex secret set|unset` call
the [`sops`](https://github.com/getsops/sops) binary on the machine you
run them on. The project LXCs get their own copy from `urbex apply`.

## Generated by `urbex bootstrap`

You never create these by hand: `urbex bootstrap` generates them and
writes them to `~/.urbex/credentials.yaml` (mode 0600), keeping any that
already exist when re-run. An environment variable with the same name
still takes precedence. These reach the LXCs only through Ansible's
environment, never through a file in the GitOps repo. Copy the file
(like any secret) to every machine that runs `urbex` commands - though
deploying needs none of it: a commit to the GitOps repo is enough.

| Credentials file key | Env var | What it is |
|---|---|---|
| `giteaAdminPassword` | `URBEX_GITEA_ADMIN_PASSWORD` | Password of `urbex-admin`, Gitea's admin user |
| `giteaToken` | `URBEX_GITEA_TOKEN` | Gitea token (repos, org, packages) used by the CLI (repos, webhooks, release tags, pushing the GitOps repo) and by Komodo (cloning, pushing and pulling images) |
| `komodoAdminPassword` | `URBEX_KOMODO_ADMIN_PASSWORD` | Password of `urbex-admin`, Komodo's initial admin |
| `komodoApiKey` / `komodoApiSecret` | `URBEX_KOMODO_API_KEY` / `URBEX_KOMODO_API_SECRET` | Komodo API key the CLI declares builds and stacks with |
| `komodoOnboardingKey` | `URBEX_KOMODO_ONBOARDING_KEY` | Key the Periphery agent on each project LXC registers itself in Komodo with |
| `komodoWebhookSecret` | `URBEX_KOMODO_WEBHOOK_SECRET` | Secret Gitea signs its webhooks to Komodo with |
| `komodoDbPassword`, `komodoJwtSecret` | `URBEX_KOMODO_DB_PASSWORD`, `URBEX_KOMODO_JWT_SECRET` | Komodo's internal database password and signing secret |
| `keycloakAdminPassword` | `URBEX_KEYCLOAK_ADMIN_PASSWORD` | Keycloak's bootstrap admin password |
| `grafanaAdminPassword` | `URBEX_GRAFANA_ADMIN_PASSWORD` | Grafana's `admin` password |

`urbex apply`, `release`, `deploy`, `promote`, and `secret` refuse to
run without the Gitea token, the Komodo API key, the onboarding key, and
the webhook secret (`credentials.MissingForPlatform()`).

Bootstrap also stores the Gitea token in Komodo, as the secret variable
`URBEX_GITEA_TOKEN`: the `urbex-release` Action uses it to look up
images and to commit staging's new version to the GitOps repo. Komodo
never shows a secret variable's value in its UI or logs. See
[platform resources](platform-resources.md).

⚠️ Rotating generated credentials isn't supported yet: re-running
bootstrap keeps every value already in the file, and changing one by
hand (the Komodo database password, for one) can leave a service unable
to start.

## Required with Cloudflare

### Cloudflare API token

- **Env var / credentials file key:** `URBEX_CLOUDFLARE_TOKEN` /
  `cloudflareToken`. The account and zone IDs are not secret: they go in
  `urbex.platform.yaml` (`cloudflare.accountId`, `cloudflare.zoneId`).
- **Required** when `urbex.platform.yaml` configures Cloudflare, by
  `bootstrap`, `teardown`, `apply`, `destroy`
  ([ADR-0022](../decisions/0022-cloudflare-tunnel-access-workers.md)).
  Bootstrap also stores it in Komodo, as a secret variable, for the web
  frontends' deploys.
- **How to get it:** Cloudflare dashboard → *Manage account* → *Account
  API tokens* → *Create token* → custom, with:

  | Scope | Permission |
  |---|---|
  | Account | Cloudflare Tunnel: Edit |
  | Account | Workers Scripts: Edit |
  | Account | Access: Apps and Policies: Edit |
  | Account | Access: Organizations, Identity Providers, and Groups: Edit - only if the Zero Trust organization has no One-time PIN login yet; urbex adds it |
  | Zone (your zone) | DNS: Edit |
  | Zone (your zone) | Workers Routes: Edit |
  | Zone (your zone) | Zone: Read |

  The account IDs are in the dashboard's URL and on the zone's
  *Overview* page. A Zero Trust organization must exist (Zero Trust →
  first visit, Free plan is enough).

## Declared, but not required by any command yet

These exist as fields in `urbex.platform.yaml`/`~/.urbex/credentials.yaml`
because the design anticipates needing them, but no current `urbex`
command reads or checks them. You can leave them unset today without
anything complaining. See [`status.md`](../status.md) for which priority
item each is waiting on.

### Brevo API key

- **Env var / credentials file key:** none defined yet - there's no
  `URBEX_BREVO_*` variable in `urbex-cli` today, since nothing consumes
  it.
- **Will be used by:** apps that declare `email.provider: brevo` in
  their `urbex.yaml` ([ADR-0015](../decisions/0015-transactional-email-brevo.md))
  - not implemented yet.
- **How to get one (when you need it):** Brevo dashboard → *SMTP & API*
  → *API Keys* → *Generate a new API key*.

## Summary

| Credential | Env var | Required today? |
|---|---|---|
| Proxmox API token | `URBEX_PROXMOX_TOKEN` | ✅ yes |
| SSH private key | (SSH agent, not an env var) | ✅ yes |
| age keypair | `URBEX_AGE_KEY` | ✅ yes (encrypts every secret) |
| Gitea/Komodo/Keycloak/Grafana passwords, tokens, keys | `URBEX_GITEA_*`, `URBEX_KOMODO_*`, ... | ✅ generated by `urbex bootstrap` |
| Cloudflare API token | `URBEX_CLOUDFLARE_TOKEN` | ✅ with Cloudflare configured |
| Brevo API key | *(none defined)* | ❌ not yet |
