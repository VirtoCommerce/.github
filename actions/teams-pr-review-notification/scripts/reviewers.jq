# Input: --argjson pr (GET pulls/N), --argjson reviews (GET pulls/N/reviews, all pages)
# Output: [{login, state}] where state is waiting | rereview | approved | comments | dismissed
$pr.user.login as $author
| [$pr.requested_reviewers[] | select(.type != "Bot") | .login] as $requested
# A reviewer's verdict is their last approve / request changes; a plain comment counts only when there is no verdict,
# so a reply after an approval does not turn ✅ into 💬. Dismissing changes the state of the review itself to DISMISSED,
# which is no verdict: a comment after it counts.
| ($reviews
   | map(select(.user.login != $author and .user.type != "Bot" and .state != "PENDING"))
   | group_by(.user.login)
   | map(sort_by(.submitted_at)
         | {key: .[0].user.login,
            value: ((map(select(.state != "COMMENTED")) | last.state) as $v
                   | if $v == null or $v == "DISMISSED" then last.state else $v end)})
   | from_entries) as $last
| ($requested + ($last | keys)) | unique | map(select(. != $author))
| map(. as $l | {login: $l, state: (
    if ($requested | any(. == $l)) then (if $last[$l] then "rereview" else "waiting" end)
    elif $last[$l] == "APPROVED" then "approved"
    elif $last[$l] == "CHANGES_REQUESTED" or $last[$l] == "COMMENTED" then "comments"
    # A dismissed review (e.g. a stale approval after a push) is not a request: GitHub does not ask the reviewer again
    elif $last[$l] == "DISMISSED" then "dismissed"
    else "waiting" end)})
