locals {
  creds_path = "~/.secrets/gke-sa.json"
  tf_bucket = "terraform-states-all"
  tf_bucket_path = "common/gke-gitlab-runners-1669121703/"

  project = "fbs-prod"
  network = "common"
  location = "europe-west1" # the cheapest one
  subnetwork = "common-gitlab-gke-ew1"
  master_ipv4_cidr_block = "10.157.211.0/28"

  pods_cidr_range = "10.76.0.0/14"
  services_cidr_range = "10.80.0.0/20"
  master_authorized_networks_cidr_blocks = [
    {
      display_name = "All internal network"
      cidr_block   = "10.0.0.0/8"
    }
  ]
  machine_type = "e2-standard-4"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = "4.34.0"
    }
  }
}

provider "google" {
  credentials = pathexpand(local.creds_path)
  project = local.project
}

# TF bucket folder
# NOT removed during terraform destroy if used in backend.tf
resource "google_storage_bucket_object" "tf_state_folder" {
  name          = local.tf_bucket_path
  bucket        = local.tf_bucket
  content       = "test"
}

# GKE Cluster
resource "google_container_cluster" "gitlab_runners" {
  name                          = "gitlab-runners"
  network                       = local.network
  subnetwork                    = local.subnetwork
  location                      = local.location
  networking_mode               = "VPC_NATIVE"
  datapath_provider             = "ADVANCED_DATAPATH"
  remove_default_node_pool      = true
  enable_intranode_visibility   = true
  initial_node_count            = 1

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = local.master_authorized_networks_cidr_blocks

      content {
        cidr_block    = cidr_blocks.value["cidr_block"]
        display_name  = cidr_blocks.value["display_name"]
      }
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = local.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block = local.pods_cidr_range
    services_ipv4_cidr_block = local.services_cidr_range
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"]
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }

    dns_cache_config {
      enabled = true
    }

    gcp_filestore_csi_driver_config {
      enabled = true
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }
}

resource "google_container_node_pool" "gitlab_runners_node_pool" {
  name       = "gitlab-runners-node-pool"
  location   = local.location
  cluster    = google_container_cluster.gitlab_runners.name
  node_count = 3

  node_config {
    preemptible     = true
    machine_type    = local.machine_type
    image_type      = "cos_containerd"
    disk_type       = "pd-ssd"
    disk_size_gb    = 100

    # Google recommendation
    service_account = data.google_service_account.gitlab_runners_nodes_sa.email
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
        env = local.network
        app = "gitlab"
        role = "runner"
    }
  }
}

# K8S-related entities
data "google_client_config" "default" {}
data "google_service_account" "gitlab_runners_nodes_sa" {
  account_id = "100757769574482081288" # gitlab-runners-nodes-sa, hardcoded to simplify otherwise
}

provider "kubernetes" {
  host = "https://${google_container_cluster.gitlab_runners.endpoint}"

  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gitlab_runners.master_auth[0].cluster_ca_certificate)
}

# Gitlab stuff to deploy from Gitlab
resource "kubernetes_service_account" "gitlab_service_account" {
  metadata {
    name = "gitlab"
    namespace = "kube-system"
  }
}
resource "kubernetes_cluster_role_binding" "gitlab_role_binding" {
  metadata {
    name = kubernetes_service_account.gitlab_service_account.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.gitlab_service_account.metadata[0].name
    namespace = "kube-system"
  }
}
