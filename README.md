# antonime

Romanian antonyms: type a word, get its antonyms.

```
Browser (static page) -> OCI API Gateway (rate limit + CORS) -> OCI Function (Python) -> Gemini API
```

Runs entirely inside OCI Always Free + the Gemini API free tier.

| Path | What |
|---|---|
| `function/` | `func.py` (fdk handler + pure `lookup()`), tests, Dockerfile |
| `infra/` | Terraform: network, Functions app, API Gateway, IAM, budget |
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
