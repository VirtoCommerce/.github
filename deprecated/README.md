# Deprecated

Retired reusable workflows, kept for history/reference only.

- **Not maintained** — excluded from Dependabot via `exclude-paths: ["deprecated/**"]` in [.github/dependabot.yml](../.github/dependabot.yml), so no dependency-update PRs are raised for anything here.
- **Not invocable** — these are `workflow_call` reusable workflows that had no callers anywhere in the org when retired. GitHub only resolves reusable workflows under `.github/workflows/`, so they can no longer be referenced via `uses:`.

To revive one, move it back to `.github/workflows/`.
