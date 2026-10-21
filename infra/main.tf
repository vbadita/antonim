# Everything of this project lives in one compartment: one place to see it,
# one scope for IAM policies, one target for cleanup.
resource "oci_identity_compartment" "antonime" {
  compartment_id = var.tenancy_ocid
  name           = "antonime"
  description    = "antonime app"
  # false: `terraform destroy` leaves the compartment itself in place.
  enable_delete = false
}

# ---- cost guard ---------------------------------------------------------------
# The account is Pay As You Go: anything beyond the free allowances is billed.
# OCI allows ONE budget per target; the tenancy already has the user's own
# "Budgetcontrol" (alert at 0.01, created by hand, not managed here). This one
# targets the project compartment, so its alert names the culprit. Budgets only
# alert, they never stop resources.
resource "oci_budget_budget" "guard" {
  compartment_id = var.tenancy_ocid # budgets live in the root compartment
  display_name   = "antonime-guard"
  description    = "Any real spend in the antonime compartment means it left the free tier"
  amount         = var.budget_amount
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [oci_identity_compartment.antonime.id]
}

# Fires on the first cent actually spent.
resource "oci_budget_alert_rule" "any_spend" {
  budget_id      = oci_budget_budget.guard.id
  display_name   = "any-actual-spend"
  type           = "ACTUAL"
  threshold_type = "ABSOLUTE"
  threshold      = 0.01
  recipients     = var.budget_alert_email
  message        = "antonime: OCI spend is above 0 in the antonime compartment. Check Cost Analysis."
}

# Fires early if the month's trend would exceed the budget.
resource "oci_budget_alert_rule" "forecast" {
  budget_id      = oci_budget_budget.guard.id
  display_name   = "forecast-over-budget"
  type           = "FORECAST"
  threshold_type = "PERCENTAGE"
  threshold      = 100
  recipients     = var.budget_alert_email
  message        = "Forecast OCI spend exceeds the monthly budget."
}
