# Deploy to AWS (EKS)

This guide deploys the AWS overlay (`overlays/aws`) to an EKS cluster. Run the commands from the repository root.

The overlay holds no account-specific or environment-specific values. The deploy reads them from AWS and from the app repository:

| Value | Source |
|---|---|
| RDS and Redis endpoints | SSM parameters `/wee/app/PGHOST` and `/wee/app/REDIS_URL`, synced by External Secrets Operator into the Secret `app-env` |
| Database password | The RDS-managed secret `rds!db-<id>` in Secrets Manager, synced into the Secret `app-secrets` |
| ECR registry | The account of the current AWS credentials, set at deploy time |
| Image tag | The short commit SHA of the app repository, set at deploy time |
| Allowed client IP | The security group with the `Name` tag `wee-nlb` |

## Requirements

- `aws`, `kubectl`, [`kustomize`](https://kubectl.docs.kubernetes.io/installation/kustomize/), `git`, and a local clone of the [app repository](https://github.com/ShocKwav3/workflow-execution-engine).
- A `kubectl` context for the EKS cluster.
- In the cluster: the AWS Load Balancer Controller, and External Secrets Operator with EKS Pod Identity.
- Two `ClusterSecretStore` objects, created with the External Secrets Operator installation, not in this repository: `aws-parameter-store` (service `ParameterStore`) and `aws-secrets-manager` (service `SecretsManager`).
- The SSM parameters above, and RDS with a managed master password.
- The security group `wee-nlb` in the cluster VPC, with inbound TCP 80 from the allowed IP only.
- The four images in ECR (`workflow-engine/api`, `outbox-relay`, `executor`, `migrate`), tagged with the commit SHA.

## Deploy

1. Set the values:
   ```bash
   APP_REPO=<path to your clone of workflow-execution-engine>
   REGION=<AWS region of the cluster>
   TAG="$(git -C "$APP_REPO" rev-parse --short HEAD)"
   REGISTRY="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$REGION.amazonaws.com"
   ```
2. Make a temporary copy of the manifests and set the images in the copy. The committed `kustomization.yaml` keeps the placeholder `unset`, and the account ID never enters this repository.
   ```bash
   WORK="$(mktemp -d)"
   cp -R k8s "$WORK/"
   (
     cd "$WORK/k8s/overlays/aws"
     for image in api outbox-relay executor migrate; do
       kustomize edit set image "workflow-engine/$image=$REGISTRY/workflow-engine/$image:$TAG"
     done
   )
   ```
3. Apply everything except the apps, and wait for the migration:
   ```bash
   kubectl apply -k "$WORK/k8s/overlays/aws" -l 'app.kubernetes.io/name notin (api,outbox-relay,executor)'
   kubectl wait --for=condition=complete "job/migrate-$TAG" -n workflow-engine --timeout=5m
   ```
   If the Job does not complete, stop here. The apps keep the previous version. Inspect the Job with `kubectl logs -n workflow-engine "job/migrate-$TAG"`.
4. Apply the apps and wait for the rollout:
   ```bash
   kubectl apply -k "$WORK/k8s/overlays/aws"
   for app in api outbox-relay executor; do
     kubectl rollout status "deploy/$app" -n workflow-engine --timeout=3m
   done
   ```
5. Delete the temporary copy:
   ```bash
   rm -rf "$WORK"
   ```

## Call the API

The api Service creates an internet-facing Network Load Balancer. It takes a few minutes until the DNS name resolves and the targets are healthy.

```bash
API_HOST="$(kubectl get service api -n workflow-engine -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
curl -i "http://$API_HOST/health"
```

Only the IPs in the security group `wee-nlb` can connect.

## Remove

Delete the api Service before you delete the cluster. The Load Balancer Controller deletes the Network Load Balancer only when the Service is deleted. If the cluster is deleted first, the load balancer stays and costs money.

```bash
kubectl delete service api -n workflow-engine
kubectl delete namespace workflow-engine
```
