output "workload_identity_provider" {
  description = "Provider resource name for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.alera.name
}

output "service_account" {
  description = "Service account impersonated by GitHub Actions."
  value       = google_service_account.github_deployer.email
}
