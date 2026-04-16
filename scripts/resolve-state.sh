#!/usr/bin/env bash
# resolve-state.sh — 배포 상태 판별 (단일 진입점)
# usage: bash resolve-state.sh {repo-name}
# output: one of {NEW, UPDATE, PAGES_OFF, ERRORED}
set -u

REPO="${1:?repo name required}"
OWNER="jasonnamii"

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
