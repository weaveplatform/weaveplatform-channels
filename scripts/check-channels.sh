#!/usr/bin/env bash
# The quality gate's checks over the channel documents, runnable locally from
# the repository root.
#
#   check-channels.sh parse                      core's ParseChannel rules the schema cannot express
#   check-channels.sh signatures <weavemanifest> every .sig verifies under keys/root.pub
#   check-channels.sh history <base-ref>         anti-rollback and pinned immutability against <base-ref>
set -euo pipefail

channel_files() {
	local f
	for f in channels/stable.json channels/pinned/*.json; do
		[ -f "$f" ] && printf '%s\n' "$f"
	done
}

# sdk/manifest.ParseChannel in weaveplatform-agent-core refuses these, and the
# schema does not say so: a module id or version that would be unsafe as a
# path component, and an inverted protocol window. Without this, an unsigned
# document passes the gate and is refused by every device once signed.
parse() {
	local f bad=0
	while read -r f; do
		if ! jq -e '
		    (.protocol.max >= .protocol.min)
		    and all(.modules[]; (.id | test("^[a-z][a-z0-9-]*$"))
		                        and (.version | test("^\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.-]+)?$")))
		  ' "$f" > /dev/null; then
			echo "::error file=$f::module id/version or protocol window that core's ParseChannel refuses"
			bad=1
		fi
	done < <(channel_files)
	return "$bad"
}

# A .sig names its signing key by key_id; the matching keys/*.pub (whose own
# .sig is the root endorsement) is found by that id, so a rotation is adding a
# key file, not editing this script. No .sig is a notice, not a failure, while
# no signing key is provisioned: core refuses an unsigned channel anyway, and
# failing here would block every promotion until one is. A .sig that does not
# verify always fails.
signatures() {
	local wm=$1 f kid key k bad=0
	while read -r f; do
		if [ ! -f "$f.sig" ]; then
			echo "::notice file=$f::unsigned"
			continue
		fi
		kid=$(jq -r '.key_id // empty' "$f.sig")
		key=
		for k in keys/*.pub; do
			[ "$k" = keys/root.pub ] && continue
			[ -f "$k" ] && [ "$(jq -r '.key_id // empty' "$k")" = "$kid" ] && key=$k
		done
		if [ ! -f keys/root.pub ] || [ -z "$key" ]; then
			echo "::error file=$f.sig::signed by key '$kid', but keys/root.pub or a keys/*.pub with that key_id is missing"
			bad=1
			continue
		fi
		"$wm" verify keys/root.pub "$key" "$f" || { echo "::error file=$f.sig::does not verify"; bad=1; }
	done < <(channel_files)
	for f in channels/stable.json.sig channels/pinned/*.json.sig; do
		[ -f "$f" ] && [ ! -f "${f%.sig}" ] && { echo "::error file=$f::signature with no document"; bad=1; }
	done
	return "$bad"
}

# Core persists the highest sequence it has accepted and refuses a lower one,
# so a merge that lowered it would strand every device that saw the old one.
# Changing the document without raising it is refused too: two different
# signed documents with one sequence leave a device that already holds that
# number unable to move to the other.
history() {
	local base=$1 old new bad=0 changes
	if git cat-file -e "$base:channels/stable.json" 2> /dev/null; then
		old=$(git show "$base:channels/stable.json" | jq '.sequence // 0')
		new=$(jq '.sequence // 0' channels/stable.json)
		if [ "$new" -lt "$old" ]; then
			echo "::error file=channels/stable.json::sequence $new is lower than $base's $old (rollback)"
			bad=1
		elif [ "$new" -eq "$old" ] && ! git diff --quiet "$base" -- channels/stable.json; then
			echo "::error file=channels/stable.json::document changed but sequence stayed at $old"
			bad=1
		else
			echo "sequence $old -> $new"
		fi
	fi
	# Pinned snapshots are referenced by URL and digest from deployed
	# configuration: once on the base branch, any change is a broken pin.
	changes=$(git diff --name-status --no-renames "$base" -- channels/pinned/ | awk '$1 != "A"')
	if [ -n "$changes" ]; then
		echo "::error::pinned snapshots are immutable once merged; this change modifies or deletes:"
		printf '%s\n' "$changes"
		bad=1
	fi
	return "$bad"
}

cmd=${1:-}
shift || true
case "$cmd" in
parse | signatures | history) "$cmd" "$@" ;;
*)
	sed -n '2,8p' "$0" >&2
	exit 2
	;;
esac
