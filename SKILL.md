---
name: github-deploy
description: |
  GitHub Pages 자동 배포 (choi·pdkim 2도메인 전용). HTML→works.choi.build / works.pdkim.com 루트 레포 서브폴더. Private+noindex+HTTPS. 단일 HTML 입력 시 images·css·js 동반 자원 자동 복사 + 배포 후 HEAD 검증 내장. **맥가이버 PRE-CHECK**: 배포 전 2도메인 병렬 조회로 기존 이력 자동감지.
    P1: 빌드, build, 배포, deploy, 깃배포, 재배포, redeploy, 피디님, 김형석, pdkim, 내꺼, 형꺼, 최남희, 최, choi.
    P2: 배포해줘, 올려줘, 업뎃해줘, deploy this, 피디님으로 배포, 최로 배포, 내꺼로 배포.
    P3: github pages, web deploy, subdir deploy, auto asset bundling, pre-check, deploy history.
    P5: works.pdkim.com으로, works.choi.build으로.
    NOT: 레포관리(→직접), DNS(→직접), 옵시디언(→obsidian-markdown), jasonnamii 도메인(→deprecated).
---

# GitHub Deploy (choi·pdkim 전용)

**깃허브배포·퍼블리싱·웹배포·깃배포** 엔진. HTML → `works.{choi.build|pdkim.com}/{레포명}/` Private + noindex + HTTPS. **2도메인 2택 체제.**

**실행 환경:** 모든 bash는 **DC `start_process`** (로컬 터미널). Cowork 샌드박스엔 `gh auth` 없음.

**원칙:** SKILL.md는 분기·규칙만. 실행은 전부 `scripts/*.sh` 호출. LLM이 bash 생성 금지.

**v1.1 (2026-04-23):** 단일 HTML 입력 시 `<img src>·<link href>·<script src>` 상대경로 자원 자동 동반. 배포 후 `curl HEAD` 전량 200 확인.

**v1.2 (2026-04-24) — 맥가이버 PRE-CHECK:** "깃배포" 발화 시 Step 0에서 `check-deploy.sh`로 2도메인 병렬 조회 → 기존 배포 자동 감지. 새 세션·기억 유실 대응.

**v1.3 (2026-04-24) — jasonnamii 폐지:** `works.jasonnamii.com` 도메인 배포 **금지**. choi/pdkim 2택만. 구 jasonnamii 로직은 `scripts/` 내부에 남아있지만 호출하지 않음 (향후 복귀 대비 보존). 선택 모호 시 반드시 핑퐁 1회.

---

## 🪛 Step 0: 맥가이버 PRE-CHECK (최우선 — "깃배포" 발화 즉시)

**트리거:** 레포명·파일명은 있는데 **도메인(choi/pdkim) 구분 안 줬을 때**. 또는 "재배포·업뎃·redeploy" 키워드. 또는 새 세션에서 "그거 다시 배포".

**1줄 실행 (DC start_process):**
```bash
bash scripts/check-deploy.sh {레포명}
```

**출력 (TSV):**
```
# github-deploy PRE-CHECK: {repo}
DOMAIN   STATUS                     URL                              LAST_COMMIT
choi     SUBDIR_EXISTS|SUBDIR_NEW   https://works.choi.build/{repo}/  2026-04-15T...
pdkim    SUBDIR_EXISTS|SUBDIR_NEW   https://works.pdkim.com/{repo}/   -
```

**자동 분기 규칙:**

| 결과 | 처리 |
|------|------|
| **1개 도메인만 기존 배포** | 해당 도메인으로 자동 UPDATE. 보고 후 즉시 배포 실행 |
| **2개 도메인 모두 기존 배포** | 형에게 1회 핑퐁: "choi·pdkim 중 어느 쪽 갱신?" |
| **전부 NEW** | 형에게 1회 핑퐁: "choi·pdkim 중 어디로 신규 배포?" (**기본값 없음**) |
| **레포명 불명** | 파일명 기반 추정 (예: `report.html` → `report`) 후 핑퐁 |

**속도:** gh api 2회 병렬 → 1~2초.

**스킵 조건:**
- 형이 도메인·레포명 둘 다 명시 (`"피디님으로 kisas-agenda 배포"`) → Step 0 생략
- 연속 턴에서 방금 배포한 레포 재배포 → Step 0 생략

---

## 🚀 라우팅 (Step 0 이후 — 이 표만 보고 분기)

| 호출 트리거 | domain 키 | 경로 |
|---|---|---|
| **피디님·김형석·pdkim** | `pdkim` | §숏서킷 |
| **내꺼·형꺼·나·내주소·최남희·최·choi** | `choi` | §숏서킷 |
| 미매칭·모호 | — | **핑퐁 1회 강제** (choi/pdkim 중 택1) |

**판별:** 최근 발화 트리거 스캔 → 첫 매칭. 복수/미매칭 시 핑퐁. **기본값 없음.** jasonnamii 트리거 감지 시 "현재 jasonnamii 배포는 중단됨. choi/pdkim 중 택1" 안내.

---

## ⚡ 숏서킷 (choi·pdkim 본류 — 1줄 직행)

choi/pdkim은 **상태판별 불필요**(항상 루트 레포 서브폴더 모드). resolve-state.sh 호출 **금지**.

**확인 2개만:**
- 대상 파일 (미지정 시 직전 HTML)
- 레포명 = URL 경로 (소문자+하이픈, 예: `kisas-tf-agenda`)

**1줄 실행 (DC start_process):**
```bash
bash scripts/deploy.sh {레포명} {원본경로} subdir {choi|pdkim}
```

- mode는 **항상 `subdir`** 고정. new/update 판단 ✗.
- 원본경로는 **단일 HTML이어도 OK** — auto-asset이 같은 폴더의 `images/` 등 자동 탐지.
- 폴더 배포 원하면 폴더 경로 전달 (index.html 루트 필수).
- 빌드 대기·Pages 활성화 **전부 스킵**. 루트 레포 Pages 이미 활성.
- HEAD 검증 내장 — `✅ 완벽 배포` / `⚠ N건 실패` 자동 출력.

**판정 순서:**
1. 도메인 트리거 매칭 → choi or pdkim 확정
2. 파일·레포명 확인 → deploy.sh 1회 호출 → 결과보고 → 종료

---

## 📦 Auto-Asset + Verify (v1.1 내장)

deploy.sh가 subdir 경로에서 자동 수행:

1. **입력 판정**
   - **폴더 입력** → 통째로 복사 (기존 동작)
   - **단일 HTML 입력** → auto-asset 스캔

2. **auto-asset 스캔** (단일 HTML만)
   - 대상 속성: `src=`, `href=`, `srcset=`, `poster=`, `data-src=`
   - 제외: 외부 URL(`http://`, `https://`, `//`), `data:`, `mailto:`, `javascript:`, `#` 앵커
   - 쿼리·해시 제거 후 경로만 사용
   - 원본 HTML과 **같은 디렉토리** 기준 상대경로 실존 체크
   - 실존 파일·폴더만 스테이지에 동일 상대경로로 복사
   - src_dir 밖으로 벗어나는 `../` 참조는 보안상 무시
   - 누락 파일은 로그만 남기고 배포는 계속

3. **HEAD 검증** (배포 후 자동)
   - 전파 45초 대기 후 `curl -I {BASE_URL}/{경로}` 전량 체크
   - 200이 아니면 경고 + 수동 재확인 URL 출력
   - `SKIP_VERIFY=1 bash scripts/deploy.sh ...` 로 끌 수 있음

**v1 범위 외:** CSS 내부 `url(...)`, inline `<style>` 참조, JS 동적 로딩.

---

## 📦 도메인 구조 (참고)

choi·pdkim은 **루트 레포 서브폴더 방식**. Project Site는 자기 레포 내부만 경로 노출 → 다른 레포 콘텐츠는 404. 따라서 `works-choi`·`works-pdkim` 루트 레포 내부 하위폴더에 강제 배치.

| 도메인 | 루트 레포 | 최종 URL |
|--------|----------|---------|
| `works.choi.build` | `jasonnamii/works-choi` 내 `/{레포명}/` | `works.choi.build/{레포명}/` |
| `works.pdkim.com` | `jasonnamii/works-pdkim` 내 `/{레포명}/` | `works.pdkim.com/{레포명}/` |

**CNAME 절대 금지:** 루트 레포(`works-choi`·`works-pdkim`)에만 있음. 서브폴더엔 일체 금지.

---

## 📋 결과보고

```
✅ 배포 완료 (루트 레포 서브폴더)
메인: https://works.{choi.build|pdkim.com}/{레포명}/   (~1-2분 후)
레포: https://github.com/jasonnamii/works-{choi|pdkim}/tree/main/{레포명} (Private)
검증: [verify] 완벽 배포: N/N 리소스 200 OK
```

---

## ⚠️ 에러 대응

| exit / 증상 | 원인 | 대응 |
|------|------|------|
| `deploy` =3 | 루트 레포 clone 실패 | `gh repo view jasonnamii/works-{choi\|pdkim}` 확인 |
| push rejected | remote 선행 커밋 | 스크립트 자동 `git pull --rebase` 재시도 |
| `check-deploy.sh` 빈 응답 | `gh auth` 미로그인 | `gh auth status` 형에게 확인 요청 |
| `[verify]` 실패 N건 | 전파 지연 or 진짜 누락 | 1~2분 뒤 BASE_URL 수동 체크. 계속 404면 원본 HTML 참조 경로 불일치 |
| `[auto-asset] MISSING` | HTML 참조는 있는데 파일 없음 | 원본 폴더 파일 누락. HTML 수정 or 파일 추가 후 재배포 |

---

## 🗄️ Deprecated: jasonnamii 도메인 (v1.3부터 차단)

`works.jasonnamii.com` 배포는 **중단**. 관련 로직 상태:

| 항목 | 상태 |
|------|------|
| SKILL.md 호출 | ❌ 차단 |
| `scripts/deploy.sh` 내부 `mode=new/update` 로직 | ✅ 보존 (복귀 대비) |
| `scripts/resolve-state.sh` jasonnamii 분기 | ✅ 보존 |
| `scripts/wait-build.sh` | ✅ 보존 |
| `check-deploy.sh` jasonnamii 조회 | ❌ 제거 |

**복귀 방법 (향후 필요 시):** 이 섹션 제거 + 라우팅 표에 jasonnamii 복원 + check-deploy.sh에 jasonnamii 블록 재추가.

---

## Gotchas

- **jasonnamii 배포 금지** — v1.3부터 차단. 트리거 감지 시 choi/pdkim 핑퐁으로 유도.
- **기본값 없음** — 도메인 모호 시 반드시 핑퐁 1회. 임의 배정 금지.
- **choi/pdkim은 숏서킷으로** — resolve-state.sh 호출 금지. mode=subdir 고정.
- **Project Site vs User Site**: 다른 레포 콘텐츠를 `works.choi.build/{다른레포}/`에 넣는 건 절대 불가 → 서브폴더 강제.
- **CNAME 금지 (서브폴더)**: choi/pdkim 서브폴더엔 CNAME 일체 금지.
- **작업 경로**: `/tmp/gh-deploy/works-{choi|pdkim}` 고정.
- **단일 HTML 입력 OK**: v1.1부터 같은 폴더 자원 자동 동반.
- **폴더 배포 시 `index.html` 루트 필수** — 없으면 Pages 404.
- **auto-asset 한계**: CSS 내부 `url(...)`, 동적 JS 로드, 절대경로는 미지원. 폴더 입력 권장.
- **전파 지연**: HEAD 검증 전 45초 대기. 그래도 404면 추가 1~2분 기다려 재확인.
- **스크립트 수정 금지**: SKILL.md는 호출만. 로직은 `scripts/*.sh`.
- **`gh auth`는 로컬만**: DC `start_process`에서만 동작. Cowork Bash ✗.
- **루트 레포 사전 존재**: `works-choi`·`works-pdkim`은 생성·Pages 활성 완료 전제.
- **HEAD 검증 끄기**: `SKIP_VERIFY=1 bash scripts/deploy.sh ...`
- **맥가이버 Step 0 건너뛰기**: 도메인·레포명 둘 다 명확하면 스킵. 하나라도 모호하면 `check-deploy.sh` 1회.
- **check-deploy.sh exit 코드**: `0`=기존 배포 1개+ 발견 · `1`=전부 신규.
