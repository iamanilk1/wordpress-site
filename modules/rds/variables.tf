variable "project_name" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "db_engine_version" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_name" {
  type        = string
  description = "Initial database name to create on the RDS instance. Defaults to 'wordpress' when empty."
  default     = "wordpress"
}

variable "rds_multi_az" {
  type    = bool
  default = false
}
