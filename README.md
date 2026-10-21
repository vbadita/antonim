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
