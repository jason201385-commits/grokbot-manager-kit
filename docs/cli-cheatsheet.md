# CLI 指令速查

以下為指令範例，依本機版本的 `--help` 確認。先設定 `KIT=/path/to/grokbot-manager-kit` 指向套件根目錄，再切換到目標專案執行；不要在提示詞放秘密。

## Codex

```bash
codex login
codex login status
codex exec --dangerously-bypass-approvals-and-sandbox -- "完成指定功能並執行驗證"
codex exec --sandbox read-only --skip-git-repo-check -- "只讀審查目前變更，列出問題與證據，不改檔"
```

改檔範例停用核准與沙箱，僅用於已授權任務，不加 `--full-auto`。審查每次開新 session，不用 resume。


**高風險預設：** 套件刻意保留 `codex exec --dangerously-bypass-approvals-and-sandbox`，會跳過所有核准並停用沙箱；CLI 可依帳號權限讀寫專案外檔案、執行命令。僅在任務已授權且具外部隔離的環境使用。較安全的替代為 `codex exec --sandbox workspace-write -- "提示詞"`；這不是本套件預設，必須由使用者明確修改 `scripts/run-task.sh` 的改檔命令才會使用，不能與 bypass 旗標並用。

Codex 審查固定使用 `--sandbox read-only --skip-git-repo-check`，讓非 Git 目錄也能審查；這不會建立 Git 儲存庫。提示詞前的 `--` 用於分隔選項（Codex／Claude）；AGY 的 `-p` 介面依該工具版本確認。

## Claude Code

```bash
claude auth login --claudeai
claude auth status
env -u CLAUDE_CODE_OAUTH_TOKEN claude -p -- "修復指定問題並驗證"
env -u CLAUDE_CODE_OAUTH_TOKEN claude -p --tools "Read,Grep,Glob" --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands --safe-mode --setting-sources '' --settings '{"disableAllHooks":true}' -- "只讀審查目前變更，列出問題與證據，不改檔"
```

移除該次呼叫的 OAuth 變數可避免過期／錯誤 token 干擾。審查不接續舊 session；只提供讀取工具、限制 MCP 與技能，並使用 `--safe-mode`、空的 `--setting-sources` 與 `disableAllHooks` 設定盡量停用自訂 hooks；管理政策仍可能生效。工具白名單不等於完整 OS 隔離，CLI 本身仍可能寫入 session 或快取；需要嚴格唯讀隔離時選 Codex read-only（須確認主機支援沙箱）。未提供 shell 工具，需查看差異時請提供差異檔或明確檔案範圍。若本機版本不支援這些旗標，回報失敗，改選 Codex；不可移除限制後重試。

## AGY（可選）

```bash
/path/to/agy -p "只讀審查指定專案，列出問題與證據，不改檔"
AGY_BIN=/path/to/agy REVIEWER=agy "$KIT"/scripts/run-task.sh review "審查指定變更"
```

AGY 的只讀提示不等於權限沙箱，須自行確認隔離。未安裝會報錯，改選 codex 或 claude 即可。

## REVIEWER 對照

| 值 | 審查方式 |
| --- | --- |
| `codex` | 建議預設，全新 session、read-only 沙箱 |
| `claude` | 全新 session、僅讀取工具，限制 MCP／技能並盡量停用 hooks；無完整 OS 隔離 |
| `agy` | 可選，使用 AGY，只讀提示與自行設定的隔離 |
| `none` | 明示略過獨立審查，仍須驗證產出 |

設定來源依序為環境變數、`config/reviewer.env`、預設 `codex`。二進位路徑也可用環境變數覆寫。

```bash
"$KIT"/scripts/run-task.sh codex "完成指定功能並驗證"
"$KIT"/scripts/run-task.sh claude "修復指定問題並驗證"
"$KIT"/scripts/run-task.sh review "審查指定變更"
REVIEWER=none "$KIT"/scripts/run-task.sh review "此次略過獨立審查"
"$KIT"/scripts/status.sh
```

腳本等待完成，印出 PID、log 路徑與退出碼，保留 CLI 失敗狀態，不自動重跑。`none` 也會留下略過紀錄。
