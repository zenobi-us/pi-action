#!/usr/bin/env bash
set -euo pipefail

REACTION_STATE="/tmp/reaction-state.json"

ISSUE_NUMBER=$(jq -r '.issue.number' "$GITHUB_EVENT_PATH")
# =============================================================================
# Subcommands
# =============================================================================

# Writes reaction state to REACTION_STATE. No network calls — pure local I/O.
#
# Usage: cmd_initialise_state <reaction_target> <repo> <issue_number> [comment_id] [reaction_id]
#   reaction_target  - "issue" or "comment"
#   repo             - owner/repo
#   issue_number     - issue number
#   comment_id       - the comment that triggered the event (optional)
#   reaction_id      - from a prior notify step (optional)
cmd_initialise_state() {
	local reaction_target=$1
	local repo=$2
	local issue_number=$3
	local comment_id="${4:-}"
	local reaction_id="${5:-}"

	jq -n \
		--arg reactionId "$reaction_id" \
		--arg reactionTarget "$reaction_target" \
		--arg commentId "$comment_id" \
		--arg issueNumber "$issue_number" \
		--arg repo "$repo" \
		'{reactionId: $reactionId, reactionTarget: $reactionTarget, commentId: $commentId, issueNumber: $issueNumber, repo: $repo}' \
		>"$REACTION_STATE"
}
# Usage: cmd_run <prompt>
cmd_run() {
	local prompt=$1
	# --- Resolve session ---
	mkdir -p state/issues state/sessions

	local mode="new"
	local session_path=""
	local mapping_file="state/issues/${ISSUE_NUMBER}.json"

	if [[ -f "$mapping_file" ]]; then
		session_path=$(jq -r '.sessionPath' "$mapping_file")
		if [[ -n "$session_path" && -f "$session_path" ]]; then
			mode="resume"
			echo "Found existing session: ${session_path}"
		else
			session_path=""
			echo "Mapped session file missing, starting fresh"
		fi
	else
		echo "No session mapping found, starting fresh"
	fi

	# --- Configure git ---
	git config user.name "gitclaw[bot]"
	git config user.email "gitclaw[bot]@users.noreply.github.com"

	# --- Run agent ---
	local -a pi_args=(bunx pi --mode json --session-dir ./state/sessions -p "$prompt")
	if [[ "$mode" == "resume" && -n "$session_path" ]]; then
		pi_args+=(--session "$session_path")
	fi

	"${pi_args[@]}" | tee /tmp/agent-raw.jsonl

	# --- Extract agent response text ---
	local agent_text
	agent_text=$(tac /tmp/agent-raw.jsonl |
		jq -r -s '[ .[] | select(.type == "message_end") ] | .[0].message.content[] | select(.type == "text") | .text')

	# --- Find latest session file ---
	local latest_session
	latest_session=$(find state/sessions -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

	# --- Save session mapping ---
	if [[ -n "$latest_session" ]]; then
		jq -n \
			--argjson issueNumber "$ISSUE_NUMBER" \
			--arg sessionPath "$latest_session" \
			--arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			'{issueNumber: $issueNumber, sessionPath: $sessionPath, updatedAt: $updatedAt}' \
			>"$mapping_file"
		echo "Saved mapping: issue #${ISSUE_NUMBER} -> ${latest_session}"
	else
		echo "Warning: no session file found to map"
	fi

	# --- Commit and push ---
	git add -A
	if ! git diff --cached --quiet; then
		git commit -m "gitclaw: work on issue #${ISSUE_NUMBER}"
	fi

	for i in 1 2 3; do
		if git push origin main; then
			break
		fi
		echo "Push failed, rebasing and retrying (${i}/3)..."
		git pull --rebase origin main
	done

	# --- Output agent response ---
	echo "$agent_text"
}

# =============================================================================
# Dispatch
# =============================================================================

case "${1:-}" in
initialise-state)
	shift
	cmd_initialise_state "$@"
	;;
run)
	shift
	cmd_run "$@"
	;;
*)
	echo "Usage: $0 {initialise-state|run}" >&2
	exit 1
	;;
esac
