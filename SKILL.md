---
name: github-deploy
description: |
  GitHub Pages 자동 배포. HTML→works.jasonnamii.com/pdkim.com/choi.build 3도메인 라우팅. Private+검색차단+HTTPS 원스톱. choi/pdkim은 루트 레포 서브폴더 자동 배포.
  P1: 빌드, build, 배포, deploy, 깃배포, 제이슨나미, 피디님, 김형석, pdkim, 내꺼, 형꺼, 최남희, 최, choi.
  P2: 배포해줘, 올려줘, deploy this, 피디님으로 배포, 최로 배포, 내꺼로 배포.
  P3: github pages, web deploy, multi-domain routing, subfolder deploy.
  P5: works.jasonnamii.com으로, works.pdkim.com으로, works.choi.build으로.
  NOT: 레포관리(→직접), DNS(→직접), 옵시디언(→obsidian-markdown).
---

# GitHub Deploy

**깃허브배포·퍼블리싱·웹배포·깃배포** 범용 엔진. HTML → `works.{도메인}/{레포명}` Private + noindex + HTTPS. 호출명으로 3도메인 라우팅.

**실행 환경:** 모든 bash는 **DC `start_process`** (로컬 터미널). Cowork 샌드박스엔 `gh auth` 없음.

**원칙:** SKILL.md는 분기·규칙만. 실행은 전부 `scripts/*.sh` 호출. LLM이 bash 생성 금지.

---

## 하드코딩 설정

| 항목 | 값 |
|------|-----|
| GitHub 계정 | `jasonnamii` (단일) |
| 공개범위 | **Private** |
| 검색 차단 | `robots.txt` + `<meta noindex>` |
| HTTPS | 강제 |
| 작업 디렉토리 | `/tmp/gh-deploy/{레포명}` or `/tmp/gh-deploy/{루트레포}` |

**{레포명}** ≡ URL 경로. 규칙: 소문자+하이픈. 예: `kisas-tf-agenda`

---

## 도메인별 배포 구조 (중요)

GitHub Pages는 **계정당 User Site 1개**만 가능. `jasonnamii`가 이미 User Site를 점유했으므로 다른 2개 도메인은 **루트 레포 서브폴더** 방식으로 우회.

| 도메인 | 배포 방식 | 타깃 | 최종 URL |
|--------|----------|------|---------|
| `works.jasonnamii.com` | **User Site + Project Site** | `jasonnamii/{레포명}` (신규 레포) | `works.jasonnamii.com/{레포명}/` |
| `works.choi.build` | **루트 레포 서브폴더** | `jasonnamii/works-choi` 내 `/{레포명}/` 폴더 | `works.choi.build/{레포명}/` |
| `works.pdkim.com` | **루트 레포 서브폴더** | `jasonnamii/works-pdkim` 내 `/{레포명}/` 폴더 | `works.pdkim.com/{레포명}/` |

**왜 다른가:** `works.choi.build`는 `jasonnamii/works-choi` 레포의 Project Site. Project Site는 **자기 레포 내부만** 경로로 노출 가능 → 다른 프로젝트 레포의 콘텐츠는 404. 따라서 `works-choi` **내부에 하위 폴더**를 만들어 배포해야 함.

**CNAME 절대 금지:** CNAME은 각 루트 레포(`works-choi`, `works-pdkim`)에만. 서브폴더엔 CNAME 파일 일체 금지.

---

## 호출명 → 도메인 라우팅

| 호출 트리거 | 메인 도메인 | 배포 방식 |
|---|---|---|
| 제이슨나미·제이슨·jasonnamii·(기본값) | `works.jasonnamii.com` | 신규 프로젝트 레포 |
| 피디님·김형석·pdkim | `works.pdkim.com` | `works-pdkim/{레포명}/` 서브폴더 |
| 내꺼·형꺼·나·내주소·최남희·최·choi | `works.choi.build` | `works-choi/{레포명}/` 서브폴더 |

**판별 로직:** 사용자 최근 발화에서 트리거 스캔 → 첫 매칭 도메인. 복수/미매칭 시 "어느 도메인으로?" 1회 확인. 기본값 = `works.jasonnamii.com`.

---

## 실행 전 확인 (필수 2가지)

| 항목 | 질문 | 미지정 시 |
|------|------|----------|
| 대상 파일 | "어떤 파일을 배포할까요?" | 직전 작업 HTML |
| 레포명 | "URL 경로는? (예: `kisas-tf-agenda`)" | 파일명 기반 자동 제안 |

**도메인 확인 불필요** — 호출명 트리거로 자동 결정.

---

## 실행 (단일 파이프라인)

> 모든 스크립트는 DC `start_process`로 실행.
> **기본 = 비동기 보고** (Step 3 스킵, ~10초 내 완결). `--wait` 지정 시에만 빌드 완료까지 동기 폴링.
> **choi/pdkim 도메인은 Step 3·5 불필요** (루트 레포 기존 Pages 사용 — 빌드 재활성화 없음).

### Step 1: 상태 판별 (1회, <2초)

```bash
bash scripts/resolve-state.sh {레포명} {도메인키}
# 도메인키: jasonnamii | choi | pdkim
# 출력: NEW | UPDATE | PAGES_OFF | ERRORED | SUBDIR
```

| 출력 | 의미 | 다음 |
|------|------|------|
| `SUBDIR` | choi/pdkim 고정 — 루트 레포 서브폴더 모드 | Step 2 (domain=choi\|pdkim) → Step 4 |
| `NEW` | jasonnamii + 레포 없음 | Step 2 (mode=new) → Step 4 |
| `UPDATE` | jasonnamii + 레포 + Pages built | Step 2 (mode=update) → Step 4 |
| `PAGES_OFF` | jasonnamii + 레포 + Pages 미활성 | Step 2 (mode=update) + 수동 Pages 활성화 |
| `ERRORED` | jasonnamii + Pages 빌드 에러 | Step 3 실행 (재생성 시도) |

### Step 2: 배포 실행

```bash
bash scripts/deploy.sh {레포명} {원본경로} {new|update} {도메인키}
# 도메인키: jasonnamii(기본) | choi | pdkim
```

**도메인별 동작:**

- **`jasonnamii`** — `/tmp/gh-deploy/{레포명}` 작업 → `jasonnamii/{레포명}` 레포 생성(new) 또는 push(update) → Pages 활성화
- **`choi`** — `/tmp/gh-deploy/works-choi` clone → `{레포명}/` 서브폴더 교체 → push. Pages 활성화 불필요 (기존 유지)
- **`pdkim`** — `/tmp/gh-deploy/works-pdkim` clone → `{레포명}/` 서브폴더 교체 → push. Pages 활성화 불필요

진행상황 에코:
```
▶ [0s] [1/4 or 1/5] 작업 디렉토리 준비
✓ [1s] ...
DONE
```

**원본경로:** 단일 `.html` 또는 폴더 모두 지원. 폴더면 `index.html` 루트 존재 필수.

### Step 3: 빌드 대기 (jasonnamii 도메인 + 선택 조건만)

choi/pdkim은 스킵 — 기존 루트 레포의 Pages가 이미 활성 상태라 push 후 1-2분 내 자동 재빌드.

**jasonnamii 기본은 스킵.** 아래 조건에서만 실행:

| 조건 | 처리 |
|------|------|
| 사용자가 `--wait` 명시 | `bash scripts/wait-build.sh {레포명} 180` |
| `resolve-state` = `ERRORED` | 재생성 필요. 강제 Step 3 |
| 첫 배포(NEW) 후 빌드 검증 요청 | 사용자 요청 시에만 |

**exit code:** `0`=built · `1`=timeout · `2`=errored 반복

### Step 4: 결과 보고 (즉시)

**jasonnamii 도메인 예시:**
```
✅ 배포 요청 완료 (빌드 백그라운드 진행)
메인: https://works.jasonnamii.com/{레포명}/   (~1-2분 후)
대체: https://jasonnamii.github.io/{레포명}/  (~30초 후)
레포: https://github.com/jasonnamii/{레포명} (Private)
```

**choi/pdkim 도메인 예시:**
```
✅ 배포 완료 (루트 레포 서브폴더)
메인: https://works.choi.build/{레포명}/   (~1-2분 후)
레포: https://github.com/jasonnamii/works-choi/tree/main/{레포명} (Private)
```

---

## 에러 대응

| exit | 원인 | 대응 |
|------|------|------|
| `deploy` exit=3 | 루트 레포(works-choi/works-pdkim) clone 실패 | 루트 레포 존재·권한 확인. `gh repo view jasonnamii/works-choi` |
| `wait-build` =2 | Private + Free 플랜 / HTTPS 타이밍 | Pro 플랜 확인. HTTPS 비활성→built→재활성화 (수동) |
| `deploy` push rejected | remote 선행 커밋 | 스크립트가 자동 `git pull --rebase && git push` 재시도 |
| `resolve-state` 반복 실패 | `gh auth` 미로그인 | `gh auth status` 형에게 확인 요청 |

---

## Gotchas

- **Project Site vs User Site**: `jasonnamii.github.io`만 User Site. `works-choi`·`works-pdkim`은 Project Site → **자기 레포 내부 경로만** 노출. 다른 레포 콘텐츠를 `works.choi.build/{다른레포}/` 경로로 넣는 건 **절대 불가능** → 서브폴더 방식 강제.
- **CNAME 절대 금지 (서브폴더)**: choi/pdkim 서브폴더엔 CNAME 일체 금지. 루트 레포가 소유.
- **작업 경로**: `/tmp/gh-deploy/{레포명|루트레포}` 고정. Cowork 세션 내 git init은 상위 git과 충돌 위험.
- **멀티파일**: 폴더 배포 시 `index.html` 루트 필수. 없으면 진입점 rename 필요 안내.
- **전파 지연**: 커스텀 도메인은 빌드 후 1~2분. `github.io` 직링크는 즉시.
- **스크립트 수정 금지**: SKILL.md는 호출만. 로직 변경은 `scripts/*.sh`에서.
- **`gh auth`는 로컬에만**: DC `start_process`(로컬 터미널)에서만 동작. Cowork 샌드박스 Bash ✗.
- **루트 레포 사전 존재 필수**: `works-choi`, `works-pdkim`은 이미 생성·Pages 활성화 상태여야 함. 신규 계정 최초 1회 수동 세팅 필요.
