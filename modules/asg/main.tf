resource "aws_launch_template" "web_named" {
  count = var.launch_template_name != "" ? 1 : 0
  name  = var.launch_template_name
  image_id      = var.image_id
  instance_type = var.instance_type
  key_name      = var.key_name
  iam_instance_profile {
    name = var.instance_profile_name
  }
  network_interfaces {
    security_groups = var.security_group_ids
  }
  user_data = var.user_data_base64
}

resource "aws_launch_template" "web_prefix" {
  count = var.launch_template_name == "" ? 1 : 0
  name_prefix   = "${var.project_name}-web-"
  image_id      = var.image_id
  instance_type = var.instance_type
  key_name      = var.key_name
  iam_instance_profile {
    name = var.instance_profile_name
  }
  network_interfaces {
    security_groups = var.security_group_ids
  }
  user_data = var.user_data_base64
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = var.desired_capacity
  max_size             = var.max_size
  min_size             = var.min_size
  vpc_zone_identifier  = var.subnet_ids
  launch_template {
    id      = var.launch_template_name != "" ? aws_launch_template.web_named[0].id : aws_launch_template.web_prefix[0].id
    version = "$Latest"
  }
  # set explicit name if provided otherwise default
  name                 = var.asg_name != "" ? var.asg_name : "${var.project_name}-web-asg"
  target_group_arns = [var.target_group_arn]
  default_cooldown = 120
  health_check_grace_period = 180
  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }
}

output "asg_name" { value = aws_autoscaling_group.web_asg.name }
