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
