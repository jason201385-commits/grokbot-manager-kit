#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
printf '相關行程（全機概覽，不限本套件啟動；僅表示仍在執行，不代表任務成功）：\n'
# 只顯示 PID、父 PID、時間與執行檔名稱，避免提示詞或參數外洩。
rows=$(ps -eo pid=,ppid=,etime=,comm= | awk '$4 ~ /^(codex|claude|agy)([-.].*)?$/')
if [[ -n $rows ]]; then
  printf 'PID  父PID  已執行時間  執行檔\n%s\n' "$rows"
else
  printf '目前未找到相關行程；自訂二進位名稱可用 run-task.sh 的 PID 配合 ps 查詢。\n'
fi
printf '\n最近日誌（最多五個）：\n'
shopt -s nullglob
files=("$ROOT"/logs/*.log)
if (( ${#files[@]} )); then
  # 檔名由腳本產生，依時間戳排序。
  printf '%s\n' "${files[@]}" | sort -r | sed -n '1,5p'
else
  printf '目前沒有日誌。\n'
fi
