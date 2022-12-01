# Gitlab GKE runners

### Important note
Падает со следующей ошибкой при запуске плана вместе с helm-сущностями (кластер готовится какое-то время после создания):
```
Error: Post "https://10.157.211.2/api/v1/namespaces/kube-system/serviceaccounts": dial tcp 10.157.211.2:443: connect: network is down
│
│   with kubernetes_service_account.helm_service_account,
│   on main.tf line 142, in resource "kubernetes_service_account" "helm_service_account":
│  142: resource "kubernetes_service_account" "helm_service_account" {
```
