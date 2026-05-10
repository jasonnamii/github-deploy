#!/usr/bin/env python3
"""
_helper.py — github-deploy 공용 Python 헬퍼 (v2.5 신설)

목적: deploy.sh의 inline heredoc 5개(cache_read·cache_sha·update_cache·
       stage_source·inject_noindex)를 단일 모듈로 통합.
효과: heredoc cold start 5회 × ~50ms → 단일 -m 호출 1회 ~50ms.
       deploy.sh 라인 -60줄, 유지보수 1소스.

usage:
  python3 _helper.py cache_read   <CACHE_FILE> <REPO> <MODE>
  python3 _helper.py cache_sha    <CACHE_FILE> <REPO> <MODE>
  python3 _helper.py update_cache <CACHE_FILE> <REPO> <MODE> <BASE_URL> <KIND> <SHA>
  python3 _helper.py stage_source <SRC> <DST>          # auto-asset 탐지+복사
  python3 _helper.py inject_noindex <TARGET_DIR>
"""
import sys, os, json, shutil, re, html
from datetime import datetime, timezone
from urllib.parse import urlparse, unquote


# ----------------------------------------------------------------
# CACHE I/O
# ----------------------------------------------------------------
def cache_read(path, repo, mode):
    """캐시 hit 시 url, miss 시 빈 문자열."""
    try:
        cache = json.load(open(path))
        key = f"{mode}:{repo}"
        if key in cache:
            print(cache[key].get("url", ""))
    except Exception:
        pass


def cache_sha(path, repo, mode):
    """캐시 hit 시 last_sha256, miss 시 빈 문자열."""
    try:
        cache = json.load(open(path))
        key = f"{mode}:{repo}"
        print(cache.get(key, {}).get("last_sha256", ""))
    except Exception:
        pass


def update_cache(path, repo, mode, url, kind, sha):
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


# ----------------------------------------------------------------
# AUTO-ASSET (단일 HTML 또는 폴더 → 동반 자원 복사)
# ----------------------------------------------------------------
def _is_external(ref):
    if not ref:
        return True
    if ref.startswith(('#', 'javascript:', 'mailto:', 'tel:', 'data:')):
        return True
    if ref.startswith(('http://', 'https://', '//')):
        return True
    return False


def stage_source(src, dst):
    os.makedirs(dst, exist_ok=True)

    # 폴더 입력 = 통째 복사
    if os.path.isdir(src):
        shutil.copytree(src, dst, dirs_exist_ok=True)
        for root, _, files in os.walk(dst):
            for f in files:
                rel = os.path.relpath(os.path.join(root, f), dst)
                print(rel)
        return

    if not os.path.isfile(src):
        print(f"ERROR: src not found: {src}", file=sys.stderr)
        sys.exit(10)

    # 단일 HTML or 단일 자산
    is_html = src.lower().endswith(('.html', '.htm'))
    dst_file = os.path.join(dst, 'index.html' if is_html else os.path.basename(src))
    shutil.copy2(src, dst_file)
    print(os.path.relpath(dst_file, dst))

    if not is_html:
        return

    # auto-asset 스캔
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
                if not url or _is_external(url):
                    continue
                clean = urlparse(url)
                path = unquote(clean.path)
                if not path:
                    continue
                refs.add(path)

    copied, missing = [], []
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


# ----------------------------------------------------------------
# NOINDEX 메타 주입
# ----------------------------------------------------------------
def inject_noindex(target):
    idx = os.path.join(target, "index.html")
    if os.path.exists(idx):
        t = open(idx, encoding='utf-8').read()
        if 'noindex' not in t:
            t = t.replace('<head>', '<head>\n<meta name="robots" content="noindex, nofollow">', 1)
            open(idx, 'w', encoding='utf-8').write(t)


# ----------------------------------------------------------------
# CLI dispatch
# ----------------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1]
    args = sys.argv[2:]
    fn = {
        "cache_read":    lambda: cache_read(*args[:3]),
        "cache_sha":     lambda: cache_sha(*args[:3]),
        "update_cache":  lambda: update_cache(*args[:6]),
        "stage_source":  lambda: stage_source(*args[:2]),
        "inject_noindex": lambda: inject_noindex(*args[:1]),
    }.get(cmd)
    if fn is None:
        print(f"unknown cmd: {cmd}", file=sys.stderr)
        sys.exit(2)
    fn()


if __name__ == "__main__":
    main()
