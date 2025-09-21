output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "db_subnet_ids" { value = [for s in aws_subnet.db : s.id] }
