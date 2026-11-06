# Getting started with the CLI

Every command, typed by you, with what it prints. Before you start,
check the [prerequisites](../getting-started.md#prerequisites): the
Proxmox token, a block of free addresses, a domain, and podman or
docker.

## 1. Get Urbex

```sh
git clone https://github.com/urbforge/urbex-cli.git ~/src/urbex-cli
cd ~/src/urbex-cli
tools/operator/urbex-op build           # builds the image, with urbex compiled from this checkout
ln -s "$PWD/tools/operator/urbex-op" ~/bin/urbex-op
export URBEX_WORKSPACE=~/urbex-work     # put this in your shell's profile
urbex-op init
```

`init` creates the **workspace**: one folder with the SSH key Urbex
reaches its LXCs with, the age key that encrypts every secret, the
GitOps repo and your projects. It prints the SSH public key, which you
need in step 3.

> Back up `~/urbex-work/home/age.key`: without it, the secrets can't be
> recovered.

## 2. Give it the Proxmox token

```sh
urbex-op set proxmoxToken               # paste urbex@pve!cli=<value>; it isn't echoed
urbex-op set cloudflareToken            # only if you use your Cloudflare zone
```

## 3. Create the platform

```sh
urbex-op 'urbex bootstrap'
```

The first run only writes `~/urbex-work/gitops/urbex.platform.yaml`.
Fill it in ([every field](../reference/platform-config.md)):

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
  sshPublicKey: "ssh-ed25519 AAAA... urbex"   # the key init printed
  pool: urbex
  keyctl: false
  network:
    cidr: 192.168.1.0/24
    gateway: 192.168.1.1
    baseHostOffset: 200           # platform at .200 and up, projects after it
```

Then run it again:

```sh
urbex-op 'urbex bootstrap'
```

It takes about twenty minutes. It creates the platform's LXCs (Gitea,
Komodo, Technitium, Keycloak, observability, and the tunnel when
Cloudflare is configured), configures them and connects them. At the end
it prints the address of each service. The `urbex-admin` passwords are in
`~/urbex-work/home/.urbex/credentials.yaml`. Running it again is safe: it
changes nothing that is already right.

## 4. Describe your app

Put your app's repository in the workspace and add a manifest:

```sh
git clone <your app> ~/urbex-work/projects/acme-app
urbex-op 'cd /work/projects/acme-app && urbex init --project acme-app'
```

Edit `urbex.yaml` ([every field](../reference/manifest.md)):

```yaml
apiVersion: urbex/v1
project: acme-app
services:
  - name: api
    runtime: go          # Urbex supplies the Dockerfile; or: java, python, docker
    port: 8080           # the service must listen on $PORT, set to this
    healthcheck: /healthz
```

```sh
urbex-op 'cd /work/projects/acme-app && urbex init'    # validates it
cd ~/urbex-work/projects/acme-app && git add urbex.yaml && git commit -m "Add urbex manifest"
```

## 5. Staging

```sh
urbex-op 'cd /work/projects/acme-app && urbex apply staging'
```

It creates the LXC, the repository on Gitea from your local `main`, the
build and the deploy, then builds `main` and deploys it. It prints the
address of each service:

```
Deployed acme-app (staging):
  api              http://192.168.1.210:8080  3f9c2e1 (...)
```

Gitea is now your app's remote. Every push to `main` is built and
deployed to staging within a few minutes:

```sh
git remote add origin http://192.168.1.200:3000/urbex/acme-app.git
git fetch origin && git branch -u origin/main
git commit -am "Better greeting" && git push
urbex-op 'cd /work/projects/acme-app && urbex status staging'
```

## 6. Production

```sh
urbex-op 'cd /work/projects/acme-app && urbex apply prod'    # once: prod's LXC, empty until promoted
urbex-op 'cd /work/projects/acme-app && urbex release'       # tags v0.1.0 on the commit staging runs
urbex-op 'cd /work/projects/acme-app && urbex promote'       # prod runs the very image staging ran
```

That's it. For configuration and secrets see
[Configuration and secrets](#configuration-and-secrets) below.

## Native tools

Without the container, build `urbex` and set up what the container does
for you:

```sh
cd ~/src/urbex-cli
mise install && mise run build && mv urbex ~/bin/          # or: go build -o ~/bin/urbex ./cmd/urbex
ssh-keygen -t ed25519 -f ~/.ssh/urbex -C urbex && ssh-add ~/.ssh/urbex
age-keygen -o ~/urbex.key                                   # back it up
export URBEX_PROXMOX_TOKEN='urbex@pve!cli=<value>'
export URBEX_AGE_KEY="$(grep AGE-SECRET-KEY ~/urbex.key)"
export URBEX_GITOPS_REPO=~/urbex-gitops
urbex bootstrap
```

Then run the commands of steps 3 to 6 without `urbex-op '...'`, from
your app's folder, wherever it is. Terraform, Ansible and sops must be
on the `PATH` there: with mise, that is `mise use -g` for each tool, or a
`mise.toml` in that folder.

## Configuration and secrets

Configuration lives in the GitOps repo, per environment: edit
`environments/<env>/<project>/<service>/config.env` in
`~/urbex-work/gitops`, commit and push, and Komodo redeploys the service.
Secrets go through the CLI, which encrypts them with the platform's age
key. It reads the value on standard input, so set it from a shell in the
container:

```sh
urbex-op shell
cd /work/projects/acme-app
read -rs VALUE && printf %s "$VALUE" | urbex secret set prod api STRIPE_KEY
urbex secret list prod api
```

The service gets `STRIPE_KEY` in its environment. The GitOps repo only
ever holds it encrypted.
