variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "candidate_number" {
  description = "Candidate number, to keep resource names unique"
  type        = string
  default     = "38"
}

variable "image_tag" {
  description = "Image tag in ECR to deploy (commit SHA)"
  type        = string
}
