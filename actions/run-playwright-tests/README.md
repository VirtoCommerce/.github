# run-playwright-tests

Runs Node/TypeScript Playwright Auto Tests.

The Node/Playwright counterpart of [run-pytest-tests](../run-pytest-tests/README.md). It checks out the test repository, writes its `.env`, installs dependencies with `npm ci` and the Playwright browsers, seeds the dataset with the `seed` Playwright project, reindexes the platform, then runs each suite in `testSuites` as its own `playwright test --project=<suite>`.

Built for the TypeScript [vc-testing-module](https://github.com/VirtoCommerce/vc-testing-module): Playwright projects `seed`, `restapi`, `graphql`, `e2e-frontend` and `e2e-backend`, configuration read from `.env`, `allure-playwright` results and the `allure` (Allure 3) package for the HTML report.

Tests tagged `@destructive` (platform restart, index drop, ...) are excluded by the test repo's config unless `RUN_DESTRUCTIVE_TESTS=true` is set in `testSecretEnvFile`.

Artifact `playwright-test-results-<run>-<attempt><artifactSuffix>` (zip):

* `report/allure-report/`: the Allure report
* `report/<project>-junit.xml` and `report/<project>-results.json`: per-project JUnit and Playwright JSON reports
* `test-results/`: traces and screenshots of failed tests

The report must be served over HTTP: unzip the artifact and run `npx allure open report/allure-report`.

## inputs:

### adminPassword:

    description: 'Admin Password'
    required: true

### adminUsername:

    description: 'Admin Username'
    required: true

### backUrl:

    description: 'Back URL'
    required: true

### baseUrl:

    description: 'Base URL'
    required: true

### browser:

    description: 'Space-separated Playwright browser(s) to install. Which browser a test runs in is set by the test repo''s playwright.config.ts.'
    required: false
    default: 'chromium'

### grep:

    description: 'Optional Playwright --grep pattern (e.g. a tag like ''@smoke''). Applied to every suite. Leave empty to run everything. @destructive tests stay excluded unless RUN_DESTRUCTIVE_TESTS=true is in testSecretEnvFile.'
    required: false
    default: ''

### nodeVersion:

    description: 'Node.js version'
    required: false
    default: '22'

### skipDocCountVerification:

    description: 'Comma-separated document types whose post-reindex count check should be skipped (reindex still runs). Use when the seed dataset has 0 records for a type. Example: ''PickupLocation'' or ''PickupLocation,ContentFile''.'
    required: false
    default: ''

### testSecretEnvFile:

    description: 'Test secret environment file content'
    required: true

### testSuites:

    description: 'Comma-separated list of suites to run, in order. Any subset of: graphql, restapi, e2e (= e2e-frontend + e2e-backend), e2e-frontend, e2e-backend'
    required: false
    default: 'graphql,restapi,e2e'

### vctestingPath:

    description: 'UI tests path'
    required: true

### vctestingRepo:

    description: 'UI tests repository'
    required: true

### vctestingRepoBranch:

    description: 'UI tests repository branch'
    required: true

### workers:

    description: 'Optional Playwright --workers value (number or percentage, e.g. ''4'' or ''50%''). Leave empty for the test repo''s default.'
    required: false
    default: ''

### artifactSuffix:

    description: 'Suffix appended to the uploaded artifact name (e.g., a matrix dimension)'
    required: false
    default: ''

## Example of usage

```yaml
- name: Run Playwright Auto Tests
  uses: VirtoCommerce/.github/actions/run-playwright-tests@v3.1000.1
  with:
    adminPassword: ${{ secrets.ADMIN_PASSWORD }}
    adminUsername: admin
    backUrl: http://localhost:8090
    baseUrl: http://localhost
    testSecretEnvFile: ${{ secrets.TEST_SECRET_ENV_FILE }}
    vctestingPath: vc-testing-module
    vctestingRepo: VirtoCommerce/vc-testing-module
    vctestingRepoBranch: dev
```
