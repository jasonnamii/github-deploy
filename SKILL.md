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

## 🚀 라우팅 (최우선 — 이 표만 보고 분기)

| 호출 트리거 | domain 키 | 경로 |
|---|---|---|
| **피디님·김형석·pdkim** | `pdkim` | **숏서킷** (아래 §숏서킷) |
| **내꺼·형꺼·나·내주소·최남희·최·choi** | `choi` | **숏서킷** (아래 §숏서킷) |
| 제이슨나미·제이슨·jasonnamii·(기본값) | `jasonnamii` | §일반 플로우 (Step 1~5) |

**판별:** 최근 발화 트리거 스캔 → 첫 매칭. 복수/미매칭 시 1회 확인. 기본값 = `jasonnamii`.

---

## ⚡ 숏서킷 (choi·pdkim 전용 — Step 1 스킵, 1줄 직행)

choi/pdkim은 **상태판별 불필요**(항상 루트 레포 서브폴더 모드). resolve-state.sh 호출 **금지**.

**확인 2개만:**
- 대상 파일 (미지정 시 직전 HTML)
- 레포명 = URL 경로 (소문자+하이픈, 예: `kisas-tf-agenda`)

**1줄 실행 (DC start_process):**
```bash
bash scripts/deploy.sh {레포명} {원본경로} subdir {choi|pdkim}
```

- mode는 **항상 `subdir`** 고정. new/update 판단 ✗.
- Step 3(wait-build)·Step 5(Pages 활성화) **전부 스킵**. 루트 레포 Pages 이미 활성.
- 완료 즉시 §결과보고 choi/pdkim 예시로 출력.

**판정 순서:**
1. domain 트리거 매칭 → `choi` or `pdkim`이면 → **즉시 이 섹션으로 점프, 아래 §일반 플로우 읽지 말 것**
2. 파일·레포명 확인 → deploy.sh 1회 호출 → 결과보고 → 종료

---

## 📘 일반 플로우 (jasonnamii 전용)

### 하드코딩 설정

| 항목 | 값 |
|------|-----|
| GitHub 계정 | `jasonnamii` (단일) |
| 공개범위 | **Private** |
| 검색 차단 | `robots.txt` + `<meta noindex>` |
| HTTPS | 강제 |
| 작업 디렉토리 | `/tmp/gh-deploy/{레포명}` |

**{레포명}** ≡ URL 경로. 규칙: 소문자+하이픈.

### Step 1: 상태 판별

```bash
bash scripts/resolve-state.sh {레포명} jasonnamii
# 출력: NEW | UPDATE | PAGES_OFF | ERRORED
```

| 출력 | 의미 | 다음 |
|------|------|------|
| `NEW` | 레포 없음 | Step 2 (mode=new) |
| `UPDATE` | 레포 + Pages built | Step 2 (mode=update) |
| `PAGES_OFF` | 레포 + Pages 미활성 | Step 2 (mode=update) + 수동 활성화 |
| `ERRORED` | Pages 빌드 에러 | Step 3 강제 (재생성) |

### Step 2: 배포 실행

```bash
bash scripts/deploy.sh {레포명} {원본경로} {new|update} jasonnamii
```

진행상황 에코 `▶ [0s] [1/5] ...` → `DONE`. 원본경로: 단일 `.html` 또는 폴더(index.html 루트 필수).

### Step 3: 빌드 대기 (기본 스킵)

아래 조건에서만 실행:

| 조건 | 처리 |
|------|------|
| `--wait` 명시 | `bash scripts/wait-build.sh {레포명} 180` |
| `ERRORED` | 강제 실행 |
| NEW 후 검증 요청 | 사용자 요청 시 |

exit: `0`=built · `1`=timeout · `2`=errored

---

## 📦 도메인별 배포 구조 (참고)

GitHub Pages는 **계정당 User Site 1개**만 가능. `jasonnamii`가 User Site 점유 → 나머지 2개는 **루트 레포 서브폴더** 우회.

| 도메인 | 방식 | 타깃 | 최종 URL |
|--------|------|------|---------|
| `works.jasonnamii.com` | Project Site | `jasonnamii/{레포명}` | `works.jasonnamii.com/{레포명}/` |
| `works.choi.build` | 루트 서브폴더 | `jasonnamii/works-choi` 내 `/{레포명}/` | `works.choi.build/{레포명}/` |
| `works.pdkim.com` | 루트 서브폴더 | `jasonnamii/works-pdkim` 내 `/{레포명}/` | `works.pdkim.com/{레포명}/` |

**왜 서브폴더:** Project Site는 자기 레포 내부만 경로 노출 → 다른 레포 콘텐츠는 404. `works-choi` 내부 하위폴더로 강제.

**CNAME 절대 금지:** 루트 레포(`works-choi`, `works-pdkim`)에만. 서브폴더엔 CNAME 일체 금지.

---

## 📋 결과보고

**jasonnamii:**
```
✅ 배포 요청 완료 (빌드 백그라운드 진행)
메인: https://works.jasonnamii.com/{레포명}/   (~1-2분 후)
대체: https://jasonnamii.github.io/{레포명}/  (~30초 후)
레포: https://github.com/jasonnamii/{레포명} (Private)
```

**choi/pdkim:**
```
✅ 배포 완료 (루트 레포 서브폴더)
메인: https://works.{choi.build|pdkim.com}/{레포명}/   (~1-2분 후)
레포: https://github.com/jasonnamii/works-{choi|pdkim}/tree/main/{레포명} (Private)
```

---

## ⚠️ 에러 대응

| exit | 원인 | 대응 |
|------|------|------|
| `deploy` =3 | 루트 레포 clone 실패 | `gh repo view jasonnamii/works-{choi\|pdkim}` 확인 |
| `wait-build` =2 | Private+Free / HTTPS 타이밍 | Pro 확인. HTTPS 비활성→built→재활성 |
| push rejected | remote 선행 커밋 | 스크립트 자동 `git pull --rebase` 재시도 |
| `resolve-state` 반복실패 | `gh auth` 미로그인 | `gh auth status` 형에게 확인 요청 |

---

## Gotchas

- **choi/pdkim은 숏서킷으로** — resolve-state.sh 호출 금지. mode=subdir 고정. new/update 판단 ✗.
- **Project Site vs User Site**: `jasonnamii.github.io`만 User Site. 다른 레포 콘텐츠를 `works.choi.build/{다른레포}/`에 넣는 건 **절대 불가** → 서브폴더 강제.
- **CNAME 금지 (서브폴더)**: choi/pdkim 서브폴더엔 CNAME 일체 금지.
- **작업 경로**: `/tmp/gh-deploy/{레포|루트레포}` 고정. Cowork 세션 내 git init은 상위 git 충돌 위험.
- **멀티파일**: 폴더 배포 시 `index.html` 루트 필수.
- **전파 지연**: 커스텀 도메인 1~2분. `github.io` 직링크 즉시.
- **스크립트 수정 금지**: SKILL.md는 호출만. 로직은 `scripts/*.sh`.
- **`gh auth`는 로컬만**: DC `start_process`에서만 동작. Cowork Bash ✗.
- **루트 레포 사전 존재**: `works-choi`, `works-pdkim`은 생성·Pages 활성 완료 전제.
