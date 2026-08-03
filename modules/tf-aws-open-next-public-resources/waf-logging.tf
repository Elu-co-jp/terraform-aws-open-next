locals {
  waf_logging_enabled = var.waf.logging != null
  waf_log_bucket_name_seed = trim(
    replace(lower(join("-", compact([
      var.prefix != null ? var.prefix : "",
      var.suffix != null ? var.suffix : "",
      "cloudfront",
    ]))), "/[^a-z0-9-]/", "-"),
    "-",
  )
  waf_log_bucket_name = format(
    "aws-waf-logs-%s-%s-%s",
    substr(local.waf_log_bucket_name_seed, 0, min(length(local.waf_log_bucket_name_seed), 24)),
    substr(sha1(local.waf_log_bucket_name_seed), 0, 6),
    data.aws_caller_identity.current.account_id,
  )
}

resource "aws_s3_bucket" "waf_logs" {
  # checkov:skip=CKV_AWS_144: Cross-region replication depends on the consumer's disaster recovery requirements
  # checkov:skip=CKV_AWS_18: Access logging would recursively create additional logs for this dedicated log bucket
  # checkov:skip=CKV_AWS_145: SSE-S3 avoids requiring every consumer to manage a customer-managed KMS key
  # checkov:skip=CKV_AWS_21: WAF logs are append-only and do not require object versioning
  # checkov:skip=CKV2_AWS_62: Event notifications depend on the consumer's log processing requirements
  count = local.waf_logging_enabled ? 1 : 0

  bucket        = local.waf_log_bucket_name
  force_destroy = try(var.waf.logging.force_destroy, false)
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  count = local.waf_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "waf_logs" {
  count = local.waf_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  count = local.waf_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  count = local.waf_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  rule {
    id     = "waf"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.waf.logging.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "waf_logs" {
  count = local.waf_logging_enabled ? 1 : 0

  statement {
    sid = "DenyInsecureTransport"

    actions = ["s3:*"]
    effect  = "Deny"
    resources = [
      aws_s3_bucket.waf_logs[0].arn,
      "${aws_s3_bucket.waf_logs[0].arn}/*",
    ]

    principals {
      identifiers = ["*"]
      type        = "*"
    }

    condition {
      test     = "Bool"
      values   = ["false"]
      variable = "aws:SecureTransport"
    }
  }

  statement {
    # Match the Sid that AWS WAF uses when it automatically maintains this statement.
    sid = "AWSLogDeliveryWrite"

    actions = ["s3:PutObject"]
    effect  = "Allow"
    resources = [
      "${aws_s3_bucket.waf_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    principals {
      identifiers = ["delivery.logs.amazonaws.com"]
      type        = "Service"
    }

    condition {
      test     = "StringEquals"
      values   = [data.aws_caller_identity.current.account_id]
      variable = "aws:SourceAccount"
    }

    condition {
      test     = "StringEquals"
      values   = ["bucket-owner-full-control"]
      variable = "s3:x-amz-acl"
    }

    condition {
      test = "ArnLike"
      # CloudFront-scope WAF resources and their log delivery configuration use us-east-1.
      values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
      variable = "aws:SourceArn"
    }
  }

  statement {
    # Match the Sid that AWS WAF uses when it automatically maintains this statement.
    sid = "AWSLogDeliveryAclCheck"

    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket",
    ]
    effect    = "Allow"
    resources = [aws_s3_bucket.waf_logs[0].arn]

    principals {
      identifiers = ["delivery.logs.amazonaws.com"]
      type        = "Service"
    }

    condition {
      test     = "StringEquals"
      values   = [data.aws_caller_identity.current.account_id]
      variable = "aws:SourceAccount"
    }

    condition {
      test = "ArnLike"
      # CloudFront-scope WAF resources and their log delivery configuration use us-east-1.
      values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
      variable = "aws:SourceArn"
    }
  }
}

resource "aws_s3_bucket_policy" "waf_logs" {
  count = local.waf_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id
  policy = data.aws_iam_policy_document.waf_logs[0].json
}

resource "aws_wafv2_web_acl_logging_configuration" "distribution_waf" {
  count = local.waf_logging_enabled ? 1 : 0

  log_destination_configs = [aws_s3_bucket.waf_logs[0].arn]
  resource_arn            = local.web_acl_id

  dynamic "redacted_fields" {
    for_each = toset([
      for header in try(var.waf.logging.redacted_headers, []) : lower(trimspace(header))
    ])

    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }

  depends_on = [
    aws_s3_bucket_lifecycle_configuration.waf_logs,
    aws_s3_bucket_ownership_controls.waf_logs,
    aws_s3_bucket_policy.waf_logs,
    aws_s3_bucket_public_access_block.waf_logs,
    aws_s3_bucket_server_side_encryption_configuration.waf_logs,
  ]
}
