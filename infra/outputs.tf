output "compartment_id" {
  value = oci_identity_compartment.antonime.id
}

output "budget_id" {
  value = oci_budget_budget.guard.id
}

output "image_repo" {
  description = "Push function images here, tagged with the git SHA"
  value       = local.image_repo
}

output "application_id" {
  value = oci_functions_application.app.id
}

output "function_id" {
  value = oci_functions_function.antonime.id
}

output "function_invoke_endpoint" {
  value = oci_functions_function.antonime.invoke_endpoint
}

output "ci_user_ocid" {
  value = oci_identity_user.ci.id
}

output "ci_api_key_fingerprint" {
  value = oci_identity_api_key.ci.fingerprint
}
