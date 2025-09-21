variable "project_name" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager secret ARN for DB credentials (required)"
  type        = string

  validation {
    condition     = length(var.db_secret_arn) > 0
    error_message = "db_secret_arn must be provided to grant EC2 permission to read DB credentials."
  }
}
