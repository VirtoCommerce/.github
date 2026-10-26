#!/usr/bin/env bash
# Rebuilds the PR review card from the current PR state and sends it to the Teams flow.
# The flow posts the card or replaces the one it already posted for this PR (see README).
set -euo pipefail
here="$(dirname "$0")"

if [ -z "${WEBHOOK_URL:-}" ]; then
  echo "::notice::webhook-url is empty (Dependabot or fork PR has no secrets), skipping"
  exit 0
fi
MODE="${MODE:-all}"
case "$MODE" in card|ping|all) ;; *) echo "::error::mode must be card, ping or all, got '$MODE'"; exit 1 ;; esac
users="${TEAMS_USERS:-}"
[ -n "$users" ] || users='{}'
# An empty value would pass every "has a Teams user" check and send a mention with an empty id
users=$(jq -c 'with_entries(select(.value | type == "string" and length > 0))' <<<"$users")

repo="$GITHUB_REPOSITORY"
number=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
key="${repo#*/}#$number"
author=$(jq -r '.pull_request.user.login' "$GITHUB_EVENT_PATH")
if [ "$(jq -r '.pull_request.user.type' "$GITHUB_EVENT_PATH")" = Bot ] && [[ ",${ALLOWED_BOTS// /}," != *",$author,"* ]]; then
  echo "::notice::$key is opened by $author, a bot not listed in allowed-bots, skipping"
  exit 0
fi

# Only the fields the card needs: PR and review bodies can push a --argjson value past the 128KB argument limit
pr=$(gh api "repos/$repo/pulls/$number" --jq 'del(.body, .base, .head.repo, ._links)')
reviews=$(gh api --paginate "repos/$repo/pulls/$number/reviews" --jq 'map(select(.user) | {user: {login: .user.login, type: .user.type}, state, submitted_at})' | jq -s 'add // []')
rows=$(jq -n --argjson pr "$pr" --argjson reviews "$reviews" -f "$here/reviewers.jq")

status=$(jq -r 'if .merged then "Merged" elif .state == "closed" then "Closed" elif .draft then "Draft" else "Open" end' <<<"$pr")
create=false
[ "$status" = Open ] && create=true

# Logins with a UPN or Entra Object ID become Teams mentions, the rest stay plain text.
# The card mentions every reviewer in any state. Teams notifies them only when the card is first posted, an update notifies nobody.
mention_defs='
  def mention($l): if $users[$l] then "<at>\($l)</at>" else "@\($l)" end;
  def entities($logins): [$logins[] | select($users[.]) | {type: "mention", text: "<at>\(.)</at>", mentioned: {id: $users[.], name: .}}];
'

card=$(jq -n --argjson pr "$pr" --argjson rows "$rows" --argjson users "$users" --arg status "$status" \
  --arg projects "${JIRA_PROJECTS:-}" "$mention_defs"'
  # Only listed projects, so UTF-8 or CVE-2024 are not taken for a ticket; anywhere in the title, so [VCST-3] and Revert "VCST-3" match
  ($projects | gsub("\\s"; "") | split(",") | map(select(. != ""))) as $p
  | (if $p == [] then null else $pr.title | [match("\\b(\($p | join("|")))-[0-9]+\\b").string] | first end) as $jira
  # A merged or closed PR keeps a short card: title, status and the buttons
  | ($status == "Merged" or $status == "Closed") as $done
  | {approved: "✅ approved", comments: "💬 comments", rereview: "🔁 re-review", waiting: "⏳ waiting", dismissed: "⚪ dismissed"} as $label
  | {
      type: "AdaptiveCard", version: "1.4",
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      body: ([
        {type: "TextBlock", text: $pr.title, weight: "Bolder", size: "Medium", wrap: true}]
        + (if $done then [] else [{type: "ColumnSet", columns: [
          {type: "Column", width: "auto", items: [{type: "Image", url: $pr.user.avatar_url, size: "Small", style: "Person"}]},
          {type: "Column", width: "stretch", verticalContentAlignment: "Center",
           items: [{type: "TextBlock", text: "\($pr.user.login) · \($pr.head.ref)", isSubtle: true, wrap: true}]}
        ]}] end)
        + [
        # Two columns instead of a FactSet: a FactSet value cannot be coloured, and Changes shows +added green, −deleted red
        ([["Status", [{type: "TextRun", text: $status}]]]
         + (if $done then [] else [["Changes", [{type: "TextRun", text: "+\($pr.additions)", color: "Good"}, {type: "TextRun", text: " / "},
                       {type: "TextRun", text: "−\($pr.deletions)", color: "Attention"},
                       {type: "TextRun", text: " · \($pr.changed_files) files"}]]]
           + (if $jira then [["Jira", [{type: "TextRun", text: $jira}]]] else [] end)
           + (if ($pr.labels | length) > 0 then [["Labels", [{type: "TextRun", text: ($pr.labels | map(.name) | join(", "))}]]] else [] end) end)
         | {type: "ColumnSet", columns: [
             {type: "Column", width: "auto", items: map({type: "TextBlock", text: .[0], weight: "Bolder", spacing: "Small"})},
             {type: "Column", width: "stretch", items: map({type: "RichTextBlock", inlines: .[1], spacing: "Small"})}]})]
        + (if $done then []
           else [{type: "TextBlock", text: "Reviewers", weight: "Bolder", spacing: "Medium"}]
             + (if $rows == [] then [{type: "TextBlock", text: "—", spacing: "Small"}]
                else [$rows[] | {type: "TextBlock", text: "\(mention(.login))   \($label[.state])", spacing: "Small", wrap: true}] end) end)),
      actions: ([{type: "Action.OpenUrl", title: "Open PR", url: $pr.html_url}]
        + (if $jira then [{type: "Action.OpenUrl", title: "Open Jira", url: "https://virtocommerce.atlassian.net/browse/\($jira)"}] else [] end)),
      msteams: {width: "Full", entities: (if $done then [] else entities([$rows[].login]) end)}
    }')

# Extra curl options: the card is sent with --retry (a repeat only updates it), a ping without (a repeat posts it twice)
post() { curl -fsS --max-time 30 "$@" -X POST -H 'Content-Type: application/json' --data-binary @- "$WEBHOOK_URL" >/dev/null; }

if [ "$MODE" != ping ]; then
  jq -n --arg key "$key" --argjson create "$create" --argjson card "$card" \
    '{key: $key, kind: "card", create: $create, card: $card}' | post --retry 3
  echo "Card for $key sent (status $status, create $create)"
fi

# Separate messages, posted by the flow as a reply under the PR card. Teams does not notify about mentions added by
# a card update, so whoever has to act gets one:
# - re-review: a reviewer who has already reviewed this PR was requested again, mention the reviewer;
# - comments: a reviewer requested changes or left a comment, mention the PR author (the author's own replies are skipped).
# Bots neither get nor trigger messages, and a message is skipped when its addressee has no Teams mention.
event_action=$(jq -r '.action // empty' "$GITHUB_EVENT_PATH")
login=""
if [ "$MODE" != card ] && [ "$status" = Open ]; then
  if [ "$GITHUB_EVENT_NAME" = pull_request ] && [ "$event_action" = review_requested ]; then
    requested=$(jq -r '.requested_reviewer.login // empty' "$GITHUB_EVENT_PATH")
    if [ -n "$requested" ] && [ "$(jq -r --arg l "$requested" 'map(select(.login == $l)) | first.state // empty' <<<"$rows")" = rereview ]; then
      login="$requested"; text="🔁 MENTION, your re-review is requested"; button="Open PR"; url=$(jq -r .html_url <<<"$pr")
    fi
  elif [ "$GITHUB_EVENT_NAME" = pull_request_review ] && [ "$event_action" = submitted ]; then
    reviewer=$(jq -r '.review.user.login' "$GITHUB_EVENT_PATH")
    case "$(jq -r '.review.state' "$GITHUB_EVENT_PATH")" in
      changes_requested|commented)
        if [ "$reviewer" != "$(jq -r .user.login <<<"$pr")" ] && [ "$(jq -r '.review.user.type' "$GITHUB_EVENT_PATH")" != Bot ]; then
          login=$(jq -r .user.login <<<"$pr"); text="💬 MENTION, $reviewer left comments"; button="Open review"
          url=$(jq -r '.review.html_url' "$GITHUB_EVENT_PATH")
        fi ;;
    esac
  fi
fi
if [ -n "$login" ] && ! jq -e --arg l "$login" '.[$l]' <<<"$users" >/dev/null; then
  echo "No Teams user for $login, message skipped"
  login=""
fi
# Single comments arrive as one review each, so a burst of them would send a message per comment. Wait 2 minutes, then send
# only from the run of this reviewer's latest comment review, so the burst gives one message. The ping job's concurrency group
# (see README) cancels the earlier runs anyway; this check covers workflows without it. A failed lookup sends the message.
if [ -n "$login" ] && [ "$GITHUB_EVENT_NAME" = pull_request_review ]; then
  sleep 120
  latest=$(gh api --paginate "repos/$repo/pulls/$number/reviews" --jq 'map(select(.user) | {login: .user.login, state, id})' |
    jq -s --arg r "$reviewer" 'add // [] | map(select(.login == $r and (.state == "COMMENTED" or .state == "CHANGES_REQUESTED")) | .id) | max') || latest=""
  if [ -n "$latest" ] && [ "$latest" != "$(jq -r '.review.id' "$GITHUB_EVENT_PATH")" ]; then
    echo "$reviewer submitted a later review, its run sends the message"
    login=""
  fi
fi
if [ -n "$login" ]; then
  jq -n --arg key "$key" --arg login "$login" --arg text "$text" --arg button "$button" --arg url "$url" \
    --argjson pr "$pr" --argjson users "$users" "$mention_defs"'
    {key: $key, kind: "ping", create: true, card: {
      type: "AdaptiveCard", version: "1.4",
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      body: [
        {type: "TextBlock", text: ($text | sub("MENTION"; mention($login))), wrap: true},
        {type: "TextBlock", text: $pr.title, isSubtle: true, wrap: true, spacing: "Small"}],
      actions: [{type: "Action.OpenUrl", title: $button, url: $url}],
      msteams: {entities: entities([$login])}}}' | post
  echo "Message for $login sent: $text"
fi
