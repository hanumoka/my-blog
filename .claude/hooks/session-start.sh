#!/bin/bash
# SessionStart hook — context.md 기반 세션 상태 + 핵심 컨텍스트 출력

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONTEXT_FILE="$ROOT_DIR/.project-memory/context.md"
RECOVERY_FILE="$ROOT_DIR/.project-memory/pre-compact-recovery.md"
STATUS_FILE="$ROOT_DIR/blog-claude-docs/session/current-status.md"

# 기본 컨텍스트
echo "CONTEXT: my-blog 학습 가이드 프로젝트. 한글소통. Claude 역할=선생님. 주제: Docker Swarm / Spring+SeaweedFS / Spring+Temporal. 블로그 작성 전 반드시 웹 검색으로 최신 정보 수집 필수."

# 진행 현황 요약
if [[ -f "$STATUS_FILE" ]]; then
  echo ""
  INPROG=$(grep -c '\- \[ \]' "$STATUS_FILE" 2>/dev/null || echo 0)
  DONE=$(grep -c '\- \[x\]' "$STATUS_FILE" 2>/dev/null || echo 0)
  echo "BLOG STATUS: 완료=${DONE}편, 진행중/예정=${INPROG}편 (상세: blog-claude-docs/session/current-status.md)"
fi

# context.md에서 핵심 정보 추출
if [[ -f "$CONTEXT_FILE" ]]; then
  echo ""

  # 현재 포커스
  FOCUS=$(sed -n '/^## 현재 포커스/,/^## /{/^## 현재 포커스/d;/^## /d;/^$/d;p;}' "$CONTEXT_FILE" | head -3)
  if [[ -n "$FOCUS" ]]; then
    echo "FOCUS: $FOCUS"
  fi

  # 미완료 TODO
  TODOS=$(grep '^\- \[ \]' "$CONTEXT_FILE" 2>/dev/null | head -5)
  if [[ -n "$TODOS" ]]; then
    echo "TODO:"
    echo "$TODOS"
  fi

  # 차단 사항
  BLOCKERS=$(sed -n '/^## 차단 사항/,/^## /{/^## 차단 사항/d;/^## /d;/^$/d;p;}' "$CONTEXT_FILE" | head -3)
  if [[ -n "$BLOCKERS" && "$BLOCKERS" != "없음" ]]; then
    echo "BLOCKERS: $BLOCKERS"
  fi
fi

# 최근 커밋
echo ""
echo "RECENT COMMITS:"
git log --oneline -3 2>/dev/null || echo "(커밋 없음)"

# pre-compact-recovery.md 존재 시 복구 안내
if [[ -f "$RECOVERY_FILE" ]]; then
  echo ""
  echo "⚠ PRE-COMPACT RECOVERY 존재: $RECOVERY_FILE"
  echo "이전 세션 컨텍스트가 저장되어 있습니다. /blog-session으로 복원하세요."
fi
