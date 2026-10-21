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
