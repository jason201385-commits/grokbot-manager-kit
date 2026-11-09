# Grok Bot 主管教學套件

Claude Code session 太多、切換與手動追進度太累？讓 Grok Bot 只理解需求、下指令與驗收，把改檔和研究交給 CLI。

架構一句話：Grok Bot＝主管；Codex／Claude Code＝下屬幹活；審查器（可選）＝AGY 或全新唯讀 Codex／Claude。

## 先決條件

準備 Grok Bot（或同等會跑 shell 的 bot），並在 **bot 可用的那台電腦**安裝、登入 Codex 與／或 Claude Code。腳本需要 Bash、常見 Unix 工具與 `env -u`。不用安裝 AGY 也能完整使用。

以下是操作範例，未連網安裝或實際登入驗證；不同版本請以本機 `--help` 為準。

## 安裝與登入

先自行安裝所需 CLI，再於同一台電腦登入；不要把登入資料放進此套件。

```bash
codex login
codex login status
codex exec --dangerously-bypass-approvals-and-sandbox -- "在指定專案完成需求並驗證"

claude auth login --claudeai
claude auth status
env -u CLAUDE_CODE_OAUTH_TOKEN claude -p -- "在指定專案修復問題並驗證"
```

Codex 上述改檔指令會停用核准與沙箱，只在已授權的專案使用，不要另加 `--full-auto`。Claude 範例只對該次指令移除 OAuth 環境變數，避免過期或錯誤 token 干擾既有登入；不會刪除登入資料。需要工具權限時，依本機設定處理，失敗要回報。

AGY 可選，已安裝才使用：`/path/to/agy -p "只讀審查指定變更"`。沒安裝就選 `REVIEWER=codex` 或 `claude`。


**高風險預設：** 套件刻意保留 `codex exec --dangerously-bypass-approvals-and-sandbox`，會跳過所有核准並停用沙箱；CLI 可依帳號權限讀寫專案外檔案、執行命令。僅在任務已授權且具外部隔離的環境使用。較安全的替代為 `codex exec --sandbox workspace-write -- "提示詞"`；這不是本套件預設，必須由使用者明確修改 `scripts/run-task.sh` 的改檔命令才會使用，不能與 bypass 旗標並用。

Codex 審查固定使用 `--sandbox read-only --skip-git-repo-check`，讓非 Git 目錄也能審查；這不會建立 Git 儲存庫。提示詞前的 `--` 用於分隔選項（Codex／Claude）；AGY 的 `-p` 介面依該工具版本確認。

## 設定審查器

設定 `KIT` 指向套件根目錄（請換成實際位置），在同一個 shell 執行：

```bash
KIT=/path/to/grokbot-manager-kit
cp "$KIT"/config/reviewer.env.example "$KIT"/config/reviewer.env
chmod +x "$KIT"/scripts/*.sh
```

編輯 `config/reviewer.env` 的 `REVIEWER=agy|codex|claude|none`（四選一，勿照抄豎線）。建議預設 `codex`：每次開全新唯讀 session。`none` 略過獨立審查，但執行者仍須驗證結果。環境變數優先於設定檔：

```bash
REVIEWER=none "$KIT"/scripts/run-task.sh review "檢查此次變更"
```

設定檔僅接受 `REVIEWER`、`CODEX_BIN`、`CLAUDE_BIN`、`AGY_BIN` 的單行值，不執行 shell。路徑可含空白，不加引號；不要填密鑰。

## 交給主管

把 [共同記憶規則](templates/shared-memory-rules.md) 的純文字清單貼進 Grok Bot 共同記憶／個人規則。先指定目標專案絕對路徑、範圍與驗收條件，再派工。

可直接貼給 Grok Bot（將括號內容換成你的需求）：

- 「派 Codex 在〔專案路徑〕完成〔功能〕，執行〔驗證〕；用 run-task.sh，提供 PID 與 log，驗證後回報。」
- 「派 Claude 在〔專案路徑〕修復〔重現步驟〕，驗收條件是〔預期結果〕，不要碰範圍外檔案。」
- 「執行者停止改檔後，請選定審查器開全新唯讀 session，檢查〔專案路徑與變更範圍〕，只列問題、證據與驗收結論。REVIEWER=none 時明示略過。」
- 「CLI 失敗先查登入、額度、路徑和權限，回報退出碼與 log 原因，不得自行代做；已有副作用不得自動重跑。」

## 執行與追蹤

腳本保留呼叫時的工作目錄，請在目標專案執行，先設定 `KIT` 指向套件根目錄：

```bash
KIT=/path/to/grokbot-manager-kit
"$KIT"/scripts/run-task.sh codex "完成指定功能並驗證"
"$KIT"/scripts/run-task.sh claude "修復指定問題並驗證"
"$KIT"/scripts/run-task.sh review "只讀審查目前專案的變更"
"$KIT"/scripts/status.sh
```

中斷時向獨立行程群組送 TERM，最多等待五秒後送 KILL，並等待 CLI 結束；優先用 `setsid`，缺少時以 Bash job control 盡力隔開群組。自行脫離群組的後代無法保證回收。

腳本前景等待並顯示子行程 PID、log 路徑與退出碼；stdout／stderr 存在套件 `logs/`。另開終端用 `ps -p <PID>` 看行程、`tail -f <log路徑>` 看輸出。PID 只證明曾啟動，成功仍需檢查退出碼、產物與驗證。日誌可能含專案內容，分享前自行檢查；提示詞不要含秘密。

## 常見問題

- **登入過期？** 先查登入狀態，再重新登入；Claude 可先移除該次指令的 OAuth 變數。
- **額度用完？** 停止並回報；由使用者決定等待或換 CLI，不自行反覆重試。
- **兩個 CLI 同時改同一檔？** 同一工作只派一位執行者；完成後才讓審查器讀取。
- **只說「已開始」？** 要求 PID、log 或工作識別碼；拿不出證據就不能當成已啟動。
- **副作用任務失敗？** 發信、部署、付款、刪除等可能已部分完成，先查狀態，不自動重跑。
- **唯讀保護？** Codex 使用 read-only 沙箱；Claude 限制讀取工具、MCP 與技能，並以 `--safe-mode --setting-sources '' --settings '{"disableAllHooks":true}'` 盡量停用自訂 hooks。管理政策仍可能生效，工具白名單不等於完整 OS 隔離，也不能保證 CLI 本身不寫入 session 或快取。AGY 僅附只讀指令，須自行確認其權限隔離；需要嚴格唯讀隔離時選 Codex read-only（仍須確認主機支援沙箱）。任何審查指令都不應要求寫入。

更多指令見 [CLI 速查](docs/cli-cheatsheet.md)。

## 上傳 GitHub

檢查內容與日誌排除規則後，由你自行 `git init`、建立遠端並 push。本套件不代做；`config/reviewer.env` 與執行日誌已忽略。授權見 [LICENSE](LICENSE)。
