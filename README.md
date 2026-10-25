# workflow-execution-engine-deploy

Deployment configuration for [workflow-execution-engine](https://github.com/ShocKwav3/workflow-execution-engine), a workflow execution engine with an HTTP API, an outbox relay and an executor, backed by PostgreSQL and Redis.

The application code, the Dockerfiles and the application CI live in the app repository. This repository holds only the description of how the system runs, so that a configuration change does not need an application build. A deploy changes the image tag here, and the cluster runs what this repository describes.

## Contents

### Kubernetes

Kubernetes manifests (Kustomize): a shared base and one overlay each for minikube and AWS EKS, with the deploy guides for both.

More: [`k8s/`](k8s/README.md)

### Terraform

Terraform configurations for the AWS environment. `bootstrap` holds the state bucket, the GitHub OIDC provider and the IAM roles that CI assumes; it is never destroyed.

More: [`infra/terraform/`](infra/terraform/README.md)

### Workflows

GitHub Actions. On every pull request and push to `main`, `render.yml` renders each Kustomize overlay and checks that the Redis configuration matches the app repository.

More: [`.github/workflows/`](.github/workflows/)
