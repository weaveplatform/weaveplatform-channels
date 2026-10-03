#!/usr/bin/env bash
# Applies one promotion to the rolling channel, and lands it on the single
# pending promotion branch. Called by .github/workflows/promote.yml; the
# subcommands below `land` are exposed so the merge rules can be exercised
# locally against a scratch copy of channels/stable.json.
#
#   promote.sh module-entry <sidecar.json> <oras-ref>   print a module's channel entry
#   promote.sh seed <stable.json>                       create an empty channel if missing
#   promote.sh apply-module <stable.json> <entry.json>  add or replace by id
#   promote.sh apply-image <stable.json> <image.json>   add or replace by repository+tag
#   promote.sh land <module|image> <entry.json>         apply on the pending branch and push
#
# land reads SUBJECT and SOURCE (the PR line), and optionally WEAVEMANIFEST and
# SIGNING_KEY_FILE (sign after applying), PROMOTE_ATTEMPTS, PROMOTE_BRANCH,
# PROMOTE_BASE.
set -euo pipefail

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The seed validates against weaveplatform-agent-core's schema: core artifacts
# may be empty.
seed() {
	local f=$1
	[ -f "$f" ] && return 0
	mkdir -p "$(dirname "$f")"
	jq -n --arg now "$(now)" '{schema:1, channel:"stable", generated_at:$now, sequence:0,
	  protocol:{min:1,max:1}, core:{version:"", artifacts:[]}, modules:[]}' > "$f"
}

# The sidecar is the module's own module.manifest.json with the per-artifact
# digest and size stamped in by the publish pipeline; nothing is typed by hand.
#
# `url` is recorded as the OCI reference the artifact was pushed under. Core
# fetches artifacts over HTTP today, so serving them is a decision still open;
# until it is made, a merged promotion is a signed statement of digests, not
# yet a download.
module_entry() {
	jq --arg ref "$2" '{
	    id, version, protocol, privilege, session,
	    capabilities: (.capabilities // []),
	    subscribes: (.subscribes // []),
	    signing: .signing,
	    artifacts: [ (.artifacts // [])[] | {os, arch, url: ($ref + "#" + .os + "-" + .arch), digest, size} ]
	  } | with_entries(select(.value != null))' "$1"
}

# Both rules bump sequence, the anti-rollback counter core persists, so it only
# ever goes up. Images follow pkg/channel.Promote in weaveplatform-oci: replaced
# by repository and tag, sorted by repository then tag.
# shellcheck disable=SC2016 # the filters are jq programs; $e is jq's
apply() {
	local kind=$1 f=$2 entry=$3 filter
	case "$kind" in
	module) filter='.modules = ([(.modules // [])[] | select(.id != $e.id)] + [$e] | sort_by(.id))' ;;
	image) filter='.images = ([(.images // [])[] | select(.repository != $e.repository or .tag != $e.tag)] + [$e]
	                          | sort_by(.repository, .tag))' ;;
	*) echo "unknown kind '$kind'" >&2; return 2 ;;
	esac
	seed "$f"
	# The channel's protocol window is what every device following it speaks.
	# A module outside it would be fetched, verified and then refused by the
	# supervisor as an unsupported protocol on every device, so it is refused
	# here, before it is offered — the registry-side check Terraform makes on a
	# provider's declared protocol_versions.
	if [ "$kind" = module ] && ! jq -e --slurpfile e "$entry" \
		'($e[0].protocol // 0) as $p | $p >= .protocol.min and $p <= .protocol.max' "$f" > /dev/null; then
		echo "::error::$(jq -r '.id + " " + .version + " speaks protocol " + ((.protocol // 0) | tostring)' "$entry"), outside the channel's window $(jq -c .protocol "$f")" >&2
		return 4
	fi
	jq --slurpfile e "$entry" --arg now "$(now)" "\$e[0] as \$e | $filter | .sequence += 1 | .generated_at = \$now" \
		"$f" > "$f.new"
	# Re-applying an entry the channel already carries must not mint a new
	# sequence: that would be a new signed document saying nothing new, and
	# a second commit on the pending branch for a promotion already in it.
	if jq -e --slurpfile a "$f" 'del(.sequence, .generated_at) == ($a[0] | del(.sequence, .generated_at))' \
		"$f.new" > /dev/null; then
		rm -f "$f.new"
		return 3
	fi
	mv "$f.new" "$f"
}

# ---- land ---------------------------------------------------------------

STABLE=channels/stable.json

# Which branch to build on. An open PR's branch is the pending promotion. A
# branch with no open PR is either history (its PR was merged or closed) or
# was pushed seconds ago by a concurrent run that has not yet opened the PR;
# telling them apart by "is there an open PR" alone would let that second
# case be force-pushed over and its promotion lost. So a branch counts as
# history only when its tip is the head of a PR that is no longer open.
choose_base() {
	local tip=$1
	[ -n "$tip" ] || { echo "origin/$BASE"; return; }
	if [ -n "$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')" ]; then
		echo "origin/$BRANCH"; return
	fi
	if [ -n "$(gh pr list --head "$BRANCH" --state all --limit 100 --json state,headRefOid \
		--jq "[.[] | select(.state != \"OPEN\" and .headRefOid == \"$tip\")][0].state // empty")" ]; then
		echo "origin/$BASE"; return
	fi
	echo "origin/$BRANCH"
}

sign() {
	if [ -n "${SIGNING_KEY_FILE:-}" ]; then
		"$WEAVEMANIFEST" sign "$SIGNING_KEY_FILE" "$STABLE"
		git add "$STABLE.sig"
	elif [ -f "$STABLE.sig" ]; then
		# A signature over the previous document would fail verification
		# against this one; an unsigned document is the honest state.
		echo "::warning::no signing key: removing the stale $STABLE.sig"
		git rm -q "$STABLE.sig"
	fi
}

# The body is rebuilt from the branch's commits every time rather than
# appended to, so it cannot gain duplicate lines and still lists a promotion
# whose run pushed but died before it reached the PR.
pr_body() {
	printf 'Merging is the promotion act. This promotion carries:\n\n'
	git log --reverse --format=%b "origin/$BASE..origin/$BRANCH" | { grep '^- ' || true; } | awk '!seen[$0]++'
}

open_or_extend_pr() {
	git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
	local body pr
	body=$(pr_body)
	pr=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')
	if [ -z "$pr" ]; then
		# Two runs can both find no PR here; the loser's create fails because
		# the head already has one, and editing that one is what it wanted.
		gh pr create --head "$BRANCH" --base "$BASE" --title "chore(promote): promote to stable" --body "$body" \
			|| gh pr edit "$BRANCH" --body "$body"
	else
		gh pr edit "$pr" --body "$body"
	fi
}

land() {
	local kind=$1 entry
	entry=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
	: "${SUBJECT:?}" "${SOURCE:?}"
	BRANCH=${PROMOTE_BRANCH:-promote/stable}
	BASE=${PROMOTE_BASE:-main}
	local attempts=${PROMOTE_ATTEMPTS:-10} i tip base rc
	for ((i = 1; i <= attempts; i++)); do
		git fetch -q --prune origin "+refs/heads/$BASE:refs/remotes/origin/$BASE"
		tip=$(git ls-remote --heads origin "refs/heads/$BRANCH" | cut -f1)
		if [ -n "$tip" ]; then
			git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
		fi
		base=$(choose_base "$tip")
		echo "attempt $i: building on $base${tip:+ (branch tip $tip)}"
		git checkout -q -f -B "$BRANCH" "$base"
		git clean -q -fd -- channels

		rc=0
		apply "$kind" "$STABLE" "$entry" || rc=$?
		if [ "$rc" = 3 ]; then
			echo "::notice::${SUBJECT} is already in $base"
			if [ "$base" = "origin/$BRANCH" ]; then open_or_extend_pr; fi
			return 0
		fi
		[ "$rc" = 0 ] || return "$rc"
		git add "$STABLE"
		sign
		git commit -q -m "chore(promote): ${SUBJECT} to stable" -m "- ${SUBJECT}, assembled from ${SOURCE}"

		# The lease is the race guard: it names the tip this run built on (or
		# that the branch must not exist), so a run that lost a race to another
		# push is refused here and starts again from the new tip, rather than
		# overwriting the other run's promotion.
		if git push -q --force-with-lease="refs/heads/$BRANCH:$tip" origin "$BRANCH:refs/heads/$BRANCH"; then
			open_or_extend_pr
			return 0
		fi
		local wait=$((RANDOM % (2 * i + 1) + i))
		echo "push lost a race (attempt $i); retrying in ${wait}s"
		sleep "$wait"
	done
	echo "::error::could not land ${SUBJECT} after $attempts attempts"
	return 1
}

cmd=${1:-}
shift || true
case "$cmd" in
module-entry) module_entry "$@" ;;
seed) seed "$@" ;;
apply-module | apply-image)
	rc=0
	apply "${cmd#apply-}" "$@" || rc=$?
	if [ "$rc" = 3 ]; then echo "already present; unchanged" >&2; exit 0; fi
	exit "$rc"
	;;
land) land "$@" ;;
*)
	sed -n '2,15p' "$0" >&2
	exit 2
	;;
esac
