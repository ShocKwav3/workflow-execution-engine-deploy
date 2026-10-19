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
overlays/aws/               EKS (not complete yet)
deploy-local.md             deploy guide for minikube
deploy-local.sh             build and deploy to minikube in one command (see deploy-local.md)
deploy-aws.md               deploy guide for EKS
```

## How it works

**Base and overlays.** `base` describes the three apps and the migration once. Each overlay includes `base` and adds what only its environment needs. The local overlay adds Postgres and Redis in the cluster. The AWS overlay will use managed services instead.

**Configuration.** The apps read their environment variables from two objects:

- `app-config` (ConfigMap): `base` sets the shared keys, and each overlay adds the keys of its environment, such as `PGHOST` and `REDIS_URL`.
- `app-secrets` (Secret): `base` only references it. Each overlay creates it.

Kustomize generates both objects with a content hash in the name. A change to a value changes the name, and the Deployments then restart with the new value.

**Image tags.** Each overlay sets the image tag of all four images in `images`. The committed value is the placeholder `unset`. A deploy sets the commit SHA of the app repository.

**Migration Job.** Kubernetes does not allow changes to the Pod template of a Job. So each overlay appends the image tag to the Job name (`migrate-<tag>`) with `replacements`, and each new version gets a new Job. `ttlSecondsAfterFinished` deletes a finished Job after one hour. Kubernetes has no start order, so the migration must complete before the apps are applied. The deploy guides do this as an explicit step, and `deploy-local.sh` stops before the apps if the Job does not complete.

**Probes and shutdown.** Each app has three HTTP probes. The startup probe (`/health`) allows up to 30 s for the start, and the other probes wait for it. The liveness probe (`/health`) restarts a container after about 30 s of failures; it checks only the process, so a database outage causes no restarts. The readiness probe (`/ready`) checks PostgreSQL and Redis, and removes the Pod from traffic after about 10 s of failures.

**Shutdown and rollout.** On shutdown, each app exits within 8 s, so `terminationGracePeriodSeconds` is 20 s for the api and 15 s for the workers. The api first sleeps 5 s in `preStop`: it keeps serving while Kubernetes removes it from the Service endpoints. A rollout starts the new Pod first and stops the old Pod only when the new Pod is ready (`maxSurge: 1`, `maxUnavailable: 0`). Resource requests come from measured use under load; there are no CPU limits.

**Redis configuration.** `overlays/local/redis/redis.conf` is a copy of [`infra/redis/redis.conf`](https://github.com/ShocKwav3/workflow-execution-engine/blob/main/infra/redis/redis.conf) in the app repository. CI fails when the two files differ. Change the app repository first, then copy the file here. The [app repository's README](https://github.com/ShocKwav3/workflow-execution-engine#stack) explains each setting.

## Deployment

| Environment | Overlay | Guide |
|---|---|---|
| Local (minikube) | `overlays/local` | [deploy-local.md](deploy-local.md) |
| Production (AWS EKS) | `overlays/aws` | [deploy-aws.md](deploy-aws.md) |
