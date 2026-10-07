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
- **How to get one - commands:** as `root` on the Proxmox host. This
  creates the least-privilege setup Urbex was validated with: a resource
  pool for everything Urbex creates, a group holding the permissions
  (scoped to the pool), and a user in the group whose token inherits
  them.
  ```sh
  # Where Urbex works: a resource pool, with the storages for root disks
  # (local-zfs here) and templates (local) in it.
  pveum pool add urbex --comment "Urbex"
  pveum pool modify urbex --storage local-zfs,local

  # The permissions, on a group: change them here, never per user.
  pveum group add urbex --comment "Urbex operators: pool urbex only"
  pveum acl modify /pool/urbex --groups urbex --roles PVEVMAdmin,PVEDatastoreUser,PVEPoolUser
  pveum acl modify /sdn/zones/localnetwork/vmbr0 --groups urbex --roles PVESDNUser

  # The user Urbex runs as, and its token (privilege separation off: it
  # inherits the group's permissions).
  pveum user add urbex@pve --comment "Urbex CLI" --groups urbex
  pveum user token add urbex@pve cli --privsep 0 --comment "urbex"

  # The Debian 13 template (needs root; the exact name: pveam available --section system).
  pveam update && pveam download local debian-13-standard_13.6-1_amd64.tar.zst
  ```
  `pveum user token add` prints the token's `full-tokenid`
  (`urbex@pve!cli`) and `value` once - Proxmox never shows it again:
  ```sh
  export URBEX_PROXMOX_TOKEN='urbex@pve!cli=<value>'
  ```
  For a person who should operate the platform too, add their user to the
  group (`pveum user modify <user>@pve --groups urbex --append 1`) rather
  than granting anything to the user. Then in `urbex.platform.yaml`:
  `proxmox.pool: urbex`, `proxmox.keyctl: false`, and the bridge in
  `proxmox.network.bridge` (the ACL above names `vmbr0`).
- **What each permission is for:** `PVEVMAdmin` manages the pool's LXCs,
  `PVEDatastoreUser` allocates disks and reads templates on the pool's
  storages, `PVEPoolUser` lets the token see the pool. `PVESDNUser` on
  the bridge is needed to attach an LXC's network interface - without
  it, Proxmox refuses with `Permission check failed
  (/sdn/zones/localnetwork/vmbr0, SDN.Use)`. Nothing else on the node is
  needed. Avoid a `root@pam` token for anything beyond a quick personal
  test.
- **From the web UI instead:** *Datacenter* → *Permissions*: *Pools*,
  *Groups*, *Permissions* → *Add* (group permission, with the paths and
  roles above), *Users*, then *API Tokens* → *Add* with **Privilege
  Separation** unchecked.
- **Checking it:**
  ```sh
  curl -sk -H "Authorization: PVEAPIToken=$URBEX_PROXMOX_TOKEN" \
    https://<proxmox>:8006/api2/json/access/permissions | jq '.data | keys'
  # ["/pool/urbex", "/sdn/zones/localnetwork/vmbr0", "/storage/local", "/storage/local-zfs"]
  ```
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
| `technitiumAdminPassword` | `URBEX_TECHNITIUM_ADMIN_PASSWORD` | Technitium's admin password - only takes effect while Technitium has no configuration yet (its own behavior); see the note below |
| `technitiumToken` | `URBEX_TECHNITIUM_TOKEN` | Technitium API token, minted with the admin password, used to create the zone and the services' DNS records ([ADR-0026](../decisions/0026-technitium-internal-dns-records.md)) |

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

⚠️ `technitiumAdminPassword` is a partial exception: bootstrap always
*generates* a value for it, but Technitium itself only accepts
`DNS_SERVER_ADMIN_PASSWORD` while it has no configuration yet. On a
platform bootstrapped before internal DNS registration existed (or
whose Technitium was set up some other way), the generated password
doesn't match what's actually configured, and minting the API token
fails. Set `technitiumAdminPassword` in `~/.urbex/credentials.yaml` to
Technitium's real admin password yourself before running `urbex
bootstrap` again.

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
- **Permissions:**

  | Scope | Permission (as the API names it) | For |
  |---|---|---|
  | Account | Cloudflare Tunnel Write | the platform's tunnel and its routes |
  | Account | Workers Scripts Write | the web frontends' Workers |
  | Account | Access: Apps and Policies Write | Access in front of Gitea and Komodo |
  | Account | Access: Organizations, Identity Providers, and Groups Write | only to enable the one-time PIN login if Zero Trust has none yet |
  | Zone (yours) | DNS Write | the public hostnames |
  | Zone (yours) | Workers Routes Write | the web frontends' custom domains |
  | Zone (yours) | Zone Read | finding the zone |

  This is the set the API calls Urbex makes need. The token Urbex was
  validated with had a few more (Cloudflare Pages, zone-level ones); if
  a call is refused, Urbex names the missing permission.
  The dashboard shows them as "... Edit"/"... Read". A Zero Trust
  organization must exist (first visit to Zero Trust; the Free plan is
  enough). The account and zone IDs are on the zone's *Overview* page.

- **How to get it - Terraform** (`cloudflare/cloudflare` v5). It looks
  the permissions up by name, so nothing is copied by hand; it
  authenticates with an existing token allowed to create tokens (e.g.
  from the dashboard template *Create Additional Tokens*), in
  `CLOUDFLARE_API_TOKEN`:
  ```hcl
  terraform {
    required_providers {
      cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
    }
  }
  provider "cloudflare" {}

  variable "account_id" { type = string }
  variable "zone_id" { type = string }

  data "cloudflare_account_api_token_permission_groups_list" "all" {
    account_id = var.account_id
  }

  locals {
    group = { for g in data.cloudflare_account_api_token_permission_groups_list.all.result : g.name => g.id }
    account_permissions = [
      "Cloudflare Tunnel Write",
      "Workers Scripts Write",
      "Access: Apps and Policies Write",
      "Access: Organizations, Identity Providers, and Groups Write",
    ]
    zone_permissions = ["DNS Write", "Workers Routes Write", "Zone Read"]
  }

  resource "cloudflare_account_token" "urbex" {
    account_id = var.account_id
    name       = "urbex"
    policies = [
      {
        effect            = "allow"
        permission_groups = [for n in local.account_permissions : { id = local.group[n] }]
        resources         = jsonencode({ "com.cloudflare.api.account.${var.account_id}" = "*" })
      },
      {
        effect            = "allow"
        permission_groups = [for n in local.zone_permissions : { id = local.group[n] }]
        resources         = jsonencode({ "com.cloudflare.api.account.zone.${var.zone_id}" = "*" })
      },
    ]
  }

  output "token" {
    value     = cloudflare_account_token.urbex.value
    sensitive = true
  }
  ```
  ```sh
  terraform apply -var account_id=<account id> -var zone_id=<zone id>
  export URBEX_CLOUDFLARE_TOKEN="$(terraform output -raw token)"
  ```
  A name that doesn't match fails the plan (`Invalid index`) before
  anything is created; the names the account offers are listed by
  ```sh
  curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/<account id>/tokens/permission_groups" | jq -r '.result[].name' | sort
  ```
  Keep the Terraform state private: it holds the token.

- **How to get it - API, with `curl` and `jq`**, the same token and
  permissions, with the same creating token in `CLOUDFLARE_API_TOKEN`:
  ```sh
  ACCOUNT=<account id> ZONE=<zone id>
  API=https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/tokens
  PERMS=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "$API/permission_groups")
  ids() { jq -c --argjson names "$1" '[.result[] | select(.name as $n | $names | index($n)) | {id}]' <<<"$PERMS"; }
  ACC=$(ids '["Cloudflare Tunnel Write","Workers Scripts Write","Access: Apps and Policies Write","Access: Organizations, Identity Providers, and Groups Write"]')
  ZON=$(ids '["DNS Write","Workers Routes Write","Zone Read"]')
  jq -n --argjson acc "$ACC" --argjson zon "$ZON" --arg a "$ACCOUNT" --arg z "$ZONE" '{
    name: "urbex",
    policies: [
      {effect: "allow", permission_groups: $acc, resources: {("com.cloudflare.api.account." + $a): "*"}},
      {effect: "allow", permission_groups: $zon, resources: {("com.cloudflare.api.account.zone." + $z): "*"}}
    ]}' |
  curl -s -X POST -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" "$API" --data @- |
  jq -r '.result.value'        # the token: shown once
  ```
  Check that `ACC` lists 4 groups and `ZON` 3 before creating.

- **How to get it - dashboard:** *Manage account* → *Account API tokens*
  → *Create token* → *Custom token*, with the permissions above (account
  ones on your account, zone ones on your zone only).

- **Checking it:**
  ```sh
  curl -s -H "Authorization: Bearer $URBEX_CLOUDFLARE_TOKEN" \
    https://api.cloudflare.com/client/v4/accounts/<account id>/tokens/verify | jq .result.status   # "active"
  ```

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
| Gitea/Komodo/Keycloak/Grafana/Technitium passwords, tokens, keys | `URBEX_GITEA_*`, `URBEX_KOMODO_*`, `URBEX_TECHNITIUM_*`, ... | ✅ generated by `urbex bootstrap` |
| Cloudflare API token | `URBEX_CLOUDFLARE_TOKEN` | ✅ with Cloudflare configured |
| Brevo API key | *(none defined)* | ❌ not yet |
