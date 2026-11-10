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

# Existing ECR repo. Read only, fails early if missing.
data "aws_ecr_repository" "app" {
  name = "wishifai-${var.candidate_number}"
}

resource "aws_ecs_express_gateway_service" "app" {
  service_name = "wishifai-${var.candidate_number}"

  # Existing class roles (given in the task) + our own task role.
  execution_role_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"
  infrastructure_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/ecsInfrastructureRoleForExpressServices"
  task_role_arn           = aws_iam_role.task.arn

  # Smaller than default (1 vCPU / 2 GB) to keep cost down.
  cpu    = "512"
  memory = "1024"

  # Default is "/", which the app doesn't serve.
  health_check_path = "/actuator/health"

  # Wait until tasks are healthy, so a broken deploy fails the apply.
  wait_for_steady_state = true

  primary_container {
    image          = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
    container_port = 8080

    # Bucket name set automatically from the bucket resource.
    environment {
      name  = "S3_BUCKET"
      value = aws_s3_bucket.images.bucket
    }

    environment {
      name  = "AWS_REGION"
      value = var.region
    }
  }

  # Cost safety: max 2 tasks (default is 20).
  scaling_target {
    min_task_count            = 1
    max_task_count            = 2
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = 60
  }

  # Keep policy until service is gone, otherwise delete can hang in DRAINING.
  depends_on = [aws_iam_role_policy.task]
}
