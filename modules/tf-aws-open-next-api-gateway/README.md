# OpenNext Regional REST API Gateway

Creates a Regional REST API Gateway origin for the default OpenNext Server Lambda alias.

The module owns:

- root and `/{proxy+}` `ANY` Lambda proxy integrations
- a deployment, stage, access and execution log groups, and alias-scoped Lambda permission
- a Regional WAF that requires both a CloudFront origin-facing IPv4 source and `X-Origin-Verify`
- full Regional WAF logging through `tf-aws-waf-logging`

CloudFront origin-facing ranges are read from the AWS `ip-ranges.json` snapshot during Terraform plan/apply. Automatic refresh after AWS publishes a new range is intentionally outside this module; run a reviewed Terraform plan/apply when the range feed changes.

API Gateway exposes the viewer address as the request origin even when the request arrives through CloudFront. The Regional WAF therefore validates the last address in `X-Forwarded-For`, which CloudFront appends as its origin-facing address. A missing or malformed header fails the origin check.

Normally pass one accepted origin verification value. During rotation, pass the current and pending values together, switch the CloudFront active value, and then remove the old value in a later apply. The map supports at most two values.

```hcl
module "api_gateway" {
  source = "../tf-aws-open-next-api-gateway"

  prefix               = "example-stg"
  lambda_function_name = module.server_function.name
  lambda_alias_name    = "staging"
  lambda_alias_arn     = module.server_function.alias_arns["staging"]

  origin_verify_secrets = {
    blue = var.origin_verify_secret_blue
  }
}
```

The API Gateway account-level CloudWatch role must already exist in the application account and Region. This repository intentionally does not own that singleton setting.

If execution logging was enabled before this module started managing its execution log group, import the existing `API-Gateway-Execution-Logs_<rest-api-id>/<stage-name>` group into `aws_cloudwatch_log_group.execution_logs` before applying.

The default execute-api endpoint remains enabled because it is the CloudFront origin. Direct requests are rejected by the Regional WAF unless they satisfy both origin checks.
