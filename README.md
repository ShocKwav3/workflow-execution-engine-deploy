# workflow-execution-engine-deploy

Kubernetes manifests for [workflow-execution-engine](https://github.com/ShocKwav3/workflow-execution-engine), written with Kustomize.

## Layout

```text
k8s/base/              api, outbox-relay and executor Deployments, the api Service, the migrate Job, shared config
k8s/overlays/local/    minikube: Postgres and Redis StatefulSets, local config and Secret, api Service as LoadBalancer
k8s/overlays/aws/      EKS (not complete yet)
```

## Deploy to minikube

Requirements: Docker Desktop, `minikube`, `kubectl`, and a local clone of the [app repository](https://github.com/ShocKwav3/workflow-execution-engine). Docker Compose and minikube use the same Docker memory, so stop Compose first.

1. Start minikube and enable metrics:
   ```bash
   minikube start --driver=docker --cpus=4 --memory=3g
   minikube addons enable metrics-server
   ```
2. Create the local Secret file (one time only):
   ```bash
   cp k8s/overlays/local/secret.env.example k8s/overlays/local/secret.env
   ```
3. Set the path of your app repository clone, and the image tag from its commit. Run all later steps in the same shell, from this repository's root.
   ```bash
   APP_REPO=<path to your clone of workflow-execution-engine>
   TAG=$(git -C "$APP_REPO" rev-parse --short HEAD)
   ```
4. Build the four images in the app repository:
   ```bash
   cd "$APP_REPO"
   docker build --target api-runtime -t workflow-engine/api:$TAG .
   docker build --target outbox-relay-runtime -t workflow-engine/outbox-relay:$TAG .
   docker build --target executor-runtime -t workflow-engine/executor:$TAG .
   docker build -f packages/core/db/Dockerfile.liquibase --target runtime -t workflow-engine/migrate:$TAG packages/core/db
   cd -
   ```
5. Copy the images into minikube:
   ```bash
   for img in api outbox-relay executor migrate; do minikube image load workflow-engine/$img:$TAG; done
   ```
6. Set the tag in the local overlay. Do not commit this change.
   ```bash
   sed -i '' "s/newTag: unset/newTag: $TAG/" k8s/overlays/local/kustomization.yaml
   ```
7. Apply everything except the three apps. This creates Postgres, Redis, the config and the migration Job.
   ```bash
   kubectl apply -k k8s/overlays/local -l 'app.kubernetes.io/name notin (api,outbox-relay,executor)'
   ```
8. Wait until the migration completes. On the first deploy, one or two migration Pods can end in `Error` while Postgres starts; the Job tries again.
   ```bash
   kubectl wait --for=condition=complete job/migrate-$TAG -n workflow-engine --timeout=5m
   ```
9. Apply the apps and wait for them:
   ```bash
   kubectl apply -k k8s/overlays/local
   for d in api outbox-relay executor; do kubectl rollout status deploy/$d -n workflow-engine --timeout=3m; done
   ```
10. In a second terminal, start the tunnel and keep it open. It can ask for your password, because the API uses port 80.
    ```bash
    minikube tunnel
    ```
11. Call the API:
    ```bash
    curl -i http://127.0.0.1/health
    ```
12. Reset the tag placeholder:
    ```bash
    git checkout k8s/overlays/local/kustomization.yaml
    ```

To stop the cluster and keep its data, run `minikube stop`. To remove the app and its data, run `kubectl delete namespace workflow-engine`.

## Redis configuration

`k8s/overlays/local/redis/redis.conf` is a copy of [`infra/redis/redis.conf`](https://github.com/ShocKwav3/workflow-execution-engine/blob/main/infra/redis/redis.conf) in the app repository. CI fails when the two files differ. Change the app repository first, then copy the file here. The [app repository's README](https://github.com/ShocKwav3/workflow-execution-engine#stack) explains each setting.
