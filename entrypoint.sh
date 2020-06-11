#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -x

fail()
{
  echo "$@" >&2
  exit 1
}

[ -n "${GITHUB_REPOSITORY}" ] || fail "No GITHUB_REPOSITORY was supplied."
[ -n "${PULL_REQUEST_LABEL}" ] || fail "No PULL_REQUEST_LABEL was supplied."
[ -n "${GITHUB_TOKEN}" ] || fail "No GITHUB_TOKEN was supplied."

# Determine https://github.com/OWNER/REPO from GITHUB_REPOSITORY.
REPO="${GITHUB_REPOSITORY##*/}"
OWNER="${GITHUB_REPOSITORY%/*}"

[ -n "${OWNER}" ] || fail "Could not determine GitHub owner from GITHUB_REPOSITORY."
[ -n "${REPO}" ] || fail "Could not determine GitHub repo from GITHUB_REPOSITORY."

# Fetch the SHAs from the pull requests that are marked with $PULL_REQUEST_LABEL.
readarray -t shas < <(
  jq -cn '
    {
      query: $query,
      variables: {
        owner: $owner,
        repo: $repo,
        pull_request_label: $pull_request_label
      }
    }' \
    --arg query '
      query($owner: String!, $repo: String!, $pull_request_label: String!) {
        repository(owner: $owner, name: $repo) {
          pullRequests(states: OPEN, labels: $pull_request_label, first: 100) {
            nodes {
              headRefOid
            }
          }
        }
      }' \
    --arg owner "$OWNER" \
    --arg repo "$REPO" \
    --arg pull_request_label "$PULL_REQUEST_LABEL" \
  | curl \
    --fail \
    --show-error \
    --header "Authorization: token $GITHUB_TOKEN" \
    --header "Content-Type: application/json" \
    --data @- \
    https://api.github.com/graphql
)

# Do not attempt to merge if there are no pull requests to be merged.
[ ${#shas[@]} -ne 0 ] || exit 0

# Merge all shas together into one commit.
git merge --commit --no-edit --no-ff --rerere-autoupdate "${shas[@]}"
