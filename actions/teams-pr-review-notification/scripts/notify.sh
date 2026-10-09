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
users="${TEAMS_USERS:-}"
[ -n "$users" ] || users='{}'

repo="$GITHUB_REPOSITORY"
number=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
key="${repo#*/}#$number"

pr=$(gh api "repos/$repo/pulls/$number")
reviews=$(gh api --paginate "repos/$repo/pulls/$number/reviews" | jq -s 'add // []')
rows=$(jq -n --argjson pr "$pr" --argjson reviews "$reviews" -f "$here/reviewers.jq")

status=$(jq -r 'if .merged then "Merged" elif .state == "closed" then "Closed" elif .draft then "Draft" else "Open" end' <<<"$pr")
create=false
[ "$status" = Open ] && create=true

# Logins with an Entra Object ID become Teams mentions, the rest stay plain text
mention_defs='
  def mention($l): if $users[$l] then "<at>\($l)</at>" else "@\($l)" end;
  def entities($logins): [$logins[] | select($users[.]) | {type: "mention", text: "<at>\(.)</at>", mentioned: {id: $users[.], name: .}}];
'

card=$(jq -n --argjson pr "$pr" --argjson rows "$rows" --argjson users "$users" --arg status "$status" "$mention_defs"'
  ($pr.title | [scan("[A-Z][A-Z0-9]+-[0-9]+")] | first) as $jira
  | {approved: "✅ approved", comments: "💬 comments", rereview: "🔁 re-review", waiting: "⏳ waiting"} as $label
  | {
      type: "AdaptiveCard", version: "1.4",
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      body: ([
        {type: "TextBlock", text: $pr.title, weight: "Bolder", size: "Medium", wrap: true},
        {type: "ColumnSet", columns: [
          {type: "Column", width: "auto", items: [{type: "Image", url: $pr.user.avatar_url, size: "Small", style: "Person"}]},
          {type: "Column", width: "stretch", verticalContentAlignment: "Center",
           items: [{type: "TextBlock", text: "\($pr.user.login) · \($pr.head.ref)", isSubtle: true, wrap: true}]}
        ]},
        # Two columns instead of a FactSet: a FactSet value cannot be coloured, and Changes shows +added green, −deleted red
        ([["Status", [{type: "TextRun", text: $status}]],
          ["Changes", [{type: "TextRun", text: "+\($pr.additions)", color: "Good"}, {type: "TextRun", text: " / "},
                       {type: "TextRun", text: "−\($pr.deletions)", color: "Attention"},
                       {type: "TextRun", text: " · \($pr.changed_files) files"}]]]
         + (if $jira then [["Jira", [{type: "TextRun", text: $jira}]]] else [] end)
         + (if ($pr.labels | length) > 0 then [["Labels", [{type: "TextRun", text: ($pr.labels | map(.name) | join(", "))}]]] else [] end)
         | {type: "ColumnSet", columns: [
             {type: "Column", width: "auto", items: map({type: "TextBlock", text: .[0], weight: "Bolder", spacing: "Small"})},
             {type: "Column", width: "stretch", items: map({type: "RichTextBlock", inlines: .[1], spacing: "Small"})}]}),
        {type: "TextBlock", text: "Reviewers", weight: "Bolder", spacing: "Medium"}]
        + (if $rows == [] then [{type: "TextBlock", text: "—", spacing: "Small"}]
           else [$rows[] | {type: "TextBlock", text: "\(mention(.login))   \($label[.state])", spacing: "Small", wrap: true}] end)),
      actions: ([{type: "Action.OpenUrl", title: "Open PR", url: $pr.html_url}]
        + (if $jira then [{type: "Action.OpenUrl", title: "Open Jira", url: "https://virtocommerce.atlassian.net/browse/\($jira)"}] else [] end)),
      msteams: {width: "Full", entities: entities([$rows[].login])}
    }')

post() { curl -fsS -X POST -H 'Content-Type: application/json' --data-binary @- "$WEBHOOK_URL" >/dev/null; }

if [ "$MODE" != ping ]; then
  jq -n --arg key "$key" --argjson create "$create" --argjson card "$card" \
    '{key: $key, kind: "card", create: $create, card: $card}' | post
  echo "Card for $key sent (status $status, create $create)"
fi

# Separate messages, posted by the flow as a reply under the PR card. Teams does not notify about mentions added by
# a card update, so whoever has to act gets one:
# - re-review: a reviewer who has already reviewed this PR was requested again, mention the reviewer;
# - comments: a reviewer requested changes or left a comment, mention the PR author (the author's own replies are skipped).
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
        if [ "$reviewer" != "$(jq -r .user.login <<<"$pr")" ]; then
          login=$(jq -r .user.login <<<"$pr"); text="💬 MENTION, $reviewer left comments"; button="Open review"
          url=$(jq -r '.review.html_url' "$GITHUB_EVENT_PATH")
        fi ;;
    esac
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
