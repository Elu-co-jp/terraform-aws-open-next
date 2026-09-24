# Route 53

data "aws_route53_zone" "hosted_zone" {
  for_each     = try(var.domain_config.create_route53_entries, false) == true ? { for hosted_zone in var.domain_config.hosted_zones : join("-", compact([hosted_zone.name, hosted_zone.private_zone])) => hosted_zone if hosted_zone.id == null } : {}
  name         = each.value.name
  private_zone = each.value.private_zone

  provider = aws.dns
}

# CloudFront

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  # Use the fixed AWS managed policy ID because the name selector does not populate id.
  id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

# Zip Archives

data "archive_file" "auth_function" {
  count       = local.should_create_auth_lambda && try(var.auth_function.function_code.zip, null) == null && try(var.auth_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/code/auth.zip"
  source_dir  = "${path.module}/code/auth"
}
