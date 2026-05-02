---
name: github-deploy
description: |
  GitHub Pages 자동 배포. **디폴트=choi 단일** (works.choi.build 루트 서브폴더). **명시 호출 시 pdkim** (works.pdkim.com 루트 서브폴더). Private+noindex+HTTPS. auto-asset·HEAD 검증·레거시 리다이렉트 내장. **Claude가 DC start_process로 deploy.sh를 무조건 자동 실행** — 1줄 명령 출력·형 맥북 수동 실행 안내 ✗.
    P1: 빌드, build, 배포, deploy, 깃배포, 재배포, redeploy, 자동배포, dc배포, dc로배포, 최, choi, pdkim, 김피디, 리다이렉트, redirect, 마이그레이션, migrate, 내꺼, 형꺼, 최남희, pdkim명시, pdkim으로.
    P2: 배포해줘, 올려줘, 자동으로 배포, dc로 배포, 리다이렉트 걸어줘, pdkim으로 배포해줘.
    P3: github pages, web deploy, subdir deploy, legacy redirect, pdkim mode, auto deploy via DC.
    P5: works.choi.build으로, works.pdkim.com으로.
    NOT: 레포관리(→직접), DNS(→직접), jasonnamii.github.io 신규배포(→deprecated·리다이렉트만).
---

# GitHub Deploy (choi 디폴트 + pdkim 명시 모드 · DC 자동실행)

**깃허브배포·퍼블리싱·웹배포·깃배포** 엔진. 디폴트는 `works.choi.build/{레포명}/`, 명시 호출 시 `works.pdkim.com/{레포명}/`. Private + noindex + HTTPS. **2도메인 체제 (디폴트 1택 + 옵션 1택).**

**🚀 실행 환경 (필독):** 모든 bash는 **Claude가 직접 DC `start_process`로 자동 실행**. `~/github-repos/skill-repos/github-deploy/scripts/deploy.sh`는 형 맥북 zsh 환경에서 `gh auth`·SSH 키·토큰을 그대로 사용. **1줄 명령 출력 후 "형이 맥북 터미널에 붙여넣어 실행" 안내 = FAIL**. 자동 실행이 디폴트, 수동 안내는 폐기.

**원칙:** SKILL.md는 분기·규칙만. 실행은 전부 `scripts/*.sh` 호출. LLM이 bash 본문 생성 ✗ → DC start_process로 스크립트 호출만.

**v2.2 (2026-05-02) — DC 자동실행 전면화:** v2.1의 "샌드박스 직접 push 불가·형이 수동 실행" 정책 폐기. DC start_process는 형 맥북 zsh를 그대로 띄우므로 `gh auth`·SSH·토큰 전부 동작. Claude가 deploy.sh를 **무조건 자동 호출**. 1줄 명령 출력 안내 전면 삭제.

**계정·레포 구조 (고정):**
- OWNER = `jasonnamii`
- choi 배포처 (디폴트) = `jasonnamii/works-choi` 루트 레포의 `/{레포명}/`
- pdkim 배포처 (명시) = `jasonnamii/works-pdkim` 루트 레포의 `/{레포명}/`
- 레거시(리다이렉트 전용) = `jasonnamii/jasonnamii.github.io`
- **스크립트 경로 (형 맥북 표준):** `~/github-repos/skill-repos/github-deploy/scripts/`

---

## 🚀 라우팅 (DC 자동실행 직행)

**디폴트 = choi.** pdkim은 명시 트리거가 있을 때만. **모든 트리거에서 Claude가 즉시 DC start_process 호출.**

| 트리거 | 액션 (Claude 자동) |
|---|---|
| **배포·build·deploy·깃배포·재배포** + 파일/레포명 (도메인 미지정) | DC start_process → `bash ~/github-repos/skill-repos/github-deploy/scripts/deploy.sh {repo} {src}` |
| **"pdkim으로 배포"·"pdkim 모드"·"김피디 배포"·`--mode=pdkim`** | DC start_process → `... deploy.sh {repo} {src} --mode=pdkim` |
| **리다이렉트·마이그레이션** | DC start_process → §레거시 마이그레이션 스크립트 |
| jasonnamii.github.io 신규 배포 언급 | "리다이렉트 전용. choi 또는 pdkim으로." 안내만 (실행 ✗) |

**pdkim 명시 키워드:** `pdkim`, `김피디`, `pdkim으로`, `pdkim 모드`, `works.pdkim.com`, `--mode=pdkim`, `mode=pdkim`. 하나라도 등장하면 pdkim.

---

## ⚡ 숏서킷 (DC 자동실행 1콜)

**확인 2~3개 (없으면 채워서 직행):**
- 대상 파일 (미지정 시 직전 HTML)
- 레포명 = URL 경로 (소문자+하이픈, 예: `kisas-tf-agenda`)
- 모드 (선택, 기본=choi)

**Claude가 호출하는 DC start_process 1콜:**

choi 디폴트:
```
mcp__Desktop_Commander__start_process(
  command='bash -lc "bash ~/github-repos/skill-repos/github-deploy/scripts/deploy.sh {레포명} \"{원본경로}\""',
  timeout_ms=180000
)
```

pdkim 명시:
```
mcp__Desktop_Commander__start_process(
  command='bash -lc "bash ~/github-repos/skill-repos/github-deploy/scripts/deploy.sh {레포명} \"{원본경로}\" --mode=pdkim"',
  timeout_ms=180000
)
```

- 3번째 인자가 없으면 choi 고정.
- 원본경로는 **단일 HTML이어도 OK** — auto-asset이 같은 폴더의 `images/` 등 자동 탐지.
- 폴더 배포 원하면 폴더 경로 전달 (index.html 루트 필수).
- 빌드 대기·Pages 활성화 **전부 스킵**. 두 루트 레포 모두 Pages 이미 활성.
- HEAD 검증 내장 — `✅ 완벽 배포` / `⚠ N건 실패` 자동 출력.
- **출력 끊김 시:** `mcp__Desktop_Commander__read_process_output(pid, timeout_ms=60000)`로 추가 수신.
- **HEAD 검증 폴백:** deploy.sh의 mapfile 에러로 검증부 누락 시 별도 `curl -sI` 1콜로 직접 200 확인.

---

## 🪛 Step 0: 재배포 감지 (옵션)

**트리거:** "재배포·업뎃·redeploy" 키워드 + 레포명만 있고 파일 경로 불명.

**Claude DC 자동 호출:**

choi:
```
mcp__Desktop_Commander__start_process(
  command='bash -lc "bash ~/github-repos/skill-repos/github-deploy/scripts/check-deploy.sh {레포명}"',
  timeout_ms=30000
)
```

pdkim:
```
... check-deploy.sh {레포명} pdkim
```

**출력 (TSV):**
```
# github-deploy PRE-CHECK: {repo}
DOMAIN   STATUS                     URL                              LAST_COMMIT
choi     SUBDIR_EXISTS|SUBDIR_NEW   https://works.choi.build/{repo}/  2026-04-15T...
```

기존 배포면 update, 아니면 new. 파일 경로만 형에게 재확인 후 즉시 deploy.sh DC 호출.

---

## 📦 Auto-Asset + Verify

deploy.sh가 자동 수행 (choi·pdkim 동일):

1. **입력 판정** — 폴더 입력 = 통째 복사 / 단일 HTML = auto-asset 스캔
2. **auto-asset 스캔** (단일 HTML만)
   - 대상: `src=`, `href=`, `srcset=`, `poster=`, `data-src=`
   - 제외: 외부 URL, `data:`, `mailto:`, `javascript:`, `#` 앵커
   - 쿼리·해시 제거 후 경로만 사용
   - 원본 HTML과 같은 디렉토리 기준 상대경로 실존 체크
   - src_dir 밖으로 벗어나는 `../` 참조는 무시
   - 누락 파일은 로그만 남기고 배포는 계속
3. **HEAD 검증** (배포 후 자동)
   - 전파 45초 대기 후 `curl -I {BASE_URL}/{경로}` 전량 체크
   - 200이 아니면 경고 + 수동 재확인 URL 출력
   - `SKIP_VERIFY=1 bash ...` 로 끌 수 있음

**v1 범위 외:** CSS 내부 `url(...)`, inline `<style>` 참조, JS 동적 로딩.

---

## 🔁 레거시 마이그레이션 (jasonnamii.github.io → choi/pdkim 리다이렉트)

**목적:** 기존 `works.jasonnamii.com/{repo}/` 링크 유지, 실제 콘텐츠는 choi/pdkim에서 서빙.

**트리거:** "리다이렉트·마이그레이션·legacy 이관" 키워드.

**Claude DC 자동 호출 (2단계):**

**Step A — 타겟에 없는 레거시 콘텐츠 복제 (404 방지):**
```
mcp__Desktop_Commander__start_process(
  command='bash -lc "bash ~/github-repos/skill-repos/github-deploy/scripts/migrate-legacy.sh jasonnamii scan"',
  timeout_ms=60000
)
```
출력된 목록 각각을 deploy.sh로 choi 또는 pdkim에 먼저 자동 배포.

**Step B — 리다이렉트 일괄 적용:**
```
mcp__Desktop_Commander__start_process(
  command='bash -lc "bash ~/github-repos/skill-repos/github-deploy/scripts/migrate-legacy.sh jasonnamii apply --target=choi"',
  timeout_ms=120000
)
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

**DNS 요구사항:** `works.jasonnamii.com` CNAME **유지 필수** (최소 3~6개월). DNS 죽으면 리다이렉트도 죽음.

---

## 📋 결과보고 (Claude 출력 템플릿)

**신규 배포 (choi):**
```
✅ 배포 완료 (choi 루트 레포 서브폴더 · DC 자동실행)
메인: https://works.choi.build/{레포명}/   (~1-2분 후)
레포: https://github.com/jasonnamii/works-choi/tree/main/{레포명} (Private)
검증: HTTP 200 OK
```

**신규 배포 (pdkim 명시):**
```
✅ 배포 완료 (pdkim 루트 레포 서브폴더 · DC 자동실행)
메인: https://works.pdkim.com/{레포명}/   (~1-2분 후)
레포: https://github.com/jasonnamii/works-pdkim/tree/main/{레포명} (Private)
검증: HTTP 200 OK
```

**리다이렉트 마이그레이션:**
```
✅ 리다이렉트 적용 완료 (jasonnamii.github.io → {target})
대상 서브폴더: N개
백업 위치: _archive/{repo}/  (원본 보존)
검증: curl HEAD → 302 or meta-refresh 확인
```

---

## ⚠️ 에러 대응

| exit / 증상 | 원인 | Claude 자동 대응 |
|------|------|------|
| `deploy` =3 | 루트 레포 clone 실패 | DC로 `gh repo view jasonnamii/works-choi` 자동 점검 |
| push rejected | remote 선행 커밋 | 스크립트 자동 `git pull --rebase` 재시도 |
| `check-deploy.sh` 빈 응답 | `gh auth` 미로그인 | DC로 `gh auth status` 자동 확인, 미로그인 시 형에게 1줄 보고 |
| `[verify]` 실패 N건 | 전파 지연 or 진짜 누락 | 1~2분 뒤 BASE_URL 자동 재체크. 계속 404면 원본 HTML 참조 경로 불일치 보고 |
| `[auto-asset] MISSING` | HTML 참조는 있는데 파일 없음 | 누락 파일 보고. 형 결정(수정 or 추가) 후 재배포 |
| `migrate-legacy.sh` scan 결과 없음 | 레거시 레포 서브폴더 구조 아님 | 레포 구조 자동 점검 후 보고. 수동 이관 필요 시 형에게 알림 |
| **mapfile: command not found** (deploy.sh 검증부) | macOS bash 3.2 한계 | push 자체는 성공. Claude가 별도 `curl -sI` DC 호출로 직접 200 확인 |
| **mode 인자 누락** | choi/pdkim 분기 모호 | 디폴트=choi 적용. pdkim 원하면 `--mode=pdkim` 명시 |

---

## 🗄️ Deprecated: jasonnamii.github.io 신규 배포

v2.0부터 신규 배포 **차단**. 리다이렉트 전용.

| 항목 | 상태 |
|------|------|
| `jasonnamii.github.io` 루트 레포 신규 배포 | ❌ 차단 |
| `scripts/deploy.sh` mode=jasonnamii | ❌ 미지원 |
| `scripts/resolve-state.sh` | ⚠️ 보존 (미호출, 향후 복귀 대비) |
| `scripts/wait-build.sh` | ⚠️ 보존 (미호출) |
| `check-deploy.sh` | ✅ choi/pdkim 분기 조회 |
| `migrate-legacy.sh` | ✅ 활성 (jasonnamii.github.io → choi/pdkim 리다이렉트) |

---

## Gotchas

- **DC start_process 자동실행이 디폴트** — Claude는 무조건 DC로 deploy.sh를 호출. "1줄 명령 출력 + 형이 수동 실행" 안내는 v2.2부터 폐기. 형이 "dc로 배포"·"자동으로"·"바로 배포" 안 적어도 DC 직행.
- **DC = 형 맥북 zsh** — DC start_process는 형 로컬 셸을 그대로 띄움 → `gh auth`·SSH 키·토큰·홈 경로 전부 사용 가능. "샌드박스 토큰 없음" 전제는 v2.1의 오해, v2.2부터 폐기.
- **스크립트 표준 경로** — `~/github-repos/skill-repos/github-deploy/scripts/deploy.sh`. `~/.claude/skills/github-deploy/scripts/`는 미설치 → fallback 금지. 경로 의심 시 DC `find ~ -maxdepth 6 -type f -name "deploy.sh" -path "*github-deploy*"` 1콜로 확인.
- **DC bash 호출 형식** — `command='bash -lc "..."'` 권장 (zsh login 환경 강제로 PATH·gh auth 안정). timeout_ms는 deploy=180000, check=30000, migrate=120000 디폴트.
- **mapfile 에러 = push 성공 신호** — deploy.sh 검증부의 `mapfile`은 macOS bash 3.2에 없음. push는 이미 끝난 상태이므로 Claude가 별도 `curl -sI {URL}` DC 호출로 200 직접 확인하면 끝. 재배포 ✗.
- **HEAD 검증 캐시** — Pages 전파 30~90초. 첫 curl 404여도 1분 더 기다려 재시도. 그래도 404면 폴더 구조·파일명 한글 인코딩 확인.
- **디폴트 = choi**, **명시 = pdkim** — "pdkim·김피디·pdkim으로" 키워드 없으면 무조건 choi. 도메인 핑퐁 ✗.
- **OWNER = jasonnamii** — 두 모드 모두 GitHub 계정은 `jasonnamii`. 착각 금지.
- **레거시는 리다이렉트만** — `jasonnamii.github.io`(works.jasonnamii.com) 신규 배포 요청 = 거부 + choi/pdkim 권유.
- **choi/pdkim은 숏서킷으로** — resolve-state.sh 호출 ✗. mode=subdir 고정.
- **Project Site vs User Site**: 다른 레포 콘텐츠를 `works.choi.build/{다른레포}/`에 넣는 건 절대 불가 → 서브폴더 강제. pdkim도 동일.
- **CNAME 금지 (서브폴더)**: 서브폴더엔 CNAME 일체 금지. 루트 레포(`works-choi`·`works-pdkim`)에만 있음.
- **작업 경로**: choi=`/tmp/gh-deploy/works-choi`, pdkim=`/tmp/gh-deploy/works-pdkim` 분리.
- **단일 HTML 입력 OK**: 같은 폴더 자원 자동 동반 (두 모드 동일).
- **폴더 배포 시 `index.html` 루트 필수** — 없으면 Pages 404.
- **auto-asset 한계**: CSS 내부 `url(...)`, 동적 JS 로드, 절대경로는 미지원. 폴더 입력 권장.
- **전파 지연**: HEAD 검증 전 45초 대기. 그래도 404면 추가 1~2분 기다려 재확인.
- **스크립트 수정 금지**: SKILL.md는 호출만. 로직은 `scripts/*.sh`.
- **HEAD 검증 끄기**: `command='bash -lc "SKIP_VERIFY=1 bash .../deploy.sh ..."'`
- **레거시 DNS 유지**: `works.jasonnamii.com` CNAME 최소 3~6개월 유지.
- **리다이렉트 적용 전 복제 필수**: `migrate-legacy.sh scan` → 복제 → `apply` 순서 엄수.

---

## ✅ WRONG / CORRECT 대조

❌ **WRONG (v2.1 잔재 — 수동 안내):**
```
사용자: "배포해줘"
→ "✅ 형 맥북 터미널에서 1줄 실행:
   bash ~/.claude/skills/github-deploy/scripts/deploy.sh {repo} {src}"
→ (Claude는 실행 ✗, 사용자가 수동 복붙)
```

✅ **CORRECT (v2.2 동작 — DC 자동실행):**
```
사용자: "배포해줘"
→ Claude가 즉시 mcp__Desktop_Commander__start_process로
  bash ~/github-repos/skill-repos/github-deploy/scripts/deploy.sh {repo} {src} 자동 호출
→ 출력 받아서 ✅ 메인 URL · HTTP 200 OK 보고
→ "dc로"·"자동으로" 같은 키워드 형이 안 적어도 직행
```

❌ **WRONG (이중 안내):**
```
DC로 자동 실행 후에도 "수동 실행하려면 ~~~" 같은 백업 안내 추가
→ 정책 혼동, 형 짜증 트리거
```

✅ **CORRECT (단일 경로):**
```
DC start_process 1콜 → 결과 보고. 끝. 수동 안내 ✗.
```
