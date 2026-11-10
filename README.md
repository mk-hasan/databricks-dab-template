# Databricks Asset Bundle template

This is a starter for one Databricks project, deployed as a [Databricks Asset Bundle](https://docs.databricks.com/dev-tools/bundles/index.html).

Copy it, replace the placeholders, and deploy. A sample orders job is included so you can confirm the deploy before you add your own code.

Azure DevOps is the pipeline in `devops-pipeline/`. GitHub Actions and Jenkins are the same flow in other files. Use one system. Setup for the other two: [docs/ci_cd_choices.md](docs/ci_cd_choices.md).

---

## Before the first deploy

You need:

- An Azure Databricks workspace with Unity Catalog
- Permission to deploy bundles and to create a schema in the catalog you set below
- A Databricks group for the people on the team. Any name except `users`
- A Databricks group that contains the deploy service principal, one group per environment
- A single-node job compute policy in each workspace. Copy the policy ID from **Compute → Policies** (it is in the policy URL). The section [Job compute](#job-compute) shows what that policy is expected to set
- The folder `/Workspace/Teams` already present. A workspace admin grants the deployer permission to create folders under it. The pipeline does not create that parent folder
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) logged in with `az login`
- Databricks CLI **0.295.1**, the version the pipelines install. Newer CLI builds can treat the workspace host differently

Workspace hosts, catalog names, policy IDs, deploy groups, the team folder, and Azure DevOps service connections in this repo are placeholders.

---

## 1. Set your project

Edit `databricks.yml` and `config/project.yml`.

| Change | Where | Example |
|--------|--------|---------|
| Bundle name | `databricks.yml` → `bundle.name` | `my_sales_project` |
| Team folder | `config/project.yml` → `team_name` | `finance-team` |
| Team group | `config/project.yml` → `team_group` | `finance-dbx-users` |
| Cost center | `config/project.yml` → `cost_center_id` | `CC-10042` |
| Cost tag | `config/project.yml` → `usecase` | `my_sales_project` |
| Purpose tag | `config/project.yml` → `purpose` | `sales` |
| Schema, per environment | `config/project.yml` → `targets.*.variables.schema` | `my_schema` |

`team_name` becomes a folder: `/Workspace/Teams/<team_name>/<bundle.name>/<dev|test|prod>`.

`cost_center_id`, `usecase`, and `purpose` are tags on every job, pipeline, and cluster. The shipped values are `YOUR-COST-CENTER-ID`, `usecase_template`, and `template`.

In `devops-pipeline/azure-pipelines-ci.yml`, set `blocking` to `true`. CI then fails while `cost_center_id` is still `YOUR-COST-CENTER-ID`, `purpose` is still `template`, or `team_group` is empty or `users`.

Bundle permissions grant `team_group` and the deploy group `CAN_MANAGE` on every job and pipeline. That level works on both jobs and pipelines, and it includes run. Leave `permissions` and `tags` off each job file. A `permissions` block on a job replaces the bundle list. Job tags come from `presets.tags` in `databricks.yml`.

```yaml
# config/project.yml — values to set. Keep the descriptions already in the file.
variables:
  team_name:
    default: finance-team
  team_group:
    default: finance-dbx-users
  cost_center_id:
    default: "CC-10042"
  usecase:
    default: my_sales_project
  purpose:
    default: sales

targets:
  dev:
    variables:
      schema: my_schema
  test:
    variables:
      schema: my_schema
  prod:
    variables:
      schema: my_schema
```

---

## 2. Set the workspaces

Edit `config/platform.yml` for the workspaces this project deploys to.

| Setting | Replace |
|---------|---------|
| `targets.*.workspace.host` | `https://adb-YOUR-*-WORKSPACE.azuredatabricks.net` |
| `targets.*.variables.catalog` | `catalog_dev`, `catalog_test`, `catalog_prod` |
| `targets.*.variables.job_compute_policy_id` | `YOUR-DEV-POLICY-ID`, `YOUR-TEST-POLICY-ID`, `YOUR-PROD-POLICY-ID` |
| `targets.*.variables.deploy_group` | `dbx-deploy-dev`, `dbx-deploy-test`, `dbx-deploy-prod` |

`dev` stays `default: true`, so local bundle commands use the dev workspace when you omit `-t`.

Policy IDs differ per workspace. Put each ID under its target:

```yaml
targets:
  dev:
    variables:
      job_compute_policy_id: "YOUR-DEV-POLICY-ID"
      deploy_group: dbx-deploy-dev
  test:
    variables:
      job_compute_policy_id: "YOUR-TEST-POLICY-ID"
      deploy_group: dbx-deploy-test
  prod:
    variables:
      job_compute_policy_id: "YOUR-PROD-POLICY-ID"
      deploy_group: dbx-deploy-prod
```

Add the CD service principal to each deploy group. That group needs permission to create folders under `/Workspace/Teams`.

---

## 3. Deploy from your machine

From the repo root, after `az login`:

```bash
export DATABRICKS_AUTH_TYPE=azure-cli
export BUNDLE_ROOT=.
export BUNDLE_TARGET=dev
bash devops-pipeline/scripts/ensure_team_folder_acl.sh
databricks bundle validate -t dev
databricks bundle deploy -t dev
```

The script creates `/Workspace/Teams/<team_name>` and sets folder permissions. It is bash; on Windows, run it from Git Bash or WSL. Pass `--target` (`-t`) on every Databricks CLI command. CLI 0.295 reads the workspace host from the selected target.

Deploy path for this example:

```text
/Workspace/Teams/finance-team/my_sales_project/dev
```

Folder permissions are explained in [docs/teams_folder_bootstrap.md](docs/teams_folder_bootstrap.md).

---

## 4. Deploy from Azure DevOps

Use the same three Azure Resource Manager service connection names in both pipeline files.

`devops-pipeline/azure-pipelines-cd.yml`:

```yaml
- name: azureServiceConnectionDev
  value: your-azure-rm-connection-dev
- name: azureServiceConnectionTest
  value: your-azure-rm-connection-test
- name: azureServiceConnectionProd
  value: your-azure-rm-connection-prod
```

`devops-pipeline/azure-pipelines-ci.yml` uses the same names as flat keys (`azureServiceConnectionDev: ...`). CI logs in with them because `bundle validate` on CLI 0.295 contacts each workspace.

Change `your-self-hosted-pool` in both files. CD uses it for every stage. CI uses a Microsoft-hosted agent for lint and tests, and the self-hosted pool for `bundle validate`. Hosted agents are usually blocked by the workspace IP access list.

| Git branch | Azure DevOps environment | Databricks target | Connection |
|------------|--------------------------|-------------------|------------|
| `dev` | `dev` | `dev` | `azureServiceConnectionDev` |
| `stage` | `test` | `test` | `azureServiceConnectionTest` |
| `main` | `prod` | `prod` | `azureServiceConnectionProd` |

The git branch `stage` deploys the Databricks target `test`.

Then:

1. Create branches `dev`, `stage`, and `main`.
2. Create two pipelines: CI → `devops-pipeline/azure-pipelines-ci.yml`, CD → `devops-pipeline/azure-pipelines-cd.yml`.
3. Authorize each pipeline to use the three service connections. Azure DevOps asks on the first run.
4. Add an Approval check on the Azure DevOps environment `prod`.
5. Require a pull request to merge into `stage` and `main`.
6. Push to `dev`. CD creates the team folder, then deploys.

Workspace hosts stay in `config/platform.yml`. They are not pipeline variables.

---

## 5. Run the sample orders jobs

After a dev deploy, open **Workflows** in the dev workspace.

| Run | What it does |
|-----|----------------|
| `dev-example-source-read` | Bronze → silver → gold on a job cluster |
| `dev-example-source-write` | Writes an outbound table from gold. Run this after the read job |
| `dev-example-source-read-serverless` | Same notebooks as the read job, on serverless compute |
| `dev-example-source-read-dlt` | The same orders flow as a Lakeflow Declarative pipeline (DLT) |

Job names start with the target: `dev-`, `test-`, or `prod-`.

With the shipped catalog and schema names, the tables are:

- `catalog_dev.template.example_orders_bronze`
- `catalog_dev.template.example_orders_silver`
- `catalog_dev.template.example_orders_gold_daily`
- `catalog_dev.template.example_orders_outbound`
- `catalog_dev.template.dlt_orders_bronze` and `dlt_orders_silver` after the DLT pipeline

Catalog comes from `config/platform.yml`. Schema comes from `config/project.yml`. After you rename them, look up `<catalog>.<schema>` instead of `catalog_dev.template`.

---

## 6. Add your own source

1. Copy `src/example_source/` to `src/<your_source>/`.
2. Copy `resources/example_source_read.job.yml` to `resources/<your_source>_read.job.yml`.
3. Copy `resources/example_source_write.job.yml` to `resources/<your_source>_write.job.yml` when you send data back to the source.
4. Rename the job keys inside those files and point the notebook paths at `src/<your_source>/`.
5. Put code in `read/bronze`, `read/silver`, `read/gold`, and `write`.
6. Delete `src/example_source/` and the `example_source_*` and `example_serverless` files in `resources/` when you no longer want the sample.

Every `resources/*.yml` file is deployed. Keep a single `databricks.yml` at the repo root.

```text
src/my_source/read/bronze|silver|gold/
src/my_source/read/dlt/          # only if you choose a declarative pipeline
src/my_source/write/
resources/my_source_read.job.yml
```

Use notebooks (classic or serverless) or a DLT pipeline for a source. The template includes both. DLT lives under `read/` because it ingests and transforms, the same job as bronze, silver, and gold.

Deploy builds the wheel from `databricks.yml` (`artifacts.python_artifact`) into `dist/*.whl`. The bronze notebook imports `src.example_source.utils.orders` from that wheel. On a classic job, attach the wheel to each task that imports it:

```yaml
libraries:
  - whl: ../dist/*.whl
```

The serverless job lists the same wheel under `environments[].spec.dependencies`, so every task in that environment can import it. Silver and gold do not import the package, so the classic job leaves the wheel off those tasks.

---

## Job compute

Classic jobs use one cluster variable from `databricks.yml`:

```yaml
job_clusters:
  - job_cluster_key: main_cluster
    new_cluster: ${var.default_job_cluster}
```

`default_job_cluster` sets the policy, cost tags, Azure on-demand instances, and single-user access. Per-environment differences stay in `config/platform.yml` (`job_compute_policy_id`). Replacing `default_job_cluster` on a target replaces the whole object.

The policy is expected to supply:

| Setting | Value |
|---------|--------|
| VM size | `Standard_F4` |
| Single-node | yes (`num_workers: 0`) |
| Spark runtime | `auto:latest-lts` |

`auto:latest-lts` works inside a compute policy. It is not a valid `spark_version` on a cluster written out by hand.

A field the policy marks `unlimited` can be set on that one job and overrides the policy default.

When the workspace has no policy, drop `policy_id` and `apply_policy_default_values` and write the cluster in the job:

```yaml
new_cluster:
  spark_version: 16.4.x-scala2.12   # a runtime ID that exists in the workspace
  node_type_id: Standard_F4
  is_single_node: true
  kind: CLASSIC_PREVIEW
  num_workers: 0
  azure_attributes:
    availability: ON_DEMAND_AZURE
  data_security_mode: SINGLE_USER
```

If a single-node deploy fails, add `kind: CLASSIC_PREVIEW`.

---

## What is in the repo

```text
.
├── databricks.yml                 ← bundle name, includes, shared cluster, permissions
├── VERSION                        ← template release (1.0.0)
├── config/
│   ├── platform.yml               ← hosts, catalogs, policies, deploy groups
│   └── project.yml                ← team, cost tags, schema
├── resources/                     ← jobs and pipelines deployed to Databricks
├── src/example_source/            ← sample orders code; copy this shape
├── devops-pipeline/               ← Azure DevOps pipelines and scripts
├── .github/workflows/             ← GitHub Actions (optional)
├── jenkins/Jenkinsfile            ← Jenkins (optional)
├── tests/
└── docs/
```

---

## Updating a project that already uses this template

Copy template-owned files from a release tag. Keep the files your project owns. Upgrade notes are in [CHANGELOG.md](CHANGELOG.md).

| File | Owner | On an upgrade |
|------|--------|----------------|
| `config/platform.yml` | Template | Overwrite from the tag |
| `devops-pipeline/templates/` | Template | Overwrite from the tag |
| `devops-pipeline/scripts/` | Template | Overwrite from the tag |
| `VERSION` | Template | Shows the release the project last took |
| `config/project.yml` | Your project | Keep your file |
| `resources/` and `src/<your_source>/` | Your project | Keep your files |
| `databricks.yml` | Mixed | Change `bundle.name` only |
| `devops-pipeline/azure-pipelines-cd.yml` | Mixed | Change the three service-connection names only |
| `devops-pipeline/azure-pipelines-ci.yml` | Mixed | Keep `blocking: true` |

Current template release: **1.0.0**.

---

## More detail

| Doc | Topic |
|-----|--------|
| [docs/ci_cd_choices.md](docs/ci_cd_choices.md) | GitHub Actions or Jenkins |
| [docs/teams_folder_bootstrap.md](docs/teams_folder_bootstrap.md) | Team folder permissions |
| [Databricks Asset Bundles](https://docs.databricks.com/dev-tools/bundles/index.html) | Bundle configuration |
| [LICENSE](LICENSE) | MIT License |
