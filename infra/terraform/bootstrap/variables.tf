variable "github_repository" {
  description = "GitHub repository whose workflows may assume the CI roles, as it appears in the OIDC sub claim: owner/repo, or owner@owner-id/repo@repo-id for repositories that use immutable subject claims."
  type        = string
  default     = "ShocKwav3@23660537/workflow-execution-engine-deploy@1417869970"
}
