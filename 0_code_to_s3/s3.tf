# ---------------------------------------------------------------------------------------------------------------------
# RANDOM SUFFIX FOR BUCKET NAMES
# ---------------------------------------------------------------------------------------------------------------------
resource "random_uuid" "s3_suffix" {}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET IN REGION 1 (SOURCE)
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "source_code_bucket_region_1" {
  bucket = "gt-s3-arc-code-${random_uuid.s3_suffix.result}-${var.aws_region_1}"
  acl    = "private"
  force_destroy = true

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "S3_code_region_1_public_block" {
  bucket = aws_s3_bucket.source_code_bucket_region_1.id

  block_public_acls   = true
  block_public_policy = true
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET IN REGION 2 (DESTINATION)
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "source_code_bucket_region_2" {
  provider = aws.region2
  bucket   = "gt-s3-arc-code-${random_uuid.s3_suffix.result}-${var.aws_region_2}"
  acl      = "private"
  force_destroy = true

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "S3_code_region_2_public_block" {
  provider = aws.region2
  bucket   = aws_s3_bucket.source_code_bucket_region_2.id

  block_public_acls   = true
  block_public_policy = true
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM ROLE FOR S3 REPLICATION
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "s3_replication_role" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication_policy" {
  name = "s3-replication-policy"
  role = aws_iam_role.s3_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source_code_bucket_region_1.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.source_code_bucket_region_1.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.source_code_bucket_region_2.arn}/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# DESTINATION BUCKET POLICY (REGION 2)
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "destination_bucket_policy" {
  provider = aws.region2
  bucket   = aws_s3_bucket.source_code_bucket_region_2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowReplicationFromSource"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication_role.arn
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.source_code_bucket_region_2.arn}/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# REPLICATION CONFIGURATION ON SOURCE BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket_replication_configuration" "replication" {
  depends_on = [
    aws_s3_bucket.source_code_bucket_region_1,
    aws_iam_role_policy.s3_replication_policy,
    aws_s3_bucket_policy.destination_bucket_policy
  ]

  bucket = aws_s3_bucket.source_code_bucket_region_1.id
  role   = aws_iam_role.s3_replication_role.arn

  rule {
    id     = "replicate-to-region2"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.source_code_bucket_region_2.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = "" # Replicate all objects
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------
output "source_code_bucket_name" {
  value = aws_s3_bucket.source_code_bucket_region_1.bucket
}

output "source_code_bucket_arn" {
  value = aws_s3_bucket.source_code_bucket_region_1.arn
}

output "source_code_bucket_region_2_name" {
  value = aws_s3_bucket.source_code_bucket_region_2.bucket
}

output "source_code_bucket_region_2_arn" {
  value = aws_s3_bucket.source_code_bucket_region_2.arn
}
