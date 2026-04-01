# Create Module Repository

Provisions a complete, standards-compliant VirtoCommerce module repository from scratch.

## What it does

1. **Validates inputs** — checks module name format (PascalCase) and version syntax (x.y.z) before requesting approval.
2. **Checks for conflicts** — verifies that neither the GitHub repository nor the SonarCloud project already exist.
3. **Requests approval** — pauses for a designated reviewer via the `create-org-repo` environment gate.
4. **Creates the GitHub repository** with the computed name `vc-module-{kebab}` and the requested visibility.
5. **Configures the repository**: merge strategy (squash-only), Actions permissions (`allowed_actions=all`), team permissions, branch structure (`main` + `dev`), and branch protection rules.
6. **Generates module code** using the selected [vc-cli-module-template](https://github.com/VirtoCommerce/vc-cli-module-template) and commits it.
7. **Wires up CI/CD**: copies workflow templates (`module-ci.yml`, `release.yml`, `publish-nugets.yml`, `module-release-hotfix.yml`) and writes the cloud deployment config.
8. **Provisions SonarCloud** (public repos only): creates and binds the project to GitHub, grants project-level admin to the token user, disables Automatic Analysis, and sets the New Code definition to "Previous version".
9. **Tags the repository** with custom properties (template, module ID, creator, creation time, workflow run link).
10. **Registers** the new repository in `deploy-module-workflows.yml`.
11. **Rolls back** GitHub and SonarCloud resources automatically on failure.

## Prerequisites

### Secrets (Settings → Secrets and variables → Actions → Secrets)

| Secret | Description |
|--------|-------------|
| `MODULE_REPO_MGMT_TOKEN` | PAT with `repo` and `admin:org` (team write) scopes. Used for all GitHub API calls and git operations. |
| `SONAR_TOKEN` | SonarCloud user token with `Administer` permission on the organization. The workflow self-grants project-level admin after provisioning, so the token does not need to belong to the org owner. Required for public repos. |

### Variables (Settings → Secrets and variables → Actions → Variables)

| Variable | Description |
|----------|-------------|
| `SONAR_ORG_KEY` | SonarCloud organization key (e.g. `virtocommerce`). Not sensitive — stored as a variable, not a secret. |

### GitHub Environment

Create an environment named **`create-org-repo`** and add required reviewers:
`Settings → Environments → New environment → create-org-repo → Required reviewers`

### Org custom properties

The following custom property schemas must be pre-defined in the organization before running the workflow:
`Settings → Custom properties → New property`

| Property name | Type | Required |
|---------------|------|----------|
| `module-template` | string | yes |
| `module-id` | string | yes |
| `platform-version` | string | yes |
| `created-by` | string | yes |
| `created-at` | string | yes |
| `workflow-run` | string | yes |
| `sonar-key` | string | only for public repos |

> Property tagging uses `continue-on-error: true` — a missing schema will not fail the workflow, but the properties will not be set.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `moduleName` | yes | — | PascalCase name (e.g. `News`, `NewsArticle`). Repository name is derived automatically as `vc-module-{kebab}`. |
| `template` | no | `vc-module-dba` | Code template: `vc-module-dba`, `vc-module-dba-xapi`, or `vc-module-xapi`. |
| `companyName` | no | `VirtoCommerce` | Namespace prefix used in generated code. |
| `author` | no | `VirtoCommerce` | Author name used in generated code. |
| `moduleVersion` | no | — | Initial module version (x.y.z). |
| `platformVersion` | no | — | Target platform version (x.y.z). |
| `coreVersion` | no | — | Target core module version (x.y.z). Used for `vc-module-dba` / `vc-module-dba-xapi` templates. |
| `xapiVersion` | no | — | Target XAPI module version (x.y.z). Used for `vc-module-xapi` / `vc-module-dba-xapi` templates. |
| `templateVersion` | no | latest | Pin the `VirtoCommerce.Module.Template` NuGet version. Leave empty to use the latest. |
| `visibility` | no | `public` | Repository visibility: `public` or `private`. SonarCloud setup is skipped for private repos. |

## Rollback

If any step after repository creation fails, the workflow automatically:
- Deletes the GitHub repository (if it was created in this run).
- Deletes the SonarCloud project (if it was created in this run).

Steps marked `continue-on-error: true` (custom properties, deploy-workflow registration) do not trigger rollback — they emit a warning annotation instead.
