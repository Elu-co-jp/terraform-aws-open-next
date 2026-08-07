variable "prefix" {
  description = "Optional resource name prefix"
  type        = string
  default     = null
}

variable "suffix" {
  description = "Optional resource name suffix"
  type        = string
  default     = null
}

variable "lambda_function_name" {
  description = "Server Lambda function name"
  type        = string
}

variable "lambda_alias_name" {
  description = "Server Lambda alias invoked by API Gateway"
  type        = string
}

variable "lambda_alias_arn" {
  description = "ARN of the Server Lambda alias invoked by API Gateway"
  type        = string
}

variable "stage_name" {
  description = "REST API deployment stage name"
  type        = string
  default     = "stable"
}

variable "integration_timeout_milliseconds" {
  description = "API Gateway Lambda integration timeout in milliseconds"
  type        = number
  default     = 29000

  validation {
    condition     = var.integration_timeout_milliseconds >= 50 && var.integration_timeout_milliseconds <= 300000
    error_message = "integration_timeout_milliseconds must be between 50 and 300000. Values above the account quota still require an approved API Gateway quota increase."
  }
}

variable "binary_media_types" {
  description = "Binary media types supported by the REST API"
  type        = list(string)
  default     = ["*/*"]
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch access and execution log retention period"
  type        = number
  default     = 90
}

variable "origin_verify_secrets" {
  description = "Accepted X-Origin-Verify values keyed by stable logical name; normally one value and at most two during rotation"
  type        = map(string)
  sensitive   = true

  validation {
    condition     = length(var.origin_verify_secrets) >= 1 && length(var.origin_verify_secrets) <= 2
    error_message = "origin_verify_secrets must contain one value normally, or two values temporarily during rotation."
  }

  validation {
    condition     = alltrue([for value in values(var.origin_verify_secrets) : length(value) >= 16 && length(value) <= 50])
    error_message = "Each origin verification secret must contain between 16 and 50 characters."
  }
}

variable "waf_log_retention_days" {
  description = "S3 retention period for full Regional WAF logs"
  type        = number
  default     = 90
}

variable "waf_log_force_destroy" {
  description = "Whether the dedicated Regional WAF log bucket may be destroyed with objects"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to resources that support tags"
  type        = map(string)
  default     = {}
}
