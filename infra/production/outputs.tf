output "artifact_repository" {
  description = "Artifact Registry repository for immutable alera-cloud images."
  value       = google_artifact_registry_repository.cloud.name
}

output "cloud_run_origin_url" {
  description = "Direct origin URL. Configure this as the Worker's ORIGIN_BASE_URL secret."
  value       = google_cloud_run_v2_service.cloud.uri
}

output "public_api_url" {
  description = "Supported public API route."
  value       = "https://${var.api_hostname}"
}

output "neon_project_id" {
  description = "External Neon project selected as the production database."
  value       = var.neon_project_id
}

output "jwt_kms_key_version" {
  description = "KMS version used to sign Alera access tokens."
  value       = data.google_kms_crypto_key_version.access_tokens_primary.name
}

output "firebase_android_app_id" {
  description = "Firebase Android app id used to generate google-services.json."
  value       = google_firebase_android_app.mobile.app_id
}

output "firebase_apple_app_id" {
  description = "Firebase Apple app id used to generate GoogleService-Info.plist."
  value       = google_firebase_apple_app.mobile.app_id
}

output "secret_names" {
  description = "Secret containers that must receive versions outside OpenTofu."
  value       = { for key, secret in google_secret_manager_secret.runtime : key => secret.secret_id }
}
