// Root module - orchestrates modular components
module "vpc" {
  source = "./modules/vpc"
  project_name = var.project_name
  vpc_cidr = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  db_subnet_cidrs = var.db_subnet_cidrs
}

module "sg" {
  source = "./modules/sg"
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  ingress_ssh_cidr = var.ingress_ssh_cidr
}

module "rds" {
  source = "./modules/rds"
  project_name = var.project_name
  db_subnet_ids = module.vpc.db_subnet_ids
  vpc_security_group_ids = [module.sg.rds_sg_id]
  db_engine_version = var.db_engine_version
  db_instance_class = var.db_instance_class
  db_name = var.db_name
}

module "efs" {
  source = "./modules/efs"
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.db_subnet_ids
  security_group_id = module.sg.efs_sg_id
}

# Create a Route53 hosted zone for the domain if the user supplied a domain_name
resource "aws_route53_zone" "primary" {
  count = var.domain_name == "" ? 0 : 1
  name  = var.domain_name
}

module "iam" {
  source = "./modules/iam"
  project_name = var.project_name
  db_secret_arn = module.rds.secret_arn
}

// Render userdata with rendered values (secret arn, efs ids, region etc.)
data "template_file" "userdata" {
  template = file("${path.module}/userdata.tpl")
  vars = {
    secret_arn = module.rds.secret_arn
    efs_id     = module.efs.efs_id
    efs_ap_id  = module.efs.efs_ap_id
    db_endpoint = module.rds.db_endpoint
    db_name     = var.db_name
    db_user     = "wpadmin"
    region      = var.region
  }
}

module "alb" {
  source = "./modules/alb"
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id = module.sg.alb_sg_id
  domain_name = var.domain_name
  hosted_zone_id = var.hosted_zone_id != "" ? var.hosted_zone_id : (length(aws_route53_zone.primary) > 0 ? aws_route53_zone.primary[0].zone_id : "")
}

module "asg" {
  source = "./modules/asg"
  project_name = var.project_name
  image_id = data.aws_ami.amazon_linux2.id
  instance_type = var.instance_type
  key_name = var.key_name
  instance_profile_name = module.iam.instance_profile_name
  security_group_ids = [module.sg.instance_sg_id]
  subnet_ids = module.vpc.public_subnet_ids
  target_group_arn = module.alb.tg_arn
  user_data_base64 = base64encode(data.template_file.userdata.rendered)
  desired_capacity = var.desired_capacity
  min_size = var.min_size
  max_size = var.max_size
  # Use name_prefix in module to avoid name collisions when re-applying
  launch_template_name = ""
  asg_name = "${var.project_name}-web-asg"
}

/* Auto-scale on ALB HTTP 5xx spikes: create CloudWatch alarm on target-group 5xx and attach step-scaling policy */
data "aws_caller_identity" "current" {}



/* Target-tracking scaling on ALB requests per target */
## Step scaling based on ALB Target Group RequestCount (www only)
resource "aws_autoscaling_policy" "scale_out_step" {
  name                   = "${var.project_name}-scale-out-step"
  autoscaling_group_name = module.asg.asg_name
  policy_type            = "StepScaling"
  adjustment_type        = "ExactCapacity"

  # With a single alarm at threshold 30, these bounds are differences over 30
  # 30-49 (diff 0-19) => capacity 2
  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 20
    scaling_adjustment          = 2
  }
  # 50-99 (diff 20-69) => capacity 4
  step_adjustment {
    metric_interval_lower_bound = 20
    metric_interval_upper_bound = 70
    scaling_adjustment          = 4
  }
  # 100+ (diff >=70) => capacity 6 (max)
  step_adjustment {
    metric_interval_lower_bound = 70
    scaling_adjustment          = 6
  }
}

resource "aws_cloudwatch_metric_alarm" "req_gt_30" {
  alarm_name          = "${var.project_name}-requests-gt-30"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 30
  alarm_description   = "Requests >= 30 in 1 minute on www"
  dimensions = {
    TargetGroup  = module.alb.tg_arn_suffix
    LoadBalancer = module.alb.alb_arn_suffix
  }
  alarm_actions = [aws_autoscaling_policy.scale_out_step.arn]
}

// Removed additional alarms; single alarm drives step policy via difference from threshold

resource "aws_autoscaling_policy" "scale_in_exact_1" {
  name                   = "${var.project_name}-scale-in-1"
  autoscaling_group_name = module.asg.asg_name
  policy_type            = "StepScaling"
  adjustment_type        = "ExactCapacity"
  step_adjustment {
    # For a LessThanThreshold alarm, use an upper bound of 0 to cover all
    # values below the threshold; avoids a positive upper bound requirement.
    metric_interval_upper_bound = 0
    scaling_adjustment          = 2
  }
}

resource "aws_cloudwatch_metric_alarm" "req_lt_10" {
  alarm_name          = "${var.project_name}-requests-lt-10"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Requests < 10 for 2 minutes on www"
  dimensions = {
    TargetGroup  = module.alb.tg_arn_suffix
    LoadBalancer = module.alb.alb_arn_suffix
  }
  alarm_actions = [aws_autoscaling_policy.scale_in_exact_1.arn]
}



// Data sources used by modules
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {}

// Outputs
output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "db_password_secret_arn" {
  value     = module.rds.secret_arn
  sensitive = true
}
