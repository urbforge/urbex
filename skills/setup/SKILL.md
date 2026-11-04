---
name: setup
description: >
  Set up Urbex from scratch on the user's Proxmox VE node: check the
  prerequisites, walk the user through preparing Proxmox (resource pool,
  user, API token, Debian template), the network (free IPs), the domain
  and the optional Cloudflare token, prepare the workspace with urbex-op,
  write urbex.platform.yaml, run urbex bootstrap, then take the first app
  to staging. Use when the user says "set up Urbex", "install Urbex",
  "bootstrap the platform", "I have a Proxmox node, get me started",
  "create the Proxmox token for Urbex", or asks what Urbex needs before it
  can run.
---

# Set up Urbex

Take the user from an empty Proxmox node to an app in staging. The
procedure is the getting started, `${CLAUDE_PLUGIN_ROOT}/docs/getting-started.md`;
every value and command is explained in `${CLAUDE_PLUGIN_ROOT}/docs/reference/`.
Read those when a step needs more than what is here. For running a
command, and the rules on what needs the user's confirmation, follow the
`cli` skill of this plugin.

## What stays with the user

Say this up front, in your own words, before step 1:

- **Root on Proxmox.** The commands that need root on the node are the
  user's to run. Give them; never run them, never ask for root access.
- **Tokens.** The user enters the Proxmox and Cloudflare tokens with
  `urbex-op set` in **their own terminal**, outside this chat. Never ask
  for a token, a password or a key in the chat, and never print
  `credentials.yaml` or `age.key`. If the user pastes a secret in the
  chat anyway, don't repeat it or use it: tell them to revoke it, create
  a new one, and set it with `urbex-op set`.
- **Confirmation** before anything that creates or destroys resources on
  their node: `urbex bootstrap` and every command in the `cli` skill's
  list.

## 1. Check the prerequisites

Run `bash ${CLAUDE_SKILL_DIR}/check-prerequisites.sh`, with the Proxmox
URL as argument once you know it (`https://<proxmox>:8006`). Then ask
the user, in one message, what you can't find out yourself:

1. The Proxmox node's address and node name (`pve` by default). Proxmox
   VE 9 is required.
2. Whether they have run the Proxmox preparation of step 2 already.
3. The LAN: its CIDR (such as `192.168.1.0/24`), gateway, and a block of
   **at least 10 free addresses** that no DHCP server hands out: Urbex
   takes the first 5 for the platform, then one per service per
   environment from the 10th on ([addresses](${CLAUDE_PLUGIN_ROOT}/docs/reference/platform-config.md#addresses)).
4. A domain name. With Cloudflare it must be their Cloudflare zone;
   without, any name works, since it's used for internal names
   (`*.urbex.<domain>`) and the admin's e-mail address.
5. Cloudflare: none (everything on the LAN), a Quick Tunnel (public
   `*.trycloudflare.com` addresses, no account), or their own zone
   (public HTTPS on their domain, Gitea and Komodo behind Cloudflare
   Access). It can be added later.

Missing tools: podman or docker is all Urbex needs, with git and
ssh-keygen. Say how to install them on the user's OS. The native path
(Go, Terraform, Ansible, sops, age, through mise) is for users who
can't run containers: see *Native tools* in the getting started.

## 2. Prepare Proxmox (the user, as root)

Give the user these commands, to run as `root` on the node (a shell from
the web UI's *Shell* works). Replace `local-zfs` with the storage for
the LXCs' disks and `vmbr0` with the bridge, if theirs differ; `pvesm
status` lists the storages, `ip -br link | grep vmbr` the bridges.

```sh
pveum pool add urbex --comment "Urbex"
pveum pool modify urbex --storage local-zfs,local
pveum group add urbex --comment "Urbex operators: pool urbex only"
pveum acl modify /pool/urbex --groups urbex --roles PVEVMAdmin,PVEDatastoreUser,PVEPoolUser
pveum acl modify /sdn/zones/localnetwork/vmbr0 --groups urbex --roles PVESDNUser
pveum user add urbex@pve --comment "Urbex CLI" --groups urbex
pveum user token add urbex@pve cli --privsep 0 --comment "urbex"
pveam update && pveam download local debian-13-standard_13.6-1_amd64.tar.zst
```

Tell them:

- `pveum user token add` prints the token's `value` **once**. They keep
  it for step 4 as `urbex@pve!cli=<value>`, and don't paste it here.
- If `pveam download` says the template doesn't exist, `pveam available
  --section system | grep debian-13` gives the current name; use it in
  `lxcTemplate` later.
- The web-UI way, and what each permission is for, are in
  [credentials](${CLAUDE_PLUGIN_ROOT}/docs/reference/credentials.md#proxmox-api-token).

A token of `root@pam` also works for a quick personal test, but not
recommended: say so if they propose it.

## 3. Cloudflare (only with their own zone)

1. A Zero Trust organization must exist: the first visit to *Zero
   Trust* in the dashboard creates it (the Free plan is enough).
2. The **account ID** and **zone ID** are on the zone's *Overview* page.
   They are not secrets: they go in `urbex.platform.yaml`.
3. The token: *Manage account* → *Account API tokens* → *Create token* →
   *Custom token*, with these permissions. They keep it for step 4.

   | Scope | Permission |
   |---|---|
   | Account | Cloudflare Tunnel Edit |
   | Account | Workers Scripts Edit |
   | Account | Access: Apps and Policies Edit |
   | Account | Access: Organizations, Identity Providers, and Groups Edit |
   | Zone (theirs only) | DNS Edit |
   | Zone (theirs only) | Workers Routes Edit |
   | Zone (theirs only) | Zone Read |

   [Credentials](${CLAUDE_PLUGIN_ROOT}/docs/reference/credentials.md#cloudflare-api-token)
   also creates it with Terraform or `curl`.
4. The e-mail addresses allowed into Gitea and Komodo through Access
   (`cloudflare.access.emails`).

With a Quick Tunnel, nothing is needed here.

## 4. Get Urbex and the workspace

`urbex-cli` is private until the first release: the user needs access to
`github.com/urbforge/urbex-cli`. Clone it where the user wants it, by
default `~/src/urbex-cli`, with the protocol that works for them
(`gh repo clone urbforge/urbex-cli`, or SSH). Then:

```sh
cd ~/src/urbex-cli
tools/operator/urbex-op build                  # a few minutes the first time
mkdir -p ~/.local/bin && ln -sf "$PWD/tools/operator/urbex-op" ~/.local/bin/urbex-op
export URBEX_WORKSPACE=~/urbex-work
urbex-op init
```

- Check that `~/.local/bin` is on their `PATH`, and have them add
  `export URBEX_WORKSPACE=~/urbex-work` to their shell's profile. Your
  own shell doesn't keep variables between commands: prefix your
  commands with `URBEX_WORKSPACE=~/urbex-work`, or use `urbex-op -w
  ~/urbex-work`.
- `init` prints the SSH public key (for `proxmox.sshPublicKey`) and
  creates `~/urbex-work/home/age.key`. Tell the user to **back up the
  age key** somewhere safe outside the workspace: every secret is
  encrypted to it, and it can't be recovered.

Now stop, and ask the user to run in another terminal (not with `!` in
this chat: `set` reads the value from the terminal without echoing it):

```sh
export URBEX_WORKSPACE=~/urbex-work
urbex-op set proxmoxToken        # urbex@pve!cli=<value>
urbex-op set cloudflareToken     # only with their own Cloudflare zone
```

When they say it's done, check that the key is there without reading it:

```sh
urbex-op 'grep -q "^proxmoxToken:" ~/.urbex/credentials.yaml && echo proxmoxToken set || echo proxmoxToken missing'
```

## 5. The platform config

```sh
urbex-op 'urbex bootstrap'
```

The first run only writes `~/urbex-work/gitops/urbex.platform.yaml` and
stops. Fill it in with the user's values (every field:
[platform config](${CLAUDE_PLUGIN_ROOT}/docs/reference/platform-config.md)).
With the token of step 2:

```yaml
domain: acme.example
git:
  giteaUrl: https://git.acme.example
  org: urbex
proxmox:
  apiUrl: https://192.168.1.10:8006/api2/json
  insecure: true                  # Proxmox's default self-signed certificate
  node: pve
  storagePool: local-zfs
  lxcTemplate: local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
  sshPublicKey: "ssh-ed25519 AAAA... urbex"   # ~/urbex-work/home/.ssh/urbex.pub
  pool: urbex                     # required with the pool-scoped token
  keyctl: false                   # required with any token but root@pam's
  network:
    cidr: 192.168.1.0/24
    gateway: 192.168.1.1
    baseHostOffset: 200           # the first free address: .200 here
    bridge: vmbr0
    dnsServers: [192.168.1.1]     # the LAN's resolvers
```

- `baseHostOffset` is the host number of the first free address in the
  CIDR. The platform takes it and the next 4 (5 with Cloudflare's
  tunnel), projects start 10 after it.
- With their own zone add `cloudflare.accountId`, `cloudflare.zoneId`
  and `cloudflare.access.emails`; with a Quick Tunnel,
  `cloudflare.quickTunnel: true`. Never both.
- Don't put the domain's resolver in `dnsServers` if the LXCs can't reach
  it (Tailscale's `100.100.100.100`, say).

Show the file to the user, then check it and the credentials without
creating anything:

```sh
urbex-op 'urbex bootstrap --dry-run'
```

Fix what it reports and run it again until it passes.

## 6. Bootstrap

Ask for confirmation, naming the node and the addresses it will take,
then:

```sh
urbex-op 'urbex bootstrap'
```

It takes about twenty minutes: run it in the background and follow it
with `urbex-op 'urbex status --progress'`, telling the user the phase
it's in. Re-running it is safe, and is how a failed run resumes. When an
error names a cause, fix it and run it again; the
[cookbook](${CLAUDE_PLUGIN_ROOT}/docs/cookbook.md) has the usual ones
(*Bootstrap was interrupted*, *Ansible refuses an LXC*, *The LXCs can't
resolve names*) and [known limitations](${CLAUDE_PLUGIN_ROOT}/docs/known-limitations.md)
the rest.

At the end, `urbex-op 'urbex status'` lists every address. Give the user
the Gitea, Komodo, Grafana and Keycloak addresses, and tell them the
`urbex-admin` passwords are in `~/urbex-work/home/.urbex/credentials.yaml`
(`giteaAdminPassword`, `komodoAdminPassword`, ...), without opening it.
Tell them to back up the workspace: after a teardown, `gitops/` is the
GitOps repo's only copy.

## 7. The first app

1. Its repository goes in the workspace, so that the container sees it:
   `git clone <app> ~/urbex-work/projects/<project>`.
2. Write its `urbex.yaml` with the `manifest` skill, commit it.
3. Ask, then `urbex-op 'cd /work/projects/<project> && urbex apply staging'`.
   It creates the LXCs, the repository on Gitea from the local `main`,
   the build, and deploys `main`. Give the user the addresses it prints.
4. Gitea is now the app's remote: every push to `main` is deployed to
   staging.
   ```sh
   cd ~/urbex-work/projects/<project>
   git remote add urbex http://<gitea address>:3000/urbex/<project>.git
   ```
   Pushing asks for Gitea credentials: the user's own Gitea account, or
   `urbex-admin` with its password from the credentials file, typed by
   the user.
5. Production, each step only when the user asks: `urbex apply prod`
   (once, empty until promoted), `urbex release`, `urbex promote`. See
   the `cli` skill.

End with what the user has: the platform's addresses, the app's staging
address, where the age key and the workspace are and that they must be
backed up, and the next commands in plain words ("deploy to staging",
"release and promote", "set a secret").
