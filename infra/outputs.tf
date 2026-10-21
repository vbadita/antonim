output "compartment_id" {
  value = oci_identity_compartment.antonime.id
}

output "budget_id" {
  value = oci_budget_budget.guard.id
}
