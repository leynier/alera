variable "gcp_project_id" {
  description = "Google Cloud project that owns the production deployment identity."
  type        = string
}

variable "state_bucket" {
  description = "Existing versioned GCS bucket used by OpenTofu."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to exchange OIDC tokens."
  type        = string
  default     = "leynier/alera"
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository id."
  type        = string
}

variable "github_repository_owner_id" {
  description = "Immutable numeric GitHub repository owner id."
  type        = string
}

variable "github_branch_ref" {
  description = "Only this Git ref may exchange OIDC tokens."
  type        = string
  default     = "refs/heads/main"
}

variable "runtime_service_account_id" {
  description = "Existing Cloud Run runtime service account id."
  type        = string
  default     = "alera-cloud"
}
