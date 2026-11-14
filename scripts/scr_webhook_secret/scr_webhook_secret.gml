/// ADAM - the Discord webhook that 'Submit your game' and crash reports post to (scr_report).
/// Committed EMPTY: the repo is public. Paste the real URL here locally; git is told
/// to leave this file alone with
///   git update-index --skip-worktree scripts/scr_webhook_secret/scr_webhook_secret.gml
/// Empty = nothing is ever sent: the form says submissions are not set up in this copy
/// and a crash is never asked about. An adam_webhook.txt beside the exe overrides it.

#macro ADAM_WEBHOOK_URL ""
