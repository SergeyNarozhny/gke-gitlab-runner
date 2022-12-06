# Gitlab GKE runners

## Setup + K8S SA
После раскатки плана нужно подправить пиринг с VPC на экспорт машрутов, чтобы по сети мастер-нод можно было ходить в рамках BGP peer:
```
gcloud compute networks peerings update <peering-name> --network=common \
    --import-custom-routes --export-custom-routes
```
Заменить `<peering-name>` на имя созданного пиринга, например, gke-n104b240e9eea24bf42c-6b73-1f9d-peer.

### Important note
Если План падает со следующей ошибкой при запуске вместе с k8s-сущностями (SA, role), то это норм:
```
Error: Post "https://10.157.211.2/api/v1/namespaces/kube-system/serviceaccounts": dial tcp 10.157.211.2:443: connect: network is down
│
│   with kubernetes_service_account.helm_service_account,
│   on main.tf line 142, in resource "kubernetes_service_account" "helm_service_account":
│  142: resource "kubernetes_service_account" "helm_service_account" {
```
Причина в том, что GKE может стартовать новый кластер до часу по времени! Все это время кластер в состоянии "ready". но не "running". После того, как кластер поднялся, он в "running", и можно снова запустить terraform apply, чтобы накатить нужный Gitlab SA с ролью.

В качестве альтенативы, можно установить Gitlab SA с соответствующей ролью через gitlab-runners-admin-sa.yaml:
```
kubectl apply -f gitlab-runners-admin-sa.yaml
```
При условии, что gcloud может авторизоваться в кластере GKE (см. https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin).

## Integrate with Gitlab
Пользуемся инструкцией из https://gitlab.fbs-d.com/help/user/project/clusters/add_existing_cluster.md для интеграции с поднятым кластером.

## Prepare Gitlab runner
Дальше создаем namespace для gital runners через kubectl:
```
kubectl create ns gitlab-runners
```
А также модифицируем kube-dns configmap, чтобы корректно резолвился сервер gitlab.fbs-d.com:
```
kubectl apply -f gitlab-runners-kube-dns-configmap.yaml
```

## Start Gitlab runner agent
Выполняем установку агента (или upgrade):
```
helm install --namespace gitlab-runners gitlab-runner -f gitlab-runners-chart-values.yaml gitlab/gitlab-runner
```
Если нужно, корректируем настройки gitlab-runners-chart-values.yaml по доке https://docs.gitlab.com/runner/configuration/advanced-configuration.html
