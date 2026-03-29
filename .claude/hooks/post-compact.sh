#!/bin/bash
# PostCompact hook — compaction 후 pre-compact-recovery.md를 자동 재주입

INPUT=$(cat)

CWD=$(python -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get('cwd', '.'))
except:
    print('.')
" <<< "$INPUT" 2>/dev/null || echo ".")

RECOVERY_FILE="$CWD/.project-memory/pre-compact-recovery.md"

if [ ! -f "$RECOVERY_FILE" ]; then
  exit 0
fi

echo "=== [RECOVERY] Compact 후 세션 컨텍스트 복원 ==="
echo ""
cat "$RECOVERY_FILE"
echo ""
echo "=== context.md 전체 내용은 .project-memory/context.md 참조 ==="

exit 0
