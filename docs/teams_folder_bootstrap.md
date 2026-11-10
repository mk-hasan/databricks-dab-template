# Teams folder bootstrap (restricted deploys)

Deployments use:

```text
/Workspace/Teams/<team_name>/<bundle.name>/<dev|test|prod>
```

Do **not** use `/Workspace/Shared` if you need access limited to the CD service principal and a team group.

## Automated in CD (preferred)

CD runs this **before** `bundle deploy`:

```text
devops-pipeline/scripts/ensure_team_folder_acl.sh
```

Wired in `devops-pipeline/azure-pipelines-cd.yml` for DEV / STAGE / PROD.

The script:

1. `mkdirs` `/Workspace/Teams/<team_name>`
2. Resolves the directory object id
3. `databricks permissions update directories …` with:
   - **`deploy_group`** (e.g. `dbx-deploy-dev`) → `CAN_MANAGE` — preferred; all CD SPs in that group get access
   - optional single `deploy_sp` → `CAN_MANAGE`
   - `team_group` → `CAN_READ` (skipped if empty or `users`)

### Inputs

| Source | Variables |
|--------|-----------|
| `config/project.yml` | `team_name`, `team_group` |
| `config/platform.yml` | `deploy_group` (per target: dev/test/prod) |
| Pipeline (per stage) | `azureServiceConnection`, `BUNDLE_TARGET` passed to ACL script |

Yes — a **group of service principals** works. Put every CD service principal in the deploy group for that environment (for example `dbx-deploy-dev`), grant that group `CAN_MANAGE` on the team folder, and you do not need one ACL entry per service principal.

### One-time admin prerequisite

`/Workspace/Teams` must exist and the **CD service principal** must be allowed to create folders / set ACL under it (admin grants this once on the parent). The script does **not** create or unlock the parent `Teams` folder.

### Configure your team

1. Set in `config/project.yml`:
   - `team_name` — e.g. `finance-team`
   - `team_group` — human Databricks group (not `users`)
2. Replace `deploy_group` in `config/platform.yml`. The file ships with `dbx-deploy-dev`, `dbx-deploy-test`, and `dbx-deploy-prod` as examples.
3. Add the CD service principal to `deploy_group`
4. Push to `dev` — CD creates `/Workspace/Teams/<team_name>`, applies ACL, then deploys

### Manual fallback (UI / laptop)

```bash
export DATABRICKS_HOST=...
export DATABRICKS_AUTH_TYPE=azure-cli   # or profile/token
export BUNDLE_ROOT=.
bash devops-pipeline/scripts/ensure_team_folder_acl.sh
```

## Bundle vs folder permissions

| Control | What it covers |
|---------|----------------|
| Folder ACL on `/Workspace/Teams/<team>` (script) | Who can browse / edit deployed files |
| Top-level `permissions:` in `databricks.yml` | Job and pipeline ACL (`CAN_MANAGE` for `deploy_group` and `team_group`) |

## Fork checklist

1. Change `team_name`, `team_group`, `bundle.name`, and `schema` in `config/project.yml` (bundle name stays in `databricks.yml`)
2. Confirm CD SP can write under `/Workspace/Teams`
3. Deploy — script + bundle run in CD
