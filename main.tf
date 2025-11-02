terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required Google APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com"
  ])
  service = each.key
}

# VPC network
resource "google_compute_network" "vpc" {
  name                    = "${var.service_name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.service_name}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
}

# Firewall: allow internal traffic
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.service_name}-fw-internal"
  project = var.project_id
  network = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]
}

# Firewall: allow external HTTP/HTTPS & custom ports
resource "google_compute_firewall" "allow_http" {
  name    = "${var.service_name}-fw-http"
  project = var.project_id
  network = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80","443","3000","3001"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.service_name}-repo"
  description   = "Docker repository for ${var.service_name}"
  format        = "DOCKER"
}

# Static external IPs for services
resource "google_compute_address" "portal_ip" {
  name    = "${var.service_name}-portal-ip"
  project = var.project_id
  region  = var.region
}

resource "google_compute_address" "hubspot_ip" {
  name    = "${var.service_name}-hubspot-ip"
  project = var.project_id
  region  = var.region
}

# GKE cluster
resource "google_container_cluster" "gke" {
  name               = "${var.service_name}-cluster"
  project            = var.project_id
  location           = var.zone
  initial_node_count = var.min_node_count
  network            = google_compute_network.vpc.name
  subnetwork         = google_compute_subnetwork.subnet.name

  depends_on = [google_project_service.apis]
}

# Node pool using your custom service account with autoscaling
resource "google_container_node_pool" "node_pool" {
  name     = "${var.service_name}-nodepool"
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.gke.name

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  node_config {
    machine_type   = var.machine_type
    service_account = var.node_pool_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [google_container_cluster.gke]
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = google_container_cluster.gke.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
}

# ConfigMap for backend environment variables
resource "kubernetes_config_map" "backend_env" {
  metadata {
    name = "${var.service_name}-env"
  }
  data = var.backend_env
}

# Outputs
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.gke.name
}

output "artifact_repo" {
  description = "Artifact Registry repository name"
  value       = google_artifact_registry_repository.repo.repository_id
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "portal_static_ip" {
  description = "Static external IP for portal service"
  value       = google_compute_address.portal_ip.address
}

output "hubspot_static_ip" {
  description = "Static external IP for hubspot service"
  value       = google_compute_address.hubspot_ip.address
}
