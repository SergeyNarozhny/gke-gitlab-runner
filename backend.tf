terraform {
 backend "gcs" {
   bucket = "terraform-states-all"
   prefix = "common/gke-gitlab-runners-1669121703/"
   credentials = "~/.secrets/gke-sa.json"
 }
}
