# Input: --argjson pr (GET pulls/N), --argjson reviews (GET pulls/N/reviews, all pages)
# Output: [{login, state}] where state is waiting | rereview | approved | comments
$pr.user.login as $author
| [$pr.requested_reviewers[].login] as $requested
# A reviewer's verdict is their last approve / request changes / dismiss; a plain comment counts only when there is no verdict,
# so a reply after an approval does not turn ✅ into 💬
| ($reviews
   | map(select(.user.login != $author and .state != "PENDING"))
   | group_by(.user.login)
   | map(sort_by(.submitted_at)
         | {key: .[0].user.login,
            value: ((map(select(.state != "COMMENTED")) | last.state) // last.state)})
   | from_entries) as $last
| ($requested + ($last | keys)) | unique | map(select(. != $author))
| map(. as $l | {login: $l, state: (
    if ($requested | any(. == $l)) then (if $last[$l] then "rereview" else "waiting" end)
    elif $last[$l] == "APPROVED" then "approved"
    elif $last[$l] == "CHANGES_REQUESTED" or $last[$l] == "COMMENTED" then "comments"
    else "waiting" end)})
