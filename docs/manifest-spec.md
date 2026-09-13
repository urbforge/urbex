# App manifest spec — `urbex.yaml`

> Lives in the app repo (see
> [ADR-0002](decisions/0002-app-manifest-in-app-repo.md)), generated and
> maintained by the LLM developing the app. The formal, machine-checkable
> version of this schema lives at
> [`schemas/urbex.schema.json`](../schemas/urbex.schema.json) (JSON
> Schema, draft 2020-12); `urbex init`/`urbex plan` validate `urbex.yaml`
> against it.

```yaml
# urbex.yaml
apiVersion: urbex/v1
project: my-app          # project name, unique on the platform

frontend:                # optional: a project may have services only
  type: web               # web | mobile
  provider: cloudflare-pages   # cloudflare-pages (web) | firebase (mobile)
  buildCommand: npm run build
  outputDir: dist

services:                # optional: a project may have a frontend only
  - name: api
    runtime: java          # java | python | go | docker
    # if runtime: docker, a ready Dockerfile is required in the repo:
    # dockerfile: ./api/Dockerfile
    port: 8080
    healthcheck: /healthz
    resources:
      cpu: 2
      memory: 2Gi
      disk: 10Gi
    env:
      staging:
        LOG_LEVEL: debug
      prod:
        LOG_LEVEL: info
    auth:
      keycloak: true
      roles: [admin, user]   # roles required, created/validated on Keycloak

domain:
  # desired subdomain under the platform-configured base domain
  # (see ADR-0007) - e.g. api.staging.my-app.<base-domain>
  subdomain: my-app

observability:
  metrics: true       # export metrics to Prometheus
  logs: true          # ship logs to the logging stack (see ADR-0004)

email:                 # optional: transactional email (see ADR-0015)
  provider: brevo       # only 'brevo' in v1, more providers planned
  fromAddress: no-reply@my-app.example.com
  fromName: My App
  # the provider API key is a secret, never set here (see ADR-0011)
```

## Design notes

- `apiVersion` allows the schema to evolve without breaking existing
  manifests.
- `frontend` and `services` are both optional but at least one must be
  present — a `urbex.yaml` with neither is invalid.
- The `env` sections per service are for non-sensitive variables; actual
  secrets **never go in the manifest** in plaintext: only the required
  keys are declared, the value is managed separately via SOPS+age in the
  GitOps repo (see
  [ADR-0011](decisions/0011-secrets-sops-age.md)) — exact reference
  mechanism to be defined during technical design.
- `resources` has reasonable defaults if omitted (`cpu: 1`,
  `memory: 1Gi`, `disk: 5Gi`, see the JSON Schema), so the LLM isn't
  forced to always specify everything.
