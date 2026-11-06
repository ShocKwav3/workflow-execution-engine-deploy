# Workflows

GitHub Actions for this repository. Two kinds of workflows:

- **CI** (`ci.yml`) runs on every pull request and every push to `main`. It never changes AWS.
- **Session workflows** (`infra.yml`, `deploy.yml`) create, deploy and remove the AWS environment. They run only on manual dispatch from `main`.

No AWS access keys are stored. Jobs get temporary credentials through GitHub OIDC and one of the two CI roles from `infra/terraform/bootstrap`.

## Setup

Repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Value | Used by |
|---|---|---|
| `AWS_ACCOUNT_ID` | The AWS account ID. The workflows build the role ARNs, the state bucket name and the ECR registry from it; GitHub masks it in the logs. | all AWS jobs |
| `OPERATOR_CIDR` | The public IPv4 address that may reach the API load balancer, as a `/32` (`echo "$(curl -fsS https://checkip.amazonaws.com)/32"`). | `infra-plan`, `infra` |

Update `OPERATOR_CIDR` when your IP address changes, then run `infra` `apply` again.

The GitHub environment `aws` allows the `main` branch only. The apply role trusts only jobs in this environment.

## CI (`ci.yml`)

Each concern is a separate job:

- `render`: renders each Kustomize overlay and checks that the Redis configuration matches the app repository.
- `terraform`: `terraform fmt -check`, then `validate` for each configuration. It does not need AWS access.
- `config-scan`: a static security scan of the Terraform code, the rendered overlays of `render`, and the workflows (Checkov). It only reports: a finding does not fail the job.
- `infra-plan`: on a pull request that changes Terraform files, runs `terraform plan` for `bootstrap` and `env` with the read-only plan role. It then checks the planned IAM policies:
  - IAM Access Analyzer policy validation (`tf-policy-validator`); an `ERROR` finding fails the job;
  - Conftest: every IAM role in `env` has a permissions boundary (policy and tests in `infra/terraform/policy/`).

  On other runs, it does nothing and succeeds. `cluster-addons` is not planned, because it needs a running cluster. The plan JSON stays on the runner; it is never uploaded.
- `ci-passed`: fails unless every job above succeeded. It is the only required check on `main`. It posts a table of the job results on the pull request, with the scan findings in collapsed sections.

## Session workflows

Run them from **Actions → <workflow> → Run workflow**, on `main`. They share the concurrency group `infra`, so they never run at the same time; a second dispatch waits.

### Session order

1. `infra`: `apply` (about 20–30 minutes).
2. `deploy` (repeat as often as needed in the session).
3. `infra`: `destroy`.

Run `deploy` in every session, also without a code change: ECR is created empty with each `apply`, and no commit records the deployed tag.

`env` bills by the hour while it exists. Run `destroy` at the end of each session.

### `infra.yml`

Inputs: `action` (`apply` or `destroy`) and `confirm`, which must repeat the action. A mismatch fails before any AWS credentials are issued.

- `apply`: plans and applies `env`, then `cluster-addons`, each from a saved plan.
- `destroy`, in this order:
  1. Deletes the api Service and the `workflow-engine` namespace, so that the Load Balancer Controller removes the NLB and the controllers remove their finalizers.
  2. Destroys `cluster-addons`.
  3. Deletes a leftover Load Balancer Controller security group, if one exists.
  4. Destroys the node group.
  5. Deletes the network interfaces that the VPC CNI leaked when the nodes terminated. They block the subnet delete.
  6. Destroys the rest of `env`.

  If the cluster does not exist, steps 1 and 2 are skipped.

### `deploy.yml`

Input: `sha` (optional), a full commit SHA of the app repository. Empty deploys the latest `main`.

- `build` (arm64 runner): stops if no cluster exists. It checks out the app repository at the SHA, then builds and pushes to ECR only the images that are not there yet (the tags are immutable). The tag is the short commit SHA.
- `deploy`: sets the image tags in `k8s/overlays/aws` on the runner only, applies everything except the apps, and waits for the migration Job. Then it applies the apps and waits for the rollout. The job summary shows the API address.

After a deploy, connect to the cluster and run the end-to-end test from the app repository:

```bash
aws eks update-kubeconfig --name wee --region us-east-1
E2E_BASE_URL="http://$(kubectl get service api -n workflow-engine -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')" pnpm test:e2e
```

The load balancer DNS name can take a few minutes to resolve.
