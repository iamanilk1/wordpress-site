# Scenario 1 — Multi‑tier Simple Login App on AWS (Terraform)

This scenario provisions a highly available, secure baseline for a classic three‑tier web application on AWS using Terraform.

It uses reusable modules to stand up:
- Networking (VPC, subnets, routing)
- Security (security groups, IAM)
- Compute (Auto Scaling Group for app servers)
- Load Balancing (Application Load Balancer)
- Data (RDS MySQL)
- Shared storage (EFS)

The goal is to provide a clean foundation for a Simple Login application (frontend + backend API + MySQL storage) with best practices for availability and security.

## Repository layout

- `main.tf`, `providers.tf`, `variables.tf`, `outputs.tf` — root stack wiring and configuration
- `terraform.tfvars` — example values for variables (edit to your needs)
- `userdata.tpl` — cloud‑init/user data for EC2 instances (install app/runtime, bootstrap)
- `modules/` — service modules (alb, asg, efs, iam, rds, sg, vpc)

## What gets created (at a glance)

- VPC with public and private subnets across multiple AZs
- Internet Gateway, route tables for public subnets (and NAT if enabled in module)
- Application Load Balancer (public) with target group + listeners
- Auto Scaling Group (private subnets) for application EC2 instances
- RDS MySQL instance (private subnets)
- EFS file system (for shared app data/logs if needed)
- Security groups with least‑privilege rules between tiers
- IAM roles/policies for EC2 and services as required

Refer to each module’s `variables.tf` for exact knobs and defaults.

## Prerequisites

- Terraform CLI (1.4+ recommended)
- AWS account and credentials configured (env vars, shared profile, or SSO)
- Appropriate IAM permissions to create the listed resources

## Configure

1) Review `variables.tf` for available inputs.
2) Edit `terraform.tfvars` with your values (region, CIDRs, instance type, DB name/user/password, key pair, etc.).
3) Optionally tailor `userdata.tpl` to install/configure your Simple Login app.

## Deploy (optional commands)

```sh
# From the scenario1 folder
terraform init
terraform plan
terraform apply
```

After apply, check outputs for:
- ALB DNS name (use this to access the app)
- RDS endpoint (for migrations/seeding)
- VPC/Subnet IDs, EFS ID (for troubleshooting/ops)

## Destroy (optional)

```sh
terraform destroy
```

Note: Some resources (e.g., RDS snapshots, EFS with files, or S3 logs if enabled) may require additional cleanup depending on module settings.

## Security & cost notes

- Resources in this scenario incur AWS costs; destroy when not in use.
- Restrict inbound traffic to ALB/SSH per your org policy.
- Store secrets (DB password, etc.) securely (e.g., SSM Parameter Store/Secrets Manager) rather than plain `tfvars`.

## Troubleshooting tips

- If ALB health checks fail, review the instance user data, SG rules, and target group port/path.
- Ensure private subnets have egress via NAT (if instances need to reach the Internet for package installs).
- Check `terraform state list` and module logs for resource details when debugging.
