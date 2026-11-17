# Deprecated

Retired reusable workflows and actions, kept for history/reference only.

- **Not maintained** — no automation touches this folder. [.github/dependabot.yml](../.github/dependabot.yml) lists its directories explicitly and `deprecated/` is not among them, so no dependency-update PRs are raised for anything here. zizmor (`workflow-security.yml`, `auto-update-templates.yml`) and pin-check ([.pinact.yaml](../.pinact.yaml)) don't collect these files either, as long as the folder holds no `action.yml`.
- **Not invocable** — everything here had no callers anywhere in the org when retired.
  - `workflows/`: `workflow_call` reusable workflows. GitHub only resolves reusable workflows under `.github/workflows/`, so they can no longer be referenced via `uses:`.
  - `actions/`: an action's `action.yml` is renamed to `action.yml.retired`. GitHub resolves an action at any path, so without the rename `uses: VirtoCommerce/.github/deprecated/actions/<name>@<ref>` would still work, and the tools above would collect it.

To revive a workflow, move it back to `.github/workflows/`. To revive an action, move it back to `actions/` and rename `action.yml.retired` to `action.yml`.
