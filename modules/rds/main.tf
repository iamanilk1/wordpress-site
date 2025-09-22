resource "random_password" "db" {
  length           = 16
  min_upper         = 1
  min_lower         = 1
  min_numeric       = 1
  min_special       = 1
  # Exclude characters not allowed by AWS RDS: /, @, ", and space
  override_special = "!#$%&*()_+-=[]{}|;:,.<>?"
}

resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids
  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  username             = "wpadmin"
  password             = random_password.db.result
  # deterministic instance identifier to avoid terraform-generated long names
  identifier           = "${lower(var.project_name)}-db"
  # create an initial database with the configured name
  db_name              = var.db_name
  multi_az             = var.rds_multi_az
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.rds.name
  vpc_security_group_ids = var.vpc_security_group_ids
}

resource "aws_secretsmanager_secret" "wp_db" {
  # keep secret name stable and lowercase
  name = "${lower(var.project_name)}-db-credentials-2"
}

resource "aws_secretsmanager_secret_version" "wp_db_version" {
  secret_id = aws_secretsmanager_secret.wp_db.id
  secret_string = jsonencode({
    username = "wpadmin"
    password = random_password.db.result
    host     = aws_db_instance.wordpress.address
    dbname   = var.db_name
  })
}

output "db_endpoint" { value = aws_db_instance.wordpress.address }
output "secret_arn" { value = aws_secretsmanager_secret.wp_db.arn }
