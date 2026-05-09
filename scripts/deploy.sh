#!/usr/bin/env bash
# deploy.sh — choi 디폴트 + pdkim 명시 모드 (v2.3)
# usage:
#   bash deploy.sh {repo} {src_path}                    # choi 디폴트
#   bash deploy.sh {repo} {src_path} --mode=pdkim       # pdkim 명시
#   bash deploy.sh {repo} {src_path} --mode=choi        # 명시도 가능
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
    cache_hit=$(python3 - "$CACHE_FILE" "$REPO" "$MODE" <<'PY' 2>/dev/null || true
import json, sys
try:
    cache = json.load(open(sys.argv[1]))
    key = f"{sys.argv[3]}:{sys.argv[2]}"
    if key in cache:
        print(cache[key].get("url", ""))
except Exception:
    pass
PY
)
  fi

  # 0-2: git ls-tree (레포 내부 폴더 확인)
  tree_hit=$(gh api "repos/${OWNER}/${ROOT_REPO}/contents/${REPO}" >/dev/null 2>&1 && echo "Y" || echo "")

  # 0-3: curl HEAD (외부 검증, 5초 타임아웃)
  local code
  code=$(curl -g -s -o /dev/null -w "%{http_code}" --max-time 5 "${BASE_URL}/" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    head_hit="Y"
  fi

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
      cached_sha=$(python3 - "$CACHE_FILE" "$REPO" "$MODE" <<'PY' 2>/dev/null || true
import json, sys
try:
    cache = json.load(open(sys.argv[1]))
    key = f"{sys.argv[3]}:{sys.argv[2]}"
    print(cache.get(key, {}).get("last_sha256", ""))
except Exception:
    pass
PY
)
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
  python3 - "$CACHE_FILE" "$REPO" "$MODE" "$BASE_URL" "$DEPLOY_KIND" "$input_sha" <<'PY' 2>/dev/null || true
import json, os, sys
from datetime import datetime, timezone
path, repo, mode, url, kind, sha = sys.argv[1:7]
cache = {}
if os.path.exists(path):
    try:
        cache = json.load(open(path))
    except Exception:
        cache = {}
key = f"{mode}:{repo}"
cache[key] = {
    "slug": repo,
    "mode": mode,
    "url": f"{url}/",
    "last_kind": kind,
    "last_sha256": sha,
    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}
json.dump(cache, open(path, "w"), indent=2, ensure_ascii=False)
PY
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
  python3 - "$src" "$dst" <<'PY'
import sys, os, shutil, re, html
from urllib.parse import urlparse, unquote

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)

def is_external(ref: str) -> bool:
    if not ref: return True
    if ref.startswith(('#', 'javascript:', 'mailto:', 'tel:', 'data:')): return True
    if ref.startswith(('http://', 'https://', '//')): return True
    return False

if os.path.isdir(src):
    shutil.copytree(src, dst, dirs_exist_ok=True)
    for root, _, files in os.walk(dst):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), dst)
            print(rel)
    sys.exit(0)

if not os.path.isfile(src):
    print(f"ERROR: src not found: {src}", file=sys.stderr)
    sys.exit(10)

is_html = src.lower().endswith(('.html', '.htm'))
if is_html:
    dst_file = os.path.join(dst, 'index.html')
else:
    dst_file = os.path.join(dst, os.path.basename(src))
shutil.copy2(src, dst_file)
print(os.path.relpath(dst_file, dst))

if not is_html:
    sys.exit(0)

src_dir = os.path.dirname(os.path.abspath(src))
with open(dst_file, encoding='utf-8', errors='replace') as f:
    text = f.read()

patterns = [
    re.compile(r'''\b(?:src|href)\s*=\s*["']([^"']+)["']''', re.I),
    re.compile(r'''\bsrcset\s*=\s*["']([^"']+)["']''', re.I),
    re.compile(r'''\bposter\s*=\s*["']([^"']+)["']''', re.I),
    re.compile(r'''\bdata-src\s*=\s*["']([^"']+)["']''', re.I),
]

refs = set()
for pat in patterns:
    for m in pat.finditer(text):
        val = html.unescape(m.group(1))
        for piece in val.split(','):
            url = piece.strip().split()[0] if piece.strip() else ''
            if not url or is_external(url):
                continue
            clean = urlparse(url)
            path = unquote(clean.path)
            if not path:
                continue
            refs.add(path)

copied = []
missing = []
for ref in sorted(refs):
    candidate_rel = ref.lstrip('/')
    abs_src = os.path.normpath(os.path.join(src_dir, candidate_rel))
    if not abs_src.startswith(os.path.abspath(src_dir)):
        print(f"  ! 경로이탈 무시: {ref}", file=sys.stderr)
        continue
    if not os.path.exists(abs_src):
        missing.append(ref)
        continue
    abs_dst = os.path.normpath(os.path.join(dst, candidate_rel))
    os.makedirs(os.path.dirname(abs_dst), exist_ok=True)
    if os.path.isdir(abs_src):
        shutil.copytree(abs_src, abs_dst, dirs_exist_ok=True)
        for root, _, files in os.walk(abs_dst):
            for f in files:
                rel = os.path.relpath(os.path.join(root, f), dst)
                copied.append(rel)
                print(rel)
    else:
        shutil.copy2(abs_src, abs_dst)
        copied.append(candidate_rel)
        print(candidate_rel)

print(f"[auto-asset] scanned refs: {len(refs)} | copied: {len(copied)} | missing: {len(missing)}",
      file=sys.stderr)
if missing:
    print("[auto-asset] MISSING (HTML 내 참조되나 파일 없음):", file=sys.stderr)
    for m in missing[:20]:
        print(f"  - {m}", file=sys.stderr)
    if len(missing) > 20:
        print(f"  ... +{len(missing)-20}개", file=sys.stderr)
PY
}

# ---------------------------------------------------------------
# inject_noindex: 대상 index.html에 noindex 메타 주입
# ---------------------------------------------------------------
inject_noindex() {
  local target="$1"
  python3 - "$target" <<'PY'
import os, sys
target = sys.argv[1]
idx = os.path.join(target, "index.html")
if os.path.exists(idx):
    t = open(idx, encoding='utf-8').read()
    if 'noindex' not in t:
        t = t.replace('<head>', '<head>\n<meta name="robots" content="noindex, nofollow">', 1)
        open(idx, 'w', encoding='utf-8').write(t)
PY
}

# ---------------------------------------------------------------
# verify_root: 루트 URL HEAD 1회 검증 (sleep 60s 고정)
#   v2.3 단순화: 파일별 검증 → 루트 URL만 (deploy.sh가 index.html로
#   리네임하므로 루트가 곧 페이지). 재시도 루프 제거.
# ---------------------------------------------------------------
verify_root() {
  local base="$1"
  say "[verify] Pages 전파 대기 60s 후 루트 HEAD 검증"
  sleep 60
  local code
  code=$(curl -g -sI -o /dev/null -w "%{http_code}" --max-time 10 "${base}/" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    ok "[verify] HTTP 200 OK → ${base}/"
    return 0
  else
    warn "[verify] HTTP ${code} → ${base}/ (전파 더 필요할 수 있음)"
    warn "[verify] 1~2분 후 직접 재확인 권장"
    return 1
  fi
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
