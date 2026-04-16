#!/usr/bin/env bash
# wait-build.sh — Pages 빌드 완료 폴링 (투명 + 재생성 시 카운터 리셋)
# usage: bash wait-build.sh {repo} [max_seconds=180]
# exit: 0=built, 1=timeout, 2=errored(재생성 실패)
set -u

REPO="${1:?repo required}"
MAX="${2:-180}"
OWNER="jasonnamii"
T0=$(date +%s)
RESET_COUNT=0
MAX_RESETS=1

elapsed() { echo $(($(date +%s)-T0)); }

fetch_status() {
  gh api "repos/${OWNER}/${REPO}/pages" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin) if sys.stdin.readable() else {}; print(d.get('status','unknown'))" \
      2>/dev/null || echo "unknown"
}

recreate_pages() {
  echo "⚠ [$(elapsed)s] Pages errored — 재생성 시도 (${RESET_COUNT}/${MAX_RESETS})"
  gh api "repos/${OWNER}/${REPO}/pages" -X DELETE >/dev/null 2>&1 || true
  sleep 3
  gh api "repos/${OWNER}/${REPO}/pages" -X POST --input - >/dev/null 2>&1 <<EOF
{"build_type":"legacy","source":{"branch":"main","path":"/"}}
EOF
  echo "✓ [$(elapsed)s] 재생성 완료 — 폴링 재시작"
}

# 폴링 간격: 짧게 시작 (5s → 10s → 15s → 20s 반복)
INTERVALS=(5 10 15 20)
i=0

while [ "$(elapsed)" -lt "$MAX" ]; do
  WAIT="${INTERVALS[$((i % ${#INTERVALS[@]}))]}"
  sleep "$WAIT"
  STATUS=$(fetch_status)
  echo "⏳ [$(elapsed)s/${MAX}s] status=${STATUS}"

  case "$STATUS" in
    built)
      echo "✓ [$(elapsed)s] 빌드 완료"
      exit 0
      ;;
    errored)
      if [ "$RESET_COUNT" -lt "$MAX_RESETS" ]; then
        RESET_COUNT=$((RESET_COUNT+1))
        recreate_pages
        i=0   # 폴링 카운터 리셋 — 재생성 후 충분히 재시도
        continue
      else
        echo "✗ [$(elapsed)s] errored 반복 — 재생성 한도 초과"
        exit 2
      fi
      ;;
  esac
  i=$((i+1))
done

echo "✗ [$(elapsed)s] timeout (status=${STATUS}) — 수동 확인 필요"
exit 1
