terraform {
  required_version = "= 1.16.5"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "= 9.8.0"
    }
  }

  # State lives in Object Storage (bucket made by scripts/bootstrap-state.sh):
  # shared by this VM and CI, versioned, and locked during every apply.
  backend "oci" {
    bucket    = "antonime-tfstate"
    namespace = "frjpwvcxyneb"
    region    = "eu-frankfurt-1"
    key       = "antonime/terraform.tfstate"
  }
}

provider "oci" {
  region = var.region
  # Credentials: ~/.oci/config [DEFAULT] (API key). Nothing secret in this repo.
}
