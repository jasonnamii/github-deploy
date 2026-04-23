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
set -eu

REPO="${1:?repo required}"
SRC="${2:?src path required}"
MODE="${3:?mode required: new|update}"
DOMAIN="${4:-jasonnamii}"
OWNER="jasonnamii"
T0=$(date +%s)

say() { echo "▶ [$(($(date +%s)-T0))s] $*"; }
ok()  { echo "✓ [$(($(date +%s)-T0))s] $*"; }

# 도메인 → 배포 방식 결정
case "$DOMAIN" in
  choi)
    ROOT_REPO="works-choi"
    WORK="/tmp/gh-deploy/${ROOT_REPO}"
    SUBDIR_MODE=1
    ;;
  pdkim)
    ROOT_REPO="works-pdkim"
    WORK="/tmp/gh-deploy/${ROOT_REPO}"
    SUBDIR_MODE=1
    ;;
  jasonnamii|*)
    ROOT_REPO=""
    WORK="/tmp/gh-deploy/${REPO}"
    SUBDIR_MODE=0
    ;;
esac

# ===============================================================
# SUBDIR_MODE=1 경로: 루트 레포에 서브폴더로 배포 (choi/pdkim)
# ===============================================================
if [ "$SUBDIR_MODE" = "1" ]; then
  say "[1/4] 루트 레포 준비 (${OWNER}/${ROOT_REPO})"
  rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"
  gh repo clone "${OWNER}/${ROOT_REPO}" "$WORK" >/dev/null 2>&1 || {
    echo "✗ 루트 레포 clone 실패: ${OWNER}/${ROOT_REPO}"
    echo "   루트 레포가 존재하고 gh auth가 유효한지 확인"
    exit 3
  }
  ok "[1/4] 루트 레포 clone 완료"

  # 기존 서브폴더 정리 후 새로 생성
  TARGET="${WORK}/${REPO}"
  say "[2/4] 서브폴더 배치 ($SRC → ${REPO}/)"
  rm -rf "$TARGET"
  mkdir -p "$TARGET"
  python3 - "$SRC" "$TARGET" <<'PY'
import sys, shutil, os
src, dst = sys.argv[1], sys.argv[2]
if os.path.isdir(src):
    shutil.copytree(src, dst, dirs_exist_ok=True)
else:
    shutil.copy2(src, os.path.join(dst, "index.html"))
PY
  ok "[2/4] 파일 배치 완료"

  # noindex + robots.txt (서브폴더 index.html만)
  say "[3/4] noindex 메타태그 주입"
  python3 - "$TARGET" <<'PY'
import os, sys
target = sys.argv[1]
idx = os.path.join(target, "index.html")
if os.path.exists(idx):
    t = open(idx, encoding='utf-8').read()
    if 'noindex' not in t:
        t = t.replace('<head>', '<head>\n<meta name="robots" content="noindex, nofollow">', 1)
        open(idx, 'w', encoding='utf-8').write(t)
PY
  ok "[3/4] 메타태그 주입 완료"

  # 커밋 + push
  cd "$WORK"
  say "[4/4] git 커밋 + push"
  git add -A >/dev/null
  if git diff --cached --quiet; then
    ok "[4/4] 변경사항 없음 — push 생략"
  else
    git -c user.email="deploy@local" -c user.name="deploy" \
        commit -q -m "Deploy ${REPO} → ${ROOT_REPO}/ ($(date +%Y-%m-%d))" || true
    git push -q || {
      echo "⚠ push 충돌 — rebase 후 재시도"
      git pull --rebase -q && git push -q
    }
    ok "[4/4] push 완료"
  fi

  echo "DONE"
  exit 0
fi

# ===============================================================
# SUBDIR_MODE=0 경로: 개별 프로젝트 레포 (jasonnamii) — 기존 로직
# ===============================================================

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
