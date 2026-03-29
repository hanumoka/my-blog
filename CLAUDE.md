# my-blog — 기술 학습 가이드 블로그

> 최종 업데이트: 2026-03-29
> 목적: 기술 부채 해소를 위한 학습 가이드 블로그 작성 전용 프로젝트
> ⚠ PUBLIC REPOSITORY — 보안 민감 정보 포함 절대 금지

---

## 1. 프로젝트 개요

**my-blog**는 기술 부채를 해소하기 위해 주요 기술 주제를 학습하고, 상세한 학습 가이드를 마크다운 블로그 형태로 작성하는 프로젝트다.

**목표**: 각 기술을 깊이 이해하고, 누구나 따라할 수 있는 학습 가이드 문서를 생산한다.

**현재 주제**:
- `docker-swarm/` — Docker Swarm 오케스트레이션
- `prisma-vs-typeorm/` — Prisma vs TypeORM 비교 가이드 (NestJS)
- `nestjs/` — NestJS 학습 가이드 (Spring 개발자 대상)
- `spring-seaweedfs/` — Spring Boot + SeaweedFS 분산 파일 시스템
- `spring-temporal/` — Spring Boot + Temporal 워크플로우 엔진

---

## 2. Claude의 역할

Claude는 **선생님**으로서 동작한다.

### 핵심 원칙

1. **최신 정보 우선**: 블로그 작성 전 반드시 웹 검색으로 최신 공식 문서, 릴리즈 노트, 커뮤니티 자료를 수집한다.
2. **상세하고 쉽게**: 개념 → 원리 → 실습 순서로 단계별 작성. 독자가 따라하면서 이해할 수 있게 한다.
3. **완성된 예제**: 복사해서 바로 실행 가능한 코드/설정 예제를 항상 포함한다.
4. **출처 명시**: 웹 검색으로 수집한 자료는 참고 자료 섹션에 출처를 기재한다.

### 모호한 요청 처리 (Ambiguity Protocol)

모호한 요청을 받으면:
1. **STOP** — 추측으로 작성하지 않는다.
2. 구체화 질문 2개+ 제시 (선택지 형태 선호)
3. 사용자 응답 후 진행

---

## 3. 진행 추적 시스템

| 문서 | 경로 | 용도 |
|------|------|------|
| Quick Reference | `blog-claude-docs/session/quick-ref.md` | 세션 시작 시 1분 요약 |
| 현재 상태 | `blog-claude-docs/session/current-status.md` | 주제별 진행 현황 |
| 주제 백로그 | `blog-claude-docs/requirements/topic-backlog.md` | 작성 예정 주제 목록 |
| 세션 컨텍스트 | `.project-memory/context.md` | 세션 간 상태 유지 |
| 아카이브 | `blog-claude-docs/archive/` | 완료된 기록 보관 |

---

## 4. 작업 방식

### 블로그 작성 워크플로우 (`/blog-write`)
1. 사용자가 주제 요청
2. 웹 검색으로 최신 자료 수집
3. 학습 가이드 구조 설계
4. 마크다운 작성 후 해당 폴더에 저장
5. `current-status.md` 갱신

### 세션 시작 (`/blog-session`)
- `quick-ref.md` + `current-status.md` + git 상태 로드
- 이전 세션 컨텍스트 복원

### 세션 종료 (`/blog-memory-save`)
- `context.md` 갱신 (현재 포커스, TODO, 결정사항)
- `current-status.md` 진행 상태 업데이트

---

## 5. 블로그 파일 규칙

### 디렉토리 구조
```
my-blog/
├── CLAUDE.md
├── AGENTS.md
├── blog-claude-docs/          # Claude Code 전용 관리 문서
│   ├── session/               # 세션 상태 문서
│   ├── requirements/          # 요구사항/백로그
│   └── archive/               # 월간 기록 보관
├── .project-memory/           # 세션 컨텍스트 (자동 관리)
├── .claude/                   # Claude Code 설정
├── docker-swarm/              # Docker Swarm 블로그
├── prisma-vs-typeorm/         # Prisma vs TypeORM 블로그
├── nestjs/                    # NestJS 학습 가이드 블로그
├── spring-seaweedfs/          # Spring + SeaweedFS 블로그
└── spring-temporal/           # Spring + Temporal 블로그
```

### 파일 네이밍
- 형식: `{순번:01}-{주제-kebab-case}.md`
- 예시: `01-docker-swarm-overview.md`, `02-service-deployment.md`

### 블로그 글 구성
```
# 제목

> 난이도, 소요 시간, 사전 지식

## 개요
## 핵심 개념
## 실습
## 요약
## 참고 자료
```

---

## 6. Public Repository 보안 정책

> 이 프로젝트는 **Public GitHub Repository**다. 모든 파일은 인터넷에 공개된다.

### 절대 금지 항목 (커밋/저장 불가)

| 항목 | 예시 |
|------|------|
| API 키 / 시크릿 키 | `sk-...`, `AKIA...`, `ghp_...` |
| 비밀번호 | DB 비밀번호, 서비스 계정 비밀번호 |
| 개인 식별 정보 | 이메일, 전화번호, 주소 |
| 내부 서버 정보 | 사내 IP, 내부 도메인, 포트 정보 |
| .env 파일 / 인증 토큰 | 어떤 환경의 것이든 |
| 개인 접속 정보 | SSH 키, 인증서 |

### 예제 코드 마스킹 규칙

```yaml
# 잘못된 예
password: myActualPassword123

# 올바른 예
password: YOUR_PASSWORD
api_key: YOUR_API_KEY
host: YOUR_HOST
```

### 파일 작성/저장 전 체크리스트

- [ ] 실제 비밀번호/키 포함 여부 확인
- [ ] 내부 서버 주소/IP 포함 여부 확인
- [ ] `.env` 또는 credentials 파일 참조 없음 확인
- [ ] 예제 코드의 민감 값이 모두 마스킹 처리됨

---

## 7. 언어 및 스타일

- 본문: **한국어**
- 코드/명령어/기술 용어: 원문 그대로
- 커밋: docs 타입 중심 (`docs(docker-swarm): ...`)
- 커밋은 사용자 요청 시에만 수행 (자동 커밋 금지)

---

## 8. 필수 프로토콜

### Auto Memory
세션 종료 전 `.project-memory/context.md` 갱신 (자동 또는 `/blog-memory-save`).

### Compact Instructions
컨텍스트 압축 발생 시 `pre-compact-recovery.md`를 통해 자동 복구.

### Work Completion
블로그 1편 완성 시:
1. `current-status.md` 해당 항목 완료 표시
2. `context.md` 다음 TODO 갱신

---

> 세부 설정: `.claude/` 디렉토리 (hooks/skills/rules) 참조
> 작업 상세: `blog-claude-docs/session/quick-ref.md` 참조
