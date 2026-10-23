# Kubernetes manifests

The Kubernetes manifests of the workflow execution engine, written with [Kustomize](https://kustomize.io/). `kubectl` has Kustomize built in: `kubectl kustomize <dir>` prints the final YAML, and `kubectl apply -k <dir>` applies it.

## Layout

```text
base/                       objects that every environment shares
  api.yaml                  api Deployment and Service
  outbox-relay.yaml         outbox-relay Deployment
  executor.yaml             executor Deployment
  migrate-job.yaml          Liquibase migration Job
  namespace.yaml            namespace workflow-engine
  kustomization.yaml        resources, labels, shared config (app-config)
overlays/local/             minikube
  postgres/, redis/         StatefulSets, headless Services, Redis configuration
  api-service-patch.yaml    api Service as LoadBalancer
  secret.env.example        template for the gitignored secret.env
  kustomization.yaml        image tags, local config, Secret
overlays/aws/               EKS
  rds-ca/global-bundle.pem  RDS root CA bundle (public AWS file)
  app-env-external-secret.yaml      endpoints from SSM Parameter Store
  app-secrets-external-secret.yaml  database password from Secrets Manager
  api-service-patch.yaml    api Service as an internet-facing Network Load Balancer
  kustomization.yaml        image placeholders, TLS settings, patches
deploy-local.md             deploy guide for minikube
deploy-local.sh             build and deploy to minikube in one command (see deploy-local.md)
deploy-aws.md               deploy guide for EKS
```

## How it works

**Base and overlays.** `base` describes the three apps and the migration once. Each overlay includes `base` and adds what only its environment needs. The local overlay adds Postgres and Redis in the cluster. The AWS overlay uses RDS and ElastiCache instead.

**Configuration.** The apps read their environment variables from these objects:

- `app-config` (ConfigMap): `base` sets the shared keys, and each overlay adds the keys of its environment.
- `app-secrets` (Secret): `base` only references it. Each overlay creates it.
- `app-env` (Secret, AWS only): the RDS and Redis endpoints.

Kustomize generates `app-config`, and the local `app-secrets`, with a content hash in the name. A change to a value changes the name, and the Deployments then restart with the new value.

**No environment values in the AWS overlay.** The AWS overlay contains no account ID, region, endpoint, password, image tag or IP address. [External Secrets Operator](https://external-secrets.io/) creates `app-env` from SSM Parameter Store and `app-secrets` from the RDS-managed secret in Secrets Manager. It finds that secret by its name prefix `rds!db-`, because RDS gives each new instance a new secret name. The `ClusterSecretStore` objects that name the region are created with the operator installation. The Network Load Balancer accepts only the IPs in the security group with the `Name` tag `wee-nlb`. The deploy sets the ECR registry and the image tag. A running Pod keeps its environment, so a value that changes in AWS reaches the apps at the next Pod restart.

**Database TLS (AWS).** The apps connect to RDS with `verify-full`. The overlay mounts the RDS root CA bundle at `/etc/rds-ca/` from a generated ConfigMap. The Node apps read `PGSSLMODE` and `PGSSLROOTCERT`, and the migration Job passes the same settings in the JDBC URL. The bundle holds only root CAs, which are valid for decades. RDS renews the server certificates itself.

**Image tags.** Each overlay sets the image tag of all four images in `images`. The committed value is the placeholder `unset`. A deploy sets the commit SHA of the app repository. On AWS, it also sets the ECR registry, in a temporary copy of the manifests.

**Migration Job.** Kubernetes does not allow changes to the Pod template of a Job. So each overlay appends the image tag to the Job name (`migrate-<tag>`) with `replacements`, and each new version gets a new Job. `ttlSecondsAfterFinished` deletes a finished Job after one hour. Kubernetes has no start order, so the migration must complete before the apps are applied. The deploy guides do this as an explicit step, and `deploy-local.sh` stops before the apps if the Job does not complete.

**Probes and shutdown.** Each app has three HTTP probes. The startup probe (`/health`) allows up to 30 s for the start, and the other probes wait for it. The liveness probe (`/health`) restarts a container after about 30 s of failures; it checks only the process, so a database outage causes no restarts. The readiness probe (`/ready`) checks PostgreSQL and Redis, and removes the Pod from traffic after about 10 s of failures.

**Shutdown and rollout.** On shutdown, each app exits within 8 s, so `terminationGracePeriodSeconds` is 20 s for the api and 15 s for the workers. The api first sleeps 5 s in `preStop`: it keeps serving while Kubernetes removes it from the Service endpoints. A rollout starts the new Pod first and stops the old Pod only when the new Pod is ready (`maxSurge: 1`, `maxUnavailable: 0`). Resource requests come from measured use under load; there are no CPU limits.

**Redis configuration.** `overlays/local/redis/redis.conf` is a copy of [`infra/redis/redis.conf`](https://github.com/ShocKwav3/workflow-execution-engine/blob/main/infra/redis/redis.conf) in the app repository. CI fails when the two files differ. Change the app repository first, then copy the file here. The [app repository's README](https://github.com/ShocKwav3/workflow-execution-engine#stack) explains each setting.

## Deployment

| Environment | Overlay | Guide |
|---|---|---|
| Local (minikube) | `overlays/local` | [deploy-local.md](deploy-local.md) |
| Production (AWS EKS) | `overlays/aws` | [deploy-aws.md](deploy-aws.md) |
