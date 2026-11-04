# Kubernetes manifests

The Kubernetes manifests of the workflow execution engine, written with [Kustomize](https://kustomize.io/). `kubectl` has Kustomize built in: `kubectl kustomize <dir>` prints the final YAML, and `kubectl apply -k <dir>` applies it.

## Layout

```text
base/                       objects that every environment shares
  api.yaml                  api Deployment and Service
  outbox-relay.yaml         outbox-relay Deployment
  executor.yaml             executor Deployment
  migrate-job.yaml          Liquibase migration Job
  network-policies.yaml     default deny, DNS, api ingress
  namespace.yaml            namespace workflow-engine
  kustomization.yaml        resources, labels, shared config (app-config)
overlays/local/             kind
  postgres/, redis/         StatefulSets, headless Services, Redis configuration
  api-service-patch.yaml    api Service as LoadBalancer
  network-policies.yaml     paths to the in-cluster Postgres and Redis
  secret.env.example        template for the gitignored secret.env
  kustomization.yaml        image tags, local config, Secret
overlays/aws/               EKS
  rds-ca/global-bundle.pem  RDS root CA bundle (public AWS file)
  app-env-external-secret.yaml      endpoints from SSM Parameter Store
  app-secrets-external-secret.yaml  database password from Secrets Manager
  api-service-patch.yaml    api Service as an internet-facing Network Load Balancer
  network-policies.yaml     paths to the RDS and ElastiCache subnets
  kustomization.yaml        image placeholders, TLS settings, patches
deploy-local.md             deploy guide for kind
deploy-local.sh             build and deploy to kind in one command (see deploy-local.md)
deploy-aws.md               deploy guide for EKS
```

## How it works

**Base and overlays.** `base` describes the three apps and the migration once. Each overlay includes `base` and adds what only its environment needs. The local overlay adds Postgres and Redis in the cluster. The AWS overlay uses RDS and ElastiCache instead.

**Configuration.** The apps read their configuration from these objects:

- `app-config` (ConfigMap), as environment variables: `base` sets the shared keys, and each overlay adds the keys of its environment.
- `app-secrets` (Secret), as files in `/etc/secrets/app`: the database password, read through `PGPASSWORD_FILE`. `base` only references it. Each overlay creates it.
- `app-env` (Secret, AWS only), as files in `/etc/secrets/env`: the RDS and Redis endpoints, read through `PGHOST_FILE` and `REDIS_URL_FILE`.

Kustomize generates `app-config`, and the local `app-secrets`, with a content hash in the name. A change to a value changes the name, and the Deployments then restart with the new value.

**No environment values in the AWS overlay.** The AWS overlay contains no account ID, region, endpoint, password, image tag or IP address. [External Secrets Operator](https://external-secrets.io/) creates `app-env` from SSM Parameter Store and `app-secrets` from the RDS-managed secret in Secrets Manager. It finds that secret by its name prefix `rds!db-`, because RDS gives each new instance a new secret name. The `ClusterSecretStore` objects that name the region are created with the operator installation. The Network Load Balancer accepts only the IPs in the security group with the `Name` tag `wee-nlb`. It sends traffic directly to the Pod IPs. The namespace label `elbv2.k8s.aws/pod-readiness-gate-inject` makes a Pod `Ready` only when its load balancer target is healthy, so a rollout keeps the old Pod until the new one can take traffic. The deploy sets the ECR registry and the image tag. The apps read the files at startup, so a value that changes in AWS reaches the apps at the next Pod restart.

**Database TLS (AWS).** The apps connect to RDS with `verify-full`. The overlay mounts the RDS root CA bundle at `/etc/rds-ca/` from a generated ConfigMap. The Node apps read `PGSSLMODE` and `PGSSLROOTCERT`, and the migration Job passes the same settings in the JDBC URL. The bundle holds only root CAs, which are valid for decades. RDS renews the server certificates itself.

**Image tags.** Each overlay sets the image tag of all four images in `images`. The committed value is the placeholder `unset`. A deploy sets the commit SHA of the app repository. On AWS, it also sets the ECR registry, in a temporary copy of the manifests.

**Migration Job.** Kubernetes does not allow changes to the Pod template of a Job. So each overlay appends the image tag to the Job name (`migrate-<tag>`) with `replacements`, and each new version gets a new Job. `ttlSecondsAfterFinished` deletes a finished Job after one hour. Kubernetes has no start order, so the migration must complete before the apps are applied. The deploy guides do this as an explicit step, and `deploy-local.sh` stops before the apps if the Job does not complete.

**Probes and shutdown.** Each app has three HTTP probes. The startup probe (`/health`) allows up to 30 s for the start, and the other probes wait for it. The liveness probe (`/health`) restarts a container after about 30 s of failures; it checks only the process, so a database outage causes no restarts. The readiness probe (`/ready`) checks PostgreSQL and Redis, and removes the Pod from traffic after about 10 s of failures.

**Shutdown and rollout.** On shutdown, each app exits within 8 s, so `terminationGracePeriodSeconds` is 20 s for the api and 15 s for the workers. The api first sleeps 5 s in `preStop`: it keeps serving while Kubernetes removes it from the Service endpoints. A rollout starts the new Pod first and stops the old Pod only when the new Pod is ready (`maxSurge: 1`, `maxUnavailable: 0`). Resource requests come from measured use under load; there are no CPU limits.

**Redis configuration.** `overlays/local/redis/redis.conf` is a copy of [`infra/redis/redis.conf`](https://github.com/ShocKwav3/workflow-execution-engine/blob/main/infra/redis/redis.conf) in the app repository. CI fails when the two files differ. Change the app repository first, then copy the file here. The [app repository's README](https://github.com/ShocKwav3/workflow-execution-engine#stack) explains each setting.

## Security settings

The settings follow the Kubernetes [Restricted Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/). The CI config scan (Checkov) checks them on the rendered overlays.

**Pods and containers** (all workloads):

- `runAsNonRoot: true`. The apps, Postgres and Redis run as UID/GID 10001: a UID above 10000 matches no user on the node. The migration Job runs as UID 1001, the Liquibase image user, because other users cannot enter the image's `/liquibase`.
- `allowPrivilegeEscalation: false`, all Linux capabilities dropped, and the seccomp profile `RuntimeDefault`.
- `readOnlyRootFilesystem: true`. Writable paths are `emptyDir` volumes: `/tmp` (64Mi), and `/var/run/postgresql` for Postgres. Postgres and Redis write their data to their PersistentVolumeClaims; `fsGroup: 10001` makes the volumes and the mounted Secret files readable for the group.
- `automountServiceAccountToken: false`: no program calls the Kubernetes API.
- Postgres and Redis start as non-root. Their entrypoints then skip the ownership fix and the user switch. Postgres fakes the passwd entry for `initdb` with nss_wrapper, in `/tmp`. After a UID change, data that an earlier UID wrote stays unreadable: delete the volumes, on kind with `kind delete cluster`.

**Secrets.** Kubernetes mounts the Secrets as files (`defaultMode: 0440`), not as environment variables. A variable is passed to child processes and can appear in crash output. The local Postgres reads `POSTGRES_PASSWORD_FILE`. Liquibase cannot read a password file, so the Job passes `LIQUIBASE_COMMAND_PASSWORD`, which keeps the password out of the process arguments.

**NetworkPolicies.** `default-deny` blocks all ingress and egress in the namespace. Other policies allow DNS to CoreDNS, ingress to the api on port 3000, and the database paths: Postgres (5432) for the apps and the migration, Redis (6379) for the outbox-relay and the executor. Locally the paths go to the Postgres and Redis Pods. On AWS they go to the private subnets of RDS and ElastiCache, whose security groups are the second layer. EKS enforces the policies only with `enableNetworkPolicy` on the `vpc-cni` add-on, which the Terraform `env` configuration sets. kind enforces them with kindnet.

**Images.** Postgres and Redis are pinned by digest. The app images are tagged with the commit SHA.

**Exceptions** (inline `checkov.io/skip` annotations with the reason):

| Check | Resource | Reason |
|---|---|---|
| `CKV_K8S_11` (CPU limits) | all workloads | A CPU limit throttles the container while the node has free CPU; the requests reserve the CPU |
| `CKV_K8S_15` (`imagePullPolicy: Always`) | all workloads | The images are loaded into the node or pinned |
| `CKV_K8S_43` (image digest) | apps, migration | The tag is a commit SHA |
| `CKV_K8S_35` (Secrets as variables) | migration | Liquibase reads a password only from arguments, variables or a properties file |
| `CKV_K8S_40` (UID above 10000) | migration | The upstream Liquibase image user owns `/liquibase` |

## Deployment

| Environment | Overlay | Guide |
|---|---|---|
| Local (kind) | `overlays/local` | [deploy-local.md](deploy-local.md) |
| Production (AWS EKS) | `overlays/aws` | [deploy-aws.md](deploy-aws.md) |

**App repository CI.** The app repository's CI deploys with `deploy-local.sh` and `overlays/local`. A change to either affects every app pull request after the merge. Keep the change backward compatible: the app code on `main` must still deploy and pass with it. The [app repository's README](https://github.com/ShocKwav3/workflow-execution-engine#changes-that-need-both-repositories) describes a change that needs both repositories.
