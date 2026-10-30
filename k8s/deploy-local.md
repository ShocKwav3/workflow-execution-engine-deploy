# Deploy to kind

This guide deploys the local overlay (`overlays/local`) to a one-node [kind](https://kind.sigs.k8s.io/) cluster. Run the commands from the repository root.

Requirements: Docker Desktop, `kind`, `kubectl`, [`kustomize`](https://kubectl.docs.kubernetes.io/installation/kustomize/), and a local clone of the [app repository](https://github.com/ShocKwav3/workflow-execution-engine). Docker Compose and kind use the same Docker memory, so stop Compose first.

## One-time setup

1. Install kind and create the cluster:
   ```bash
   brew install kind
   kind create cluster
   ```
2. Install metrics-server, which `kubectl top` and the load test need:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml
   ```
3. Let metrics-server accept the self-signed kubelet certificates of kind. Use this flag only on a local cluster.
   ```bash
   kubectl patch -n kube-system deployment metrics-server --type=json \
     -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
   ```
4. Create the local Secret file:
   ```bash
   cp k8s/overlays/local/secret.env.example k8s/overlays/local/secret.env
   ```

## Deploy

```bash
DEPLOY_APP_REPO=<path to your clone of workflow-execution-engine> k8s/deploy-local.sh
```

`deploy-local.sh` builds the four images at the app repository's `HEAD`, loads them into kind, runs the migration Job, and then rolls out the apps.

- The image tag is the short commit SHA, so the script stops if the app repository has uncommitted changes.
- To deploy images that already exist, set `DEPLOY_TAG=<tag>` instead of `DEPLOY_APP_REPO`. The script then builds nothing.
- It sets the tag with `kustomize edit set image` for this run only. The committed `kustomization.yaml` keeps the placeholder `unset`.
- If the migration Job does not complete, the script stops before it applies the apps, so the apps keep the previous version. On the first deploy, one or two migration Pods can end in `Error` while Postgres starts; the Job tries again.

## Call the API

1. In a second terminal, forward a local port to the API Service and keep it open:
   ```bash
   kubectl port-forward -n workflow-engine svc/api 3000:80
   ```
2. Call the API:
   ```bash
   curl -i http://localhost:3000/health
   ```

The forward connects to one api Pod. If that Pod stops, for example after a deploy, start the forward again.

## Stop or remove

- To stop the cluster and keep its data, run `docker stop kind-control-plane`. To start it again, run `docker start kind-control-plane`.
- To remove the cluster and its data, run `kind delete cluster`.
