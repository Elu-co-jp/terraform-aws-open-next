variable "bucket_name_seed" {
  description = "Stable seed used to build the aws-waf-logs-* bucket name"
  type        = string
}

variable "web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL to log"
  type        = string
}

variable "force_destroy" {
  description = "Whether the dedicated log bucket may be destroyed with objects"
  type        = bool
  default     = false
}

variable "retention_days" {
  description = "Number of days to retain WAF log objects"
  type        = number
  default     = 90

  validation {
    condition     = var.retention_days >= 1 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be a positive integer."
  }
}

variable "redacted_headers" {
  description = "HTTP headers redacted from full WAF logs"
  type        = list(string)
  default     = ["authorization", "apikey", "cookie", "x-api-key"]

  validation {
    condition = (
      length(distinct([for header in var.redacted_headers : lower(trimspace(header))])) <= 100 &&
      alltrue([
        for header in var.redacted_headers :
        length(header) >= 1 &&
        length(header) <= 64 &&
        can(regex("^[0-9A-Za-z-]+$", header))
      ])
    )
    error_message = "redacted_headers must contain at most 100 valid HTTP header names, each between 1 and 64 characters."
  }
}

variable "tags" {
  description = "Tags applied to the dedicated S3 log bucket"
  type        = map(string)
  default     = {}
}
