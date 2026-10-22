variable "tenancy_ocid" {
  description = "Tenancy OCID (root compartment): parent of the project compartment, target of the budget."
  type        = string
}

variable "region" {
  description = "Home region: Always Free allowances only apply there."
  type        = string
  default     = "eu-frankfurt-1"
}

variable "budget_amount" {
  description = "Monthly budget, whole number in the account's rate-card currency."
  type        = number
  default     = 1
}

variable "budget_alert_email" {
  description = "Who gets budget alerts (kept out of Git: set in terraform.tfvars)."
  type        = string
}

variable "function_image" {
  description = "Bootstrap image: used only when the function is first created. CI deploys every later image (lifecycle.ignore_changes), so this never has to change."
  type        = string
  default     = "fra.ocir.io/frjpwvcxyneb/antonime/function:43ef6b2"
}

variable "proxy_instance_ocid" {
  description = "The VM running nginx + the signing proxy: the only principal allowed to invoke the function."
  type        = string
  default     = "ocid1.instance.oc1.eu-frankfurt-1.antheljrhtkscaicttg6ritpvsa42i6u52u62bw5fywpdabpbiecskgnx3pa"
}

variable "ci_user_email" {
  description = "Email for the CI user (identity domains require one). Kept out of Git: terraform.tfvars."
  type        = string
}
