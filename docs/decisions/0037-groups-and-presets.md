# ADR-0037: Applications grouped on one LXC, and presets

## Status

Proposed. Extends [ADR-0028](0028-application-model.md), whose
placements `app` and `stack` it generalizes, for the *arr preset of
[urbforge/urbex-cli#63](https://github.com/urbforge/urbex-cli/issues/63)
([urbforge/urbex#105](https://github.com/urbforge/urbex/issues/105)).
Jellyfin's exposure was decided by Teg.

## Context

ADR-0028 places a stack's applications one per LXC (`app`, the default)
or all on one LXC (`stack`). The *arr stack a home lab owner installs
first wants neither. It wants three LXCs for one stack:

| LXC | Applications |
|---|---|
| `arr` | Sonarr, Radarr, Prowlarr |
| `download` | Gluetun and qBittorrent, which must share Gluetun's network |
| `media` | Jellyfin, Seerr |

Writing such a stack by hand means about eight services, their volumes
and the shared media folder. Then the wiring is done in each web UI:
API keys, Prowlarr's apps, the download client, root folders, Jellyfin's
libraries, Seerr's servers. Others have scripted that wiring
(leespe11/jellyfin-xtream-arr-vpn, see #63). Urbex can do it for the
stacks home labs run most, if it knows the stack.

Jellyfin streams video from the same host and port as its web UI.
Cloudflare's terms restrict serving video through its CDN and Tunnel,
which is how Urbex publishes a `public: true` application.

## Decision

### 1. Groups: `lxc: <name>`

An application may name the LXC it runs on within its stack:

```yaml
services:
  - name: sonarr
    image: lscr.io/linuxserver/sonarr
    version: "4"
    lxc: arr
  - name: radarr
    image: lscr.io/linuxserver/radarr
    version: "5"
    lxc: arr
  - name: jellyfin
    image: docker.io/jellyfin/jellyfin
    version: "10.11"
    lxc: media
```

- Applications of one stack with the same `lxc` share one LXC per
  environment: `<project>-<lxc>-<env>` (`media-arr-prod`). An
  application without `lxc` keeps its placement: its own LXC with
  `app`, the stack's with `stack`. `placement: stack` is the case where
  every application is in one group named after the project.
- As ADR-0028 has it for `stack`, each application keeps its own folder
  in the GitOps repo, its own Komodo Stack (on the group's Server), its
  own internal name (pointing to the group's LXC) and its own
  healthcheck. Two applications of a group may not publish the same
  port.
- **The group is the machine.** Its VMID and IP are allocated and
  recorded once, under its name. Its resources - cores, memory and root
  disk - are the sum of its applications'. Its shares, devices
  ([urbforge/urbex-cli#138](https://github.com/urbforge/urbex-cli/issues/138))
  and features are the union of its applications'. Its applications
  share a `machine`: `lxc` and `vm` in one group are refused.
- **A group's name** follows a service name's rules, and may not be the
  name of an application of the stack that isn't in it: the internal
  names would collide.
- **Moving an application between groups**, or into or out of one, is a
  replacement:
  - **without named volumes:** `apply` deploys it on the new LXC and
    removes it from the old one;
  - **with named volumes:** `apply` refuses and names them, as for any
    replacement (ADR-0028). Data is never moved silently. `--delete-data`
    accepts losing it; otherwise back it up, move, restore.

  A group left with no application is destroyed like an application
  removed: freely without volumes, with `--delete-data` otherwise.
- **Sharing a network inside a group.** Gluetun and qBittorrent is a
  network namespace shared by two applications of one LXC
  (`network_mode: service:`). It is declared on the application that
  joins
  ([urbforge/urbex-cli#139](https://github.com/urbforge/urbex-cli/issues/139)),
  and allowed only within a group.

### 2. Presets: a stack Urbex knows

A preset is a stack Urbex ships, declared with a few parameters:

```yaml
apiVersion: urbex/v1
project: media
environments: [prod]
preset:
  name: arr
  with:
    share: media                # storage.shares entry, mounted at /data everywhere
    vpn: { provider: mullvad }  # its credentials are secrets (urbex secret)
    public: [seerr]             # what goes through the tunnel; never jellyfin
services:
  - name: jellyfin              # an override: merged over the preset's jellyfin
    resources: { cpu: 4, memory: 6Gi }
```

- **It expands into ordinary applications.** They have groups, images
  and versions, volumes, shares, `uses`, healthcheck and resources.
  Everything downstream sees only those: `plan`, `apply`, the GitOps
  repo, `status`, `updates`. `urbex plan` prints the expansion.
- **The user can override any field** by declaring an application of
  the same name in `services`. Its fields win over the preset's, field
  by field, and lists are replaced, not merged. An application the
  preset doesn't have is added to the stack. `preset.without: [<app>]`
  drops one.
- **Presets are embedded in the CLI and versioned with it.** A preset
  names images by tag, like any image app. The first `apply` pins each
  to a digest (`version.env`), so a newer CLI with newer tags in its
  preset moves nothing running. `urbex updates` and `urbex deploy
  --update` move them, as for any image app. A change to a preset that
  would replace an application (a group, a volume) is listed in the
  CLI's Breaking notes.
- **A preset may carry configuration**: steps `apply` runs once the
  stack is healthy, through the applications' own APIs. Examples are
  API keys seeded before the first start, Prowlarr linked to Sonarr and
  Radarr, the download client, root folders, Jellyfin's libraries, and
  quality profiles
  ([urbforge/urbex-cli#145](https://github.com/urbforge/urbex-cli/issues/145),
  [#146](https://github.com/urbforge/urbex-cli/issues/146)).
  - Each step is idempotent.
  - Files an application owns are seeded only when missing, never
    overwritten.
  - Settings applied through an API are applied on every `apply`: the
    declaration wins over the web UI.
  - What only the user can do (an indexer's account) is listed by `apply`
    and `urbex status` as left to do.
  - The keys it generates are secrets, encrypted in the GitOps repo.
- **`urbex init --template <preset>`**
  ([urbforge/urbex-cli#79](https://github.com/urbforge/urbex-cli/issues/79))
  writes the expansion as a plain `urbex.yaml`, without `preset`, for
  those who want every line in their repo. The configuration steps then
  no longer run: they belong to the preset.

### 3. Jellyfin on the LAN only

- The `arr` preset never publishes Jellyfin through the Cloudflare
  Tunnel. Jellyfin is reached on the LAN, by its internal name, and its
  streaming never crosses Cloudflare. Seerr, which serves no video, may
  be public (`public: [seerr]`), behind its login or OIDC.
- An override that sets `public: true` on Jellyfin, or on another
  application from a media server's image (Jellyfin, Plex, Emby), is
  applied with a warning: Cloudflare's terms restrict video through the
  Tunnel, and the account is the user's.
- Remote viewing comes with ADR-0035's other access modes: a VPN to the
  LAN, or a proxy that doesn't go through Cloudflare. It doesn't come
  through the Tunnel.

## Rationale

- `lxc: <name>` is one optional field. It covers `app` (no field),
  `stack` (one group) and everything between, without a new placement
  per case. A group is a machine as an application is today, so the
  allocator, Terraform and the ledger don't change shape.
- Separate Komodo Stacks per application, even inside a group, keep
  ADR-0028's per-application deploys, versions and healthchecks; only
  the machine is shared.
- A preset that expands into ordinary applications adds no second model
  to learn or to operate: the GitOps repo, `status` and every command
  see what they already know. Overrides by name keep the preset useful
  when a home lab differs on one point. `init --template` is the way out
  for those who want no magic.
- Configuration through the applications' APIs is what makes a preset
  worth more than an example in the cookbook. Keeping it in the preset,
  not in `urbex.yaml`, avoids a general workflow language.
- Jellyfin on the LAN: Cloudflare's terms, and a home lab's media is
  watched at home first. Seerr is the part worth reaching from outside.

## Out of scope, or later

- Presets beyond `arr` (Immich, Paperless-ngx, Nextcloud): one issue
  each, once `arr` has shown the shape.
- Presets from outside the CLI (a registry, a user's own): later, if
  asked.
- Moving a named volume between groups automatically.
- A group spread over several machines, or hosts other than Proxmox
  ([urbforge/urbex#24](https://github.com/urbforge/urbex/issues/24)).

## Consequences

- `urbex.yaml` gains `lxc` per application, and `preset` (`name`,
  `with`, `without`) per stack. Both are optional; today's manifests
  stay valid. The schema and its copy in urbex-cli follow.
- The work, as sub-issues of urbforge/urbex-cli#63:
  [#137](https://github.com/urbforge/urbex-cli/issues/137) groups;
  [#138](https://github.com/urbforge/urbex-cli/issues/138) devices;
  [#139](https://github.com/urbforge/urbex-cli/issues/139) the shared
  network (VPN sidecar);
  [#140](https://github.com/urbforge/urbex-cli/issues/140) ports and
  `exposure: access`;
  [#141](https://github.com/urbforge/urbex-cli/issues/141) `tcp` and
  `command` healthchecks;
  [#142](https://github.com/urbforge/urbex-cli/issues/142) `auth.oidc`;
  [#143](https://github.com/urbforge/urbex-cli/issues/143) Keycloak as
  Access's identity provider;
  [#144](https://github.com/urbforge/urbex-cli/issues/144) `preset: arr`;
  [#145](https://github.com/urbforge/urbex-cli/issues/145) its wiring;
  [#146](https://github.com/urbforge/urbex-cli/issues/146) quality as
  code; [#147](https://github.com/urbforge/urbex-cli/issues/147) its
  Grafana; [#148](https://github.com/urbforge/urbex-cli/issues/148) VPN
  resilience; [#149](https://github.com/urbforge/urbex-cli/issues/149)
  extras. The first usable milestone is this ADR, #137, #138, #139 and
  #144.
- ADR-0028's `placement: stack`, not implemented yet, is built as one
  group (#137).
- The manifest reference, the cookbook's *arr recipe (urbforge/urbex#97)
  and getting started gain groups and presets as they land. The recipe
  then points to `preset: arr`.
- A preset ties images and configuration steps to a CLI release:
  updating a preset is a release, with its notes.
