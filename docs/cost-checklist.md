# What could still cost money (checked 2026-10-22)

The OCI account is **Pay As You Go**: nothing stops spend by default. Every
billable item below has a free band, a cap, and a console page to verify it.

| Resource | Free band (Oracle price list) | Used so far | Cap | Verify in the console |
|---|---|---|---|---|
| Functions invocations | 2M / month (B90618) | 31 | proxy: 6 invocations/min global = max 267,840/month; IAM: only the VM may invoke | Developer Services -> Functions -> antonime-app -> antonime -> Metrics (Invocations) |
| Functions execution | 400,000 GB-s / month (B90617) | 8.9 GB-s (71.6 s x 128 MB) | same cap: worst case 267,840 x 10 s x 0.125 GB = 334,800 GB-s | same page -> Metrics (Execution duration) |
| API Gateway | **none** (B92072, 2.79 EUR / 1M calls) | not used | `zero api-gateway quotas in compartment antonime` (enforced, tested) | Governance -> Quota policies -> antonime-caps |
| OCIR images | Object Storage 10 GB (B91628) | 3 images, billable 0 GB | one image per function commit (deploy-function.sh reuses existing tags); quota `antonime-cap`: object storage 5 GB in the compartment | Developer Services -> Container Registry -> antonime/function |
| Terraform state bucket | same 10 GB | 0.6 MB, 42 versions | versioned; tiny | Storage -> Buckets -> antonime-tfstate |
| Logging | 10 GB / month (B92593) | a few KB | 30-day retention | Observability -> Logging -> Log groups -> antonime-logs |
| NAT gateway, service gateway, VCN, NAT public IP (ephemeral) | not in the price list (no charge) | - | quota: vcn-count 1, reserved-public-ip-count 0 | Networking -> Virtual cloud networks -> antonime-vcn |
| Outbound data | 10 TB / month | negligible | - | Billing -> Cost analysis (filter: Networking) |
| Compute, block storage, load balancers, databases | - | not used | quotas `zero` in the compartment | Governance -> Quota policies |
| Gemini API | free tier, Google project without billing | ~40 calls | Google's free quota (hard: no billing account); function lru_cache + 100 calls/min | Google AI Studio -> API keys / usage; Google Cloud -> Billing: project not linked |
| GitHub Actions | free for public repos (incl. arm64 runners) | ~6 runs | public repo | GitHub -> Settings -> Billing |

## Safety nets (alerts, not caps)

- Budget **antonime-guard**: alert on the first 0.01 actually spent in the `antonime` compartment, and on a forecast above the 1-unit monthly budget.
- Budget **Budgetcontrol** (pre-existing, tenancy-wide): alert at 0.01 actual spend.
- Budgets are evaluated about every 24 h, so a sudden spike is seen the next day: the caps above are the real protection.

## Monthly 2-minute check

1. Billing & Cost Management -> **Cost analysis**: this month, group by service -> must be 0.
2. Billing & Cost Management -> **Budgets**: antonime-guard and Budgetcontrol actual spend = 0.
3. Functions -> antonime -> Metrics: invocations far below 2M.
4. Container Registry -> antonime/function: image count small.
5. Google Cloud console -> Billing -> "Projects not linked to a billing account" contains the Gemini project.
