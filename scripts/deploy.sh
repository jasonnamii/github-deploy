#!/usr/bin/env bash
# deploy.sh — 신규/업데이트/서브디렉토리 통합 배포 (도메인별 분기)
# usage: bash deploy.sh {repo} {src_path} {mode: new|update|subdir} {domain: jasonnamii|choi|pdkim}
#   src_path: 단일 html 또는 폴더
#   mode:
#     - new|update: jasonnamii 전용 (레포 생성·갱신 분기)
#     - subdir:     choi/pdkim 전용 — SUBDIR_MODE=1 자동. new/update 무관.
#   domain:
#     - jasonnamii: 개별 프로젝트 레포 (jasonnamii/{repo}) — User Site 구조
#     - choi:       루트 레포 서브폴더 (jasonnamii/works-choi/{repo}/)
#     - pdkim:      루트 레포 서브폴더 (jasonnamii/works-pdkim/{repo}/)
# 주의: choi/pdkim은 mode 값 무시 — SUBDIR_MODE=1 자동 진입. mode=subdir 권장.
#
# [v1.1] 단일 HTML 입력 시 같은 폴더의 상대경로 참조 자원(images/·css/·js/· 등)
#        자동 탐지·동반 복사. HTML만 올라가고 이미지 404 되는 사고 방지.
set -eu

REPO="${1:?repo required}"
SRC="${2:?src path required}"
MODE="${3:?mode required: new|update|subdir}"
DOMAIN="${4:-jasonnamii}"
OWNER="jasonnamii"
T0=$(date +%s)

say() { echo "▶ [$(($(date +%s)-T0))s] $*"; }
ok()  { echo "✓ [$(($(date +%s)-T0))s] $*"; }
warn(){ echo "⚠ [$(($(date +%s)-T0))s] $*"; }

# 도메인 → 배포 방식 결정
case "$DOMAIN" in
  choi)
    ROOT_REPO="works-choi"
    WORK="/tmp/gh-deploy/${ROOT_REPO}"
    SUBDIR_MODE=1
    BASE_URL="https://works.choi.build/${REPO}"
    ;;
  pdkim)
    ROOT_REPO="works-pdkim"
    WORK="/tmp/gh-deploy/${ROOT_REPO}"
    SUBDIR_MODE=1
    BASE_URL="https://works.pdkim.com/${REPO}"
    ;;
  jasonnamii|*)
    ROOT_REPO=""
    WORK="/tmp/gh-deploy/${REPO}"
    SUBDIR_MODE=0
    BASE_URL="https://jasonnamii.github.io/${REPO}"
    ;;
esac

# ---------------------------------------------------------------
# 공통: 단일 HTML → 동반 자원 자동 복사 (auto-asset)
# 폴더 입력이면 통째로 복사. 단일 HTML이면 참조 스캔 + 실존 파일 동반 복사.
# 리턴(stdout): 복사된 자산 상대경로 목록 (HEAD 검증용)
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

def copied_assets_log(paths):
    """스캔 리포트를 stderr에 출력 (stdout은 복사 목록 전용)."""
    for p in paths:
        print(f"  + {p}", file=sys.stderr)

if os.path.isdir(src):
    # 폴더 입력 — 통째로 복사 (기존 동작)
    shutil.copytree(src, dst, dirs_exist_ok=True)
    # 복사된 파일 목록 stdout
    for root, _, files in os.walk(dst):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), dst)
            print(rel)
    sys.exit(0)

# 단일 파일 입력
if not os.path.isfile(src):
    print(f"ERROR: src not found: {src}", file=sys.stderr)
    sys.exit(10)

# HTML이면 index.html로 리네임, 그 외 확장자는 원본명 유지
is_html = src.lower().endswith(('.html', '.htm'))
if is_html:
    dst_file = os.path.join(dst, 'index.html')
else:
    dst_file = os.path.join(dst, os.path.basename(src))
shutil.copy2(src, dst_file)
print(os.path.relpath(dst_file, dst))

if not is_html:
    sys.exit(0)

# HTML 참조 스캔
src_dir = os.path.dirname(os.path.abspath(src))
with open(dst_file, encoding='utf-8', errors='replace') as f:
    text = f.read()

# src=, href=, srcset= 속성에서 URL 추출
# (CSS url(...), inline script 는 v1 범위 외)
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
        # srcset은 쉼표로 여러 URL
        for piece in val.split(','):
            url = piece.strip().split()[0] if piece.strip() else ''
            if not url or is_external(url):
                continue
            # 절대경로(/...) 는 v1에서 보존하되 실존 체크는 src_dir 기준 상대로도 시도
            # 쿼리·해시 제거
            clean = urlparse(url)
            path = unquote(clean.path)
            if not path:
                continue
            refs.add(path)

# 실존 파일만 복사
copied = []
missing = []
for ref in sorted(refs):
    # 절대경로("/images/...") → 맨 앞 / 제거해서 src_dir 기준 시도
    candidate_rel = ref.lstrip('/')
    abs_src = os.path.normpath(os.path.join(src_dir, candidate_rel))

    # src_dir 밖으로 탈출 방지 (../../ 공격 방지)
    if not abs_src.startswith(os.path.abspath(src_dir)):
        print(f"  ! 경로이탈 무시: {ref}", file=sys.stderr)
        continue

    if not os.path.exists(abs_src):
        missing.append(ref)
        continue

    # dst 내부 동일 상대경로에 복사
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

# stderr 리포트
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
# 공통: noindex 주입 (대상 index.html만)
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
# 공통: 배포 후 HEAD 검증 (루프 하드캡 1회)
# ---------------------------------------------------------------
verify_deploy() {
  local base="$1"; shift
  local -a paths=("$@")
  local fail=0 ok_count=0
  say "[verify] HEAD 체크 시작 (전파 대기 45s)"
  sleep 45
  for p in "${paths[@]}"; do
    # 공백·특수문자 포함 가능 → URL 인코딩은 생략, curl -g 로 글로브 해제
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
# SUBDIR_MODE=1 경로: 루트 레포에 서브폴더로 배포 (choi/pdkim)
# ===============================================================
if [ "$SUBDIR_MODE" = "1" ]; then
  say "[1/5] 루트 레포 준비 (${OWNER}/${ROOT_REPO})"
  rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"
  gh repo clone "${OWNER}/${ROOT_REPO}" "$WORK" >/dev/null 2>&1 || {
    echo "✗ 루트 레포 clone 실패: ${OWNER}/${ROOT_REPO}"
    echo "   루트 레포가 존재하고 gh auth가 유효한지 확인"
    exit 3
  }
  ok "[1/5] 루트 레포 clone 완료"

  TARGET="${WORK}/${REPO}"
  say "[2/5] 서브폴더 배치 ($SRC → ${REPO}/) + 동반 자원 자동 탐지"
  rm -rf "$TARGET"
  ASSET_LIST=$(stage_source "$SRC" "$TARGET")
  ok "[2/5] 파일 배치 완료 ($(echo "$ASSET_LIST" | wc -l | tr -d ' ')개 파일)"

  say "[3/5] noindex 메타태그 주입"
  inject_noindex "$TARGET"
  ok "[3/5] 메타태그 주입 완료"

  cd "$WORK"
  say "[4/5] git 커밋 + push"
  git add -A >/dev/null
  if git diff --cached --quiet; then
    ok "[4/5] 변경사항 없음 — push 생략"
  else
    git -c user.email="deploy@local" -c user.name="deploy" \
        commit -q -m "Deploy ${REPO} → ${ROOT_REPO}/ ($(date +%Y-%m-%d))" || true
    git push -q || {
      warn "push 충돌 — rebase 후 재시도"
      git pull --rebase -q && git push -q
    }
    ok "[4/5] push 완료"
  fi

  # HEAD 검증 (--skip-verify 없을 때만)
  if [ "${SKIP_VERIFY:-0}" != "1" ]; then
    # 배열로 변환
    mapfile -t PATHS <<<"$ASSET_LIST"
    verify_deploy "$BASE_URL" "${PATHS[@]}"
  fi

  echo "DONE"
  exit 0
fi

# ===============================================================
# SUBDIR_MODE=0 경로: 개별 프로젝트 레포 (jasonnamii)
# ===============================================================

say "[1/6] 작업 디렉토리 준비 (${WORK})"
rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"

if [ "$MODE" = "update" ]; then
  say "[1/6] 기존 레포 clone"
  gh repo clone "${OWNER}/${REPO}" "$WORK" >/dev/null 2>&1
else
  mkdir -p "$WORK"
  (cd "$WORK" && git init -q -b main)
fi
ok "[1/6] 디렉토리 준비 완료"

say "[2/6] 파일 배치 ($SRC → $WORK) + 동반 자원 자동 탐지"
ASSET_LIST=$(stage_source "$SRC" "$WORK")
ok "[2/6] 배치 완료 ($(echo "$ASSET_LIST" | wc -l | tr -d ' ')개 파일)"

say "[3/6] noindex 메타태그 + robots.txt"
inject_noindex "$WORK"
printf "User-agent: *\nDisallow: /\n" > "$WORK/robots.txt"
ok "[3/6] 메타태그·robots.txt 완료"

cd "$WORK"
say "[4/6] git 커밋 + ${MODE}"
git add -A >/dev/null
if git diff --cached --quiet; then
  ok "[4/6] 변경사항 없음 — push 생략"
else
  git -c user.email="deploy@local" -c user.name="deploy" \
      commit -q -m "Deploy: ${REPO} ($(date +%Y-%m-%d))" || true
  if [ "$MODE" = "new" ]; then
    gh repo create "$REPO" --private --source=. --push >/dev/null 2>&1
  else
    git push -q
  fi
  ok "[4/6] push 완료"
fi

if [ "$MODE" = "new" ]; then
  say "[5/6] GitHub Pages 활성화"
  gh api "repos/${OWNER}/${REPO}/pages" -X POST --input - >/dev/null 2>&1 <<EOF
{"build_type":"legacy","source":{"branch":"main","path":"/"}}
EOF
  ok "[5/6] Pages 활성화 완료"
fi

# HEAD 검증 (jasonnamii는 github.io 직링크 사용 — 전파 빠름)
if [ "${SKIP_VERIFY:-0}" != "1" ]; then
  say "[6/6] HEAD 검증 (github.io 직링크)"
  mapfile -t PATHS <<<"$ASSET_LIST"
  verify_deploy "$BASE_URL" "${PATHS[@]}"
fi

echo "DONE"
