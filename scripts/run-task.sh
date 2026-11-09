#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -ne 2 || -z $2 ]]; then
  printf '用法：%s <codex|claude|agy|review> "提示詞..."\n' "$0" >&2
  exit 2
fi
mode=$1
prompt=$2
case "$mode" in codex|claude|agy|review) ;; *) printf '錯誤：未知模式。\n' >&2; exit 2 ;; esac
# 只解析白名單鍵值，不載入或執行設定檔程式碼。
if [[ -f "$ROOT/config/reviewer.env" ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ $line != *=* ]]; then
      printf '錯誤：設定須為單行鍵值。\n' >&2; exit 2
    fi
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      REVIEWER|CODEX_BIN|CLAUDE_BIN|AGY_BIN)
        if [[ ! -v $key ]]; then printf -v "$key" '%s' "$value"; fi ;;
      *) printf '錯誤：設定含不支援的鍵。\n' >&2; exit 2 ;;
    esac
  done < "$ROOT/config/reviewer.env"
fi
REVIEWER=${REVIEWER-codex}
CODEX_BIN=${CODEX_BIN-codex}
CLAUDE_BIN=${CLAUDE_BIN-claude}
AGY_BIN=${AGY_BIN-agy}
case "$REVIEWER" in agy|codex|claude|none) ;; *) printf '錯誤：REVIEWER 須為 agy、codex、claude 或 none。\n' >&2; exit 2 ;; esac
umask 077
mkdir -p "$ROOT/logs"
log=$(mktemp "$ROOT/logs/$(date +%Y%m%d-%H%M%S)-${mode}-XXXXXX.log")
printf '日誌：%s\n' "$log"
fail() { printf '%s\n' "$1" | tee -a "$log" >&2; exit 127; }
target=$mode
if [[ $mode == review ]]; then
  target=$REVIEWER
  prompt="只讀審查，不改檔、不執行有副作用的操作；只回報問題、證據與驗收結論。任務：$prompt"
fi
if [[ $target == none ]]; then
  printf 'REVIEWER=none：已略過獨立審查，執行者仍須驗證。\n' | tee -a "$log"
  exit 0
fi
case "$target" in
  codex)
    command -v -- "$CODEX_BIN" >/dev/null 2>&1 || fail '找不到 Codex，請安裝或設定 CODEX_BIN。'
    if [[ $mode == review ]]; then
      cmd=("$CODEX_BIN" exec --sandbox read-only --skip-git-repo-check -- "$prompt")
    else
      cmd=("$CODEX_BIN" exec --dangerously-bypass-approvals-and-sandbox -- "$prompt")
    fi ;;
  claude)
    command -v -- "$CLAUDE_BIN" >/dev/null 2>&1 || fail '找不到 Claude Code，請安裝或設定 CLAUDE_BIN。'
    cmd=(env -u CLAUDE_CODE_OAUTH_TOKEN "$CLAUDE_BIN" -p)
    if [[ $mode == review ]]; then
      cmd+=(--tools 'Read,Grep,Glob' --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands --safe-mode --setting-sources '' --settings '{"disableAllHooks":true}')
    fi
    cmd+=(-- "$prompt") ;;
  agy)
    command -v -- "$AGY_BIN" >/dev/null 2>&1 || fail '找不到 AGY；請設定 AGY_BIN，或改用 REVIEWER=codex／claude／none。AGY 並非必要依賴。'
    cmd=("$AGY_BIN" -p "$prompt") ;;
esac
# setsid 建立獨立 session；無 setsid 時以 Bash job control 隔開群組。
caller_pgid=$(ps -o pgid= -p "$$")
caller_pgid=${caller_pgid//[[:space:]]/}
if command -v setsid >/dev/null 2>&1; then
  launcher=(setsid)
else
  set -m
  launcher=()
fi
pid=''
stop_cli() {
  local signal=$1 i pgid
  trap '' INT TERM HUP
  if [[ -n $pid ]]; then
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null) || pgid=''
    pgid=${pgid//[[:space:]]/}
    # 只准向以 CLI PID 命名的獨立群組送訊號，絕不碰呼叫者群組。
    if [[ $pid != "$caller_pgid" && ( $pgid == "$pid" || -z $pgid ) ]]; then
      kill -TERM -- "-$pid" 2>/dev/null || true
      # 處理 setsid 尚未完成的啟動競態。
      kill -TERM -- "$pid" 2>/dev/null || true
      for ((i=0; i<50; i++)); do
        kill -0 -- "-$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -KILL -- "-$pid" 2>/dev/null || true
    else
      # 無法確認隔離時，只處理直接子行程，避免誤殺其他工作。
      kill -TERM -- "$pid" 2>/dev/null || true
      for ((i=0; i<50; i++)); do
        kill -0 -- "$pid" 2>/dev/null || break
        sleep 0.1
      done
    fi
    kill -KILL -- "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  printf '已中斷；日誌：%s\n' "$log"
  exit "$signal"
}
trap 'stop_cli 130' INT
trap 'stop_cli 143' TERM
trap 'stop_cli 129' HUP
"${launcher[@]}" "${cmd[@]}" > "$log" 2>&1 &
pid=$!
printf 'CLI PID：%s\n' "$pid"
rc=0
wait "$pid" || rc=$?
trap - INT TERM HUP
printf '退出碼：%s；日誌：%s\n' "$rc" "$log"
exit "$rc"
