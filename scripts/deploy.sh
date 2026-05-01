#!/usr/bin/env bash
# deploy.sh — choi 단일 도메인 배포 (v2.0)
# usage: bash deploy.sh {repo} {src_path}
#   src_path: 단일 html 또는 폴더
#   배포처: jasonnamii/works-choi/{repo}/ → https://works.choi.build/{repo}/
#
# [v1.1] 단일 HTML 입력 시 같은 폴더 상대경로 자원 자동 동반.
# [v2.0] domain 파라미터 제거. choi 고정. OWNER=jasonnamii 유지.
set -eu

REPO="${1:?repo required}"
SRC="${2:?src path required}"
OWNER="jasonnamii"
ROOT_REPO="works-choi"
WORK="/tmp/gh-deploy/${ROOT_REPO}"
BASE_URL="https://works.choi.build/${REPO}"
T0=$(date +%s)

say() { echo "▶ [$(($(date +%s)-T0))s] $*"; }
ok()  { echo "✓ [$(($(date +%s)-T0))s] $*"; }
warn(){ echo "⚠ [$(($(date +%s)-T0))s] $*"; }

# ---------------------------------------------------------------
# stage_source: 단일 HTML → 동반 자원 자동 복사 (auto-asset)
# 폴더 입력이면 통째로 복사. 단일 HTML이면 참조 스캔 + 실존 파일 동반 복사.
# stdout: 복사된 자산 상대경로 목록 (HEAD 검증용)
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
# verify_deploy: 배포 후 HEAD 검증 (루프 하드캡 1회)
# ---------------------------------------------------------------
verify_deploy() {
  local base="$1"; shift
  local -a paths=("$@")
  local fail=0 ok_count=0
  say "[verify] HEAD 체크 시작 (전파 대기 45s)"
  sleep 45
  for p in "${paths[@]}"; do
    local code
    code=$(curl -g -s -o /dev/null -w "%{http_code}" "${base}/${p}" || echo "000")
    if [ "$code" = "200" ]; then
      ok_count=$((ok_count+1))
    else
      warn "  404/오류: ${p} → ${code}"
      fail=$((fail+1))
    fi
  done
  if [ "$fail" = "0" ]; then
    ok "[verify] 완벽 배포: ${ok_count}/${#paths[@]} 리소스 200 OK"
  else
    warn "[verify] ${fail}건 실패 / 총 ${#paths[@]}건 — GitHub Pages 전파 지연이거나 파일 누락"
    warn "[verify] 1~2분 후 수동 재확인 권장: ${base}/"
  fi
}

# ===============================================================
# 본류: choi 루트 레포 서브폴더 배포
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
ok "[2/4] 파일 배치 완료 ($(echo "$ASSET_LIST" | wc -l | tr -d ' ')개 파일)"

say "[3/4] noindex 메타태그 주입"
inject_noindex "$TARGET"
ok "[3/4] 메타태그 주입 완료"

cd "$WORK"
say "[4/4] git 커밋 + push"
git add -A >/dev/null
if git diff --cached --quiet; then
  ok "[4/4] 변경사항 없음 — push 생략"
else
  git -c user.email="deploy@local" -c user.name="deploy" \
      commit -q -m "Deploy ${REPO} → ${ROOT_REPO}/ ($(date +%Y-%m-%d))" || true
  git push -q || {
    warn "push 충돌 — rebase 후 재시도"
    git pull --rebase -q && git push -q
  }
  ok "[4/4] push 완료"
fi

if [ "${SKIP_VERIFY:-0}" != "1" ]; then
  mapfile -t PATHS <<<"$ASSET_LIST"
  verify_deploy "$BASE_URL" "${PATHS[@]}"
fi

echo "DONE"
