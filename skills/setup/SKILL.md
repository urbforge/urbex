---
name: setup
description: >
  Set up Urbex from scratch on the user's Proxmox VE node: find the node,
  the LAN, free addresses, storage, bridge, template and Cloudflare zone
  by itself, prepare the workspace with urbex-op, have the user run a
  script that prepares Proxmox and stores its token (or give them the
  root commands), give the Cloudflare token's steps, propose a complete
  urbex.platform.yaml for one confirmation, run urbex
  bootstrap, then take the first app to staging. Use when the user says
  "set up Urbex", "install Urbex", "bootstrap the platform", "I have a
  Proxmox node, get me started", "create the Proxmox token for Urbex", or
  asks what Urbex needs before it can run.
---

# Set up Urbex

Take the user from an empty Proxmox node to an app in staging. The
prerequisites are in `${CLAUDE_PLUGIN_ROOT}/docs/getting-started.md`,
the procedure in `${CLAUDE_PLUGIN_ROOT}/docs/getting-started/with-the-cli.md`;
every value and command is explained in `${CLAUDE_PLUGIN_ROOT}/docs/reference/`.
For running a command, and the rules on what needs the user's
confirmation, follow the `cli` skill of this plugin.

**Find, propose, confirm.** Don't open with a list of questions. Find
every value you can yourself, with the scripts below, from the user's
machine and, once the tokens are stored, from the Proxmox and Cloudflare
APIs. Then propose the whole configuration at once, saying where each
value comes from, and ask for one confirmation. Ask a question only when
there is no way to find the answer or two equally good choices (several
Proxmox nodes, several Cloudflare zones), and then propose a default.

## What stays with the user

Say this up front, in a few lines:

- **Root on Proxmox.** Preparing the node needs an administrator: the
  user runs `prepare-proxmox.py` in their own terminal, where it asks for
  the password, or the root block on the node. Never run either
  yourself, and never ask for the password or root access in the chat.
- **Tokens.** The user enters the Proxmox and Cloudflare tokens with
  `urbex-op set` in **their own terminal**, outside this chat. Never ask
  for a token, a password or a key in the chat, and never print
  `credentials.yaml` or `age.key`: the scripts read the tokens and print
  only what isn't secret. If the user pastes a secret in the chat anyway,
  don't repeat it or use it: tell them to revoke it, create a new one,
  and set it with `urbex-op set`.
- **Confirmation** before anything that creates or destroys resources on
  their node: `urbex bootstrap` and every command in the `cli` skill's
  list.

## 1. Look around (no questions)

```sh
bash ${CLAUDE_SKILL_DIR}/check-prerequisites.sh
python3 ${CLAUDE_SKILL_DIR}/discover-network.py
```

- `check-prerequisites.sh`: git, ssh-keygen, python3, podman or docker,
  an existing `urbex-op`, workspace or `urbex`, access to `urbex-cli`.
  For a missing tool, say how to install it on the user's OS. podman or
  docker is all Urbex needs; the native path (Go, Terraform, Ansible,
  sops, age, through mise) is for users who can't run containers: see
  *Native tools* in `${CLAUDE_PLUGIN_ROOT}/docs/getting-started/with-the-cli.md`.
- `discover-network.py` pings the LAN's addresses once (a /24 at most) and
  prints, as JSON, this machine's address, the LAN's CIDR, gateway and
  DNS servers, the hosts answering on Proxmox's port 8006
  (`proxmoxCandidates`), the addresses in use, and a proposed block of
  free addresses (`proposal.baseHostOffset`). With `--proxmox <host>` it
  also checks the node is on the same LAN. `--no-scan` skips the pings.

An existing workspace (`~/urbex-work`, `$URBEX_WORKSPACE`) with a
`gitops/urbex.platform.yaml` means a platform may already exist: read
that file and go on from where it is, instead of starting over.

## 2. One short question

Tell the user, in a few lines, what you found: the Proxmox node (when
there is one candidate; when several, list them and propose one), the
LAN, the free block you propose. Then ask only:

- **Cloudflare**: none (everything on the LAN, the default), a Quick
  Tunnel (public `*.trycloudflare.com` addresses, no account), or their
  own zone (public HTTPS on their domain, Gitea and Komodo behind
  Cloudflare Access). It can be added later.

## 3. Get Urbex and the workspace

`urbex-cli` is private until the first release: the user needs access to
`github.com/urbforge/urbex-cli`. Clone it, by default in
`~/src/urbex-cli`, with the protocol that works (`gh repo clone
urbforge/urbex-cli`, or SSH). Then:

```sh
cd ~/src/urbex-cli
tools/operator/urbex-op build                  # a few minutes the first time
mkdir -p ~/.local/bin && ln -sf "$PWD/tools/operator/urbex-op" ~/.local/bin/urbex-op
urbex-op -w ~/urbex-work init
```

- Check that `~/.local/bin` is on their `PATH`, and have them add
  `export URBEX_WORKSPACE=~/urbex-work` to their shell's profile. Your
  own shell doesn't keep variables between commands: use `urbex-op -w
  ~/urbex-work` or prefix `URBEX_WORKSPACE=~/urbex-work`.
- `init` creates the SSH key (`~/urbex-work/home/.ssh/urbex.pub` goes in
  `proxmox.sshPublicKey`) and the age key. Tell the user to **back up
  `~/urbex-work/home/age.key`** outside the workspace: every secret is
  encrypted to it, and it can't be recovered.

While the build runs, go on with step 4: the user can read it meanwhile.

## 4. Prepare Proxmox and the tokens (the user)

Always offer the user both ways, in two lines, and let them choose; the
script is the one to recommend:

- **A. The script**: they type an administrator's password in their
  terminal, and the script does the rest, token included.
- **B. The commands by hand**: they run a root block on the node, and
  store the token themselves. Nothing gets their password.

**A. The script, in the user's own terminal.** It logs in to
the Proxmox API as an administrator, shows what it will do and waits for
a yes, then creates the pool, group, user and template, and stores the
token in the workspace with `urbex-op set proxmoxToken`, without
showing it. Resolve the script's absolute path and give the user the
command with it, the node's address and the workspace filled in:

```sh
python3 <absolute path of ${CLAUDE_SKILL_DIR}>/prepare-proxmox.py --host <node address> --workspace ~/urbex-work
```

Tell them, in a few lines:

- Run it in **their own terminal**, not with `!` in this chat: it asks
  for the password of `root@pam` (`--user` for another administrator)
  without echoing it, and for a TOTP code if the account has one. The
  password is used only to log in, for this run, and isn't stored.
- With Proxmox's own self-signed certificate, it shows the certificate's
  fingerprint and asks them to compare it with the node's (*node* →
  *System* → *Certificates*) before sending the password.
- It changes nothing until they answer yes to the list it prints, and
  can be run again: what exists is kept, the token is replaced only if
  they say so.

When they say it's done, go to step 5: `discover-platform.py` finds the
token in the workspace.

**B. The commands by hand**, when they choose them, or the script can't
log in (no Python, an account it can't use): give them this block, to run as `root` on the node, from a shell in the web UI
(*node* → *Shell*). It picks the storage, the bridge and the latest Debian
13 template by itself and prints them, and the token's value comes last.

```sh
STORAGE=$(pvesm status --content rootdir --enabled 1 | awk 'NR>1 && $3=="active" && $2!="dir" {print $1; exit}')
[ -n "$STORAGE" ] || STORAGE=$(pvesm status --content rootdir --enabled 1 | awk 'NR>1 && $3=="active" {print $1; exit}')
TEMPLATES=$(pvesm status --content vztmpl --enabled 1 | awk 'NR>1 && $3=="active" {print $1; exit}')
BRIDGE=$(ip -o route show default | awk '{print $5; exit}')
pveam update >/dev/null
TEMPLATE=$(pveam available --section system | awk -v arch="$(dpkg --print-architecture)" '$2 ~ /^debian-13-standard_/ && $3 == arch {print $2}' | sort -V | tail -1)
echo "disks on $STORAGE, templates on $TEMPLATES, bridge $BRIDGE, template $TEMPLATE"

pveum pool add urbex --comment "Urbex"
pveum pool modify urbex --storage "$STORAGE,$TEMPLATES"
pveum group add urbex --comment "Urbex operators: pool urbex only"
pveum acl modify /pool/urbex --groups urbex --roles PVEVMAdmin,PVEDatastoreUser,PVEPoolUser
pveum acl modify "/sdn/zones/localnetwork/$BRIDGE" --groups urbex --roles PVESDNUser
pveum user add urbex@pve --comment "Urbex CLI" --groups urbex
pveam download "$TEMPLATES" "$TEMPLATE"
pveum user token add urbex@pve cli --privsep 0 --comment "urbex"
```

Tell them:

- The last command prints the token's `value` **once**. The token is
  `urbex@pve!cli=<value>`: they keep it, and don't paste it here.
- If a line says the pool, group or user already exists, an earlier run
  got that far: the rest still applies.
- What each line does, and the web-UI way:
  [credentials](${CLAUDE_PLUGIN_ROOT}/docs/reference/credentials.md#proxmox-api-token).

A token of `root@pam` also works for a quick personal test, but isn't
recommended: say so if they propose it.

**With their own Cloudflare zone**, also:

1. A Zero Trust organization must exist: the first visit to *Zero
   Trust* in the dashboard creates it (the Free plan is enough).
2. The token: *Manage account* → *Account API tokens* → *Create token* →
   *Custom token*, with these permissions; they keep it for the next step.

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
   also creates it with Terraform or `curl`. The account and zone IDs
   aren't needed: the token finds them.

Then ask the user to store what they kept in another terminal (not with
`!` in this chat: `set` reads the value from the terminal without echoing
it). After the script, only the Cloudflare one is left:

```sh
export URBEX_WORKSPACE=~/urbex-work
urbex-op set proxmoxToken        # only after the root block: urbex@pve!cli=<value>
urbex-op set cloudflareToken     # only with their own Cloudflare zone
```

## 5. Propose the platform config

With the tokens stored, ask the APIs (GET requests only; the tokens are
read from the workspace and never printed):

```sh
python3 ${CLAUDE_SKILL_DIR}/discover-platform.py --workspace ~/urbex-work --proxmox https://<node>:8006 [--cloudflare]
```

It prints, as JSON: whether TLS needs `insecure`, the token's id and
permissions, the node, the bridge, the storages and the one to use, the
latest Debian 13 template, the pool and what is in it, whether the
platform's VMIDs are free, and with `--cloudflare` the zones the token
sees with their account and zone IDs. `errors` and `warnings` say what
to fix: a missing permission, the template not downloaded, an existing
platform. Fix them with the user and run it again.

Then run `urbex-op -w ~/urbex-work 'urbex bootstrap'` once: the first run
only writes `~/urbex-work/gitops/urbex.platform.yaml` and stops. Fill it
in from the two scripts' output (every field:
[platform config](${CLAUDE_PLUGIN_ROOT}/docs/reference/platform-config.md)):

| Field | From |
|---|---|
| `proxmox.apiUrl`, `insecure`, `node`, `storagePool`, `lxcTemplate`, `pool`, `keyctl`, `network.bridge`, `vmIdBase` | `discover-platform.py` |
| `proxmox.network.cidr`, `gateway`, `dnsServers`, `baseHostOffset` | `discover-network.py` |
| `proxmox.sshPublicKey` | `~/urbex-work/home/.ssh/urbex.pub` |
| `domain`, `cloudflare.accountId`, `cloudflare.zoneId` | the zone, with Cloudflare; without, propose `home.arpa` (the name reserved for home networks): it's only used for internal names and the admin's e-mail |
| `git.giteaUrl` | `https://git.<domain>` (not used yet) |
| `cloudflare.access.emails` | `git config user.email` |
| `cloudflare.quickTunnel: true` | with a Quick Tunnel, instead of the IDs |

Show the user the file, with a short line per value saying where it
comes from, and ask for one confirmation. Say explicitly the one thing
no script can check: **the address block must be outside the DHCP range
and unused** (a device that's off looks free). Change what they correct,
then check the file and the credentials without creating anything:

```sh
urbex-op -w ~/urbex-work 'urbex bootstrap --dry-run'
```

## 6. Bootstrap

Ask for confirmation, naming the node and the addresses it will take,
then:

```sh
urbex-op -w ~/urbex-work 'urbex bootstrap'
```

It takes about twenty minutes: run it in the background and follow it
with the `cli` skill's `follow-progress.py` (*Following a long command*),
telling the user each phase as it ends. Re-running it is safe, and is how a failed run
resumes. When an error names a cause, fix it and run it again; the
[cookbook](${CLAUDE_PLUGIN_ROOT}/docs/cookbook.md) has the usual ones
(*Bootstrap was interrupted*, *Ansible refuses an LXC*, *The LXCs can't
resolve names*) and [known limitations](${CLAUDE_PLUGIN_ROOT}/docs/known-limitations.md)
the rest.

At the end, `urbex-op -w ~/urbex-work 'urbex status'` lists every
address. Give the user the Gitea, Komodo, Grafana and Keycloak
addresses, and tell them the `urbex-admin` passwords are in
`~/urbex-work/home/.urbex/credentials.yaml` (`giteaAdminPassword`,
`komodoAdminPassword`, ...), without opening it. Tell them to back up
the workspace: after a teardown, `gitops/` is the GitOps repo's only
copy.

## 7. The first app

1. Its repository goes in the workspace, so that the container sees it:
   `git clone <app> ~/urbex-work/projects/<project>`. Without an app,
   propose a small one to try the flow.
2. Write its `urbex.yaml` with the `manifest` skill, which finds the
   values in the code and proposes them the same way; commit it.
3. Ask, then
   `urbex-op -w ~/urbex-work 'cd /work/projects/<project> && urbex apply staging'`.
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
