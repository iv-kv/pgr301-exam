# Bucket for uploaded images. Name must be globally unique across all AWS accounts.
resource "aws_s3_bucket" "images" {
  bucket        = "pgr301-wishifai-${var.candidate_number}-images"
  force_destroy = true
}

# Current AWS account ID, used in ARNs below.
data "aws_caller_identity" "current" {}

# Task role: permissions for the app itself (not ECS). Only ECS tasks can use it.
resource "aws_iam_role" "task" {
  name = "wishifai-task-role-${var.candidate_number}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least privilege: only the calls the app actually makes.
resource "aws_iam_role_policy" "task" {
  name = "wishifai-task-policy-${var.candidate_number}"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UploadImages"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Sid      = "DetectLabels"
        Effect   = "Allow"
        Action   = "rekognition:DetectLabels"
        Resource = "*"
      },
      {
        # EU inference profile routes to several EU regions, so region is wildcard.
        Sid    = "InvokeClaude"
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        Resource = [
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0"
        ]
      },
      {
        Sid      = "PublishMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}
