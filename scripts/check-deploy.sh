#!/usr/bin/env bash
# check-deploy.sh — choi/pdkim 배포 이력 조회 (v2.1)
# usage:
#   bash check-deploy.sh {repo-name}            # choi 디폴트
#   bash check-deploy.sh {repo-name} pdkim      # pdkim 명시
#   bash check-deploy.sh {repo-name} choi       # 명시도 가능
# output:
#   # github-deploy PRE-CHECK: {repo}
#   DOMAIN  STATUS          URL                              LAST_COMMIT
#   choi    SUBDIR_EXISTS   https://works.choi.build/{repo}/ 2026-04-15T...
# exit: 0=existing | 1=new

set -u
REPO="${1:?repo name required}"
MODE="${2:-choi}"
OWNER="jasonnamii"

case "$MODE" in
  choi)
    ROOT_REPO="works-choi"
    DOMAIN_URL="https://works.choi.build"
    ;;
  pdkim)
    ROOT_REPO="works-pdkim"
    DOMAIN_URL="https://works.pdkim.com"
    ;;
  *)
    echo "✗ 알 수 없는 mode: $MODE (choi|pdkim 중 하나)" >&2
    exit 2
    ;;
esac

echo "# github-deploy PRE-CHECK: ${REPO} (mode=${MODE})"
echo -e "DOMAIN\tSTATUS\tURL\tLAST_COMMIT"

if gh api "repos/${OWNER}/${ROOT_REPO}/contents/${REPO}" >/dev/null 2>&1; then
  LAST=$(gh api "repos/${OWNER}/${ROOT_REPO}/commits?path=${REPO}&per_page=1" --jq '.[0].commit.committer.date' 2>/dev/null || echo "-")
  echo -e "${MODE}\tSUBDIR_EXISTS\t${DOMAIN_URL}/${REPO}/\t${LAST}"
  exit 0
else
  echo -e "${MODE}\tSUBDIR_NEW\t-\t-"
  exit 1
fi
