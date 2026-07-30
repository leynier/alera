# GitHub Deployment Identity Bootstrap

This independent OpenTofu root creates the keyless GitHub Actions identity used to deploy Alera Cloud. Its OIDC provider accepts tokens only from the immutable `leynier/alera` repository id on `refs/heads/main`.

Apply this root once with local Google Application Default Credentials:

```sh
cp backend.hcl.example backend.hcl
tofu init -backend-config=backend.hcl
tofu plan -out=bootstrap.tfplan
tofu apply bootstrap.tfplan
```

The state lives under `alera/bootstrap/github` in the existing versioned state bucket. The deployer can manage the production resources declared by `infra/production`, push Artifact Registry images, impersonate the Cloud Run runtime account, and lock production state. It has no persistent service-account key.

Use the two outputs as the GitHub Environment variables `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT`.
