locals {
  runtime_secrets = {
    database_url               = "alera-database-url"
    edge_origin_token          = "alera-edge-origin-token"
    edge_previous_origin_token = "alera-edge-previous-origin-token"
    github_oauth_client_secret = "alera-github-oauth-client-secret"
    google_oauth_client_secret = "alera-google-oauth-client-secret"
    tombstone_pepper           = "alera-tombstone-pepper"
  }
}

resource "google_secret_manager_secret" "runtime" {
  for_each = local.runtime_secrets

  secret_id = each.value
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_iam_member" "cloud_access" {
  for_each = google_secret_manager_secret.runtime

  project   = var.gcp_project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.cloud.member
}
