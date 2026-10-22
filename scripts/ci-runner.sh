#!/usr/bin/env bash
# Switch where the org's CI runs: GitHub-hosted runners, or the in-cluster ARC
# runners (arc-dind) on the install's own cluster.
#
# Every workflow in the org's private repos picks its runner from the CI_RUNNER
# repository variable (`runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}`, and the
# same expression in the `runner:` input passed to build.yml). This script sets that
# variable on every private repo at once, so switching is one command, not a commit.
#
#   github       CI_RUNNER=ubuntu-latest. Spends the org's Actions minutes; runs
#                even when the cluster is down.
#   self-hosted  CI_RUNNER=arc-dind. Free; jobs queue until the cluster's ARC
#                runners are up. The runners are Linux on arm64, so jobs that need
#                macOS or an amd64-only container (rb-terminal's package-* installer
#                jobs) are skipped in this mode.
#   status       print each repo's current value.
#
# Why per repo and not one organisation variable: on GitHub's Free plan, private
# repositories cannot read organisation-level variables. Public repos are left
# alone: their GitHub-hosted minutes are free, and a self-hosted runner on a public
# repo would run any fork's pull request on the cluster.
#
# Needs the GitHub CLI logged in as an org admin (gh auth login).
#
# Usage: ci-runner.sh github|self-hosted|status [org]   (default org: foundryRB)
set -euo pipefail

mode="${1:-}"
org="${2:-foundryRB}"

case "$mode" in
    github) value=ubuntu-latest ;;
    self-hosted) value=arc-dind ;;
    status) value= ;;
    *)
        echo "usage: $(basename "$0") github|self-hosted|status [org]" >&2
        exit 2
        ;;
esac

repos=$(gh repo list "$org" --no-archived --visibility private --limit 200 --json name --jq '.[].name' | sort)
if [ -z "$repos" ]; then
    echo "ERROR: no private repositories found in $org (is gh logged in?)" >&2
    exit 1
fi

for repo in $repos; do
    if [ -z "$value" ]; then
        current=$(gh variable get CI_RUNNER --repo "$org/$repo" 2>/dev/null || echo "(unset: ubuntu-latest)")
        printf '%-24s %s\n' "$repo" "$current"
    else
        gh variable set CI_RUNNER --repo "$org/$repo" --body "$value"
        printf '%-24s -> %s\n' "$repo" "$value"
    fi
done
