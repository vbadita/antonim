# Functions only need OUTBOUND traffic: Gemini (internet) and OCIR (Oracle
# services). So: a private subnet, no ingress rules, no public IPs.
#   0.0.0.0/0                      -> NAT gateway     (Gemini API)
#   all FRA services in OSN        -> service gateway (OCIR image pulls, Logging)
# VCN gateways have no line in Oracle's price list: they cost nothing.

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

locals {
  osn = data.oci_core_services.all.services[0]
}

resource "oci_core_vcn" "main" {
  compartment_id = oci_identity_compartment.antonime.id
  display_name   = "antonime-vcn"
  # Distinct from the existing 10.0.0.0/16 VCNs, in case they are ever peered.
  cidr_blocks = ["10.20.0.0/16"]
  dns_label   = "antonime"
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = oci_identity_compartment.antonime.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "antonime-nat"
}

resource "oci_core_service_gateway" "osn" {
  compartment_id = oci_identity_compartment.antonime.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "antonime-sgw"
  services {
    service_id = local.osn.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = oci_identity_compartment.antonime.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "antonime-private-rt"

  route_rules {
    destination       = local.osn.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.osn.id
  }
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }
}

resource "oci_core_security_list" "functions" {
  compartment_id = oci_identity_compartment.antonime.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "antonime-functions-sl"

  # No ingress_security_rules: nothing can connect in. Egress is HTTPS only.
  egress_security_rules {
    description      = "OCIR, Logging and other Oracle services"
    destination      = local.osn.cidr_block
    destination_type = "SERVICE_CIDR_BLOCK"
    protocol         = "6" # TCP
    tcp_options {
      min = 443
      max = 443
    }
  }
  egress_security_rules {
    description      = "Gemini API (generativelanguage.googleapis.com)"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_subnet" "functions" {
  compartment_id             = oci_identity_compartment.antonime.id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "antonime-functions"
  cidr_block                 = "10.20.1.0/24"
  dns_label                  = "fn"
  prohibit_public_ip_on_vnic = true # private subnet
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.functions.id]
}
