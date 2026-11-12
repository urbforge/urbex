---
name: cli
description: >
  Run Urbex's urbex CLI for the user, natively or through urbex-op, and
  know which commands need their confirmation: bootstrap, plan, apply,
  release, deploy, promote, secret, status, users, destroy, teardown, and
  configuration in the GitOps repo. Use when the user says "deploy to
  staging", "release and promote", "what runs in prod?", "roll back
  production", "set the STRIPE_KEY secret", "change the configuration",
  "update postgres", "show me the test users", "why didn't my push
  deploy?", "destroy staging", or names any urbex command.
---

# The urbex CLI

Every command, its steps, flags and output are in the
[CLI reference](${CLAUDE_PLUGIN_ROOT}/docs/reference/cli.md); the
[cookbook](${CLAUDE_PLUGIN_ROOT}/docs/cookbook.md) maps tasks to commands
(*Roll back production*, *Fix production quickly*, *A push didn't
deploy*, ...). Read the section of a command before its first use in a
session. Nothing in the CLI is interactive: every command can run here.

## How to run a command

Find out once per session which way the user runs Urbex:

- **Container** (`command -v urbex-op`): every command runs as
  `urbex-op '<commands>'`, against the workspace in `$URBEX_WORKSPACE`
  (default `~/urbex-workspace`), mounted at `/work`. Your shell doesn't
  keep variables between commands, so pass it each time
  (`urbex-op -w ~/urbex-work '...'`) if it isn't in the user's profile.
  Project commands run in the project's folder, which must be inside the
  workspace:
  ```sh
  urbex-op 'cd /work/projects/acme-app && urbex status staging'
  ```
  The GitOps repo is `/work/gitops` there, `<workspace>/gitops` on the
  host. After updating the `urbex-cli` checkout, `urbex-op build` rebuilds
  the image.
- **Native** (`command -v urbex`): run `urbex ...` in the project's
  folder, with `URBEX_GITOPS_REPO` set to the GitOps repo's working copy
  (or `--gitops-repo`). Credentials come from environment variables, then
  `~/.urbex/credentials.yaml`.

Neither: use the `setup` skill.

## Following a long command

`bootstrap`, `apply`, `destroy` and `teardown --yes` take minutes, up to
twenty. Run them with `--events json`, in the background (a background
task, or a watch whose events are the command's lines):

```sh
urbex-op -w ~/urbex-work 'urbex bootstrap --events json'
```

Each line is a JSON event, and nothing else: `run-start` (with `log`,
the file the command's own output goes to), `phase-start` (`title`,
`estimate` in seconds), `step` (an Ansible task or a machine Terraform
is done with: don't relay those one by one), `phase-end` (`seconds`),
`phase-skip` (`note`), `phase-fail` (`error`), and last `run-end`
(`result`: `ok` or `failed`, `error`). The command exits when the run
ends, non-zero on failure. Tell the user each phase as it ends, in a few
words. Every field: *Progress events* in
`${CLAUDE_PLUGIN_ROOT}/docs/reference/cli.md`.

- The run goes on if this session or the background task goes away.
  Follow it again, from its first event, with
  `urbex-op -w ~/urbex-work 'urbex status --progress --events json --watch'`;
  it stops at `run-end`, with `result: stopped` for a run that died
  without finishing.
- On `phase-fail` or a failed `run-end`, read the end of the `log` file
  (in the workspace: `~/urbex-work/home/.urbex/progress/...`) for the
  cause: the events show only where it stopped.
- Asked for the status in between, run `urbex status --progress` once.
- An error before the run starts (invalid config, missing credential)
  comes on standard error with no event: read it there.

## Ask the user before

These change production, destroy something, or are hard to undo. Say
what the command will do, with the environment and project, and wait for
a yes for that command:

- `urbex bootstrap` (it creates or changes the platform's LXCs);
- `urbex apply prod`, `urbex deploy prod ...`, `urbex promote`;
- `urbex release` (it tags a version on Gitea; versions are never
  reused);
- `urbex destroy <env>`, `urbex teardown --yes`;
- any `--delete-data` (it deletes data, nothing is kept) or
  `--allow-major` (the data may need a migration first);
- `urbex secret set` or `unset` in prod;
- a push to the project's `main` on Gitea (it deploys to staging).

`init`, `plan`, `status`, `users`, `secret list` and `bootstrap
--dry-run` change nothing: run them freely. So are `apply staging` and
`deploy staging` when the user asked for a deploy to staging.

When a command refuses ("has named volumes", "a replacement is never
allowed", "release it first"), tell the user what it said and what it
suggests. Don't add a flag that overrides the refusal on your own.

## Secrets and credentials

- Never print, read or copy `credentials.yaml`, `age.key`, or a
  decrypted `secrets.sops.env`, and never ask for a token, password or
  key in the chat. To check that a credential is set, test for the key
  without printing the value (`grep -q '^giteaToken:' ...`).
- **Setting a secret**: the value must not go through the chat. Give the
  user the commands to run in their own terminal:
  ```sh
  urbex-op shell
  cd /work/projects/acme-app
  read -rs VALUE && printf %s "$VALUE" | urbex secret set prod api STRIPE_KEY
  ```
  Natively, the same without `urbex-op shell`. A secret you generate
  yourself (a random session key, say) can be piped straight in:
  `openssl rand -hex 32 | tr -d '\n' | urbex secret set ...`, inside one
  `urbex-op '...'` command, without printing it.
- `urbex secret list <env> <service>` shows the names only: use it to
  check.
- The keys Urbex generates for linked applications (`PGPASSWORD`,
  `POSTGRES_PASSWORD`, ...) can't be set: `apply` owns them.
- `urbex users staging` prints the staging test users' passwords. Run it
  when the user asks for them; they are test accounts, but don't copy
  them elsewhere.

## Everyday tasks

| The user says | Run |
|---|---|
| "deploy to staging" | Push to `main` on Gitea (staging follows it); `urbex status staging` until it runs the new commit. The first time, `urbex apply staging`. |
| "what runs where?" | `urbex status` (platform and every project), `urbex status <env>` (one project). |
| "release and promote" | `urbex release`, then `urbex promote`; ask first. |
| "roll back prod" | `urbex deploy prod --version <previous release>`; ask first. |
| "deploy commit X to staging" | `urbex deploy staging --version <short hash>`; `--follow-main` to follow `main` again. |
| "add a service" or "more memory" | Change `urbex.yaml` (the `manifest` skill), then `urbex plan <env>` and `urbex apply <env>`. |
| "change a port or healthcheck" | Change `urbex.yaml`, then `urbex deploy <env>`. |
| "change the configuration" | Edit `environments/<env>/<project>/<service>/config.env` in the GitOps repo, commit, push: Komodo redeploys the service. Pull first; never edit `compose.yaml` or `version.env` there. |
| "update postgres" (an app from an image) | Change `version` in `urbex.yaml`, `urbex deploy staging --app <name> --update`, check, then `urbex promote`. A new major version with data needs a migration: ask. |
| "who can log in?" | `urbex users <env>`. |
| "my push didn't deploy" / "the build failed" | `urbex status staging`, then the cookbook's *A push didn't deploy* and *A build or a deploy failed*; logs in Grafana and Komodo. |
| "apps don't come back after a reboot" | `urbex status <env>`, its *Reconciler* section, and the cookbook's *The reconciler holds applications back*. |
| "remove staging" / "remove the project" | `urbex destroy <env>` for each environment; ask first. |
| "remove the whole platform" | `urbex teardown`, then `--yes` after the user has read what it destroys. Every repository and image on Gitea goes with it. |

After a command, report what changed and where it runs (the addresses it
printed), in a few lines. For errors, quote the CLI's one-line message:
it says what to do.
