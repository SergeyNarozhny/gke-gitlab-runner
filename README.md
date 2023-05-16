# Gitlab GKE runners

## Setup + K8S SA
После раскатки плана нужно подправить пиринг с VPC на экспорт машрутов, чтобы по сети мастер-нод можно было ходить в рамках BGP peer:
```
$ gcloud compute networks peerings update <peering-name> --network=common \
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

## Integrate with Gitlab
Пользуемся инструкцией из https://gitlab.fbs-d.com/help/user/clusters/agent/install/index.md для интеграции с поднятым кластером.
В частности, получаем креды кластера в локальный конфиг кубера - https://cloud.google.com/kubernetes-engine/docs/deploy-app-cluster#get_authentication_credentials_for_the_cluster, например,
```
$ gcloud container clusters get-credentials gitlab-runners --region asia-southeast2 --project fx-prod
```
Затем переключаемся на него кубером:
```
$ kubectl config view
$ kubectl config current-context
$ kubectl config use-context gke_fx-prod_asia-southeast2_gitlab-runners
```

## Prepare Gitlab runner environment
Дальше создаем namespace для gital runners через kubectl:
```
$ kubectl create ns gitlab-runner
```
Накидываем на gitlab-runners-cache-sa IAM рольку для Storage Object Owner, чтобы он мог ходить в CS бакет кеша раннера.
Дальше создаем ключик для gitlab-runners-cache-sa и закидываем его креды в секрет **gcsaccess**:
```
$ kubectl create secret --namespace gitlab-runner generic gcsaccess \
 --from-literal=gcs-access-id="YourAccessID" \
 --from-literal=gcs-private-key="YourPrivateKey"
```
Дальше создаем файловые секреты:
```
$ kubectl create secret --namespace gitlab-runner generic gitlab-cacerts \
 --from-file=./ca/ca-certificates.crt
$ kubectl create secret --namespace gitlab-runner generic gitlab-ca \
 --from-file=./ca/ca-certificates.crt
```

## Start Gitlab runner agent
Выполняем установку агента (или upgrade) - https://gitlab.fbs-d.com/infra/helms/gke-gitlab-runner, например,
```
$ helm upgrade --install --namespace gitlab-runner gitlab-runner . \
 --values values-asia.yaml
```

## Troubleshooting
В случае если какие-либо раннеры вне GKE пытаются запустить джобы через контейнеры GKE, а также насоздавали своих неймспейсов в кластере, данные неймспейсы можно удалить вручную. Например, если пайплайн oauth продолжает запускаться через раннеры GKE, хотя не должен по environment scope, следует удалить его неймспейс из GKE-кластера:
```
$ kubectl get ns --no-headers | awk /oauth-/'{print $1}' | xargs kubectl delete ns
```
