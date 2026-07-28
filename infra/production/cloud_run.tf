locals {
  plain_environment = {
    ALERA_ALLOW_DIRECT_ORIGIN    = "false"
    ALERA_AUDIENCE               = "alera-cloud"
    ALERA_BIND                   = "0.0.0.0:8080"
    ALERA_FCM_MODE               = "http"
    ALERA_FCM_PROJECT_ID         = var.gcp_project_id
    ALERA_GITHUB_CLIENT_ID       = var.github_oauth_client_id
    ALERA_GOOGLE_CLIENT_ID       = var.google_oauth_client_id
    ALERA_ISSUER                 = "https://${var.api_hostname}"
    ALERA_KMS_PREVIOUS_JWKS_JSON = var.previous_jwks_json
    ALERA_KMS_PUBLIC_KEY_B64URL  = var.kms_public_key_b64url
    ALERA_KMS_SIGN_URL           = "https://cloudkms.googleapis.com/v1/${data.google_kms_crypto_key_version.access_tokens_primary.name}:asymmetricSign"
    ALERA_MAX_MOBILE_DEVICES     = tostring(var.account_mobile_limit)
    ALERA_MAX_RUNTIMES           = tostring(var.account_runtime_limit)
    ALERA_PUBLIC_BASE_URL        = "https://${var.api_hostname}"
    ALERA_PUSH_BURST_LIMIT       = "10"
    ALERA_PUSH_DAILY_LIMIT       = tostring(var.notification_daily_limit)
    ALERA_PUSH_DELIVERY_ENABLED  = tostring(var.push_delivery_enabled)
    ALERA_PUSH_HOURLY_LIMIT      = tostring(var.notification_hourly_limit)
    ALERA_SIGNING_KEY_ID         = var.signing_key_id
    ALERA_SIGNING_MODE           = "google-kms"
    RUST_LOG                     = "alera_cloud=info,tower_http=info"
  }
  secret_environment = merge(
    {
      ALERA_EDGE_ORIGIN_TOKEN    = google_secret_manager_secret.runtime["edge_origin_token"].secret_id
      ALERA_GITHUB_CLIENT_SECRET = google_secret_manager_secret.runtime["github_oauth_client_secret"].secret_id
      ALERA_GOOGLE_CLIENT_SECRET = google_secret_manager_secret.runtime["google_oauth_client_secret"].secret_id
      ALERA_TOMBSTONE_PEPPER     = google_secret_manager_secret.runtime["tombstone_pepper"].secret_id
      DATABASE_URL               = google_secret_manager_secret.runtime["database_url"].secret_id
    },
    var.enable_previous_edge_origin_token ? {
      ALERA_EDGE_PREVIOUS_ORIGIN_TOKEN = google_secret_manager_secret.runtime["edge_previous_origin_token"].secret_id
    } : {},
  )
}

resource "google_cloud_run_v2_service" "cloud" {
  name                = local.service_name
  location            = var.gcp_region
  deletion_protection = true
  ingress             = "INGRESS_TRAFFIC_ALL"
  labels              = local.labels

  template {
    labels = merge(local.labels, {
      revision = var.cloud_run_revision
    })

    service_account                  = google_service_account.cloud.email
    timeout                          = "30s"
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = var.cloud_run_image

      ports {
        container_port = 8080
      }

      resources {
        cpu_idle          = true
        startup_cpu_boost = true
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 3
        period_seconds        = 3
        failure_threshold     = 10

        http_get {
          path = "/healthz"
          port = 8080
        }
      }

      liveness_probe {
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 30
        failure_threshold     = 3

        http_get {
          path = "/healthz"
          port = 8080
        }
      }

      dynamic "env" {
        for_each = local.plain_environment
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secret_environment
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_kms_crypto_key_iam_member.cloud_signer,
    google_project_iam_member.fcm_sender,
    google_secret_manager_secret_iam_member.cloud_access,
    google_project_service.required["run.googleapis.com"],
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.gcp_project_id
  location = google_cloud_run_v2_service.cloud.location
  name     = google_cloud_run_v2_service.cloud.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
