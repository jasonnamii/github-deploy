---
name: github-deploy
description: |
  GitHub Pages 자동 배포 (choi 단일). HTML→works.choi.build 루트 레포 서브폴더. Private+noindex+HTTPS. auto-asset·HEAD 검증·레거시 리다이렉트 내장.
    P1: 빌드, build, 배포, deploy, 깃배포, 재배포, redeploy, 최, choi, 리다이렉트, redirect, 마이그레이션, migrate, 내꺼, 형꺼, 최남희.
    P2: 배포해줘, 올려줘, 리다이렉트 걸어줘.
    P3: github pages, web deploy, subdir deploy, legacy redirect.
    P5: works.choi.build으로.
    NOT: 레포관리(→직접), DNS(→직접), jasonnamii·pdkim 신규배포(→deprecated).
---

# GitHub Deploy (choi 단일 도메인)

**깃허브배포·퍼블리싱·웹배포·깃배포** 엔진. HTML → `works.choi.build/{레포명}/` Private + noindex + HTTPS. **1도메인 체제.**

**실행 환경:** 모든 bash는 **DC `start_process`** (로컬 터미널). Cowork 샌드박스엔 `gh auth` 없음.

**원칙:** SKILL.md는 분기·규칙만. 실행은 전부 `scripts/*.sh` 호출. LLM이 bash 생성 금지.

**v2.0 (2026-04-24) — choi 단일체제:** `works.jasonnamii.com`·`works.pdkim.com` **신규 배포 금지**. choi 1택만. 레거시 2도메인은 **경로보존 리다이렉트**로 유지 (`migrate-legacy.sh`). GitHub 계정은 `jasonnamii` 그대로.

**계정·레포 구조 (고정):**
- OWNER = `jasonnamii` (변경 없음 — 모든 레포는 이 계정 하위)
- choi 배포처 = `jasonnamii/works-choi` 루트 레포의 `/{레포명}/`
- 레거시(리다이렉트 전용) = `jasonnamii/works-pdkim`, `jasonnamii/jasonnamii.github.io`

---

## 🚀 라우팅 (1줄 직행)

신규 배포는 **무조건 choi**. 도메인 판별·핑퐁 로직 **없음**.

| 트리거 | 액션 |
|---|---|
| **배포·build·deploy·깃배포·재배포** + 파일/레포명 | choi로 직행 |
| **리다이렉트·마이그레이션** | §레거시 마이그레이션 |
| jasonnamii·pdkim 신규 배포 언급 | "choi 단일 체제로 변경됨. 신규는 choi만. 리다이렉트 필요하면 migrate-legacy.sh" 안내 |

---

## ⚡ 숏서킷 (choi 본류 — 1줄 직행)

**확인 2개만:**
- 대상 파일 (미지정 시 직전 HTML)
- 레포명 = URL 경로 (소문자+하이픈, 예: `kisas-tf-agenda`)

**1줄 실행 (DC start_process):**
```bash
bash scripts/deploy.sh {레포명} {원본경로}
```

- 도메인 파라미터 **제거됨** (choi 고정).
- 원본경로는 **단일 HTML이어도 OK** — auto-asset이 같은 폴더의 `images/` 등 자동 탐지.
- 폴더 배포 원하면 폴더 경로 전달 (index.html 루트 필수).
- 빌드 대기·Pages 활성화 **전부 스킵**. 루트 레포 Pages 이미 활성.
- HEAD 검증 내장 — `✅ 완벽 배포` / `⚠ N건 실패` 자동 출력.

---

## 🪛 Step 0: 재배포 감지 (옵션)

**트리거:** "재배포·업뎃·redeploy" 키워드 + 레포명만 있고 파일 경로 불명.

**1줄 실행 (DC start_process):**
```bash
bash scripts/check-deploy.sh {레포명}
```

**출력 (TSV):**
```
# github-deploy PRE-CHECK: {repo}
DOMAIN   STATUS                     URL                              LAST_COMMIT
choi     SUBDIR_EXISTS|SUBDIR_NEW   https://works.choi.build/{repo}/  2026-04-15T...
```

choi 단일 조회 → 기존 배포면 update, 아니면 new. 파일 경로만 형에게 재확인.

---

## 📦 Auto-Asset + Verify

deploy.sh가 자동 수행:

1. **입력 판정**
   - **폴더 입력** → 통째로 복사
   - **단일 HTML 입력** → auto-asset 스캔

2. **auto-asset 스캔** (단일 HTML만)
   - 대상 속성: `src=`, `href=`, `srcset=`, `poster=`, `data-src=`
   - 제외: 외부 URL, `data:`, `mailto:`, `javascript:`, `#` 앵커
   - 쿼리·해시 제거 후 경로만 사용
   - 원본 HTML과 같은 디렉토리 기준 상대경로 실존 체크
   - src_dir 밖으로 벗어나는 `../` 참조는 무시
   - 누락 파일은 로그만 남기고 배포는 계속

3. **HEAD 검증** (배포 후 자동)
   - 전파 45초 대기 후 `curl -I {BASE_URL}/{경로}` 전량 체크
   - 200이 아니면 경고 + 수동 재확인 URL 출력
   - `SKIP_VERIFY=1 bash scripts/deploy.sh ...` 로 끌 수 있음

**v1 범위 외:** CSS 내부 `url(...)`, inline `<style>` 참조, JS 동적 로딩.

---

## 🔁 레거시 마이그레이션 (jasonnamii·pdkim → choi 리다이렉트)

**목적:** 기존 `works.jasonnamii.com/{repo}/`·`works.pdkim.com/{repo}/` 링크를 유지하면서, 실제 콘텐츠는 `works.choi.build/{repo}/`에서 서빙.

**트리거:** "리다이렉트·마이그레이션·legacy 이관" 키워드.

**실행 (2단계):**

**Step A — choi에 없는 레거시 콘텐츠 복제 (404 방지):**
```bash
bash scripts/migrate-legacy.sh {jasonnamii|pdkim} scan
# 결과: 레거시에만 있고 choi에 없는 {repo} 목록 출력
```
출력된 목록 각각을 choi에 먼저 배포 (수동 또는 자동 루프).

**Step B — 리다이렉트 일괄 적용:**
```bash
bash scripts/migrate-legacy.sh {jasonnamii|pdkim} apply
# 모든 서브폴더 index.html을 리다이렉트 HTML로 교체, 원본은 _archive/ 백업
```

**리다이렉트 HTML 템플릿 (경로 보존):**
```html
<!DOCTYPE html><html><head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=https://works.choi.build{PATH}">
<link rel="canonical" href="https://works.choi.build{PATH}">
<script>location.replace('https://works.choi.build' + location.pathname + location.search + location.hash)</script>
</head><body>이 페이지는 <a href="https://works.choi.build{PATH}">works.choi.build{PATH}</a>로 이동되었습니다.</body></html>
```

**레거시 레포 매핑:**
| 레거시 도메인 | 루트 레포 | 비고 |
|---|---|---|
| `works.jasonnamii.com` | `jasonnamii/jasonnamii.github.io` | User Site. 루트 레포 서브폴더 방식 가정. 다른 구조면 `migrate-legacy.sh scan`이 감지 |
| `works.pdkim.com` | `jasonnamii/works-pdkim` | 루트 레포 서브폴더 |

**DNS 요구사항:** `works.jasonnamii.com`·`works.pdkim.com` CNAME **유지 필수** (최소 3~6개월). DNS 죽으면 리다이렉트도 죽음.

---

## 📋 결과보고

**신규 배포:**
```
✅ 배포 완료 (choi 루트 레포 서브폴더)
메인: https://works.choi.build/{레포명}/   (~1-2분 후)
레포: https://github.com/jasonnamii/works-choi/tree/main/{레포명} (Private)
검증: [verify] 완벽 배포: N/N 리소스 200 OK
```

**리다이렉트 마이그레이션:**
```
✅ 리다이렉트 적용 완료 ({legacy} → choi)
대상 서브폴더: N개
백업 위치: _archive/{repo}/  (원본 보존)
검증: curl HEAD → 302 or meta-refresh 확인
```

---

## ⚠️ 에러 대응

| exit / 증상 | 원인 | 대응 |
|------|------|------|
| `deploy` =3 | 루트 레포 clone 실패 | `gh repo view jasonnamii/works-choi` 확인 |
| push rejected | remote 선행 커밋 | 스크립트 자동 `git pull --rebase` 재시도 |
| `check-deploy.sh` 빈 응답 | `gh auth` 미로그인 | `gh auth status` 형에게 확인 요청 |
| `[verify]` 실패 N건 | 전파 지연 or 진짜 누락 | 1~2분 뒤 BASE_URL 수동 체크. 계속 404면 원본 HTML 참조 경로 불일치 |
| `[auto-asset] MISSING` | HTML 참조는 있는데 파일 없음 | 원본 폴더 파일 누락. HTML 수정 or 파일 추가 후 재배포 |
| `migrate-legacy.sh` scan 결과 없음 | 레거시 레포 서브폴더 구조 아님 | 레포 구조 직접 확인 (User Site일 수도 있음). 수동 이관 필요 |

---

## 🗄️ Deprecated: jasonnamii·pdkim 신규 배포

v2.0부터 신규 배포 **차단**. 리다이렉트 전용.

| 항목 | 상태 |
|------|------|
| SKILL.md choi 이외 호출 | ❌ 차단 |
| `scripts/deploy.sh` domain 파라미터 | ❌ 제거 (choi 고정) |
| `scripts/resolve-state.sh` | ⚠️ 보존 (미호출, 향후 복귀 대비) |
| `scripts/wait-build.sh` | ⚠️ 보존 (미호출) |
| `check-deploy.sh` | ✅ choi 단일 조회로 슬림화 |
| `migrate-legacy.sh` | ✅ 신규 (리다이렉트 전용) |

**복귀 방법 (향후):** deploy.sh에 domain 파라미터 복원 + 라우팅 표에 도메인 트리거 복원.

---

## Gotchas

- **choi 고정** — 신규 배포는 무조건 `works.choi.build/{레포명}/` (최남희=choi=내꺼=형꺼 동의어). 도메인 핑퐁 없음. redirect 대상은 레거시 전용.
- **OWNER = jasonnamii** — 계정은 그대로. 착각 금지.
- **레거시는 리다이렉트만** — jasonnamii·pdkim에 신규 배포 요청 들어오면 거부 + choi 권유.
- **choi는 숏서킷으로** — resolve-state.sh 호출 금지. mode=subdir 고정.
- **Project Site vs User Site**: 다른 레포 콘텐츠를 `works.choi.build/{다른레포}/`에 넣는 건 절대 불가 → 서브폴더 강제.
- **CNAME 금지 (서브폴더)**: choi 서브폴더엔 CNAME 일체 금지. 루트 레포(`works-choi`)에만 있음.
- **작업 경로**: `/tmp/gh-deploy/works-choi` 고정.
- **단일 HTML 입력 OK**: 같은 폴더 자원 자동 동반.
- **폴더 배포 시 `index.html` 루트 필수** — 없으면 Pages 404.
- **auto-asset 한계**: CSS 내부 `url(...)`, 동적 JS 로드, 절대경로는 미지원. 폴더 입력 권장.
- **전파 지연**: HEAD 검증 전 45초 대기. 그래도 404면 추가 1~2분 기다려 재확인.
- **스크립트 수정 금지**: SKILL.md는 호출만. 로직은 `scripts/*.sh`.
- **`gh auth`는 로컬만**: DC `start_process`에서만 동작. Cowork Bash ✗.
- **루트 레포 사전 존재**: `works-choi`는 생성·Pages 활성 완료 전제.
- **HEAD 검증 끄기**: `SKIP_VERIFY=1 bash scripts/deploy.sh ...`
- **레거시 DNS 유지**: `works.jasonnamii.com`·`works.pdkim.com` CNAME은 최소 3~6개월 유지. DNS 죽이면 리다이렉트도 죽음.
- **리다이렉트 적용 전 복제 필수**: choi에 없는 콘텐츠에 리다이렉트 걸면 404. `migrate-legacy.sh scan` → 복제 → `apply` 순서 엄수.
