output "bucket_name" {
  description = "Name of the dedicated WAF log bucket"
  value       = aws_s3_bucket.waf_logs.bucket
}

output "bucket_arn" {
  description = "ARN of the dedicated WAF log bucket"
  value       = aws_s3_bucket.waf_logs.arn
}

output "retention_days" {
  description = "Configured WAF log retention period"
  value       = var.retention_days
}

output "redacted_headers" {
  description = "Normalized headers redacted from WAF logs"
  value       = local.normalized_redacted_headers
}
