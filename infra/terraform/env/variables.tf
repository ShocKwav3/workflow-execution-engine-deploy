variable "operator_cidr" {
  description = "Public IPv4 address of the operator, as a /32 CIDR, that may reach the API load balancer. No default: pass it with -var or TF_VAR_operator_cidr."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && endswith(var.operator_cidr, "/32")
    error_message = "operator_cidr must be a single IPv4 address in CIDR form, for example 203.0.113.10/32."
  }
}
