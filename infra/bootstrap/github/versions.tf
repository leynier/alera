terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.40.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.gcp_project_id
}
