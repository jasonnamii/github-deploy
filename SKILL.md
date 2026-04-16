---
name: github-deploy
description: |
  GitHub Pages 자동 배포. HTML→works.jasonnamii.com에 Private+검색차단+HTTPS 원스톱. 신규·업데이트·에러복구 자동 분기. scripts/ 기반 결정적 실행.
  P1: 빌드, build, 배포, deploy, 깃허브배포, 퍼블리싱, 웹배포, gh deploy, 깃배포.
  P2: 빌드해, 빌드해줘, 배포해줘, deploy this, 올려줘.
  P3: github pages, web deploy, publish, deployment.
  P5: works.jasonnamii.com으로, 웹으로.
  NOT: 레포관리(→직접), 도메인(→직접), DNS(→직접), 옵시디언(→obsidian-markdown).
---

# GitHub Deploy

**깃허브배포·퍼블리싱·웹배포·깃배포** 범용 엔진. HTML → `works.jasonnamii.com/{레포명}` Private + noindex + HTTPS.

**실행 환경:** 모든 bash는 **DC `start_process`** (로컬 터미널). Cowork 샌드박스엔 `gh auth` 없음.

**원칙:** SKILL.md는 분기·규칙만. 실행은 전부 `scripts/*.sh` 호출. LLM이 bash 생성 금지.

---

## 하드코딩 설정

| 항목 | 값 |
|------|-----|
| GitHub 계정 | `jasonnamii` |
| 커스텀 도메인 | `works.jasonnamii.com` (루트 레포 CNAME 소유, 이미 존재) |
| 공개범위 | **Private** |
| 검색 차단 | `robots.txt` + `<meta noindex>` |
| HTTPS | 강제 |
| 작업 디렉토리 | `/tmp/gh-deploy/{레포명}` |

**{레포명}** ≡ 레포명 ≡ URL 경로 ≡ 작업 디렉토리. 규칙: 소문자+하이픈. 예: `kisas-tf-agenda`

**도메인 구조 (절대 금지):** CNAME은 루트 레포에만. 프로젝트 레포에 CNAME·`cname` 지정 시 루트 도메인 탈취 → 다른 프로젝트 전부 404.

---

## 실행 전 확인 (필수 2가지)

| 항목 | 질문 | 미지정 시 |
|------|------|----------|
| 대상 파일 | "어떤 파일을 배포할까요?" | 직전 작업 HTML |
| 레포명 | "URL 경로는? (예: `kisas-tf-agenda`)" | 파일명 기반 자동 제안 |

---

## 실행 (단일 파이프라인)

> 모든 스크립트는 DC `start_process`로 실행.

### Step 1: 상태 판별 (1회, <2초)

```bash
bash scripts/resolve-state.sh {레포명}
# 출력: NEW | UPDATE | PAGES_OFF | ERRORED
```

| 출력 | 의미 | 다음 |
|------|------|------|
| `NEW` | 레포 없음 | Step 2 (mode=new) |
| `UPDATE` | 레포 + Pages built | Step 2 (mode=update) → Step 3 스킵 가능 (빌드 대기만) |
| `PAGES_OFF` | 레포 있음 + Pages 미활성 | Step 2 (mode=update) + 수동 Pages 활성화 |
| `ERRORED` | Pages 빌드 에러 상태 | Step 3 바로 (재생성 시도) |

### Step 2: 배포 실행

```bash
bash scripts/deploy.sh {레포명} {원본경로} {new|update}
```

진행상황 에코:
```
▶ [0s] [1/5] 작업 디렉토리 준비
✓ [1s] [1/5] 디렉토리 준비 완료
▶ [1s] [2/5] 파일 배치
...
DONE
```

**원본경로:** 단일 `.html` 또는 폴더 모두 지원. 폴더면 `index.html` 루트 존재 필수.

### Step 3: 빌드 대기 (투명 폴링)

```bash
bash scripts/wait-build.sh {레포명} 180
```

매회 `⏳ [경과s/180s] status=building` 에코. 에러 시 재생성 1회 자동(카운터 리셋).

**exit code:**
- `0` → built (성공)
- `1` → timeout (수동 확인 안내)
- `2` → errored 반복 (Pro 플랜 확인 또는 HTTPS 타이밍)

### Step 4: 결과 보고

```
✅ 배포 완료
URL: https://works.jasonnamii.com/{레포명}/  (1~2분 후)
즉시: https://jasonnamii.github.io/{레포명}/
레포: https://github.com/jasonnamii/{레포명} (Private)
```

---

## 에러 대응

| exit | 원인 | 대응 |
|------|------|------|
| `wait-build` =2 | Private + Free 플랜 / HTTPS 타이밍 | Pro 플랜 확인. HTTPS 비활성→built→재활성화 (수동) |
| `deploy` push rejected | remote 선행 커밋 | `cd /tmp/gh-deploy/{레포명} && git pull --rebase && git push` |
| `resolve-state` 반복 실패 | `gh auth` 미로그인 | `gh auth status` 형에게 확인 요청 |

---

## Gotchas

- **CNAME 절대 금지**: 프로젝트 레포엔 CNAME 파일·`cname` 필드 일체 금지. 루트 레포가 소유.
- **작업 경로**: `/tmp/gh-deploy/{레포명}` 고정. Cowork 세션 내 git init은 상위 git과 충돌 위험.
- **멀티파일**: 폴더 배포 시 `index.html` 루트 필수. 없으면 진입점 rename 필요 안내.
- **전파 지연**: 커스텀 도메인은 빌드 후 1~2분. `github.io` 직링크는 즉시.
- **스크립트 수정 금지**: SKILL.md는 호출만. 로직 변경은 `scripts/*.sh`에서. LLM이 매번 bash 생성 = 오타·누락 재발.
- **`gh auth`는 로컬에만**: DC `start_process`(로컬 터미널)에서만 동작. Cowork 샌드박스 Bash ✗.
