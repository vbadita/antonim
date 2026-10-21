data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

locals {
  # e.g. fra.ocir.io/<namespace>/antonime/function
  ocir_host  = "${lower(data.oci_identity_regions.home.regions[0].key)}.ocir.io"
  image_repo = "${local.ocir_host}/${data.oci_objectstorage_namespace.ns.namespace}/${oci_artifacts_container_repository.function.display_name}"
}

data "oci_identity_regions" "home" {
  filter {
    name   = "name"
    values = [var.region]
  }
}

# Private repository. Tags are git SHAs, never reused. (is_immutable would
# enforce that, but OCIR answers "Setting isImmutable is not currently supported".)
resource "oci_artifacts_container_repository" "function" {
  compartment_id = oci_identity_compartment.antonime.id
  display_name   = "antonime/function"
  is_public      = false
}

# GENERIC_ARM: images are built natively on this Arm VM (and on Arm CI runners).
# The shape cannot be changed after creation.
resource "oci_functions_application" "app" {
  compartment_id = oci_identity_compartment.antonime.id
  display_name   = "antonime-app"
  subnet_ids     = [oci_core_subnet.functions.id]
  shape          = "GENERIC_ARM"
}

resource "oci_functions_function" "antonime" {
  application_id = oci_functions_application.app.id
  display_name   = "antonime"
  # `image` is deprecated in favour of source_details { source_type = "CONTAINER_IMAGE" }
  # (that is what OCI reports back). Kept for now: switching the block on an
  # existing function needs its own plan/test, and CI owns the image anyway.
  image              = var.function_image
  memory_in_mbs      = 128 # smallest size: cheapest GB-seconds
  timeout_in_seconds = 10

  lifecycle {
    # CI owns these after the first deploy:
    #  - image:  each push to main deploys a new git-SHA tag
    #  - config: holds GEMINI_API_KEY, set by CI/CLI so the secret never
    #            enters Terraform state
    ignore_changes = [image, image_digest, config]
  }
}

# Invocation logs (stdout/stderr of the function) for debugging.
# OCI Logging: first 10 GB/month free; our JSON lines are ~200 bytes.
resource "oci_logging_log_group" "antonime" {
  compartment_id = oci_identity_compartment.antonime.id
  display_name   = "antonime-logs"
}

resource "oci_logging_log" "invoke" {
  log_group_id       = oci_logging_log_group.antonime.id
  display_name       = "antonime-app-invoke"
  log_type           = "SERVICE"
  retention_duration = 30 # days
  is_enabled         = true
  configuration {
    source {
      category    = "invoke"
      resource    = oci_functions_application.app.id
      service     = "functions"
      source_type = "OCISERVICE"
    }
  }
}
