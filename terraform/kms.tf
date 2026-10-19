# Customer managed key for the persistent data volume.
#
# Why not aws/ebs: the Control Tower daily backup plan copies every recovery
# point to the central backup vault in another account, and AWS Backup cannot
# copy EBS/EC2 recovery points encrypted with an AWS managed key across
# accounts (its key policy cannot be changed). This key lets the local backup
# role and the central backup account use it for those copies.

data "aws_iam_policy_document" "data_volume_key" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  # Control Tower's backup role in this account creates the recovery points.
  # Referenced only; the role itself is owned by Control Tower.
  statement {
    sid = "ControlTowerBackupRoleUse"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:role/aws-controltower-BackupRole"]
    }
  }

  # The central backup account copies the recovery points into its vault.
  statement {
    sid = "CentralBackupAccountCopy"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.backup_central_account_id}:root"]
    }
  }

  # Grants are only for AWS services (EBS, AWS Backup) acting on behalf of the
  # principals above.
  statement {
    sid       = "BackupGrantsForAwsResources"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${var.account_id}:role/aws-controltower-BackupRole",
        "arn:aws:iam::${var.backup_central_account_id}:root",
      ]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_kms_key" "data_volume" {
  description             = "Wiki.js host persistent data volume (EBS), shareable with the central backup account"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.data_volume_key.json

  tags = { Name = "wiki-js-prod-data" }

  # Losing this key makes the data volume and every backup of it unreadable.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "data_volume" {
  name          = "alias/wiki-js-prod-data"
  target_key_id = aws_kms_key.data_volume.key_id
}
