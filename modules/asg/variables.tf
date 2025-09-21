variable "project_name" { type = string }
variable "launch_template_name" {
	type    = string
	default = ""
}
variable "asg_name" {
	type    = string
	default = ""
}
variable "image_id" { type = string }
variable "instance_type" { type = string }
variable "key_name" { type = string }
variable "instance_profile_name" { type = string }
variable "security_group_ids" { type = list(string) }
variable "subnet_ids" { type = list(string) }
variable "target_group_arn" { type = string }
variable "user_data_base64" { type = string }
variable "desired_capacity" { type = number }
variable "min_size" { type = number }
variable "max_size" { type = number }
