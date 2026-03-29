---
name: blog-memory-save
description: 세션 종료 시 .project-memory/context.md 갱신 + 진행 상태 저장
user-invocable: true
argument-hint: "[작업 유형: blog|docs|none]"
---

세션 종료 전 프로젝트 상태를 저장합니다.

## 실행 절차

### 1. 현재 세션 변경사항 수집
- `git status --short`로 변경 파일 목록 확인
- 변경 내용 요약 정리

### 2. 작업 유형 분류
$ARGUMENTS가 비어있으면 자동 분류:
- **blog**: 블로그 .md 파일 추가/수정
- **docs**: claude-docs 문서만 변경
- **none**: 변경사항 없음 (context.md만 갱신)

### 3. Work Completion (유형별)

#### blog인 경우
1. `blog-claude-docs/session/current-status.md` 완료 항목 체크
2. `blog-claude-docs/requirements/topic-backlog.md` 백로그 갱신

#### docs인 경우
- 해당 문서만 날짜 갱신

### 4. `.project-memory/context.md` 갱신

각 섹션별 업데이트:
- **마지막 업데이트**: 현재 날짜 + 세션 요약
- **현재 포커스**: 변경 시 갱신
- **최근 결정사항**: 새 결정 append (최대 10개, FIFO)
- **다음 TODO**: 완료 항목 `[x]`, 새 항목 추가
- **차단 사항**: 발생/해제 반영

### 5. 갱신 요약 출력

```
## Memory Save 완료

### 갱신 파일
- context.md: [변경 내용]
- current-status.md: [변경 내용]

### 세션 요약
- 작업 유형: [blog/docs/none]
- 완성 블로그: [제목]
- 다음 예정: [주제]
```

## 주의사항
- context.md 핵심 정책 섹션 수정 금지
- 기존 결정사항 삭제 금지 (append only)
- 시크릿/토큰 절대 포함 금지
