locals {
  service_name = "alera-cloud"
  labels = {
    application = "alera"
    component   = "cloud"
    environment = "production"
    managed_by  = "opentofu"
  }
  required_services = toset([
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "firebase.googleapis.com",
    "fcm.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "cloud" {
  location      = var.gcp_region
  repository_id = "alera-cloud"
  description   = "Immutable Alera Cloud Run images"
  format        = "DOCKER"
  labels        = local.labels

  depends_on = [google_project_service.required["artifactregistry.googleapis.com"]]
}

resource "google_service_account" "cloud" {
  account_id   = "alera-cloud"
  display_name = "Alera Cloud Runtime"
  description  = "Least-privilege identity for the Alera Cloud Run service."
}

resource "google_project_iam_member" "fcm_sender" {
  project = var.gcp_project_id
  role    = "roles/firebasecloudmessaging.admin"
  member  = google_service_account.cloud.member
}
