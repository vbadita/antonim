# Least privilege: the Functions service may read images only from the
# repositories in this project's compartment, nothing else.
resource "oci_identity_policy" "faas_pull" {
  compartment_id = oci_identity_compartment.antonime.id
  name           = "antonime-faas-pull"
  description    = "OCI Functions may pull images from OCIR repos in the antonime compartment"
  statements = [
    "Allow service faas to read repos in compartment id ${oci_identity_compartment.antonime.id}",
  ]
}

# The signing proxy on the VM authenticates as the instance itself (instance
# principal): no key file on disk to leak or rotate. The group matches exactly
# one instance OCID, not "all instances in a compartment".
resource "oci_identity_dynamic_group" "invokers" {
  compartment_id = var.tenancy_ocid # dynamic groups live in the root compartment
  name           = "antonime-invokers"
  description    = "The VM whose proxy may invoke the antonime function"
  matching_rule  = "instance.id = '${var.proxy_instance_ocid}'"
}

# Invoke only: cannot read config (where GEMINI_API_KEY lives), update the
# image or touch anything outside this compartment.
resource "oci_identity_policy" "invoke" {
  compartment_id = oci_identity_compartment.antonime.id
  name           = "antonime-invoke"
  description    = "Only the proxy VM may invoke functions in the antonime compartment"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.invokers.name} to use fn-invocation in compartment id ${oci_identity_compartment.antonime.id}",
  ]
}

# ---- CI (GitHub Actions) ------------------------------------------------------
# A dedicated user, not the admin key: if the GitHub secret leaks, the blast
# radius is "push an image / update this one function", nothing else.
resource "oci_identity_user" "ci" {
  compartment_id = var.tenancy_ocid
  name           = "antonime-ci"
  description    = "GitHub Actions deployer for vbadita/antonim"
  email          = var.ci_user_email
}

resource "oci_identity_group" "ci" {
  compartment_id = var.tenancy_ocid
  name           = "antonime-ci"
  description    = "Deploys the antonime function from CI"
}

resource "oci_identity_user_group_membership" "ci" {
  user_id  = oci_identity_user.ci.id
  group_id = oci_identity_group.ci.id
}

# Public half only; the private key lives in GitHub Secrets (OCI_CLI_KEY_CONTENT).
resource "oci_identity_api_key" "ci" {
  user_id   = oci_identity_user.ci.id
  key_value = file("${path.module}/ci-api-key.pub.pem")
}

# manage + where: the verb that contains the permission, narrowed to exactly
# the permissions needed. Found by testing (2026-10-22), not just the docs:
# pushing a NEW tag also needs REPOSITORY_CREATE (docs: "only if the repository
# doesn't exist"); REPOSITORY_INSPECT is not needed. No DELETE anywhere, no
# FN_FUNCTION_CREATE/DELETE.
resource "oci_identity_policy" "ci" {
  compartment_id = oci_identity_compartment.antonime.id
  name           = "antonime-ci"
  description    = "CI may push function images and update the antonime function, nothing more"
  statements = [
    "Allow group ${oci_identity_group.ci.name} to manage repos in compartment id ${oci_identity_compartment.antonime.id} where any {request.permission = 'REPOSITORY_READ', request.permission = 'REPOSITORY_UPDATE', request.permission = 'REPOSITORY_CREATE'}",
    "Allow group ${oci_identity_group.ci.name} to manage fn-function in compartment id ${oci_identity_compartment.antonime.id} where any {request.permission = 'FN_FUNCTION_READ', request.permission = 'FN_FUNCTION_UPDATE'}",
  ]
}
