---
name: blog-troubleshoot
description: 트러블슈팅 기록 조회/등록 (TS-NNN). 블로그 작성 중 발생한 문제 패턴 관리
user-invocable: true
argument-hint: "[조회: TS-NNN 또는 키워드 | 등록: 문제 설명]"
---

트러블슈팅 패턴을 조회하거나 새로 등록합니다.

## 동작 모드

### 조회 모드 (TS-NNN 또는 키워드)

$ARGUMENTS가 "TS-"로 시작하거나 키워드인 경우:
1. `.claude/memory/troubleshooting-patterns.md`에서 검색
2. 관련 패턴 목록 출력
3. 유사 패턴 제안

### 등록 모드 (문제 설명)

$ARGUMENTS가 문제 설명인 경우:
1. 기존 TS-NNN 번호 확인 → 다음 번호 부여
2. 사용자에게 정보 수집:
   - 증상 (어떤 오류/문제?)
   - 원인 (왜 발생?)
   - 해결 (어떻게 해결?)
   - 관련 주제/파일

3. `.claude/memory/troubleshooting-patterns.md`에 추가:

```markdown
### [TS-NNN] 제목

**증상**: ...
**원인**: ...
**해결**: ...
**관련 주제**: docker-swarm / spring-seaweedfs / spring-temporal
**날짜**: YYYY-MM-DD
```

4. 반복 패턴 분석:
   - 유사한 기존 TS 항목이 있으면 연관 표시

### 출력 형식

```
## 트러블슈팅 등록 완료

- ID: TS-NNN
- 제목: [제목]
- 관련 기존 패턴: TS-XXX (있는 경우)
```

## 주의사항
- 증상/원인/해결 모두 구체적으로 기록
- 관련 파일 경로는 프로젝트 루트 기준
- 시크릿/토큰 마스킹 처리
