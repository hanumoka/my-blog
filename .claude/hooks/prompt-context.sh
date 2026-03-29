#!/bin/bash
# UserPromptSubmit hook — 키워드 감지 시 컨텍스트 자동 주입

PROMPT=$(cat)

# Docker / Swarm 키워드
if echo "$PROMPT" | grep -qiE '(docker|swarm|container|service|stack|compose|overlay|ingress|replicas)'; then
  echo "[CONTEXT] Docker/Swarm 주제 감지 → docker-swarm/ 폴더 참조. 웹 검색으로 최신 Docker 공식 문서 확인 필수. 작성 규칙: .claude/rules/blog-writing.md"
fi

# Spring 키워드
if echo "$PROMPT" | grep -qiE '(spring|스프링|springboot|spring.boot|mvc|bean|autowired|jpa|hibernate)'; then
  echo "[CONTEXT] Spring 주제 감지 → 해당 폴더 참조. Spring 공식 문서(docs.spring.io) 우선 참조. 버전 명시 필수."
fi

# SeaweedFS 키워드
if echo "$PROMPT" | grep -qiE '(seaweedfs|seaweed|weed|filer|volume.server|master.server)'; then
  echo "[CONTEXT] SeaweedFS 주제 감지 → spring-seaweedfs/ 폴더 참조. SeaweedFS GitHub(github.com/seaweedfs/seaweedfs) 최신 릴리즈 확인 필수."
fi

# Temporal 키워드
if echo "$PROMPT" | grep -qiE '(temporal|workflow|activity|worker|signal|query|schedule|saga)'; then
  echo "[CONTEXT] Temporal 주제 감지 → spring-temporal/ 폴더 참조. Temporal 공식 문서(docs.temporal.io) 우선 참조."
fi

# 블로그 작성 요청 키워드
if echo "$PROMPT" | grep -qiE '(블로그|작성|써줘|정리|가이드|학습|튜토리얼|예제|실습)'; then
  echo "[CONTEXT] 블로그 작성 요청 감지 → /blog-write 스킬 워크플로우 실행. 웹 검색으로 최신 정보 수집 후 작성. 구성: 개요→핵심개념→실습→요약→참고자료"
fi

# 트러블슈팅 키워드
if echo "$PROMPT" | grep -qiE '(오류|에러|error|문제|안됨|안 됨|실패|troubleshoot|트러블)'; then
  echo "[CONTEXT] 트러블슈팅 감지 → .claude/memory/troubleshooting-patterns.md 참조. /blog-troubleshoot으로 패턴 기록 가능."
fi

exit 0
