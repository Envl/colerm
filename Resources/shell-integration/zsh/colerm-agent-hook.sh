#!/bin/sh
# Colerm session-scoped agent lifecycle hook reporter.
# Atomically drops a single status line into $COLERM_STATUS_DIR for $COLERM_SESSION_ID.
# Always exits 0 with no stdout/stderr so agent execution is never disrupted.

set -u

status_dir="${COLERM_STATUS_DIR:-}"
session_id="${COLERM_SESSION_ID:-}"
[ -n "$status_dir" ] && [ -d "$status_dir" ] && [ -n "$session_id" ] || exit 0

agent="${1:-}"
event="${2:-}"
hint=""

read_bounded_stdin() {
  if [ ! -t 0 ]; then
    /bin/dd bs=4096 count=1 2>/dev/null || true
  fi
}

case "$agent:$event" in
  claude:UserPromptSubmit|claude:PostToolUse)
    hint="state=working:app=claude-code:auth=1"
    ;;
  claude:PreToolUse)
    payload="$(read_bounded_stdin)"
    case "$payload" in
      *'"tool_name":"AskUserQuestion"'*|*'"tool_name": "AskUserQuestion"'*)
        hint="state=blocked:kind=question:app=claude-code:auth=1"
        ;;
      *'"tool_name":"ExitPlanMode"'*|*'"tool_name": "ExitPlanMode"'*)
        hint="state=blocked:kind=permission:app=claude-code:auth=1"
        ;;
      *)
        hint="state=working:app=claude-code:auth=1"
        ;;
    esac
    ;;
  claude:PermissionRequest)
    hint="state=blocked:kind=permission:app=claude-code:auth=1"
    ;;
  claude:Notification)
    payload="$(read_bounded_stdin)"
    case "$payload" in
      *'"notification_type":"permission_prompt"'*|*'"notification_type": "permission_prompt"'*)
        hint="state=blocked:kind=permission:app=claude-code:auth=1"
        ;;
      *'"notification_type":"elicitation_dialog"'*|*'"notification_type": "elicitation_dialog"'*)
        hint="state=blocked:kind=question:app=claude-code:auth=1"
        ;;
      *'"notification_type":"idle_prompt"'*|*'"notification_type": "idle_prompt"'*)
        hint="state=done:app=claude-code:auth=1"
        ;;
      *)
        hint=""
        ;;
    esac
    ;;
  claude:Stop)
    hint="state=done:app=claude-code:auth=1"
    ;;
  claude:SessionEnd)
    hint="state=idle:app=claude-code:auth=1"
    ;;
  codex:notify)
    payload="${3:-}"
    if [ -z "$payload" ]; then
      payload="$(read_bounded_stdin)"
    fi
    case "$payload" in
      *'"type":"agent-turn-complete"'*|*'"type": "agent-turn-complete"'*)
        hint="state=done:app=codex"
        ;;
      *'"type":"approval-requested"'*|*'"type": "approval-requested"'*)
        hint="state=blocked:kind=permission:app=codex"
        ;;
      *)
        hint=""
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

[ -n "$hint" ] || exit 0
tmp_file="$status_dir/.tmp.$$"
if printf '%s %s\n' "$session_id" "$hint" > "$tmp_file" 2>/dev/null; then
  /bin/mv -f "$tmp_file" "$status_dir/evt.$$" 2>/dev/null || /bin/rm -f "$tmp_file" 2>/dev/null || true
else
  /bin/rm -f "$tmp_file" 2>/dev/null || true
fi
exit 0
