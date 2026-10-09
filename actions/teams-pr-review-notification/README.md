# teams-pr-review-notification

Keep one Microsoft Teams card per pull request in sync with its review state.

The action rebuilds an Adaptive Card from the current PR state on every event and sends it to a Teams Workflows flow. The flow posts the card the first time and replaces it afterwards, so the channel holds one card per PR:

- title, author, branch, status (Open / Draft / Merged / Closed), `+added` / `−deleted` lines and files, Jira ticket and labels;
- every reviewer with their state: ⏳ waiting, 🔁 re-review, ✅ approved, 💬 comments.

Who gets a Teams notification:

- everyone requested when the card is created (the PR is opened as Open, or a draft is marked Ready for review): the new card mentions them;
- a reviewer whose review is requested again (Re-request review): a 🔁 message that mentions the reviewer;
- the PR author, when a reviewer requests changes or leaves a comment: a 💬 message that mentions the author (the reviewer stays plain text, the author's own replies are skipped).

The messages are separate because Teams does not notify about mentions added by a card update; the flow posts them as replies under the PR card. Every other change (approvals, new commits, title, labels, reviewers added later, merge, close) only updates the card.

A draft PR gets no card until it is marked Ready for review.

## inputs:

### webhook-url:

    description: 'URL of the Teams Workflows flow that posts or updates the card. Empty skips the run (Dependabot and fork PRs)'
    required: false
    default: ''

### teams-users:

    description: 'JSON {"github-login": "Entra Object ID"} for Teams mentions, logins not listed stay plain text'
    required: false
    default: '{}'

### mode:

    description: 'card: only post or update the PR card; ping: only the re-review / review comments message; all: both. Split them into two jobs so a queued card run never cancels a message'
    required: false
    default: 'all'

### github-token:

    description: 'Token with pull-requests: read'
    required: false
    default: ${{ github.token }}

## Example of usage

Two jobs: `card` runs one at a time per PR, so a slower run never overwrites the card with an older state and two runs never post two cards. GitHub cancels the queued runs in between, which is fine because every run rebuilds the whole card. `ping` runs outside that queue, so no message is cancelled.

```yaml
name: Notify Teams about PR reviews

on:
  pull_request:
    types: [opened, reopened, ready_for_review, converted_to_draft,
            review_requested, review_request_removed, closed,
            synchronize, edited, labeled, unlabeled]
  pull_request_review:
    types: [submitted, dismissed]

permissions:
  contents: read

jobs:
  card:
    runs-on: ubuntu-latest
    concurrency:
      group: teams-pr-${{ github.event.pull_request.number }}
      cancel-in-progress: false
    permissions:
      pull-requests: read
    steps:
      - uses: VirtoCommerce/.github/actions/teams-pr-review-notification@v3.1000.4
        with:
          mode: card
          webhook-url: ${{ secrets.TEAMS_PR_WEBHOOK }}
          teams-users: ${{ secrets.TEAMS_USERS }}

  ping:
    if: github.event.action == 'review_requested' || github.event_name == 'pull_request_review'
    runs-on: ubuntu-latest
    permissions:
      pull-requests: read
    steps:
      - uses: VirtoCommerce/.github/actions/teams-pr-review-notification@v3.1000.4
        with:
          mode: ping
          webhook-url: ${{ secrets.TEAMS_PR_WEBHOOK }}
          teams-users: ${{ secrets.TEAMS_USERS }}
```

Secrets of the repository:

- `TEAMS_PR_WEBHOOK`: the HTTP URL of the flow trigger;
- `TEAMS_USERS`: `{"github-login": "<Entra Object ID>", ...}`. A Teams mention needs the user's Object ID (Entra ID → Users → the user → Object ID, or Graph `GET /users/<email>?$select=id`). Keep it in a secret: repositories are public and Actions logs are visible to everyone.

Several repositories can share one channel: they use the same flow URL, and the card key (`<repository>#<PR number>`) keeps their cards apart.

## Teams side

One flow and one SharePoint list per channel. The action sends one JSON shape:

```json
{ "key": "vc-frontend#2546", "kind": "card", "create": true, "card": { "type": "AdaptiveCard", "version": "1.4", "body": [] } }
```

`kind` is `card` (the PR card) or `ping` (a separate message); `create` is `true` only when the PR is open and not a draft, so draft events never create a card.

1. In the channel, add a list (+ → Lists → Blank list) with the column `MessageId` (single line of text). `Title` holds the key.
2. In Power Automate, create a flow with the trigger **When a Teams webhook request is received** (not V2: V2 accepts only requests with an Entra token), **Who can trigger the flow** = **Anyone**. The signed URL is the secret.
3. **Parse JSON** on the trigger body with the schema of the shape above.
4. **Condition** `kind` = `ping`:
   - yes: **Get items** from the list, filter `Title eq '<key>'`, top 1, then:
     - an item is found: **Reply with an adaptive card in a channel** (Flow bot, the channel) with its `MessageId`, Adaptive Card = `string(body('Parse_JSON')?['card'])`;
     - no item: **Post card in a chat or channel** with the card;
   - no: **Get items** from the list, filter `Title eq '<key>'`, top 1, then:
     - an item is found: **Update an adaptive card in a chat or channel** with its `MessageId` and the card;
     - no item and `create` = `true`: **Post card in a chat or channel**, then **Create item** with `Title` = key and `MessageId` = the posted message id (`body.id`).

Run the flow under a service account, so it does not stop when its author leaves.

## Tests

```bash
bash scripts/reviewers.test.sh
```
