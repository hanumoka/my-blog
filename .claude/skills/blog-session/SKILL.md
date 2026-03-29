---
name: blog-session
description: 블로그 세션 시작 시 컨텍스트 로드. 현재 상태, 진행상황 확인 시 사용
user-invocable: true
disable-model-invocation: true
---

my-blog 세션 시작 프로토콜을 실행합니다.

## 순서

1. `blog-claude-docs/session/quick-ref.md` 읽기
2. `blog-claude-docs/session/current-status.md` 읽기
3. `.project-memory/context.md` 읽기
4. `git status --short` + `git log --oneline -5` 확인
5. 종합 보고서 작성 (한글)

## 보고 형식

```markdown
## 세션 복원 완료

**현재 포커스**: [작업 중인 주제]
**블로그 진행**: 완료 N편 / 전체 N편

### 마지막 완료 작업
- [작업 내용]

### 다음 작업
1. [다음 할 일]
2. [그 다음 할 일]

### Quick Links
- blog-claude-docs/session/current-status.md
- blog-claude-docs/requirements/topic-backlog.md
```

## 주의사항

- 파일이 없으면 에러 없이 스킵
- 항상 한글로 보고
- pre-compact-recovery.md가 있으면 복구 안내 포함
