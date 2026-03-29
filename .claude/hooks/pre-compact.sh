#!/bin/bash
# PreCompact hook — compaction 전 핵심 상태를 pre-compact-recovery.md에 저장

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONTEXT_FILE="$ROOT_DIR/.project-memory/context.md"
RECOVERY_FILE="$ROOT_DIR/.project-memory/pre-compact-recovery.md"

# context.md가 없으면 스킵
[[ ! -f "$CONTEXT_FILE" ]] && exit 0

{
  echo "# Pre-Compact Recovery"
  echo "> 자동 생성: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "> compaction 전 상태 스냅샷. 세션 복구 시 참조."
  echo ""

  # context.md 전체 복사
  echo "## Context Snapshot"
  cat "$CONTEXT_FILE"
  echo ""

  # 최근 git 변경사항
  echo "## Git Status at Compact"
  echo '```'
  git status --short 2>/dev/null | head -20
  echo '```'
  echo ""

  # 최근 커밋
  echo "## Recent Commits"
  echo '```'
  git log --oneline -5 2>/dev/null
  echo '```'
} > "$RECOVERY_FILE"

echo "Pre-compact 상태가 저장되었습니다: $RECOVERY_FILE"
exit 0
