output "s3_bucket" {
  description = "Bucket for uploaded images"
  value       = aws_s3_bucket.images.bucket
}
