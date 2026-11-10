# CI/CD choices

Use **one** of these. They call the same scripts and the same branch map.

| Git branch | Databricks target |
|------------|-------------------|
| `dev` | `dev` |
| `stage` | `test` |
| `main` | `prod` |

| System | Files |
|--------|--------|
| Azure DevOps | `devops-pipeline/azure-pipelines-ci.yml`, `devops-pipeline/azure-pipelines-cd.yml` |
| GitHub Actions | `.github/workflows/ci.yml`, `.github/workflows/cd.yml` |
| Jenkins | `jenkins/Jenkinsfile` |

`bundle validate` and `bundle deploy` log in with the Azure CLI, read the workspace host from `config/platform.yml`, and pass `--target`. GitHub-hosted and Microsoft-hosted agents are usually blocked by the workspace IP access list. Point validate and deploy at a runner or agent whose outbound IP is allowed.

Prod approval is not a shell step:

- Azure DevOps: approval check on the `prod` environment
- GitHub: required reviewers on the `prod` environment
- Jenkins: the **Approve prod** input on `main`

## GitHub Actions

1. Create environments `dev`, `test`, and `prod`. Require a reviewer on `prod`.
2. On each environment, add secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`.
3. For CI validate, also add repository secrets `AZURE_TENANT_ID`, `AZURE_CLIENT_ID_DEV`, `AZURE_SUBSCRIPTION_ID_DEV`, and the `_TEST` and `_PROD` pair.
4. Federate each app registration to this repository (OIDC). `azure/login` does not use a client secret.
5. Register a self-hosted runner and set `runs-on: self-hosted` to that runner's labels if the default label does not match.
6. Set repository variable `BLOCKING` to `true` in a real project. Unset, quality and placeholder checks do not fail the build.
7. Until the dev client-id secret exists, CI skips validate and still runs quality and tests. CD stays off until repository variable `CD_ENABLED` is `true` (set that after the environment secrets exist).

## Jenkins

1. Install the Azure CLI and the Credentials Binding plugin on the controller.
2. Create Azure service principal credentials `azure-sp-dev`, `azure-sp-test`, and `azure-sp-prod`.
3. Create a multibranch pipeline. Script path: `jenkins/Jenkinsfile`.
4. Give the deploy agent the label `your-self-hosted-pool`, or change that label in the Jenkinsfile.
5. Set `BLOCKING` to `true` in the Jenkinsfile environment block for a real project.

Delete the workflow files or the Jenkinsfile you do not use, so a push does not start two deploys.
