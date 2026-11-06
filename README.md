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
- `infra-plan`: on a pull request that changes Terraform files, runs `terraform plan` for `bootstrap` and `env` with the read-only plan role (GitHub OIDC, no stored AWS keys). It then checks the planned IAM policies with IAM Access Analyzer policy validation (`tf-policy-validator`; an `ERROR` finding fails the job), and checks with Conftest that every IAM role in `env` has a permissions boundary (policy in `infra/terraform/policy/`). On other runs, it does nothing and succeeds. It needs the repository secrets `AWS_ACCOUNT_ID` and `OPERATOR_CIDR`. `cluster-addons` is not planned, because it needs a running cluster.
- `ci-passed`: fails unless every job above succeeded. It is the only required check on `main`. It posts a table of the job results on the pull request, with the scan findings in collapsed sections.

The config scan only reports: a finding does not fail the job or block the merge.

`.github/workflows/infra.yml` creates or removes the AWS environment. It runs only on manual dispatch from `main` (**Actions → infra → Run workflow**), in the GitHub environment `aws`, with the apply role. Choose `apply` or `destroy`, and type the same word in `confirm`.

- `apply`: plans and applies `env`, then `cluster-addons`.
- `destroy`: deletes the api Service and the `workflow-engine` namespace (so that the Load Balancer Controller removes the NLB), destroys `cluster-addons`, deletes a leftover Load Balancer Controller security group, then destroys `env`.

`.github/workflows/deploy.yml` deploys the app to the running environment. It runs only on manual dispatch from `main` (**Actions → deploy → Run workflow**), after `infra` `apply`. The optional input `sha` is a full commit SHA of the app repository; empty deploys the latest `main`.

- `build` (arm64): stops if no cluster exists, checks out the app repository, and builds and pushes to ECR only the images that are not there yet. The tag is the short commit SHA.
- `deploy`: sets the image tags in a copy of `k8s/overlays/aws` on the runner, applies everything except the apps, waits for the migration Job, then applies the apps and waits for the rollout. No commit records the deployed tag.

Run `deploy` in every session, also without a code change: ECR is created empty with each `apply`.

More: [`.github/workflows/`](.github/workflows/)
