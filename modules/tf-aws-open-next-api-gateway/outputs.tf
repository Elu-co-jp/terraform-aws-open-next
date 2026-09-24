output "rest_api_id" {
  description = "REST API identifier"
  value       = aws_api_gateway_rest_api.this.id
}

output "rest_api_name" {
  description = "REST API name used by CloudWatch ApiName dimensions"
  value       = aws_api_gateway_rest_api.this.name
}

output "execution_arn" {
  description = "REST API execution ARN"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "stage_name" {
  description = "REST API stage name"
  value       = aws_api_gateway_stage.this.stage_name
}

output "origin_domain_name" {
  description = "execute-api hostname for use as the CloudFront origin"
  value       = "${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
}

output "origin_path" {
  description = "REST API stage path for use as the CloudFront origin path"
  value       = "/${aws_api_gateway_stage.this.stage_name}"
}

output "web_acl_arn" {
  description = "Regional WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.this.arn
}

output "cloudfront_origin_ipv4_cidrs" {
  description = "CloudFront origin-facing IPv4 snapshot applied to the Regional WAF IP set"
  value       = data.aws_ip_ranges.cloudfront_origin_facing.cidr_blocks
}

output "waf_logging" {
  description = "Regional WAF full logging configuration"
  value = {
    bucket_name      = module.waf_logging.bucket_name
    bucket_arn       = module.waf_logging.bucket_arn
    retention_days   = module.waf_logging.retention_days
    redacted_headers = module.waf_logging.redacted_headers
  }
}
