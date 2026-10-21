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
