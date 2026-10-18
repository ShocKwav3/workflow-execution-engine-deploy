# workflow-execution-engine-deploy

Kubernetes manifests for [workflow-execution-engine](https://github.com/ShocKwav3/workflow-execution-engine), written with Kustomize.

## Layout

```text
k8s/base/              api, outbox-relay and executor Deployments, the api Service, the migrate Job, shared config
k8s/overlays/local/    minikube: Postgres and Redis StatefulSets, local config and Secret, api Service as LoadBalancer
k8s/overlays/aws/      EKS (not complete yet)
```

## Redis configuration

`k8s/overlays/local/redis/redis.conf` is a copy of `infra/redis/redis.conf` in the app repository. CI fails when the two files differ. Change the app repository first, then copy the file here. The app repository's README explains each setting.
