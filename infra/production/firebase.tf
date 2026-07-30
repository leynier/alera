resource "google_firebase_project" "alera" {
  provider = google-beta
  project  = var.gcp_project_id

  depends_on = [google_project_service.required["firebase.googleapis.com"]]
}

resource "google_firebase_android_app" "mobile" {
  provider = google-beta

  project      = var.gcp_project_id
  display_name = "Alera Mobile"
  package_name = "dev.leynier.alera_mobile"

  depends_on = [google_firebase_project.alera]
}

resource "google_firebase_apple_app" "mobile" {
  provider = google-beta

  project      = var.gcp_project_id
  display_name = "Alera Mobile"
  bundle_id    = "dev.leynier.aleraMobile"

  depends_on = [google_firebase_project.alera]
}
