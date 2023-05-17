terraform {
 backend "gcs" {
   bucket = "terraform-states-fx-prod"
   prefix = "common/gke-gitlab-runners-asia-1684164323/"
   credentials = "~/.secrets/gke-fx-prod-sa.json"
 }
}
