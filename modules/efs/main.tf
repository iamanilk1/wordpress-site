resource "aws_efs_file_system" "wp_efs" {
  creation_token = "${var.project_name}-efs"
  encrypted = true
  tags = { Name = "${var.project_name}-efs" }
}

resource "aws_efs_access_point" "efs_ap" {
  file_system_id = aws_efs_file_system.wp_efs.id
  posix_user {
    uid = 1000
    gid = 1000
  }
  root_directory {
    path = "/wordpress"
    creation_info {
      owner_gid = 1000
      owner_uid = 1000
      permissions = "0755"
    }
  }
}

resource "aws_efs_mount_target" "mt" {
  count = length(var.subnet_ids)
  file_system_id = aws_efs_file_system.wp_efs.id
  subnet_id = var.subnet_ids[count.index]
  security_groups = [var.security_group_id]
}

output "efs_id" { value = aws_efs_file_system.wp_efs.id }
output "efs_ap_id" { value = aws_efs_access_point.efs_ap.id }
