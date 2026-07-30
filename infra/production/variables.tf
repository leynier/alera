variable "gcp_project_id" {
  description = "Existing Google Cloud project that owns Cloud Run, KMS, and Firebase."
  type        = string
}

variable "gcp_region" {
  description = "United States region for Cloud Run and KMS."
  type        = string
  default     = "us-central1"
}

variable "cloud_run_image" {
  description = "Immutable container image digest for alera-cloud."
  type        = string

  validation {
    condition     = strcontains(var.cloud_run_image, "@sha256:")
    error_message = "cloud_run_image must be pinned by sha256 digest."
  }
}

variable "cloud_run_revision" {
  description = "Non-secret revision marker. Change it whenever an out-of-band latest secret version must create a new Cloud Run revision."
  type        = string
  default     = "initial"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.cloud_run_revision))
    error_message = "cloud_run_revision must be a lowercase Cloud Run label value."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone id for alera.build. Authenticate the provider with CLOUDFLARE_API_TOKEN."
  type        = string
}

variable "api_hostname" {
  description = "Public Cloudflare hostname for the API edge."
  type        = string
  default     = "api.alera.build"
}

variable "google_oauth_client_id" {
  description = "Public Google OAuth desktop client id."
  type        = string
}

variable "github_oauth_client_id" {
  description = "Public GitHub OAuth App client id."
  type        = string
}

variable "signing_key_id" {
  description = "Stable kid published in Alera JWTs and JWKS for the active KMS version."
  type        = string
  default     = "alera-production-v1"
}

variable "kms_key_version" {
  description = "Active Cloud KMS key version number."
  type        = string
  default     = "1"
}

variable "kms_public_key_b64url" {
  description = "Raw 32-byte Ed25519 KMS public key encoded as unpadded base64url. This is public key material."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{43}$", var.kms_public_key_b64url))
    error_message = "kms_public_key_b64url must be an unpadded base64url Ed25519 public key."
  }
}

variable "previous_jwks_json" {
  description = "Public JWKS keys retained while access tokens from the previous signing version can remain valid."
  type        = string
  default     = "{\"keys\":[]}"

  validation {
    condition     = can(jsondecode(var.previous_jwks_json))
    error_message = "previous_jwks_json must be valid JSON."
  }
}

variable "enable_previous_edge_origin_token" {
  description = "Expose the previous edge token secret during a zero-downtime rotation."
  type        = bool
  default     = false
}

variable "neon_project_id" {
  description = "Existing Neon Free project id. The connection URL is injected through Secret Manager and is never read by OpenTofu."
  type        = string
}

variable "notification_daily_limit" {
  description = "Maximum accepted push deliveries per account and UTC day."
  type        = number
  default     = 500
}

variable "notification_hourly_limit" {
  description = "Maximum accepted push deliveries per account and rolling hour."
  type        = number
  default     = 60
}

variable "push_delivery_enabled" {
  description = "Global push-delivery circuit breaker. Set false to reject sends before event persistence or quota consumption."
  type        = bool
  default     = true
}

variable "account_mobile_limit" {
  description = "Maximum enrolled mobile devices per account."
  type        = number
  default     = 5
}

variable "account_runtime_limit" {
  description = "Maximum enrolled runtimes per account."
  type        = number
  default     = 10
}
