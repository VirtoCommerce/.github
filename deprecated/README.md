# Deprecated

Retired reusable workflows, kept for history/reference only.

- **Not maintained** — no automation touches this folder. [.github/dependabot.yml](../.github/dependabot.yml) lists its directories explicitly and `deprecated/` is not among them, so no dependency-update PRs are raised for anything here. zizmor (`workflow-security.yml`, `auto-update-templates.yml`) and pin-check ([.pinact.yaml](../.pinact.yaml)) don't collect these files either, as long as the folder holds no `action.yml`.
- **Not invocable** — these are `workflow_call` reusable workflows that had no callers anywhere in the org when retired. GitHub only resolves reusable workflows under `.github/workflows/`, so they can no longer be referenced via `uses:`.

To revive one, move it back to `.github/workflows/`.
