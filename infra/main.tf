# Bucket for uploaded images. Name must be globally unique across all AWS accounts.
resource "aws_s3_bucket" "images" {
  bucket        = "pgr301-wishifai-${var.candidate_number}-images"
  force_destroy = true
}
