# AGENTS.md — my-blog 범용 규칙

> 모든 에이전트/도구가 참조하는 프로젝트 공통 규칙.
> 세부 규칙: `.claude/rules/*.md`

---

## 1. 프로젝트 개요

**my-blog**는 기술 부채 해소를 위한 학습 가이드 블로그 작성 전용 프로젝트.
- 주제: Docker Swarm / Spring + SeaweedFS / Spring + Temporal
- Claude 역할: 선생님 (상세하고 쉬운 학습 가이드 작성)

---

## 2. 디렉토리 구조

```
my-blog/
├── blog-claude-docs/          # Claude Code 관리 문서 (세션/요구사항/아카이브)
├── .project-memory/           # 세션 컨텍스트 (자동 관리)
├── .claude/                   # Claude Code 설정 (hooks/skills/rules/memory)
├── docker-swarm/              # Docker Swarm 블로그 파일
├── spring-seaweedfs/          # Spring + SeaweedFS 블로그 파일
└── spring-temporal/           # Spring + Temporal 블로그 파일
```

---

## 3. 파일 명명 규칙

### 블로그 파일
- 형식: `{순번:01}-{주제-kebab-case}.md`
- 예시: `01-docker-swarm-overview.md`

### 문서 파일 (blog-claude-docs)
- 날짜 포함 아카이브: `YYYY-MM.md`
- 상태 문서: 버전/날짜 항상 상단에 명시

---

## 4. 커밋 규칙

```
<type>(<scope>): <subject>

Co-Authored-By: Claude Code <noreply@anthropic.com>
```

- **Type**: docs, chore, fix
- **Scope**: docker-swarm, spring-seaweedfs, spring-temporal, claude-docs
- 사용자 요청 시에만 커밋 (자동 커밋 금지)
- `git add -A` 금지 — 개별 파일 지정

---

## 5. 문서 편집 규칙

- `blog-claude-docs/` 파일 수정 시 상단 날짜 갱신
- `current-status.md`는 블로그 작성 완료 시 즉시 갱신
- `quick-ref.md`는 프로젝트 상태 변경 시 갱신

---

## 6. 보안 규칙 (PUBLIC REPO — 엄격 적용)

> **이 저장소는 Public이다.** 모든 커밋 내용이 인터넷에 공개된다.
> 아래 규칙은 예외 없이 적용된다.

### 절대 금지 — 다음 내용은 어떤 파일에도 포함 불가

- API 키, 시크릿 키, 액세스 토큰 (형태 불문)
- 비밀번호 (DB, 서비스, 계정 등 모두)
- 개인 식별 정보 (이메일, 전화번호, 주소)
- 내부 서버 IP, 사내 도메인, 내부 포트
- `.env` 파일 내용 / SSH 키 / 인증서
- 실제 운영 환경 설정값

### 예제 코드 마스킹 필수

```
비밀번호 → YOUR_PASSWORD
API 키   → YOUR_API_KEY
호스트   → YOUR_HOST
IP       → 192.168.x.x 또는 YOUR_SERVER_IP
```

### 커밋 전 필수 확인

파일 저장/커밋 전 반드시 확인:
1. 실제 키/비밀번호 포함 여부
2. 내부 서버 정보 포함 여부
3. .env 참조 또는 인증 정보 포함 여부

---

## 7. 플랫폼 규칙

- **OS**: Windows 11 (bash 셸 사용)
- **경로**: bash에서는 `/c/Users/...` 형식
- **nul 파일**: Windows 아티팩트 — git add에서 제외

---

## 8. Ambiguity Protocol

모호한 요청을 받으면:
1. **STOP** — 추측으로 작성하지 않음
2. 구체화 질문 2개+ 제시 (선택지 형태 선호)
3. 사용자 응답 후 진행

---

## 9. 웹 검색 원칙

블로그 작성 시 항상:
1. 공식 문서 / 공식 GitHub 최우선 참조
2. 최신 릴리즈 버전 확인 (구버전 예제 주의)
3. 커뮤니티 자료(블로그, Stack Overflow)는 날짜 확인 후 인용
4. 출처는 참고 자료 섹션에 URL과 함께 기재
