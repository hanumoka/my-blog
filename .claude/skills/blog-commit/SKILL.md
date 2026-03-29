---
name: blog-commit
description: my-blog 커밋 규칙에 맞는 커밋 생성
user-invocable: true
disable-model-invocation: true
argument-hint: "[커밋 메시지 힌트]"
---

my-blog 커밋 규칙에 따라 커밋을 생성합니다.

## 커밋 메시지 형식

```
<type>(<scope>): <subject>

<body> (선택)

Co-Authored-By: Claude Code <noreply@anthropic.com>
```

- **Type**: `docs`, `chore`, `fix`
- **Scope**: `docker-swarm`, `spring-seaweedfs`, `spring-temporal`, `claude-docs`

## 절차

1. `git status --short`로 변경사항 확인
2. `git diff --stat`로 변경 규모 파악
3. `git log --oneline -3`으로 최근 커밋 스타일 확인
4. 변경사항 분석 후 적절한 type/scope 선택
5. 관련 파일만 `git add` (개별 지정, -A 금지)
6. HEREDOC으로 커밋 메시지 전달
7. `Co-Authored-By: Claude Code <noreply@anthropic.com>` 포함
8. $ARGUMENTS에 "push" 포함 시 push 수행

## 주의사항
- `.env`, 시크릿 파일 절대 커밋 금지
- `nul` 파일 (Windows 아티팩트) 제외
- `git add -A` 사용 금지
- `--amend` 사용 금지 (새 커밋 생성)
- 사용자 명시 요청 시에만 커밋
