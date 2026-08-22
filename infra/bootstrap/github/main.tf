locals {
  deployer_account_id = "alera-github-deployer"
  deployer_project_roles = toset([
    "roles/artifactregistry.admin",
    "roles/cloudkms.admin",
    "roles/cloudkms.publicKeyViewer",
    "roles/firebase.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ])
  required_services = toset([
    "iam.googleapis.com",
    "sts.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "github_deployer" {
  account_id   = local.deployer_account_id
  display_name = "Alera GitHub Deployer"
  description  = "Keyless GitHub Actions identity for Alera production cloud deployments."

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "OIDC identities accepted from the Alera repository."

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_iam_workload_identity_pool_provider" "alera" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "alera-main"
  display_name                       = "Alera Main"
  description                        = "Only leynier/alera workflows running from refs/heads/main."

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
  }
  attribute_condition = join(" && ", [
    "assertion.repository == '${var.github_repository}'",
    "assertion.repository_id == '${var.github_repository_id}'",
    "assertion.repository_owner_id == '${var.github_repository_owner_id}'",
    "assertion.ref == '${var.github_branch_ref}'",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account_iam_member" "github_workload_identity" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${var.github_repository_id}"
}

resource "google_project_iam_member" "github_deployer" {
  for_each = local.deployer_project_roles

  project = var.gcp_project_id
  role    = each.value
  member  = google_service_account.github_deployer.member
}

resource "google_storage_bucket_iam_member" "production_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = google_service_account.github_deployer.member
}

resource "google_project_iam_member" "production_state_metadata_reader" {
  project = var.gcp_project_id
  role    = "roles/storage.bucketViewer"
  member  = google_service_account.github_deployer.member
}

data "google_service_account" "cloud_runtime" {
  account_id = var.runtime_service_account_id
}

resource "google_service_account_iam_member" "act_as_cloud_runtime" {
  service_account_id = data.google_service_account.cloud_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.github_deployer.member
}
