#!/usr/bin/env bash
# Builds the app images at the app repository's HEAD and deploys the local overlay to minikube.
set -euo pipefail

NAMESPACE=workflow-engine
APPS=(api outbox-relay executor)
OVERLAY="$(cd "$(dirname "$0")" && pwd)/overlays/local"
KUSTOMIZATION="$OVERLAY/kustomization.yaml"

require() {
  if ! command -v "$1" > /dev/null; then
    echo "error: '$1' is not installed. Install it with: $2" >&2
    exit 1
  fi
}

require git "https://git-scm.com/downloads"
require docker "https://docs.docker.com/get-started/get-docker/"
require minikube "brew install minikube (or https://minikube.sigs.k8s.io/docs/start/)"
require kubectl "brew install kubectl (or https://kubernetes.io/docs/tasks/tools/)"
require kustomize "brew install kustomize (or https://kubectl.docs.kubernetes.io/installation/kustomize/)"

APP_REPO="${DEPLOY_APP_REPO:?set DEPLOY_APP_REPO to the path of your workflow-execution-engine clone}"

# The tag names a commit, so the build must contain exactly that commit.
if [ -n "$(git -C "$APP_REPO" status --porcelain)" ]; then
  echo "error: $APP_REPO has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

TAG="$(git -C "$APP_REPO" rev-parse --short HEAD)"
echo "==> Tag $TAG"

echo "==> Build images"
# Bake resolves the contexts in the file from the working directory.
(cd "$APP_REPO" && TAG="$TAG" docker buildx bake -f docker/docker-bake.hcl --load)

echo "==> Load images into minikube"
for image in api outbox-relay executor migrate; do
  minikube image load "workflow-engine/$image:$TAG"
done

# The tag is set for this run only; the committed file keeps the placeholder.
BACKUP="$(mktemp)"
cp "$KUSTOMIZATION" "$BACKUP"
trap 'cp "$BACKUP" "$KUSTOMIZATION"; rm -f "$BACKUP"' EXIT

(
  cd "$OVERLAY"
  for image in api outbox-relay executor migrate; do
    kustomize edit set image "workflow-engine/$image:$TAG"
  done
)

echo "==> Apply everything except the apps"
kubectl apply -k "$OVERLAY" -l "app.kubernetes.io/name notin ($(IFS=,; echo "${APPS[*]}"))"

echo "==> Wait for the migration"
if ! kubectl wait --for=condition=complete "job/migrate-$TAG" -n "$NAMESPACE" --timeout=5m; then
  echo "error: job/migrate-$TAG did not complete. The apps were not changed." >&2
  echo "Inspect it with: kubectl get pods -n $NAMESPACE -l job-name=migrate-$TAG" >&2
  exit 1
fi

echo "==> Apply the apps"
kubectl apply -k "$OVERLAY"
for app in "${APPS[@]}"; do
  kubectl rollout status "deploy/$app" -n "$NAMESPACE" --timeout=3m
done

echo "==> Deployed $TAG"
