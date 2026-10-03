#!/usr/bin/env bash
# Downloads weavemanifest from the weaveplatform-agent-core release named in
# .github/agent-core-version, checks it against that release's checksums, and
# extracts it into <dir>. The same pin selects the channel schema the quality
# gate validates against, so the verifier and the schema always come from one
# core release.
#
#   fetch-weavemanifest.sh <os_arch> <dir>     e.g. linux_amd64 "$RUNNER_TEMP"
set -euo pipefail
plat=$1 dir=$2
ver=$(tr -d '[:space:]' < .github/agent-core-version)
repo="${GITHUB_REPOSITORY_OWNER:-weaveplatform}/weaveplatform-agent-core"
gh release download "$ver" -R "$repo" -D "$dir" --clobber \
	-p "weaveplatform-agent_*_${plat}.tar.gz" -p 'weaveplatform-agent_*_checksums.txt'
cd "$dir"
if command -v sha256sum > /dev/null; then sum=(sha256sum); else sum=(shasum -a 256); fi
grep "_${plat}\.tar\.gz\$" weaveplatform-agent_*_checksums.txt | "${sum[@]}" -c -
tar -xzf weaveplatform-agent_*_"${plat}".tar.gz weavemanifest
echo "weavemanifest from $repo $ver"
