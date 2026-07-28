terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.40.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.40.0"
    }
  }

  backend "gcs" {}
}

provider "cloudflare" {}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
