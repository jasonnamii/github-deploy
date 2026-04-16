#!/usr/bin/env bash
# deploy.sh — 신규/업데이트 통합 배포
# usage: bash deploy.sh {repo} {src_path} {mode: new|update}
#   src_path: 단일 html 또는 폴더
set -eu

REPO="${1:?repo required}"
SRC="${2:?src path required}"
MODE="${3:?mode required: new|update}"
OWNER="jasonnamii"
WORK="/tmp/gh-deploy/${REPO}"
T0=$(date +%s)

say() { echo "▶ [$(($(date +%s)-T0))s] $*"; }
ok()  { echo "✓ [$(($(date +%s)-T0))s] $*"; }

# 1) 작업 디렉토리
say "[1/5] 작업 디렉토리 준비 (${WORK})"
rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"

if [ "$MODE" = "update" ]; then
  say "[1/5] 기존 레포 clone"
  gh repo clone "${OWNER}/${REPO}" "$WORK" >/dev/null 2>&1
else
  mkdir -p "$WORK"
  (cd "$WORK" && git init -q -b main)
fi
ok "[1/5] 디렉토리 준비 완료"

# 2) 파일 배치
say "[2/5] 파일 배치 ($SRC → $WORK)"
python3 - "$SRC" "$WORK" <<'PY'
import sys, shutil, os
src, dst = sys.argv[1], sys.argv[2]
if os.path.isdir(src):
    shutil.copytree(src, dst, dirs_exist_ok=True)
else:
    shutil.copy2(src, os.path.join(dst, "index.html"))
PY

# 3) noindex + robots.txt
say "[3/5] noindex 메타태그 + robots.txt"
python3 - "$WORK" <<'PY'
import os
work = __import__('sys').argv[1]
idx = os.path.join(work, "index.html")
if os.path.exists(idx):
    t = open(idx, encoding='utf-8').read()
    if 'noindex' not in t:
        t = t.replace('<head>', '<head>\n<meta name="robots" content="noindex, nofollow">', 1)
        open(idx, 'w', encoding='utf-8').write(t)
open(os.path.join(work, 'robots.txt'), 'w').write("User-agent: *\nDisallow: /\n")
PY
ok "[3/5] 메타태그·robots.txt 완료"

# 4) 커밋 + push/생성
cd "$WORK"
say "[4/5] git 커밋 + ${MODE}"
git add -A >/dev/null
if git diff --cached --quiet; then
  ok "[4/5] 변경사항 없음 — push 생략"
else
  git -c user.email="deploy@local" -c user.name="deploy" \
      commit -q -m "Deploy: ${REPO} ($(date +%Y-%m-%d))" || true
  if [ "$MODE" = "new" ]; then
    gh repo create "$REPO" --private --source=. --push >/dev/null 2>&1
  else
    git push -q
  fi
  ok "[4/5] push 완료"
fi

# 5) Pages 활성화 (신규만)
if [ "$MODE" = "new" ]; then
  say "[5/5] GitHub Pages 활성화"
  gh api "repos/${OWNER}/${REPO}/pages" -X POST --input - >/dev/null 2>&1 <<EOF
{"build_type":"legacy","source":{"branch":"main","path":"/"}}
EOF
  ok "[5/5] Pages 활성화 완료"
fi

echo "DONE"
