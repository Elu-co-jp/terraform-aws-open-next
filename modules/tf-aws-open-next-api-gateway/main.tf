data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_ip_ranges" "cloudfront_origin_facing" {
  regions  = ["global"]
  services = ["cloudfront_origin_facing"]
}

locals {
  resource_name = join("-", compact([
    var.prefix,
    "open-next-server",
    var.suffix,
  ]))
  secret_keys = nonsensitive(toset(keys(var.origin_verify_secrets)))
  integration_uri = format(
    "arn:%s:apigateway:%s:lambda:path/2015-03-31/functions/%s/invocations",
    data.aws_partition.current.partition,
    data.aws_region.current.region,
    var.lambda_alias_arn,
  )
}

resource "aws_api_gateway_rest_api" "this" {
  name        = local.resource_name
  description = "Regional REST API origin for the OpenNext Server Lambda"

  binary_media_types           = var.binary_media_types
  disable_execute_api_endpoint = false

  endpoint_configuration {
    ip_address_type = "ipv4"
    types           = ["REGIONAL"]
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method" "root" {
  # checkov:skip=CKV_AWS_59: The API is intentionally a Lambda proxy; the associated Regional WAF requires CloudFront origin-facing IP and X-Origin-Verify before invocation
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_rest_api.this.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.integration_uri
  timeout_milliseconds    = var.integration_timeout_milliseconds
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  # checkov:skip=CKV_AWS_59: The API is intentionally a Lambda proxy; the associated Regional WAF requires CloudFront origin-facing IP and X-Origin-Verify before invocation
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.integration_uri
  timeout_milliseconds    = var.integration_timeout_milliseconds
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode({
      binary_media_types   = var.binary_media_types
      root_method_id       = aws_api_gateway_method.root.id
      root_integration_id  = aws_api_gateway_integration.root.id
      proxy_resource_id    = aws_api_gateway_resource.proxy.id
      proxy_method_id      = aws_api_gateway_method.proxy.id
      proxy_integration_id = aws_api_gateway_integration.proxy.id
      lambda_alias_arn     = var.lambda_alias_arn
      timeout_milliseconds = var.integration_timeout_milliseconds
    }))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "access_logs" {
  # checkov:skip=CKV_AWS_338: Retention follows the caller's environment-specific application log policy
  # checkov:skip=CKV_AWS_158: CloudWatch Logs service-side encryption is sufficient; a customer-managed KMS key is not required by this design
  name              = "/aws/apigateway/${local.resource_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "execution_logs" {
  # checkov:skip=CKV_AWS_338: Retention follows the caller's environment-specific application log policy
  # checkov:skip=CKV_AWS_158: CloudWatch Logs service-side encryption is sufficient; a customer-managed KMS key is not required by this design
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.this.id}/${var.stage_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = var.tags
}

resource "aws_api_gateway_stage" "this" {
  # checkov:skip=CKV_AWS_120: Dynamic OpenNext SSR/API responses must not be cached at API Gateway; CloudFront owns response caching
  # checkov:skip=CKV_AWS_73: X-Ray is not enabled by default because application tracing is an explicit opt-in with additional cost
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      extendedRequestId  = "$context.extendedRequestId"
      sourceIp           = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      resourcePath       = "$context.resourcePath"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
      integrationError   = "$context.integrationErrorMessage"
    })
  }

  tags = var.tags
}

resource "aws_api_gateway_method_settings" "all" {
  # checkov:skip=CKV_AWS_225: Dynamic OpenNext SSR/API responses must not be cached at API Gateway; CloudFront owns response caching
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    data_trace_enabled = false
    logging_level      = "ERROR"
    metrics_enabled    = true
  }

  depends_on = [aws_cloudwatch_log_group.execution_logs]
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id   = "AllowExecutionFromApiGateway-${var.lambda_alias_name}"
  action         = "lambda:InvokeFunction"
  function_name  = var.lambda_function_name
  qualifier      = var.lambda_alias_name
  principal      = "apigateway.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "${aws_api_gateway_rest_api.this.execution_arn}/${aws_api_gateway_stage.this.stage_name}/*/*"

  # Keep the API non-invokable until the origin gate is associated with the stage.
  depends_on = [aws_wafv2_web_acl_association.this]
}

resource "aws_wafv2_ip_set" "cloudfront_origin_facing" {
  name               = "${local.resource_name}-cloudfront-origin-facing"
  description        = "AWS-managed CloudFront origin-facing IPv4 ranges captured at Terraform plan/apply time"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = data.aws_ip_ranges.cloudfront_origin_facing.cidr_blocks
  tags               = var.tags
}

resource "aws_wafv2_web_acl" "this" {
  # checkov:skip=CKV_AWS_192: This origin Web ACL only authenticates CloudFront; attack-protection managed rules including Log4j inspection belong to the viewer-facing CloudFront Web ACL
  name        = "${local.resource_name}-origin"
  description = "Restricts the OpenNext API Gateway origin to CloudFront and accepted origin verification secrets"
  scope       = "REGIONAL"
  tags        = var.tags

  default_action {
    allow {}
  }

  rule {
    name     = "block-non-cloudfront-origin-facing-ip"
    priority = 0

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.cloudfront_origin_facing.arn

            # Match the CloudFront origin-facing IP appended to X-Forwarded-For.
            ip_set_forwarded_ip_config {
              fallback_behavior = "NO_MATCH"
              header_name       = "X-Forwarded-For"
              position          = "LAST"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.resource_name}-cloudfront-origin-facing"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "block-invalid-origin-verify-secret"
    priority = 1

    action {
      block {}
    }

    statement {
      not_statement {
        dynamic "statement" {
          for_each = length(local.secret_keys) == 1 ? local.secret_keys : toset([])

          content {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = var.origin_verify_secrets[statement.value]

              field_to_match {
                single_header {
                  name = "x-origin-verify"
                }
              }

              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
        }

        dynamic "statement" {
          for_each = length(local.secret_keys) == 2 ? [local.secret_keys] : []

          content {
            or_statement {
              dynamic "statement" {
                for_each = statement.value

                content {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = var.origin_verify_secrets[statement.value]

                    field_to_match {
                      single_header {
                        name = "x-origin-verify"
                      }
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.resource_name}-origin-verify"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.resource_name}-origin"
    sampled_requests_enabled   = false
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = "arn:${data.aws_partition.current.partition}:apigateway:${data.aws_region.current.region}::/restapis/${aws_api_gateway_rest_api.this.id}/stages/${aws_api_gateway_stage.this.stage_name}"
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

module "waf_logging" {
  source = "../tf-aws-waf-logging"

  bucket_name_seed = "${local.resource_name}-api-gateway"
  web_acl_arn      = aws_wafv2_web_acl.this.arn
  force_destroy    = var.waf_log_force_destroy
  retention_days   = var.waf_log_retention_days
  redacted_headers = ["authorization", "cookie", "x-api-key", "x-origin-verify"]
  tags             = var.tags
}
