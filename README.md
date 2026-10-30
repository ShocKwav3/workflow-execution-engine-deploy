# workflow-execution-engine-deploy

Deployment configuration for [workflow-execution-engine](https://github.com/ShocKwav3/workflow-execution-engine), a workflow execution engine with an HTTP API, an outbox relay and an executor, backed by PostgreSQL and Redis.

The application code, the Dockerfiles and the application CI live in the app repository. This repository holds only the description of how the system runs, so that a configuration change does not need an application build. A deploy changes the image tag here, and the cluster runs what this repository describes.

## Contents

### Kubernetes

Kubernetes manifests (Kustomize): a shared base and one overlay each for a local kind cluster and AWS EKS, with the deploy guides for both.

More: [`k8s/`](k8s/README.md)

### Terraform

Terraform configurations for the AWS environment. `bootstrap` holds the state bucket, the GitHub OIDC provider and the IAM roles that CI assumes; it is never destroyed. `env` holds the network, the EKS cluster, the data stores and ECR; it is created for a session and destroyed after it. `cluster-addons` installs the Load Balancer Controller and External Secrets Operator into the cluster; it is applied after `env` and destroyed before it.

More: [`infra/terraform/`](infra/terraform/README.md)

### Workflows

GitHub Actions. Every pull request and push to `main` runs `.github/workflows/ci.yml`. Each concern is a separate job:

- `render`: renders each Kustomize overlay and checks that the Redis configuration matches the app repository.
- `terraform`: `terraform fmt -check`, then `validate` for each configuration. It does not need AWS access.
- `config-scan`: a static security scan of the Terraform code, the rendered overlays of `render`, and the workflows (Checkov).
- `ci-passed`: fails unless every job above succeeded. It is the only required check on `main`. It posts a table of the job results on the pull request, with the scan findings in collapsed sections.

The config scan only reports: a finding does not fail the job or block the merge.

More: [`.github/workflows/`](.github/workflows/)
