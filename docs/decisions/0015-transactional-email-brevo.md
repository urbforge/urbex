# ADR-0015: Transactional email via a managed provider (Brevo first)

## Status

Accepted

## Context

Apps built on Urbex often need transactional email (signup confirmation,
password reset, notifications). Self-hosting a mail server on an LXC on a
home Proxmox is impractical: residential ISPs commonly block outbound
port 25, there is no usable PTR record or IP reputation for a home IP,
and major providers (Gmail, Outlook) will reject or spam-box mail from it
regardless of correct SPF/DKIM/DMARC configuration. This mirrors the
reasoning already applied to ingress (see
[ADR-0005](0005-cloudflare-tunnel-ingress.md)): where self-hosting is
structurally disadvantaged, Urbex relies on a managed service instead.

## Decision

- v1 supports **Brevo** as a managed transactional email provider,
  declared per-app in `urbex.yaml` under an `email` section (`provider:
  brevo`, `fromAddress`, `fromName`).
- The provider's API key is a **secret**, never written in the manifest:
  it is managed the same way as other project secrets, via SOPS+age in
  the GitOps repo (see [ADR-0011](0011-secrets-sops-age.md)), and
  injected into the service's environment at deploy time.
- The manifest's `email.provider` field is modeled as an **enum designed
  for extension**: Brevo is the only accepted value in v1, but the schema
  and the CLI's internal provider abstraction are built so that adding a
  new provider means adding an enum value and a small provider adapter,
  not redesigning the manifest shape.

## Rationale

- A managed provider sidesteps deliverability problems that are
  essentially unsolvable from home-lab infrastructure without paying for
  a relay anyway — at which point a dedicated transactional email service
  is simpler and usually cheaper.
- Building the abstraction for multiple providers now (even with only one
  implemented) avoids a breaking manifest change when a second provider
  is added later.

## Consequences

- The app manifest schema (`schemas/urbex.schema.json`) gains an optional
  `email` object; see [`manifest-spec.md`](../manifest-spec.md).
- `urbex apply`/`deploy` must know how to map `email.provider: brevo` to
  the right environment variables/secret references for the service; a
  provider-agnostic internal interface should be used so future providers
  (e.g. Resend, Postmark, Amazon SES — see
  [`roadmap.md`](../roadmap.md)) don't require touching unrelated code
  paths.
- Documentation must make clear that Urbex does not manage domain
  verification (SPF/DKIM records) with the email provider automatically
  in v1 — that remains a manual setup step for the user's domain.
