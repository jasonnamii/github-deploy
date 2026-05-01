#!/usr/bin/env bash
# migrate-legacy.sh — 레거시 도메인(jasonnamii·pdkim) → choi 리다이렉트 마이그레이션 (v2.0)
# usage:
#   bash migrate-legacy.sh {pdkim|jasonnamii} scan   # choi에 없는 서브폴더 목록 출력
#   bash migrate-legacy.sh {pdkim|jasonnamii} apply  # 리다이렉트 + _archive 백업 + push
#
# 전제: 
#   - gh auth 로그인 완료 (jasonnamii 계정)
#   - scan 결과로 출력된 레포들은 apply 전에 choi로 먼저 복제 (Step A)
set -eu

LEGACY="${1:?legacy key required: pdkim|jasonnamii}"
ACTION="${2:?action required: scan|apply}"
OWNER="jasonnamii"
CHOI_ROOT="works-choi"

case "$LEGACY" in
  pdkim)
    LEGACY_ROOT="works-pdkim"
    LEGACY_DOMAIN="works.pdkim.com"
    ;;
  jasonnamii)
    LEGACY_ROOT="jasonnamii.github.io"
    LEGACY_DOMAIN="works.jasonnamii.com"
    ;;
  *)
    echo "✗ 지원하지 않는 legacy: $LEGACY (pdkim|jasonnamii 중 하나)" >&2
    exit 2
    ;;
esac

WORK="/tmp/gh-migrate-${LEGACY}"
T0=$(date +%s)
say() { echo "▶ [$(($(date +%s)-T0))s] $*"; }
ok()  { echo "✓ [$(($(date +%s)-T0))s] $*"; }
warn(){ echo "⚠ [$(($(date +%s)-T0))s] $*"; }

# ---------------------------------------------------------------
# SCAN: 레거시 서브폴더 목록 추출 + choi 존재 여부 비교
# ---------------------------------------------------------------
if [ "$ACTION" = "scan" ]; then
  say "[1/2] ${LEGACY} 서브폴더 목록 조회"
  SUBDIRS=$(gh api "repos/${OWNER}/${LEGACY_ROOT}/contents" \
    --jq '.[] | select(.type=="dir") | .name' 2>/dev/null \
    | grep -vE '^(_archive|\.)' || true)
  
  if [ -z "$SUBDIRS" ]; then
    warn "[scan] ${LEGACY_ROOT}에 서브폴더 없음 — 마이그레이션 대상 없음"
    exit 0
  fi
  
  ok "[1/2] 발견 $(echo "$SUBDIRS" | wc -l | tr -d ' ')개"
  
  say "[2/2] choi 존재 여부 비교"
  echo ""
  echo "# migrate-legacy scan: ${LEGACY} → choi"
  echo -e "SUBDIR\tCHOI_STATUS\tACTION_NEEDED"
  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    if gh api "repos/${OWNER}/${CHOI_ROOT}/contents/${sub}" >/dev/null 2>&1; then
      echo -e "${sub}\tEXISTS\tSKIP"
    else
      echo -e "${sub}\tMISSING\tCOPY_BEFORE_APPLY"
    fi
  done <<<"$SUBDIRS"
  echo ""
  ok "[2/2] scan 완료. MISSING 항목은 apply 전에 choi로 복제 필요"
  exit 0
fi

# ---------------------------------------------------------------
# APPLY: 리다이렉트 + _archive 백업 + push
# ---------------------------------------------------------------
if [ "$ACTION" = "apply" ]; then
  say "[1/5] 작업 디렉토리 준비"
  rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"
  
  say "[2/5] ${LEGACY_ROOT} clone"
  gh repo clone "${OWNER}/${LEGACY_ROOT}" "$WORK" >/dev/null 2>&1 || {
    echo "✗ clone 실패: ${OWNER}/${LEGACY_ROOT}"
    exit 3
  }
  ok "[2/5] clone 완료"
  
  cd "$WORK"
  mkdir -p _archive
  
  say "[3/5] 서브폴더 스캔 + 리다이렉트 교체"
  COUNT=0
  for sub in */; do
    sub="${sub%/}"
    [ "$sub" = "_archive" ] && continue
    [ ! -d "$sub" ] && continue
    
    # choi 존재 확인 (apply 시에도 한 번 더 가드)
    if ! gh api "repos/${OWNER}/${CHOI_ROOT}/contents/${sub}" >/dev/null 2>&1; then
      warn "  SKIP: ${sub} (choi에 없음 — 먼저 복제하세요)"
      continue
    fi
    
    # 백업
    rm -rf "_archive/${sub}"
    cp -r "${sub}" "_archive/${sub}"
    
    # 원본 교체
    rm -rf "${sub}"
    mkdir -p "${sub}"
    cat > "${sub}/index.html" <<REDIRECT
<!DOCTYPE html><html lang="ko"><head>
<meta charset="utf-8">
<meta name="robots" content="noindex, nofollow">
<title>이동됨 → works.choi.build/${sub}/</title>
<meta http-equiv="refresh" content="0; url=https://works.choi.build/${sub}/">
<link rel="canonical" href="https://works.choi.build/${sub}/">
<script>location.replace("https://works.choi.build/${sub}/" + (location.search || "") + (location.hash || ""));</script>
</head><body>
<p>이 페이지는 <a href="https://works.choi.build/${sub}/">works.choi.build/${sub}/</a>로 이동되었습니다.</p>
</body></html>
REDIRECT
    COUNT=$((COUNT+1))
    ok "  리다이렉트: ${sub} (백업: _archive/${sub})"
  done
  
  if [ "$COUNT" = "0" ]; then
    warn "[3/5] 교체 대상 0개 — 종료"
    exit 0
  fi
  ok "[3/5] ${COUNT}개 서브폴더 리다이렉트 완료"
  
  say "[4/5] git 커밋 + push"
  git add -A >/dev/null
  if git diff --cached --quiet; then
    ok "[4/5] 변경사항 없음 — push 생략"
  else
    git -c user.email="deploy@local" -c user.name="deploy" \
        commit -q -m "Redirect to works.choi.build; preserve originals in _archive/ ($(date +%Y-%m-%d))"
    git push -q || {
      warn "push 충돌 — rebase 후 재시도"
      git pull --rebase -q && git push -q
    }
    ok "[4/5] push 완료"
  fi
  
  say "[5/5] Fastly CDN 캐시 주의"
  warn "  GitHub Pages CDN은 max-age=600 (10분). 그 전까진 구 콘텐츠 보일 수 있음"
  warn "  10분 후 https://${LEGACY_DOMAIN}/<sub>/ 접속 시 choi로 자동 점프"
  
  echo "DONE"
  exit 0
fi

echo "✗ 알 수 없는 action: $ACTION (scan|apply 중 하나)" >&2
exit 2
