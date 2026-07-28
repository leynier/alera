locals {
  cloud_run_hostname = trimprefix(google_cloud_run_v2_service.cloud.uri, "https://")
}

resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_hostname
  content = local.cloud_run_hostname
  type    = "CNAME"
  proxied = true
  ttl     = 1
  comment = "Alera API origin. The alera-api-edge Worker route must intercept this hostname."
  tags    = ["application:alera", "managed-by:opentofu"]
}
