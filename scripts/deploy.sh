#!/usr/bin/env bash
# deploy.sh — choi 디폴트 + pdkim 명시 모드 (v2.5)
# usage:
#   bash deploy.sh {repo} {src_path}                    # choi 디폴트
#   bash deploy.sh {repo} {src_path} --mode=pdkim       # pdkim 명시
#   bash deploy.sh {repo} {src_path} --mode=choi        # 명시도 가능
#
# v2.5 변경점 (2026-05-10 — 속도 Top5 적용):
#   1. verify_root: sleep 60 고정 → HEAD polling (sleep 20 + 5s×12 break)
#      → 평균 -30~45s/배포. 200 즉시 break, 미전파 시 80s까지 polling.
#   2. Phase 0 라우팅: gh api + curl HEAD 직렬 → 병렬 (& + wait)
#      → -3~5s/재배포 라우팅.
#
# v2.4 변경점 (2026-05-09 — F1·F2·F3 병목 제거):
#   1. F1 sha256 비교: Phase 0에서 입력 파일 sha256 vs 캐시 last_sha256 비교
#      → 동일 콘텐츠면 1초 이내 "최신본 동일" 1줄 종료 (재배포 콜 폭증 차단)
#   2. F2 .deploy-status.txt: 매 phase 종료 시 STATUS/COMMIT/TIME/URL/HTTP_CODE 박제
#      → timeout 시 Claude가 cat 1콜로 즉시 결과 파악 (재시도 루프 차단)
#   3. F3 stdout flush: say/ok/warn에 sync 추가 → MCP stream timeout 회피
#
# v2.3 변경점:
#   1. Phase 0 라우팅 게이트: .deploy-cache.json + git ls-tree + curl HEAD
#   2. mapfile 제거 → while read (macOS bash 3.2 호환)
#   3. 검증 로직 단순화 → 리네임 후 루트 URL 1회 HEAD (sleep 60s 고정)
#   4. .deploy-cache.json 자동 갱신 (재배포시 라우팅 0초)
#
# src_path: 단일 html 또는 폴더
# 배포처:
#   choi  → jasonnamii/works-choi/{repo}/  → https://works.choi.build/{repo}/
#   pdkim → jasonnamii/works-pdkim/{repo}/ → https://works.pdkim.com/{repo}/
set -eu

# v2.5: _helper.py 위치 — deploy.sh와 동일 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="${1:?repo required}"
SRC="${2:?src path required}"
MODE_ARG="${3:-}"

# --mode 파싱 (디폴트=choi)
MODE="choi"
case "$MODE_ARG" in
  --mode=choi|mode=choi|choi)   MODE="choi" ;;
  --mode=pdkim|mode=pdkim|pdkim) MODE="pdkim" ;;
  "") MODE="choi" ;;
  *)
    echo "✗ 알 수 없는 mode: $MODE_ARG (choi|pdkim 중 하나)" >&2
    exit 2
    ;;
esac

OWNER="jasonnamii"
case "$MODE" in
  choi)
    ROOT_REPO="works-choi"
    BASE_URL="https://works.choi.build/${REPO}"
    ;;
  pdkim)
    ROOT_REPO="works-pdkim"
    BASE_URL="https://works.pdkim.com/${REPO}"
    ;;
esac

WORK="/tmp/gh-deploy/${ROOT_REPO}"
CACHE_DIR="${HOME}/github-repos/skill-repos/github-deploy/.cache"
CACHE_FILE="${CACHE_DIR}/deploy-cache.json"
STATUS_FILE="${CACHE_DIR}/deploy-status.txt"
T0=$(date +%s)

# F3: stdout flush 강제 — MCP stream timeout 회피
say() { echo "▶ [$(($(date +%s)-T0))s] $*"; sync 2>/dev/null || true; }
ok()  { echo "✓ [$(($(date +%s)-T0))s] $*"; sync 2>/dev/null || true; }
warn(){ echo "⚠ [$(($(date +%s)-T0))s] $*"; sync 2>/dev/null || true; }

# F2: 매 phase 종료 시 status 박제 — timeout 시 Claude가 cat 1콜로 결과 파악
write_status() {
  local status="$1" phase="${2:-}" commit="${3:-}" code="${4:-}"
  mkdir -p "$CACHE_DIR"
  cat > "$STATUS_FILE" <<EOF
STATUS=${status}
PHASE=${phase}
MODE=${MODE}
REPO=${REPO}
URL=${BASE_URL}/
COMMIT=${commit}
HTTP_CODE=${code}
DEPLOY_KIND=${DEPLOY_KIND:-pending}
TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PID=$$
EOF
}

# F1: 입력 파일 sha256 (단일 HTML 또는 폴더 전체)
compute_input_sha() {
  local src="$1"
  if [ -d "$src" ]; then
    find "$src" -type f -exec shasum -a 256 {} \; 2>/dev/null | sort | shasum -a 256 | awk '{print $1}'
  elif [ -f "$src" ]; then
    shasum -a 256 "$src" | awk '{print $1}'
  else
    echo ""
  fi
}


# ===============================================================
# Phase 0: 라우팅 게이트 (재배포 vs 신규배포 자동 분기)
#   1. 캐시 우선 조회 (.deploy-cache.json)
#   2. git ls-tree (레포 내부 폴더 존재 확인)
#   3. curl HEAD (외부 200/404 검증)
#   4. 결과 보고 → DEPLOY_KIND=redeploy | new
# ===============================================================
DEPLOY_KIND="new"
DEPLOY_SOURCE="-"

route_phase0() {
  local cache_hit="" tree_hit="" head_hit=""

  # 0-1: 캐시 조회 (없으면 패스, 있으면 우선)
  if [ -f "$CACHE_FILE" ]; then
    cache_hit=$(python3 "${SCRIPT_DIR}/_helper.py" cache_read "$CACHE_FILE" "$REPO" "$MODE" 2>/dev/null || true)
  fi

  # v2.5: 0-2 + 0-3 병렬화 (gh api + curl HEAD을 백그라운드 동시 실행)
  # 직렬 5+5=10s → 병렬 max(5,5)=5s. 평균 -3~5s/재배포 라우팅.
  local p0_tmp
  p0_tmp=$(mktemp -d)
  ( gh api "repos/${OWNER}/${ROOT_REPO}/contents/${REPO}" >/dev/null 2>&1 && echo "Y" > "$p0_tmp/tree" || true ) &
  local p0_pid_tree=$!
  ( curl -g -s -o /dev/null -w "%{http_code}" --max-time 5 "${BASE_URL}/" 2>/dev/null > "$p0_tmp/code" || echo "000" > "$p0_tmp/code" ) &
  local p0_pid_head=$!
  wait $p0_pid_tree $p0_pid_head 2>/dev/null || true

  # 결과 수집
  tree_hit=$(cat "$p0_tmp/tree" 2>/dev/null || echo "")
  local code
  code=$(cat "$p0_tmp/code" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    head_hit="Y"
  fi
  rm -rf "$p0_tmp"

  # 0-4: 분기 결정
  if [ -n "$cache_hit" ]; then
    DEPLOY_KIND="redeploy"
    DEPLOY_SOURCE="cache"
  elif [ -n "$tree_hit" ] || [ -n "$head_hit" ]; then
    DEPLOY_KIND="redeploy"
    if [ -n "$tree_hit" ] && [ -n "$head_hit" ]; then
      DEPLOY_SOURCE="tree+head"
    elif [ -n "$tree_hit" ]; then
      DEPLOY_SOURCE="tree"
    else
      DEPLOY_SOURCE="head"
    fi
  else
    DEPLOY_KIND="new"
    DEPLOY_SOURCE="-"
  fi

  # 0-5: 보고
  if [ "$DEPLOY_KIND" = "redeploy" ]; then
    say "[phase 0] 기배포 발견 (${DEPLOY_SOURCE}) → 재배포 모드 → ${BASE_URL}/"

    # 0-6: F1 sha256 short-circuit — 동일 콘텐츠면 1초 종료
    if [ -n "$cache_hit" ] && [ -f "$CACHE_FILE" ]; then
      local cached_sha new_sha
      cached_sha=$(python3 "${SCRIPT_DIR}/_helper.py" cache_sha "$CACHE_FILE" "$REPO" "$MODE" 2>/dev/null || true)
      new_sha=$(compute_input_sha "$SRC")
      if [ -n "$cached_sha" ] && [ -n "$new_sha" ] && [ "$cached_sha" = "$new_sha" ]; then
        ok "[phase 0] 입력 sha256 동일 → 이미 최신본 배포됨. 재push 생략"
        write_status "skip-same-sha" "phase0" "" "200"
        echo "DONE-SKIP (sha256 match, mode=${MODE} → ${BASE_URL}/)"
        exit 0
      fi
    fi
  else
    say "[phase 0] 기배포 없음 → 신규배포 모드 → ${BASE_URL}/ 생성"
  fi
  write_status "phase0-done" "phase0"
}

# 캐시 갱신 함수 (Phase 1 끝나고 호출)
update_cache() {
  mkdir -p "$CACHE_DIR"
  local input_sha
  input_sha=$(compute_input_sha "$SRC")
  python3 "${SCRIPT_DIR}/_helper.py" update_cache "$CACHE_FILE" "$REPO" "$MODE" "$BASE_URL" "$DEPLOY_KIND" "$input_sha" 2>/dev/null || true
}

say "[mode] ${MODE} → ${OWNER}/${ROOT_REPO}/${REPO}/"
route_phase0


# ---------------------------------------------------------------
# stage_source: 단일 HTML → 동반 자원 자동 복사 (auto-asset)
# 폴더 입력이면 통째로 복사. 단일 HTML이면 참조 스캔 + 실존 파일 동반 복사.
# stdout: 복사된 자산 상대경로 목록 (참고용)
# ---------------------------------------------------------------
stage_source() {
  local src="$1" dst="$2"
  python3 "${SCRIPT_DIR}/_helper.py" stage_source "$src" "$dst"
}

# ---------------------------------------------------------------
# inject_noindex: 대상 index.html에 noindex 메타 주입
# ---------------------------------------------------------------
inject_noindex() {
  local target="$1"
  python3 "${SCRIPT_DIR}/_helper.py" inject_noindex "$target"
}

# ---------------------------------------------------------------
# verify_root: 루트 URL HEAD 1회 검증 (sleep 60s 고정)
#   v2.3 단순화: 파일별 검증 → 루트 URL만 (deploy.sh가 index.html로
#   리네임하므로 루트가 곧 페이지). 재시도 루프 제거.
# ---------------------------------------------------------------
verify_root() {
  # v2.5: sleep 60 고정 → HEAD polling (sleep 20 + 5s × 12회 break)
  # 평균 -30~45s/배포. false-positive 방지 위해 초기 20s 대기 후 polling.
  local base="$1"
  local code i
  say "[verify] Pages 전파 초기 20s 대기 후 HEAD polling (5s × 12회)"
  sleep 20
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    code=$(curl -g -sI -o /dev/null -w "%{http_code}" --max-time 5 "${base}/" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
      ok "[verify] HTTP 200 OK → ${base}/ (poll #${i}, 총 $((20 + i*5))s)"
      return 0
    fi
    sleep 5
  done
  warn "[verify] HTTP ${code} → ${base}/ (80s 폴링 후 미전파, 추가 1~2분 대기 권장)"
  return 1
}


# ===============================================================
# Phase 1: 본류 (루트 레포 서브폴더 배포)
# ===============================================================
say "[1/4] 루트 레포 준비 (${OWNER}/${ROOT_REPO})"
rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"
gh repo clone "${OWNER}/${ROOT_REPO}" "$WORK" >/dev/null 2>&1 || {
  echo "✗ 루트 레포 clone 실패: ${OWNER}/${ROOT_REPO}"
  echo "   루트 레포가 존재하고 gh auth가 유효한지 확인"
  exit 3
}
ok "[1/4] 루트 레포 clone 완료"

TARGET="${WORK}/${REPO}"
say "[2/4] 서브폴더 배치 ($SRC → ${REPO}/) + 동반 자원 자동 탐지"
rm -rf "$TARGET"
ASSET_LIST=$(stage_source "$SRC" "$TARGET")
ASSET_COUNT=$(echo "$ASSET_LIST" | grep -c . || echo "0")
ok "[2/4] 파일 배치 완료 (${ASSET_COUNT}개 파일)"

say "[3/4] noindex 메타태그 주입"
inject_noindex "$TARGET"
ok "[3/4] 메타태그 주입 완료"

cd "$WORK"
say "[4/4] git 커밋 + push"
git add -A >/dev/null
if git diff --cached --quiet; then
  ok "[4/4] 변경사항 없음 — push 생략"
  PUSHED=0
else
  git -c user.email="deploy@local" -c user.name="deploy" \
      commit -q -m "Deploy ${REPO} → ${ROOT_REPO}/ (${DEPLOY_KIND}, $(date +%Y-%m-%d))" || true
  git push -q || {
    warn "push 충돌 — rebase 후 재시도"
    git pull --rebase -q && git push -q
  }
  ok "[4/4] push 완료"
  LAST_COMMIT=$(git log -1 --format='%h' 2>/dev/null || echo "")
  write_status "phase4-pushed" "phase4" "$LAST_COMMIT"
  PUSHED=1
fi

# ===============================================================
# Phase 2: 검증 + 캐시 갱신
# ===============================================================
if [ "${SKIP_VERIFY:-0}" != "1" ] && [ "$PUSHED" = "1" ]; then
  verify_root "$BASE_URL" || true
elif [ "$PUSHED" = "0" ]; then
  say "[verify] 변경 없음 → 검증 생략"
fi

update_cache
ok "[cache] .deploy-cache.json 갱신 완료 (${MODE}:${REPO})"

# F2: 최종 status 박제
LAST_COMMIT=$(cd "$WORK" && git log -1 --format='%h' 2>/dev/null || echo "")
write_status "success" "done" "$LAST_COMMIT" "200"

echo "DONE (kind=${DEPLOY_KIND}, mode=${MODE} → ${BASE_URL}/)"
