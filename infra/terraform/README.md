# Terraform

Terraform configurations for the AWS environment. Each folder is a separate configuration with its own state.

| Folder | Contents | Lifetime |
|---|---|---|
| `bootstrap/` | S3 state bucket, GitHub OIDC provider, CI plan role and CI apply role, ECR blob mounting | Created once, never destroyed |
| `env/` | VPC, EKS cluster and nodes, RDS PostgreSQL, ElastiCache Redis, ECR repositories, IAM roles for the cluster and its controllers | Created for a session, then destroyed |
| `cluster-addons/` | Helm releases in the cluster: AWS Load Balancer Controller, External Secrets Operator and its `ClusterSecretStore` objects | Applied after `env`, destroyed before it |

Requirements: Terraform 1.17 or later, and AWS credentials for the target account (for example `aws login`).

## bootstrap

`bootstrap` holds the resources that every other configuration depends on. It is applied from a workstation, not from CI.

- **State bucket:** `wee-tfstate-<account-id>-us-east-1-an`, in the account regional namespace. Versioning and SSE-S3 encryption are on, SSE-C uploads and public access are blocked, and Terraform refuses to destroy it. The bucket was created by hand and then imported, because Terraform needs it before it can store state.
- **State:** every configuration stores its state in this bucket under its own key (`bootstrap/terraform.tfstate` for this one), with S3-native locking (`use_lockfile`).
- **GitHub OIDC provider:** lets GitHub Actions jobs exchange their OIDC token for temporary AWS credentials. No access keys are stored.
- **Who can assume the CI roles:** only workflow runs of this repository that the repository owner's GitHub account started. Both trust policies check the token's `actor_id` (`github_actor_id`) in addition to `sub`.
- **Plan role** (`ci/wee-terraform-plan`): trusted only for pull request jobs of this repository. `ReadOnlyAccess`, plus write access to the state lock files.
- **Apply role** (`ci/wee-terraform-apply`): trusted only for jobs in the `aws` GitHub environment, which allows the `main` branch only. It manages the services of the AWS environment, and IAM roles and policies under the path `/wee/`. Every role it creates or changes must carry the permissions boundary `PowerUserAccess`, so those roles cannot manage IAM. It cannot remove a boundary or change the CI roles.
- **ECR blob mounting:** an account-wide ECR setting. Repositories share identical image layers, so the common base layers of the app images are stored once.

Outputs: `state_bucket`, `plan_role_arn`, `apply_role_arn`, `apply_boundary_arn`.

## env

`env` holds the AWS environment. It is created for a working session and destroyed after it. State key: `env/terraform.tfstate`.

- **Network:** a VPC with 2 public and 2 private subnets in `use1-az1` and `use1-az2`, an internet gateway, one NAT gateway, and an S3 gateway endpoint. The public subnets carry `kubernetes.io/role/elb`, so the AWS Load Balancer Controller places internet-facing load balancers there.
- **EKS:** cluster `wee` (Kubernetes 1.36, access entries only), a managed node group of 3 × `t4g.small` (arm64) in the private subnets, and the EKS add-ons VPC CNI, Pod Identity Agent, kube-proxy and CoreDNS. Cluster access comes from explicit access entries for the admin role and the two CI roles, not from the identity that created the cluster.
- **Data stores:** RDS PostgreSQL 16 (`wee-postgres`) and ElastiCache Redis OSS 7.1 (`wee-redis`, `maxmemory-policy noeviction`, TLS required), both private. RDS keeps the master password in Secrets Manager; it never enters the Terraform state.
- **Security groups:** `wee-rds` and `wee-redis` accept connections only from the EKS cluster security group. `wee-nlb` accepts port 80 only from `operator_cidr`.
- **Configuration for the cluster:** SSM parameters `/wee/app/PGHOST` and `/wee/app/REDIS_URL`, written from the data store endpoints.
- **ECR:** `workflow-engine/{api,outbox-relay,executor,migrate}`, immutable tags, a lifecycle policy that keeps the 2 newest tagged images. `force_delete` lets `destroy` remove repositories that still contain images.
- **IAM:** roles for the EKS cluster, the nodes, the AWS Load Balancer Controller and External Secrets Operator. Every role has the path `/wee/` and the permissions boundary `PowerUserAccess`, so the CI apply role can manage it. The controller roles reach their Pods through EKS Pod Identity.

Input: `operator_cidr`, the public IPv4 address that may reach the API load balancer, as a `/32`. It has no default; pass it as `TF_VAR_operator_cidr`.

Outputs: `cluster_name`, `db_secret_arn`, `ecr_repository_urls`, `rds_endpoint`, `redis_endpoint`.

## cluster-addons

`cluster-addons` installs the cluster add-ons with `helm_release`. It is a separate configuration because the Helm provider needs a running cluster when Terraform plans. State key: `cluster-addons/terraform.tfstate`.

- **Inputs from `env`:** `data "aws_eks_cluster"` reads the cluster `wee` by name: the API endpoint, the CA certificate and the VPC ID. The configuration reads no other state, and `env` needs no extra outputs.
- **Authentication:** the Helm provider gets a short-lived token from `aws eks get-token` at each run, with the AWS credentials of whoever runs Terraform. That identity needs an EKS access entry with cluster admin rights (see `env`).
- **AWS Load Balancer Controller:** chart 3.6.2 in `kube-system`. The IAM policy file in `env` belongs to this version; update both together. The service account name must match the Pod Identity association in `env`.
- **External Secrets Operator:** chart 2.14.0 in `external-secrets`, with its CRDs.
- **`ClusterSecretStore` objects:** `aws-parameter-store` and `aws-secrets-manager`, in the local chart `charts/secret-stores`, installed after ESO. A `kubernetes_manifest` would need the ESO CRDs at plan time, so the stores are a Helm release. Raise the chart `version` when you change a template.

## Initialize

The state bucket name contains the account ID, so it is not in the code. Pass it to `terraform init` in each configuration directory:

```bash
cd infra/terraform/bootstrap   # or infra/terraform/env, infra/terraform/cluster-addons
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
terraform init -backend-config="bucket=wee-tfstate-${ACCOUNT_ID}-us-east-1-an"
```

## Rebuild

Initialize each configuration first (see above).

1. Create the AWS environment, and point `kubectl` at the new cluster. Each new cluster has a new API endpoint.
   ```bash
   cd infra/terraform/env
   export TF_VAR_operator_cidr="$(curl -fsS https://checkip.amazonaws.com)/32"
   terraform apply
   aws eks update-kubeconfig --name wee --region us-east-1
   ```
2. Install the add-ons:
   ```bash
   cd ../cluster-addons
   terraform apply
   ```
3. Push the images and deploy the app: [`k8s/deploy-aws.md`](../../k8s/deploy-aws.md).

`env` bills by the hour while it exists (EKS control plane, nodes, NAT gateway, RDS, ElastiCache), and the API load balancer adds to that. Tear everything down at the end of each session.

## Teardown

The order matters. The controllers delete what they created in AWS and remove their finalizers only while they run.

1. Delete the api Service and the app namespace, and wait until the namespace is gone. The Load Balancer Controller deletes the Network Load Balancer; External Secrets Operator releases its `ExternalSecret` objects.
   ```bash
   kubectl delete service api -n workflow-engine
   kubectl delete namespace workflow-engine
   kubectl wait --for=delete namespace/workflow-engine --timeout=5m
   aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[].LoadBalancerName'
   ```
   Expect `[]` from the last command.
2. Remove the add-ons:
   ```bash
   cd infra/terraform/cluster-addons
   terraform destroy
   ```
3. Remove the AWS environment:
   ```bash
   cd ../env
   export TF_VAR_operator_cidr="$(curl -fsS https://checkip.amazonaws.com)/32"
   terraform destroy
   ```
   If the VPC delete waits on a `DependencyViolation`, the controller's shared backend security group `k8s-traffic-wee-…` is still in the VPC. Delete it with `aws ec2 delete-security-group`, and the destroy continues.

If `cluster-addons` is destroyed while the namespace still exists, the deletes hang on finalizers. Apply only the controller again (`terraform apply -target=helm_release.lb_controller`), wait for the namespace, then destroy.

## Format and validate

Run before each commit. Neither command calls AWS.

```bash
terraform fmt -recursive infra/terraform
terraform -chdir=infra/terraform/bootstrap validate
terraform -chdir=infra/terraform/env validate
terraform -chdir=infra/terraform/cluster-addons validate
```

CI runs the same checks on every pull request, with `terraform init -backend=false`. `validate` needs an initialized configuration directory. Commit `.terraform.lock.hcl`; never commit `.terraform/`, state files or saved plan files (`*.tfplan`).
