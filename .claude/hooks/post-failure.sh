#!/bin/bash
# PostToolUseFailure hook — Bash 실패 시 로깅

INPUT=$(cat)

TOOL_NAME=$(python -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get('tool_name', ''))
except:
    print('')
" <<< "$INPUT" 2>/dev/null || echo "")

# Bash 실패만 처리
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# 로그 디렉토리 확인 및 기록
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
LOG_FILE="$LOG_DIR/failures.log"

if [ -d "$LOG_DIR" ]; then
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$TIMESTAMP] Bash 명령 실패" >> "$LOG_FILE" 2>/dev/null
fi

echo "[FAILURE] Bash 명령 실패 — .claude/logs/failures.log 참조"

exit 0
