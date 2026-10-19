# Deploy to minikube

This guide deploys the local overlay (`overlays/local`) to a one-node minikube cluster. Run the commands from the repository root.

Requirements: Docker Desktop, `minikube`, `kubectl`, [`kustomize`](https://kubectl.docs.kubernetes.io/installation/kustomize/), and a local clone of the [app repository](https://github.com/ShocKwav3/workflow-execution-engine). Docker Compose and minikube use the same Docker memory, so stop Compose first.

## One-time setup

1. Start minikube and enable metrics:
   ```bash
   minikube start --driver=docker --cpus=4 --memory=3g
   minikube addons enable metrics-server
   ```
2. Create the local Secret file:
   ```bash
   cp k8s/overlays/local/secret.env.example k8s/overlays/local/secret.env
   ```

## Deploy

```bash
DEPLOY_APP_REPO=<path to your clone of workflow-execution-engine> k8s/deploy-local.sh
```

`deploy-local.sh` builds the four images at the app repository's `HEAD`, loads them into minikube, runs the migration Job, and then rolls out the apps.

- The image tag is the short commit SHA, so the script stops if the app repository has uncommitted changes.
- It sets the tag with `kustomize edit set image` for this run only. The committed `kustomization.yaml` keeps the placeholder `unset`.
- If the migration Job does not complete, the script stops before it applies the apps, so the apps keep the previous version. On the first deploy, one or two migration Pods can end in `Error` while Postgres starts; the Job tries again.

## Call the API

1. In a second terminal, start the tunnel and keep it open. It can ask for your password, because the API uses port 80.
   ```bash
   minikube tunnel
   ```
2. Call the API:
   ```bash
   curl -i http://127.0.0.1/health
   ```

## Stop or remove

To stop the cluster and keep its data, run `minikube stop`. To remove the app and its data, run `kubectl delete namespace workflow-engine`.
