---
name: github-deploy
description: |
  GitHub Pages 자동 배포. HTML→works.jasonnamii.com에 Private+검색차단+HTTPS 원스톱 배포·업데이트.
  P1: 빌드, build, 배포, deploy, 깃허브배포, 퍼블리싱, 웹배포.
  P2: 빌드해, 빌드해줘, 배포해줘, deploy this.
  P3: github pages, web deploy, publish.
  P5: works.jasonnamii.com으로.
  NOT: 레포관리(→직접), 도메인(→직접), DNS(→직접).
---

<!-- Trigger Conditions
P1: 빌드, build, 배포, deploy, 깃허브배포, 퍼블리싱, 웹배포.
P2: 빌드해, 빌드해줘, 배포해줘, deploy this.
P3: github pages, web deploy, publish.
P5: works.jasonnamii.com으로, 웹으로.
NOT: 깃허브 레포 관리(→직접수행), 도메인 구매(→직접수행), DNS 설정(→직접수행), 옵시디언 문서(→obsidian-markdown).
-->

# GitHub Deploy

HTML 파일을 `works.jasonnamii.com/{레포명}`에 배포한다. Private 레포 + 검색 차단 + HTTPS 강제.

---

## 하드코딩 설정

| 항목 | 값 | 변경 불가 |
|------|-----|----------|
| GitHub 계정 | `jasonnamii` | ✓ |
| 커스텀 도메인 | `works.jasonnamii.com` | ✓ |
| 루트 레포 | `works.jasonnamii.com` (CNAME 소유, 이미 존재) | ✓ |
| 레포 공개범위 | **Private** | ✓ |
| 검색 차단 | robots.txt `Disallow: /` + `<meta name="robots" content="noindex, nofollow">` | ✓ |
| HTTPS | 강제 (`https_enforced: true`) | ✓ |
| 실행 환경 | **DC `start_process`** (로컬 터미널). Cowork 샌드박스에 `gh auth` 없어서 실패 | ✓ |

**{레포명}** ≡ GitHub 리포지토리명 ≡ URL 경로 ≡ 로컬 작업 디렉토리명. 규칙: 소문자+하이픈만. 예: `kisas-tf-agenda`

## 도메인 구조 (필수 이해)

```
works.jasonnamii.com          ← 루트 레포 (CNAME 소유, 빈 페이지, 이미 존재)
├── /kisas-tf-agenda/         ← 프로젝트 레포 A (CNAME 없음)
├── /다른프로젝트/              ← 프로젝트 레포 B (CNAME 없음)
└── ...
```

**핵심: CNAME은 루트 레포(`works.jasonnamii.com`)에만 있다. 프로젝트 레포에 CNAME을 넣으면 도메인 충돌이 발생하므로 절대 금지.**

---

## 배포 경로 판별

| 조건 | 경로 |
|------|------|
| 레포가 GitHub에 없음 | **신규 배포** (전 절차) |
| 레포 존재 + Pages 활성 | **업데이트** (push만) |
| 레포 존재 + Pages 미활성 | **Pages 활성화 후 업데이트** (4단계부터 합류) |

판별:
```bash
# 1차: 레포 존재 확인
gh api repos/jasonnamii/{레포명} 2>/dev/null
# 404 → 신규 배포

# 2차: Pages 상태 확인 (레포 존재 시)
gh api repos/jasonnamii/{레포명}/pages 2>/dev/null
# 404 → Pages 미활성 → 4단계(Pages 활성화)부터 실행 후 업데이트
# 200 → 업데이트
```

---

## 실행 전 확인 (필수)

형에게 반드시 확인하는 2가지:

| 항목 | 질문 | 미지정 시 |
|------|------|----------|
| 대상 파일 | "어떤 파일을 배포할까요?" | 직전 작업 HTML 사용 |
| 레포명(=URL 경로) | "URL 경로를 어떻게 할까요? (예: `kisas-tf-agenda`)" | 파일명 기반 자동 제안 |

URL 규칙: `works.jasonnamii.com/{프로젝트명-업무1뎁스-업무2뎁스}`

---

## 신규 배포 절차

> **모든 bash 명령은 DC `start_process`로 실행한다.** (하드코딩 설정 §실행 환경 참조)

### 1단계: 작업 디렉토리 준비

```bash
cd /tmp && rm -rf {레포명} && mkdir {레포명} && cd {레포명} && git init
```

### 2단계: 파일 배치

대상 HTML을 `index.html`로 복사. **noindex 메타태그가 없으면 삽입.**

```bash
# HTML 복사 (단일 파일)
python3 -c "import shutil; shutil.copy2('{원본경로}', '/tmp/{레포명}/index.html')"

# 멀티파일(CSS/JS/이미지 포함 폴더)인 경우:
# python3 -c "import shutil; shutil.copytree('{원본폴더}', '/tmp/{레포명}', dirs_exist_ok=True)"

# noindex 메타태그 확인 + 삽입 (python3로 통일 — BSD/GNU sed 호환 문제 회피)
python3 -c "
p = '/tmp/{레포명}/index.html'
t = open(p).read()
if 'noindex' not in t:
    t = t.replace('<head>', '<head>\n<meta name=\"robots\" content=\"noindex, nofollow\">', 1)
    open(p, 'w').write(t)
"
```

robots.txt 생성 (**CNAME은 넣지 않는다** — 루트 레포가 소유):

```bash
echo -e "User-agent: *\nDisallow: /" > robots.txt
```

### 3단계: 레포 생성 + push

```bash
git add -A
git commit -m "Deploy: {레포명}"
gh repo create {레포명} --private --source=. --push
```

### 4단계: Pages 활성화

```bash
gh api repos/jasonnamii/{레포명}/pages -X POST --input - <<'EOF'
{"build_type":"legacy","source":{"branch":"main","path":"/"}}
EOF
```

### 5단계: 빌드 대기 + 자동 복구

**적응형 폴링:** 초회 10초 → 2회 20초 → 3회 40초 → 4회 60초 (최대 4회, 총 대기 ~130초). max_wait = 180초. 초과 시 '빌드 지연' 보고 + 수동 확인 안내. 고정 5회×20초 → 적응형으로 교체.

```bash
# 빌드 완료까지 폴링 (적응형 간격)
BUILD_OK=false
INTERVALS=(10 20 40 60)  # 초회 10초, 이후 20초, 40초, 60초
for i in "${!INTERVALS[@]}"; do
  sleep "${INTERVALS[$i]}"
  STATUS=$(gh api repos/jasonnamii/{레포명}/pages -q '.status')
  if [ "$STATUS" = "built" ]; then
    BUILD_OK=true
    break
  elif [ "$STATUS" = "errored" ]; then
    echo "⚠️ Pages errored — DELETE → 재생성 시도"
    gh api repos/jasonnamii/{레포명}/pages -X DELETE
    sleep 5
    gh api repos/jasonnamii/{레포명}/pages -X POST --input - <<'RETRY'
{"build_type":"legacy","source":{"branch":"main","path":"/"}}
RETRY
    # 재생성 후 폴링 계속
  fi
done

if [ "$BUILD_OK" = false ]; then
  echo "❌ 빌드 미완료 (status: $STATUS). 형에게 수동 확인 요청."
fi
```

**주의: 프로젝트 레포에는 CNAME을 설정하지 않는다.** HTTPS는 루트 레포의 인증서가 자동 적용된다.

### 6단계: 결과 보고

```
✅ 배포 완료
URL: https://works.jasonnamii.com/{레포명}/ (1~2분 후 접속 가능, github.io는 즉시)
레포: https://github.com/jasonnamii/{레포명} (Private)
검색차단: robots.txt + noindex
HTTPS: 강제
```

---

## 업데이트 절차

기존 레포에 파일만 갱신한다.

```bash
cd /tmp && rm -rf {레포명}
gh repo clone jasonnamii/{레포명} /tmp/{레포명}
cd /tmp/{레포명}

# 파일 교체 (단일 파일)
python3 -c "import shutil; shutil.copy2('{원본경로}', '/tmp/{레포명}/index.html')"

# 멀티파일인 경우:
# python3 -c "import shutil; shutil.copytree('{원본폴더}', '/tmp/{레포명}', dirs_exist_ok=True)"

# noindex 확인 + 삽입 (python3 통일)
python3 -c "
p = '/tmp/{레포명}/index.html'
t = open(p).read()
if 'noindex' not in t:
    t = t.replace('<head>', '<head>\n<meta name=\"robots\" content=\"noindex, nofollow\">', 1)
    open(p, 'w').write(t)
"

git add -A && git commit -m "Update: {레포명}" && git push
```

빌드 완료 확인(5단계 폴링 로직 동일 적용) 후 URL 보고.

---

## 에러 대응

| 에러 | 원인 | 대응 |
|------|------|------|
| `gh: Not Found (404)` on pages | Private 레포 + Free 플랜 | 형에게 Pro 플랜 필요 안내 |
| Pages `errored` 반복 | 빌드 타이밍 / HTTPS 인증서 미발급 | Pages 삭제 → 재생성 (`DELETE` → `POST`). HTTPS 타이밍이면: HTTPS 비활성 → 빌드 → built 확인 → HTTPS 재활성화 |
| push rejected | remote 선행 커밋 | `git pull --rebase` 후 재push |

---

## Gotchas

- **파일 경로 주의**: Cowork outputs(`/sessions/*/mnt/outputs/`)의 파일은 로컬에서 접근 가능하다. `python3 shutil.copy2`로 복사.
- **CNAME은 루트 레포에만**: 프로젝트 레포에 CNAME 파일을 넣거나 `gh api pages -X PUT`에 `cname`을 지정하면 루트 도메인을 뺏어와서 다른 프로젝트 전부 404가 된다. 프로젝트 레포에는 CNAME 관련 설정 일체 금지.
- **`/tmp/` 사용**: git 작업은 `/tmp/`에서 한다. 세션 디렉토리는 git init 시 Cowork 내부 git과 충돌할 수 있다.
- **전파 지연**: `works.jasonnamii.com/{레포명}`은 빌드 후 최대 수 분 걸릴 수 있다. `jasonnamii.github.io/{레포명}`은 즉시 접속 가능. 빌드 완료 후 형에게 "1~2분 후 접속 가능" 안내.
- **멀티파일 배포**: CSS/JS/이미지가 분리된 프로젝트는 `shutil.copytree`로 폴더째 복사. `index.html`이 루트에 있는지 반드시 확인. 없으면 형에게 진입점 파일 확인 후 rename.
