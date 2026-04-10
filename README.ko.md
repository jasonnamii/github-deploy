# GitHub Pages 자동 배포

> 🇺🇸 [English README](./README.md)

**HTML 파일을 GitHub Pages에 원클릭으로 배포합니다.**

## 사전 요구사항

- **GitHub CLI (`gh`)** — push 권한을 가진 인증된 상태
- **GitHub Pages** — 대상 저장소에서 활성화됨
- **Claude Cowork 또는 Claude Code** 환경

## 목적

github-deploy는 배포의 복잡함을 없앱니다. HTML 파일을 지정하면 저장소 생성, Pages 설정, 커스텀 도메인, 검색 엔진 차단, HTTPS 강제화를 모두 처리합니다. 결과: works.jasonnamii.com에 라이브 사이트가 배포되며 수동 설정은 전혀 필요 없습니다.

## 사용 시점 및 방법

HTML 파일을 공개할 준비가 되었을 때 발동합니다. Private 저장소 생성, Pages 설정, 도메인 연결, robots.txt + noindex 설정, HTTPS 강제화를 한 번에 처리합니다.

## 사용 예시

| 상황 | 프롬프트 | 결과 |
|---|---|---|
| 단일 HTML 배포 | `"이 대시보드를 works.jasonnamii.com에 배포해줘."` | Private 저장소 생성→push→Pages 활성화→도메인→프라이버시→HTTPS→라이브 |
| 포트폴리오 배포 | `"5개 디자인 컴프를 포트폴리오로 배포해줘."` | 저장소 생성→모두 push→Pages→도메인→프라이버시→HTTPS→라이브 |
| 배포 업데이트 | `"새 버전으로 다시 배포해줘."` | 업데이트 push→Pages 자동 재구성→사이트 업데이트 |

## 핵심 기능

- 원클릭 배포 — 수동 저장소/브랜치/Pages 설정 불필요
- Private 저장소 기본값
- 검색 엔진 차단: robots.txt + meta noindex
- 커스텀 도메인 자동 연결 (works.jasonnamii.com)
- 자동 SSL을 통한 HTTPS 강제화
- HTML, CSS, JS, 이미지 및 자산 모두 지원

## 연관 스킬

- **[html-div-style](https://github.com/jasonnamii/html-div-style)** — 스타일이 적용된 HTML 배포
- **[apple-design-style](https://github.com/jasonnamii/apple-design-style)** — Apple 디자인 HTML 배포
- **[ui-action-designer](https://github.com/jasonnamii/ui-action-designer)** — 인터랙티브 UI 디자인 배포

## 설치

```bash
git clone https://github.com/jasonnamii/github-deploy.git ~/.claude/skills/github-deploy
```

## 업데이트

```bash
cd ~/.claude/skills/github-deploy && git pull
```

`~/.claude/skills/`에 배치된 스킬은 Claude Code 및 Cowork 세션에서 자동으로 사용할 수 있습니다.

## Cowork 스킬 생태계

25개 이상의 커스텀 스킬 중 하나입니다. 전체 카탈로그: [github.com/jasonnamii/cowork-skills](https://github.com/jasonnamii/cowork-skills)

## 라이선스

MIT 라이선스 — 자유롭게 사용, 수정, 공유하세요.