# workflow-execution-engine-deploy

Deployment configuration for [workflow-execution-engine](https://github.com/ShocKwav3/workflow-execution-engine), a workflow execution engine with an HTTP API, an outbox relay and an executor, backed by PostgreSQL and Redis.

The application code, the Dockerfiles and the application CI live in the app repository. This repository holds only the description of how the system runs, so that a configuration change does not need an application build. A deploy changes the image tag here, and the cluster runs what this repository describes.

## Contents

- [`k8s/`](k8s/README.md): Kubernetes manifests (Kustomize), how they work, and the deploy guides for minikube and AWS EKS.
- `.github/workflows/render.yml`: on every pull request and push to `main`, CI renders each Kustomize overlay and checks that the Redis configuration matches the app repository.
