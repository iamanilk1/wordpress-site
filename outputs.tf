output "created_hosted_zone_id" {
	value       = length(aws_route53_zone.primary) > 0 ? aws_route53_zone.primary[0].zone_id : ""
	description = "The hosted zone id created for the domain (empty if none created)."
}

#output "alb_dns_name" {
#	value = module.alb.alb_dns_name
#}

#output "tg_arn" {
#	value = module.alb.tg_arn
#}

