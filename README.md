# antonime

Romanian antonyms: type a word, get its antonyms.

```
Browser -> Cloudflare -> nginx on the VM (apps.badita.com/antonim: rate limit, static page)
        -> signing proxy (instance principal) -> OCI Function (Python) -> Gemini API
```

Runs inside OCI's free allowances + the Gemini API free tier. OCI API Gateway
was the first design but has no free band in Oracle's price list (part B92072,
2.79 EUR per 1M calls), so nginx on the existing Always Free VM does its job.

| Path | What |
|---|---|
| `function/` | `func.py` (fdk handler + pure `lookup()`), tests, Dockerfile |
| `proxy/` | signing proxy: validation, global invocation cap, instance-principal invoke |
| `deploy/` | nginx snippets, systemd unit |
| `infra/` | Terraform: compartment, budget, network, Functions app, IAM |
| `frontend/` | `index.html`, published to GitHub Pages |
| `.github/workflows/deploy.yml` | test -> build/push/deploy + smoke test -> frontend |

## Local development

```bash
python3.12 -m venv .venv
.venv/bin/pip install --no-deps -r function/requirements.txt -r function/requirements-dev.txt
cd function && ../.venv/bin/pytest -q && ../.venv/bin/ruff check .
```

Dependencies: edit `function/requirements*.in`, then `scripts/lock.sh` and
`scripts/check-lock-age.sh` (every pinned release must be >= 14 days old).

## OCI bootstrap (once)

```bash
scripts/install-tools.sh        # pinned oci-cli + Terraform (GPG-verified)
# ~/.oci/config: API key of an admin user (bootstrap only)
scripts/bootstrap-state.sh      # private, versioned bucket for Terraform state
cd infra && cp terraform.tfvars.example terraform.tfvars   # fill in, never commit
terraform init && terraform plan && terraform apply
```

Cost guard: budget `antonime-guard` alerts on the first 0.01 spent in the
`antonime` compartment (OCI allows one budget per target; the tenancy-wide one
is managed outside this repo).

## Free-tier caps (all tested)

| Layer | Cap | Why |
|---|---|---|
| nginx | 5 req/s per visitor IP (burst 5) -> JSON 429 | abuse per client |
| nginx | 1-day cache, `proxy_cache_lock` | repeated words cost nothing |
| proxy | **6 invocations/min, global** -> 429 | 6 x 60 x 24 x 31 = 267,840/month; even at the 10 s timeout x 128 MB that is 334,800 GB-s < 400,000 free |
| IAM | only the proxy VM (dynamic group, `use fn-invocation`) may invoke | nothing can bypass the proxy |
| function | lru_cache + 100 LLM calls/min | protects the Gemini quota |
| OCI quota | `zero api-gateway quotas` (enforced) | the paid gateway cannot be created |
| Gemini | key on a project without billing | Google's free quota is the last cap |

## Install on the VM

```bash
scripts/deploy-function.sh "$(terraform -chdir=infra output -raw function_id)"
scripts/install-proxy.sh      # /opt/antonime-proxy + antonime-proxy.service
scripts/install-nginx.sh      # snippets + SELinux port label + reload
```
