# Terraform

Terraform configurations for the AWS environment. Each folder is a separate configuration with its own state.

| Folder | Contents | Lifetime |
|---|---|---|
| `bootstrap/` | S3 state bucket, GitHub OIDC provider, CI plan role and CI apply role | Created once, never destroyed |

Requirements: Terraform 1.15 or later, and AWS credentials for the target account (for example `aws login`).

## bootstrap

`bootstrap` holds the resources that every other configuration depends on. It is applied from a workstation, not from CI.

- **State bucket:** `wee-tfstate-<account-id>-us-east-1-an`, in the account regional namespace. Versioning and SSE-S3 encryption are on, SSE-C uploads and public access are blocked, and Terraform refuses to destroy it. The bucket was created by hand and then imported, because Terraform needs it before it can store state.
- **State:** every configuration stores its state in this bucket under its own key (`bootstrap/terraform.tfstate` for this one), with S3-native locking (`use_lockfile`).
- **GitHub OIDC provider:** lets GitHub Actions jobs exchange their OIDC token for temporary AWS credentials. No access keys are stored.
- **Plan role** (`ci/wee-terraform-plan`): trusted only for pull request jobs of this repository. `ReadOnlyAccess`, plus write access to the state lock files.
- **Apply role** (`ci/wee-terraform-apply`): trusted only for jobs in the `aws` GitHub environment, which allows the `main` branch only. It manages the services of the AWS environment, and IAM roles and policies under the path `/wee/`. Every role it creates or changes must carry the permissions boundary `PowerUserAccess`, so those roles cannot manage IAM. It cannot remove a boundary or change the CI roles.

Outputs: `state_bucket`, `plan_role_arn`, `apply_role_arn`, `apply_boundary_arn`.

## Initialize

The state bucket name contains the account ID, so it is not in the code. Pass it to `terraform init`:

```bash
cd infra/terraform/bootstrap
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
terraform init -backend-config="bucket=wee-tfstate-${ACCOUNT_ID}-us-east-1-an"
```

## Format and validate

Run before each commit. Neither command calls AWS.

```bash
terraform fmt -recursive infra/terraform
terraform -chdir=infra/terraform/bootstrap validate
```

`validate` needs an initialized configuration directory. Commit `.terraform.lock.hcl`; never commit `.terraform/` or state files.
