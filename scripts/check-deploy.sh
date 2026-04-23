#!/usr/bin/env bash
# check-deploy.sh — choi 단일 도메인 배포 이력 조회 (v2.0)
# usage: bash check-deploy.sh {repo-name}
# output:
#   # github-deploy PRE-CHECK: {repo}
#   DOMAIN  STATUS          URL                              LAST_COMMIT
#   choi    SUBDIR_EXISTS   https://works.choi.build/{repo}/ 2026-04-15T...
# exit: 0=existing | 1=new

set -u
REPO="${1:?repo name required}"
OWNER="jasonnamii"
ROOT_REPO="works-choi"
DOMAIN_URL="https://works.choi.build"

echo "# github-deploy PRE-CHECK: ${REPO}"
echo -e "DOMAIN\tSTATUS\tURL\tLAST_COMMIT"

if gh api "repos/${OWNER}/${ROOT_REPO}/contents/${REPO}" >/dev/null 2>&1; then
  LAST=$(gh api "repos/${OWNER}/${ROOT_REPO}/commits?path=${REPO}&per_page=1" --jq '.[0].commit.committer.date' 2>/dev/null || echo "-")
  echo -e "choi\tSUBDIR_EXISTS\t${DOMAIN_URL}/${REPO}/\t${LAST}"
  exit 0
else
  echo -e "choi\tSUBDIR_NEW\t-\t-"
  exit 1
fi
