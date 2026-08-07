data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  normalized_bucket_name_seed = trim(replace(lower(var.bucket_name_seed), "/[^a-z0-9-]/", "-"), "-")
  bucket_name = format(
    "aws-waf-logs-%s-%s-%s",
    substr(local.normalized_bucket_name_seed, 0, min(length(local.normalized_bucket_name_seed), 24)),
    substr(sha1(local.normalized_bucket_name_seed), 0, 6),
    data.aws_caller_identity.current.account_id,
  )
  normalized_redacted_headers = sort(distinct([
    for header in var.redacted_headers : lower(trimspace(header))
  ]))
}

resource "aws_s3_bucket" "waf_logs" {
  # checkov:skip=CKV_AWS_144: Cross-region replication depends on the consumer's disaster recovery requirements
  # checkov:skip=CKV_AWS_18: Access logging would recursively create additional logs for this dedicated log bucket
  # checkov:skip=CKV_AWS_145: SSE-S3 avoids requiring every consumer to manage a customer-managed KMS key
  # checkov:skip=CKV_AWS_21: WAF logs are append-only and do not require object versioning
  # checkov:skip=CKV2_AWS_62: Event notifications depend on the consumer's log processing requirements
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    id     = "waf"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "waf_logs" {
  statement {
    sid = "DenyInsecureTransport"

    actions = ["s3:*"]
    effect  = "Deny"
    resources = [
      aws_s3_bucket.waf_logs.arn,
      "${aws_s3_bucket.waf_logs.arn}/*",
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
    sid = "AWSLogDeliveryWrite"

    actions = ["s3:PutObject"]
    effect  = "Allow"
    resources = [
      "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
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
      test     = "ArnLike"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
      variable = "aws:SourceArn"
    }
  }

  statement {
    sid = "AWSLogDeliveryAclCheck"

    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket",
    ]
    effect    = "Allow"
    resources = [aws_s3_bucket.waf_logs.arn]

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
      test     = "ArnLike"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
      variable = "aws:SourceArn"
    }
  }
}

resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id
  policy = data.aws_iam_policy_document.waf_logs.json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  log_destination_configs = [aws_s3_bucket.waf_logs.arn]
  resource_arn            = var.web_acl_arn

  dynamic "redacted_fields" {
    for_each = toset(local.normalized_redacted_headers)

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
