# Changelog

Template versions follow SemVer. Tags are cut from `main`.

- **Patch** — overwrite the template-owned files listed in the release. No other action.
- **Minor** — same overwrite. New files are opt-in.
- **Major** — follow the upgrade notes in that version before deploying.

Every release has an entry here. `VERSION` and `presets.tags.template_version` in `databricks.yml` stay identical.

## 1.0.0

First version with an ownership split, so a later tag can be copied onto a fork without merging the whole repo.

### Safety

- Job and pipeline YAML no longer grants `users` view or run.
- Bundle permissions grant `CAN_MANAGE` to `deploy_group` and `team_group`. One level is used because it is valid on both jobs and DLT pipelines, and it includes run.
- Top-level `job_compute_policy_id` and `deploy_group` default to empty. Real values stay on each target in `config/platform.yml`.
- Cost center placeholder is `YOUR-COST-CENTER-ID`. `purpose` is a variable (the template project keeps `template`).

### Layout

- `config/platform.yml` — hosts, catalogs, policy IDs, deploy groups. Overwrite this on upgrade.
- `config/project.yml` — team, group, cost center, purpose, usecase, schema. Never overwrite this.
- `databricks.yml` — bundle name, includes, the shared cluster variable, permissions, presets. Forks change `bundle.name` only.
- The sample orders example stays in `resources/` and `src/example_source/`, the same folders a real usecase uses. Remove it by deleting those files. `resources/*.yml` is what gets deployed.
- Classic jobs use `new_cluster: ${var.default_job_cluster}` instead of a copied cluster block. Job-level `tags` were removed; `presets.tags` covers them. Cluster `custom_tags` stay inside the shared cluster variable.
- Deploy logic lives in `devops-pipeline/templates/`. Shell helpers live in `devops-pipeline/scripts/`. A fork's `azure-pipelines-ci.yml` and `azure-pipelines-cd.yml` only hold service-connection names and the `blocking` flag.
- CD stages are deployment jobs on Azure DevOps Environments `dev`, `test`, and `prod`. Add an approval check on the `prod` environment, and branch policies on `stage` and `main`, in the Azure DevOps project.
- CI takes a `blocking` flag (false in this repo, true in forks). Forks fail when `YOUR-COST-CENTER-ID` remains, `purpose` is still `template`, or `team_group` is empty or `users`.
- CI runs `bundle validate` for dev, test, and prod. CLI 0.295 contacts the workspace, so CI logs in with the same three service connections as CD.

### Upgrading a fork that copied the repo before 1.0.0

This is a one-time move. Later releases are a checkout of the template-owned files onto a branch, then a PR to `dev`.

1. Add `config/platform.yml` and `config/project.yml` from this tag.
2. Move team, cost center, usecase, purpose, and schema into `config/project.yml`. Set `team_group` to the team's Databricks group.
3. Replace `databricks.yml` with the 1.0.0 file and set `bundle.name`.
4. Move any real jobs to `resources/`. Point their classic clusters at `${var.default_job_cluster}` and delete their `permissions` and `tags` blocks.
5. Replace `devops-pipeline/azure-pipelines-cd.yml` with the thin 1.0.0 file and put the team's service-connection names back.
6. Set `blocking` to `true` in `devops-pipeline/azure-pipelines-ci.yml`.
7. Open the PR against the fork's `dev` branch.
