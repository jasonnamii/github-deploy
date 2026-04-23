#!/usr/bin/env bash
# check-deploy.sh — 맥가이버 PRE-CHECK: 레포명으로 2도메인(choi·pdkim) 배포 이력 즉석 조회
# usage: bash check-deploy.sh {repo-name}
# output:
#   # github-deploy PRE-CHECK: {repo}
#   DOMAIN  STATUS          URL                              LAST_COMMIT
#   choi    SUBDIR_EXISTS   https://works.choi.build/{repo}/ 2026-04-15T...
#   pdkim   SUBDIR_NEW      -                                -
# exit: 0=1개 이상 발견 | 1=전부 신규

set -u
REPO="${1:?repo name required}"
OWNER="jasonnamii"

# v1.3: jasonnamii 도메인 조회 제거. choi·pdkim 2도메인만.

check_subdir() {
  local KEY="$1"           # choi | pdkim
  local ROOT_REPO="works-${KEY}"
  local DOMAIN_URL=""
  case "$KEY" in
    choi)  DOMAIN_URL="https://works.choi.build" ;;
    pdkim) DOMAIN_URL="https://works.pdkim.com" ;;
  esac

  # gh api로 서브폴더 존재 확인
  if gh api "repos/${OWNER}/${ROOT_REPO}/contents/${REPO}" >/dev/null 2>&1; then
    LAST=$(gh api "repos/${OWNER}/${ROOT_REPO}/commits?path=${REPO}&per_page=1" --jq '.[0].commit.committer.date' 2>/dev/null || echo "-")
    echo -e "${KEY}\tSUBDIR_EXISTS\t${DOMAIN_URL}/${REPO}/\t${LAST}"
    return 0
  else
    echo -e "${KEY}\tSUBDIR_NEW\t-\t-"
    return 1
  fi
}

# 병렬 실행
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

check_subdir choi > "$TMPDIR/c" 2>/dev/null &
PID1=$!
check_subdir pdkim > "$TMPDIR/p" 2>/dev/null &
PID2=$!

wait $PID1; R1=$?
wait $PID2; R2=$?

echo "# github-deploy PRE-CHECK: ${REPO}"
echo -e "DOMAIN\tSTATUS\tURL\tLAST_COMMIT"
cat "$TMPDIR/c" "$TMPDIR/p"

# 1개 이상 발견 → exit 0 / 전부 신규 → exit 1
if [ $R1 -eq 0 ] || [ $R2 -eq 0 ]; then
  exit 0
else
  exit 1
fi
