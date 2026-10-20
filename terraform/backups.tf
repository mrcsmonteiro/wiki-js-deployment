# Off-instance logical backups: a nightly Wiki.js pg_dump and the PCA SQLite
# backup, uploaded by the host's backup timer (ansible/roles/backups).
#
# This complements the Control Tower daily snapshot of the data volume: those
# snapshots are block-level and restore the whole volume; these are small,
# portable files that restore one database.
#
# The instance role may only PUT objects (no read, no delete), so a compromised
# host cannot remove earlier backups. Versioning keeps overwritten keys.

locals {
  # Account-regional namespace, like the cloud-platform state buckets: no other
  # account can create or squat this name.
  backup_bucket_name = "wiki-js-prod-backups-${var.account_id}-${var.aws_region}-an"
}

resource "aws_s3_bucket" "backups" {
  bucket           = local.backup_bucket_name
  bucket_namespace = "account-regional"

  tags = { Name = "wiki-js-prod-backups" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

data "aws_iam_policy_document" "backups_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.backups]
}

# Upload-only access for the host's backup timer.
resource "aws_iam_role_policy" "backups_upload" {
  name = "wikijs-backups-upload"
  role = aws_iam_role.ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UploadBackupsOnly"
        Effect = "Allow"
        Action = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.backups.arn}/wikijs/*",
          "${aws_s3_bucket.backups.arn}/pca/*",
        ]
      },
    ]
  })
}
