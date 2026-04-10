# github-deploy

> 🇰🇷 [한국어 README](./README.ko.md)

**One-click GitHub Pages deployment for HTML files.**

## Prerequisites

- **GitHub CLI (`gh`)** — authenticated with push access
- **GitHub Pages** enabled on target repository
- **Claude Cowork or Claude Code** environment

## Goal

github-deploy eliminates deployment friction. Point it at HTML files and it handles everything: repo creation, Pages configuration, custom domain, search engine blocking, and HTTPS enforcement. Result: live site at works.jasonnamii.com with zero manual configuration.

## When & How to Use

Trigger when you have HTML files ready to publish. Creates private repo, configures Pages, binds domain, sets up robots.txt + noindex, enables HTTPS in one step.

## Use Cases

| Scenario | Prompt | What Happens |
|---|---|---|
| Deploy single HTML | `"Deploy this dashboard to works.jasonnamii.com."` | Create private repo→push→enable Pages→domain→privacy→HTTPS→live |
| Deploy portfolio | `"Deploy 5 design comps as portfolio."` | Create repo→push all→Pages→domain→privacy→HTTPS→live |
| Update deployment | `"Redeploy with new version."` | Push updates→Pages auto-rebuilds→site updates |

## Key Features

- One-click deployment — no manual repo/branch/Pages setup
- Private repo by default
- Search engine blocking: robots.txt + meta noindex
- Custom domain auto-binding (works.jasonnamii.com)
- HTTPS enforcement with auto SSL
- Handles HTML, CSS, JS, images, and assets

## Works With

- **[html-div-style](https://github.com/jasonnamii/html-div-style)** — deploy styled HTML
- **[apple-design-style](https://github.com/jasonnamii/apple-design-style)** — deploy Apple-designed HTML
- **[ui-action-designer](https://github.com/jasonnamii/ui-action-designer)** — deploy interactive UI designs

## Installation

```bash
git clone https://github.com/jasonnamii/github-deploy.git ~/.claude/skills/github-deploy
```

## Update

```bash
cd ~/.claude/skills/github-deploy && git pull
```

Skills placed in `~/.claude/skills/` are automatically available in Claude Code and Cowork sessions.

## Part of Cowork Skills

This is one of 25+ custom skills. See the full catalog: [github.com/jasonnamii/cowork-skills](https://github.com/jasonnamii/cowork-skills)

## License

MIT License — feel free to use, modify, and share.
