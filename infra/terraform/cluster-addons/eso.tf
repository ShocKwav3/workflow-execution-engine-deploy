resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.14.0"
  namespace        = "external-secrets"
  create_namespace = true

  set = [
    {
      # Must match the Pod Identity association in the env config.
      name  = "serviceAccount.name"
      value = "external-secrets"
    },
  ]
}

# A kubernetes_manifest would need the ESO CRDs at plan time; Helm does not check them.
resource "helm_release" "secret_stores" {
  name      = "secret-stores"
  chart     = "${path.module}/charts/secret-stores"
  namespace = "external-secrets"

  set = [
    {
      name  = "region"
      value = data.aws_region.current.region
    },
  ]

  depends_on = [helm_release.eso]
}
