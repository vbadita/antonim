# HARD caps (budgets only alert; quotas make the create call fail).
# Pay As You Go account: anything not explicitly allowed here could be billed.
resource "oci_limits_quota" "antonime" {
  compartment_id = var.tenancy_ocid # quota policies live in the root compartment
  name           = "antonime-caps"
  description    = "Keep the antonime compartment inside the free allowances"
  statements = [
    # Functions: NOT enforced at create time (tested 2026-10-21: a 2nd app and a
    # 2nd function were both created). Kept because the overrun becomes visible
    # (`oci limits resource-availability get` shows available = -1). The real
    # Functions cap is who may invoke (IAM) + the nginx rate limit in front.
    "set faas quota application-count to 1 in compartment antonime",
    "set faas quota function-count to 1 in compartment antonime",
    "set vcn quota vcn-count to 1 in compartment antonime",
    # API Gateway has no free band (2.79 EUR / 1M calls): forbid it outright.
    # Enforced: creating one fails with QuotaExceeded (tested 2026-10-21).
    "zero api-gateway quotas in compartment antonime",
    # nothing else that bills by the hour may appear here
    "zero vcn quota reserved-public-ip-count in compartment antonime",
    "zero compute-core quotas in compartment antonime",
    "zero block-storage quotas in compartment antonime",
    "zero load-balancer quotas in compartment antonime",
    "zero database quotas in compartment antonime",
  ]
}
