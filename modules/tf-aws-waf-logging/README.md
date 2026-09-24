# WAF full logging

Creates a dedicated `aws-waf-logs-*` S3 bucket and attaches full logging to one WAFv2 Web ACL. It supports both CloudFront-scope Web ACLs in `us-east-1` and Regional Web ACLs by deriving the log-delivery source Region from the module provider.

The bucket has public access blocked, bucket-owner-enforced ownership, SSE-S3 encryption, lifecycle expiration, and a TLS-only bucket policy. Configure sensitive HTTP fields with `redacted_headers`.

Configure the module provider for the same account and Region as the Web ACL. Use `us-east-1` for a CloudFront-scope Web ACL and the protected resource Region for a Regional Web ACL. `redacted_headers` applies only to full WAF logs and does not redact sampled requests; disable sampled requests or configure Web ACL data protection separately when sampled request data can contain sensitive fields.

```hcl
module "waf_logging" {
  source = "../tf-aws-waf-logging"

  bucket_name_seed = "example-api-gateway"
  web_acl_arn      = aws_wafv2_web_acl.this.arn
  retention_days   = 90
  redacted_headers = ["authorization", "cookie", "x-api-key", "x-origin-verify"]
}
```

Moving existing inline logging resources into this module changes their Terraform addresses. Import or `terraform state mv` the existing resources before applying; this module does not include `moved` blocks because callers can have different parent addresses.
