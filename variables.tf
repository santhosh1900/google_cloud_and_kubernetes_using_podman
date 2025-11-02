# Variables for claim_concierge_portal_backend infrastructure

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "Example-project-ID"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for GKE cluster"
  type        = string
  default     = "us-central1-a"
}

variable "service_name" {
  description = "Service name for naming resources"
  type        = string
  default     = "PROJECT_NAME"
}

variable "network_cidr" {
  description = "CIDR range for VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR range for subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "min_node_count" {
  description = "Minimum number of nodes in the node pool (autoscaling)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes in the node pool (autoscaling)"
  type        = number
  default     = 10
}

variable "machine_type" {
  description = "GCE machine type to use for nodes (4 vCPU approx 8GB RAM) - Minimum Requirement"
  type        = string
  default     = "e2-standard-4"  # 4 vCPU, 8 GB RAM
}

# Environment variables for backend servers
variable "backend_env" {
  description = "Map of environment variables for backend servers"
  type        = map(string)
  default     = {
    PORT            = 3000
    CC_STAGE        = "dev"
    DB_NAME         = "example_db"
    DB_USER         = "example-user"
    DB_PASSWORD     = "password"
    DB_HOST         = "34.51.111.91"
    DB_PORT         = 5432
    SECURE_COOKIE   = "no"
    CC_JWT_SECRET   = "example_secrete"
    ENCRYPTION_KEY_BASE64   = "example_hash_value"
    AUTH_COOKIE_NAME        = "_cc_auth"
    FRONT_END_PORTAL = "https://example-frontend.com"
  }
}

variable "node_pool_service_account" {
  description = "Service account email to use for GKE node pool"
  type        = string
  default     = "example_terraform_service_account"
}
