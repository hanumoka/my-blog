# Quick Reference — my-blog

> 최종 업데이트: 2026-03-29
> 목적: 세션 시작 시 1분 요약
> 읽기 시간: 30초

---

## 프로젝트 개요 (3줄 요약)

**my-blog**는 기술 부채 해소를 위한 학습 가이드 블로그 작성 프로젝트.

**목표**: Docker Swarm / Prisma vs TypeORM / NestJS / Spring+SeaweedFS / Spring+Temporal 주제를 상세하고 쉬운 학습 가이드로 작성.

**현재 상태**: docker-swarm 11편 + prisma-vs-typeorm 7편 + nestjs 15편 완료 (총 33편) — 다음 주제 대기 중

---

## 현재 진행 상태

| 폴더 | 상태 | 완성 |
|------|------|------|
| docker-swarm | 완료 | 11편 |
| prisma-vs-typeorm | 완료 | 7편 |
| nestjs | 완료 | 15편 |
| spring-seaweedfs | 미시작 | 0편 |
| spring-temporal | 미시작 | 0편 |

> 상세: [current-status.md](current-status.md)

---

## Claude Code 설정 요약

| 구분 | 수량 | 내용 |
|------|:----:|------|
| **스킬** | 5개 | blog-session, blog-write, blog-commit, blog-memory-save, blog-troubleshoot |
| **훅** | 6개 | session-start, pre/post-compact, post-failure, notify-done, prompt-context |
| **규칙** | 2개 | blog-writing (glob: **/*.md), known-mistakes |

---

## Quick Links

- [current-status.md](current-status.md) — 주제별 진행 현황
- [topic-backlog.md](../requirements/topic-backlog.md) — 작성 예정 주제
- [CLAUDE.md](../../CLAUDE.md) — 프로젝트 정책
- [.project-memory/context.md](../../.project-memory/context.md) — 세션 컨텍스트

---

## 주요 스킬 명령

| 명령 | 용도 |
|------|------|
| `/blog-session` | 세션 시작 (상태 로드) |
| `/blog-write <주제>` | 블로그 작성 워크플로우 |
| `/blog-memory-save` | 세션 종료 (상태 저장) |
| `/blog-commit` | 커밋 생성 |
| `/blog-troubleshoot` | 트러블슈팅 기록 |

---

**마지막 업데이트**: 2026-03-29 (nestjs 시리즈 15편 완료)
