variable "project_name" {
  type    = string
  default = "wp-ha"
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/20","10.0.16.0/20"]
}

variable "db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.128.0/20","10.0.144.0/20"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type    = string
  default = null
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "ingress_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "domain_name" {
  type        = string
  default     = ""
  description = "example.com to enable HTTPS + DNS"
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Existing public hosted zone ID (optional)."
}

variable "db_engine_version" {
  type    = string
  default = "8.0"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "wordpress"
}

variable "rds_multi_az" {
  type    = bool
  default = true
}