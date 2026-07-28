resource "google_kms_key_ring" "identity" {
  name     = "alera-identity"
  location = var.gcp_region

  depends_on = [google_project_service.required["cloudkms.googleapis.com"]]
}

resource "google_kms_crypto_key" "access_tokens" {
  name     = "alera-access-token-signing"
  key_ring = google_kms_key_ring.identity.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_ED25519"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "google_kms_crypto_key_version" "access_tokens_primary" {
  crypto_key = google_kms_crypto_key.access_tokens.id
  version    = var.kms_key_version
}

resource "google_kms_crypto_key_iam_member" "cloud_signer" {
  crypto_key_id = google_kms_crypto_key.access_tokens.id
  role          = "roles/cloudkms.signerVerifier"
  member        = google_service_account.cloud.member
}
