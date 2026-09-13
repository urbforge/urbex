# Credentials & prerequisites reference

Every value `urbex` reads from an environment variable, from
`~/.urbex/credentials.yaml`, or from `urbex.platform.yaml` - what it's
for, whether any command actually checks it yet, and exactly how to get
it. See [ADR-0012](decisions/0012-platform-config-and-credentials.md)
for the design (non-sensitive config in `urbex.platform.yaml`, secrets
never in the GitOps repo).

## Required today

Only these two are enforced - `urbex bootstrap`/`plan`/`apply`/`destroy`
refuse to run without them (`credentials.MissingForProvisioning()` in
`urbex-cli`). `urbex deploy` needs neither, since it only runs Ansible
over SSH.

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
- **Least privilege:** a dedicated Proxmox user with the `PVEVMAdmin`
  role on the relevant node/pool is enough for Urbex to create, modify,
  and destroy LXC containers. Avoid using a `root@pam` token for
  anything beyond a quick personal test.

### SSH key

- **Where it's set:** `proxmox.sshPublicKey` in `urbex.platform.yaml`
  (the public key itself, not a credential file entry - only the
  matching private key needs to stay off the GitOps repo).
- **Used by:** the Terraform LXC module (installs it as the `root`
  user's authorized key at container creation) and Ansible (connects
  over SSH to configure every LXC).
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
- **Used by:** nothing yet, other than the CLI's credential-completeness
  check. Despite being required to run `bootstrap`/`plan`/`apply`/
  `destroy`, **no code actually encrypts or decrypts anything with it**
  - see the "secret encryption" gap in [`status.md`](status.md). It's
  required now so the credential surface doesn't change shape once
  [ADR-0011](decisions/0011-secrets-sops-age.md) is actually wired up.
- **How to get one:** install [age](https://github.com/FiloSottile/age)
  (`brew install age`, or your distro's package), then:
  ```sh
  age-keygen -o urbex.key
  ```
  The file's `AGE-SECRET-KEY-1...` line is `URBEX_AGE_KEY`. Keep the
  file itself somewhere durable outside the GitOps repo - Urbex has no
  way to recover a lost age key, and once SOPS encryption is wired up,
  losing it means losing every secret encrypted to it.

## Declared, but not required by any command yet

These exist as fields in `urbex.platform.yaml`/`~/.urbex/credentials.yaml`
because the design anticipates needing them, but no current `urbex`
command reads or checks them. You can leave them unset today without
anything complaining. See [`status.md`](status.md) for which priority
item each is waiting on.

### Cloudflare API token, account ID, zone ID

- **Env var / credentials file key:** `URBEX_CLOUDFLARE_TOKEN` /
  `cloudflareToken`; `cloudflare.accountId` and `cloudflare.zoneId` go in
  `urbex.platform.yaml` directly (non-sensitive).
- **Will be used by:** Cloudflare Tunnel ingress provisioning
  ([ADR-0005](decisions/0005-cloudflare-tunnel-ingress.md)) - not
  implemented yet.
- **How to get them (when you need them):** Cloudflare dashboard → *My
  Profile* → *API Tokens* → *Create Token*, scoped to the zone matching
  `urbex.platform.yaml`'s `domain`, with `Zone:DNS:Edit` and
  `Account:Cloudflare Tunnel:Edit` permissions. The account ID and zone
  ID are both shown on that zone's *Overview* page, right-hand sidebar.

### Gitea admin token

- **Env var / credentials file key:** `URBEX_GITEA_TOKEN` /
  `giteaToken`
- **Will be used by:** pushing the GitOps repo and creating app repos on
  the Gitea LXC `urbex bootstrap` provisions
  ([ADR-0006](decisions/0006-bootstrap-command.md)) - not implemented
  yet; today the GitOps repo is just a local directory (see
  [`guide.md`](guide.md#running-urbex-from-a-fresh-machine-or-a-fresh-agent-session)).
- **How to get one (when you need it):** once Gitea is up
  (`http://<gitea-ip>:3000` after bootstrap - the IP is in
  `terraform/base/terraform.tfstate`), complete its first-run setup to
  create an admin account, then *Settings* → *Applications* → *Generate
  New Token* with repo read/write scope.

### Brevo API key

- **Env var / credentials file key:** none defined yet - there's no
  `URBEX_BREVO_*` variable in `urbex-cli` today, since nothing consumes
  it.
- **Will be used by:** apps that declare `email.provider: brevo` in
  their `urbex.yaml` ([ADR-0015](decisions/0015-transactional-email-brevo.md))
  - not implemented yet.
- **How to get one (when you need it):** Brevo dashboard → *SMTP & API*
  → *API Keys* → *Generate a new API key*.

## Summary

| Credential | Env var | Required today? |
|---|---|---|
| Proxmox API token | `URBEX_PROXMOX_TOKEN` | ✅ yes |
| SSH private key | (SSH agent, not an env var) | ✅ yes |
| age keypair | `URBEX_AGE_KEY` | ✅ yes (checked, but unused) |
| Cloudflare API token | `URBEX_CLOUDFLARE_TOKEN` | ❌ not yet |
| Gitea admin token | `URBEX_GITEA_TOKEN` | ❌ not yet |
| Brevo API key | *(none defined)* | ❌ not yet |
