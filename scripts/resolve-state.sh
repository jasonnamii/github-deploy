#!/usr/bin/env bash
# resolve-state.sh — 배포 상태 판별 (단일 진입점, 도메인별 분기)
# usage: bash resolve-state.sh {repo-name} [domain: jasonnamii|choi|pdkim]
# output:
#   jasonnamii: NEW | UPDATE | PAGES_OFF | ERRORED
#   choi/pdkim: SUBDIR (루트 레포 서브폴더 모드 — 상태 구분 불필요)
set -u

REPO="${1:?repo name required}"
DOMAIN="${2:-jasonnamii}"
OWNER="jasonnamii"

# choi/pdkim: 루트 레포 서브폴더 모드 — 무조건 SUBDIR
case "$DOMAIN" in
  choi|pdkim)
    echo "SUBDIR"
    exit 0
    ;;
esac

# jasonnamii: 기존 로직
# 1) repo existence
if ! gh api "repos/${OWNER}/${REPO}" >/dev/null 2>&1; then
  echo "NEW"
  exit 0
fi

# 2) pages status
PAGES_JSON=$(gh api "repos/${OWNER}/${REPO}/pages" 2>/dev/null || echo "")
if [ -z "$PAGES_JSON" ]; then
  echo "PAGES_OFF"
  exit 0
fi

STATUS=$(echo "$PAGES_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
case "$STATUS" in
  built)   echo "UPDATE" ;;
  errored) echo "ERRORED" ;;
  *)       echo "UPDATE" ;;  # building/null도 UPDATE로 취급 (clone+push 가능)
esac
