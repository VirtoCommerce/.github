# Residual callers of deprecated actions / workflows

Active (non-commented) references across all 211 non-deploy-list org repos + internal sources. `self-deprecated` = the caller itself moved to `deprecated/`; `archived` = caller repo archived (wont run); `LIVE-pinned` = active caller on an immutable version tag (safe until it bumps); `LIVE-MUTABLE` = active caller on `@master`/branch (**breaks on merge to default branch**).

## Deprecated actions (vc-github-actions)

| Action | Caller repo | Caller workflow | Ref | Class |
|---|---|---|---|---|
| `build-theme` | vc-composer-theme | main.yml | `@master` | LIVE-MUTABLE |
| `build-theme` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `build-theme` | vc-demo-theme-default | main.yml | `@master` | archived |
| `build-theme` | vc-demo-theme-b2b | main.yml | `@master` | archived |
| `build-theme` | vc-theme-b2b | main.yml | `@master` | archived |
| `build-theme` | vc-theme-default | main.yml | `@master` | archived |
| `build-theme` | vc-theme-material | main.yml | `@master` | archived |
| `build-theme` | vc-theme-material | release-alpha.yml | `@master` | archived |
| `build-vue-theme` | vc-marketplace-theme | main.yml | `@master` | LIVE-MUTABLE |
| `check-acr-repos-size-limit` | vc-github-actions | acr-size-limit.yaml | `@master` | self-deprecated |
| `cloud-get-deploy-param` | — | — | — | no callers |
| `deploy-workflow` | vc-github-actions | deploy-sdk.yml | `@master` | self-deprecated |
| `deploy-workflow` | vc-github-actions | deploy.yml | `@master` | self-deprecated |
| `docker-check-modules` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `docker-install-modules` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `docker-install-sampledata` | — | — | — | no callers |
| `docker-install-theme` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `docker-restore-dump` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `docker-start-environment` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `docker-validate-swagger` | — | — | — | no callers |
| `generate-dashboard` | vc-github-actions | dashboard.yml | `@master` | self-deprecated |
| `generate-dashboard-durations` | vc-github-actions | dashboard.yml | `@master` | self-deprecated |
| `katalon-studio-github-action` | vc-demo-theme-b2b | autotest.yml | `@master` | archived |
| `katalon-studio-github-action` | .github | e2e.yml | `@master` | self-deprecated |
| `katalon-studio-github-action` | vc-module-experience-api | main_postman.yml | `@master` | archived |
| `katalon-studio-github-action` | vc-github-actions | katalon-report.yml | `@master` | self-deprecated |
| `katalon-studio-github-action` | vc-github-actions | katalon.yml | `@master` | self-deprecated |
| `katalon-studio-github-action` | vc-github-actions | suiteDebug.yml | `@master` | self-deprecated |
| `katalon-studio-github-action` | vc-quality-gate-katalon | demo_workflow.yml | `@master` | LIVE-MUTABLE |
| `pr-body-get-link` | vc-storefront | pr-deploy.yml | `@master` | LIVE-MUTABLE |
| `publish-katalon-report` | .github | e2e.yml | `@master` | self-deprecated |
| `publish-katalon-report` | vc-github-actions | katalon-report.yml | `@master` | self-deprecated |
| `publish-katalon-report` | vc-github-actions | katalon.yml | `@master` | self-deprecated |
| `publish-katalon-report` | vc-github-actions | suiteDebug.yml | `@master` | self-deprecated |
| `publish-katalon-report` | vc-quality-gate-katalon | demo_workflow.yml | `@master` | LIVE-MUTABLE |
| `publish-theme` | vc-composer-theme | main.yml | `@master` | LIVE-MUTABLE |
| `publish-theme` | vc-demo-theme-default | main.yml | `@master` | archived |
| `publish-theme` | vc-demo-theme-b2b | main.yml | `@master` | archived |
| `publish-theme` | vc-marketplace-theme | main.yml | `@master` | LIVE-MUTABLE |
| `publish-theme` | vc-theme-b2b | main.yml | `@master` | archived |
| `publish-theme` | vc-theme-default | main.yml | `@master` | archived |
| `publish-theme` | vc-theme-material | main.yml | `@master` | archived |
| `publish-theme` | vc-theme-material | release-alpha.yml | `@master` | archived |
| `run-e2e-tests` | .github | e2e-autotests.yml | `@master` | self-deprecated |
| `run-graphql-tests` | .github | ui-autotests.yml | `@master` | self-deprecated |
| `set-version-up` | — | — | — | no callers |
| `sonar-theme` | vc-demo-xapi-app | main.yml | `@master` | archived |
| `sonar-theme` | vc-demo-theme-default | main.yml | `@master` | archived |
| `sonar-theme` | vc-demo-theme-b2b | main.yml | `@master` | archived |
| `sonar-theme` | vc-odt-mpa-theme | main.yml | `@master` | archived |
| `sonar-theme` | vc-theme-b2b | main.yml | `@master` | archived |
| `sonar-theme` | vc-theme-default | main.yml | `@master` | archived |
| `sonar-theme` | vc-theme-material | main.yml | `@master` | archived |
| `sonar-theme` | vc-theme-material | release-alpha.yml | `@master` | archived |
| `update-deploy-config` | vc-github-actions | deploy-cloud-config-deployment.yml | `@master` | self-deprecated |
| `update-deploy-config` | vc-github-actions | deploy-config-deployment.yml | `@master` | self-deprecated |
| `update-virtocommerce-docs-2` | vc-github-actions | virtocommerce-docs-2.yml | `@master` | self-deprecated |
| `update-virtocommercecom` | vc-module-Authorize.Net | module-ci.yml | `@master` | archived |
| `update-virtocommercecom` | vc-module-ai-document-parser | module-ci.yml | `@master` | LIVE-MUTABLE |
| `update-virtocommercecom` | vc-module-metadata | module-ci.yml | `@master` | archived |
| `update-virtocommercecom` | vc-module-quote-experience-api | module-ci.yml | `@master` | archived |
| `update-webhook-configuration` | vc-github-actions | jira-pr-webhook-update.yaml | `@master` | self-deprecated |
| `validate-swagger` | — | — | — | no callers |

## Deprecated reusable workflows (.github)

| Workflow | Caller repo | Caller workflow | Ref | Class |
|---|---|---|---|---|
| `e2e-autotests.yml` | vc-testing-module | e2e-tests-docker.yml | `@v3.800.23` | LIVE-pinned |
| `e2e.yml` | vc-ci-test | module-ci-common.yml | `@v3.800.24` | LIVE-pinned |
| `e2e.yml` | vc-dev-training | module-ci.yml | `@v3.800.22` | LIVE-pinned |
| `e2e.yml` | vc-github-actions | Katalon_new.yml | `@v3.800.37` | self-deprecated |
| `e2e.yml` | vc-module-Authorize.Net | module-ci.yml | `@v3.200.20` | archived |
| `e2e.yml` | vc-module-ai-document-parser | module-ci.yml | `@v3.200.35` | LIVE-pinned |
| `e2e.yml` | vc-module-catalog-export-import | module-ci.yml | `@v3.200.36` | archived |
| `e2e.yml` | vc-module-environments-compare | module-ci.yml | `@v3.800.17` | LIVE-pinned |
| `e2e.yml` | vc-github-actions | katalon_platform_test.yml | `@main` | self-deprecated |
| `e2e.yml` | vc-module-marketing-campaigns | module-ci.yml | `@v3.800.25` | LIVE-pinned |
| `e2e.yml` | vc-module-metadata | module-ci.yml | `@v3.200.20` | archived |
| `e2e.yml` | vc-module-opentelemetry | module-ci.yml | `@v3.800.25` | LIVE-pinned |
| `e2e.yml` | vc-module-one-shell-app | module-ci.yml | `@v3.800.24` | LIVE-pinned |
| `e2e.yml` | vc-module-quote-experience-api | module-ci.yml | `@v3.200.20` | archived |
| `e2e.yml` | vc-module-test-module | module-ci.yml | `@v3.800.26` | LIVE-pinned |
| `e2e.yml` | vc-module-shopify-taxonomy | module-ci.yml | `@v3.800.12` | LIVE-pinned |
| `e2e.yml` | vc-module-ui-migration | module-ci.yml | `@v3.800.16` | LIVE-pinned |
| `get-metadata.yml` | — | — | — | no callers |
| `increment-version.yml` | — | — | — | no callers |
| `ui-autotests.yml` | vc-ci-test | module-ci-common.yml | `@v3.800.24` | LIVE-pinned |
| `ui-autotests.yml` | vc-dev-training | module-ci.yml | `@v3.800.22` | LIVE-pinned |
| `ui-autotests.yml` | vc-module-environments-compare | module-ci.yml | `@v3.800.17` | LIVE-pinned |
| `ui-autotests.yml` | vc-module-marketing-campaigns | module-ci.yml | `@v3.800.25` | LIVE-pinned |
| `ui-autotests.yml` | vc-module-opentelemetry | module-ci.yml | `@v3.800.25` | LIVE-pinned |
| `ui-autotests.yml` | vc-module-one-shell-app | module-ci.yml | `@v3.800.24` | LIVE-pinned |
| `ui-autotests.yml` | vc-module-test-module | module-ci.yml | `@v3.800.26` | LIVE-pinned |
| `ui-autotests.yml` | vc-module-ui-migration | module-ci.yml | `@v3.800.16` | LIVE-pinned |
| `ui-autotests.yml` | vc-testing-module | graphql-tests-docker.yml | `@v3.800.23` | LIVE-pinned |
