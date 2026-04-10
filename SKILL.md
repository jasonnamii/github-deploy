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

## 도메인 구조 (필수 이해)

```
works.jasonnamii.com          ← 루트 레포 (CNAME 소유, 빈 페이지, 이미 존재)
├── /kisas-tf-agenda/         ← 프로젝트 레포 A (CNAME 없음)
├── /다른프로젝트/              ← 프로젝트 레포 B (CNAME 없음)
└── ...
```

**핵심: CNAME은 루트 레포(`works.jasonnamii.com`)에만 있다. 프로젝트 레포에 CNAME을 넣으면 도메인 충돌이 발생하므로 절대 금지.**

---

## 신규 배포 vs 업데이트

| 조건 | 경로 |
|------|------|
| 형이 지정한 레포명이 GitHub에 없음 | **신규 배포** |
| 형이 지정한 레포명이 이미 존재 | **업데이트** (push만) |

판별: `gh api repos/jasonnamii/{레포명}` 응답 코드로 자동 판별.

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

로컬 터미널(DC `start_process`)로 형 맥에서 실행한다.

### 1단계: 작업 디렉토리 준비

```bash
cd /tmp && rm -rf {레포명} && mkdir {레포명} && cd {레포명} && git init
```

### 2단계: 파일 배치

대상 HTML을 `index.html`로 복사. **noindex 메타태그가 없으면 삽입.**

```bash
# HTML 복사
python3 -c "import shutil; shutil.copy2('{원본경로}', '/tmp/{레포명}/index.html')"

# noindex 메타태그 확인 + 삽입 (charset 유무 양쪽 대응)
grep -q 'noindex' /tmp/{레포명}/index.html || \
  sed -i '' 's|<head>|<head>\n<meta name="robots" content="noindex, nofollow">|' /tmp/{레포명}/index.html
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

### 5단계: 빌드 대기

```bash
# 빌드 완료까지 폴링 (최대 3회, 30초 간격)
for i in 1 2 3; do
  sleep 30
  STATUS=$(gh api repos/jasonnamii/{레포명}/pages -q '.status')
  [ "$STATUS" = "built" ] && break
done
```

**주의: 프로젝트 레포에는 CNAME을 설정하지 않는다.** HTTPS는 루트 레포의 인증서가 자동 적용된다.

### 6단계: 결과 보고

```
✅ 배포 완료
URL: https://works.jasonnamii.com/{레포명}/
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

# 파일 교체
python3 -c "import shutil; shutil.copy2('{원본경로}', '/tmp/{레포명}/index.html')"

# noindex 확인
grep -q 'noindex' index.html || \
  sed -i '' 's|<head>|<head>\n<meta name="robots" content="noindex, nofollow">|' index.html

git add -A && git commit -m "Update: {레포명}" && git push
```

빌드 완료 확인 후 URL 보고.

---

## 에러 대응

| 에러 | 원인 | 대응 |
|------|------|------|
| `gh: Not Found (404)` on pages | Private 레포 + Free 플랜 | 형에게 Pro 플랜 필요 안내 |
| Pages `errored` 반복 | 빌드 타이밍 이슈 | Pages 삭제 → 재생성 (`DELETE` → `POST`) |
| push rejected | remote 선행 커밋 | `git pull --rebase` 후 재push |
| HTTPS 인증서 미발급 | DNS 전파 미완료 | HTTPS 끄고 빌드 → 완료 후 HTTPS 재활성화 |

---

## Gotchas

- **로컬 터미널 필수**: `gh` CLI는 형 맥에 설치되어 있다. Cowork 샌드박스 Bash가 아닌 로컬 터미널(DC `start_process`)로 실행해야 한다.
- **파일 경로 주의**: Cowork outputs(`/sessions/*/mnt/outputs/`)의 파일은 로컬에서 접근 가능하다. `python3 shutil.copy2`로 복사.
- **레포명 규칙**: 소문자+하이픈만. 한글·공백·밑줄 금지. URL 경로가 되므로 깔끔하게.
- **CNAME은 루트 레포에만**: 프로젝트 레포에 CNAME 파일을 넣거나 `gh api pages -X PUT`에 `cname`을 지정하면 루트 도메인을 뺏어와서 다른 프로젝트 전부 404가 된다. 프로젝트 레포에는 CNAME 관련 설정 일체 금지.
- **`/tmp/` 사용**: git 작업은 `/tmp/`에서 한다. 세션 디렉토리는 git init 시 Cowork 내부 git과 충돌할 수 있다. 로컬 터미널은 `/tmp/` 접근 가능.
- **빌드 errored 루프**: Pages가 errored를 반복하면 DELETE → 재POST가 가장 확실하다. HTTPS 활성화 타이밍에 인증서 미발급이면 errored가 뜨므로, 먼저 HTTPS 없이 빌드 → built 확인 → HTTPS 활성화 순서가 안전하다.
- **전파 지연**: 프로젝트 사이트가 커스텀 도메인 하위 경로에 매핑되는 데 최대 수 분 걸릴 수 있다. `jasonnamii.github.io/{레포명}`으로는 즉시 접속 가능하지만 `works.jasonnamii.com/{레포명}`은 지연될 수 있으므로, 빌드 완료 후 형에게 "1~2분 후 접속 가능"을 안내한다.
