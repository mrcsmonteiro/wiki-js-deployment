resource "aws_iam_role" "ssm_role" {
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

# Lets the Wiki.js boot unit read the database password. The parameter is a
# SecureString with the AWS managed aws/ssm key, created by hand (never in this
# repo or in state). The aws/ssm key policy already allows decryption through
# SSM for principals in this account, so no KMS statement is needed.
resource "aws_iam_role_policy" "wikijs_db_password" {
  name = "wikijs-db-password-read"
  role = aws_iam_role.ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadWikijsDbPassword"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter${var.db_password_parameter}"
      },
    ]
  })
}
