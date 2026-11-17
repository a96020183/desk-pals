# 公仔櫃 Desk Pals：Mac 安裝說明

跟 Windows 版同一套公仔櫃：右下角的紙箱公仔櫃、續命小隊（躲躲、沒電、刺刺）、經典一櫃、天線寶寶一櫃、皮克敏一櫃（這三櫃只在個人版）、用自己的照片做公仔（分享短片、`.deskpal` 匯出匯入）、讀書小幫手（學校行事曆、作業、考試、熬夜、搶課）、串門子劇情、午餐、下班時間、各種提醒，全部都有。玩法見 [README](README.md)。

> Mac 版是 Windows 版（`DeskPals.cs`）的 Swift 移植。用起來怪怪的話，先看最下面的自查方法。

> 這份是 **VS Code 擴充套件**的裝法。不用 VS Code（也不用 Xcode）的話，直接用 `DeskPals-<版號>.dmg`：把 Desk Pals 拖進「應用程式」，第一次打開照 DMG 裡的說明按「仍要打開」，見 [README 的安裝](README.md#安裝)。

## 需要先有

- VS Code
- Xcode Command Line Tools：打開「終端機」輸入下面這行。已經裝過的話會顯示 already installed，不用理它。
  ```
  xcode-select --install
  ```

## 安裝

1. 把 `desk-pals-<版號>.vsix` 放到任意資料夾。
2. VS Code → 左邊「延伸模組」→ 右上角「⋯」→「從 VSIX 安裝…」→ 選這個檔。
3. 重新開啟 VS Code。

第一次啟動時會在背景編譯，大約 30 秒到 1 分鐘，之後公仔櫃就會出現在螢幕右下角。以後開機會自動出現，不用開 VS Code。

**從舊版升級**（只有 Spidey 的那版，或 0.8 以前程式放在 `~/Library/Application Support/SpideyDesktop` 的版本）：不用做任何事。新版第一次開起來會自動叫舊的收工、拿掉舊的開機啟動項（`local.spidey-pet`）和舊程式，Spidey 的感情等級也會帶過來。之後程式、設定、紀錄都在 `~/Library/Application Support/DeskPals`。

## 跟 Windows 版不一樣的地方

- **右鍵**：Mac 上按右鍵或 Control＋點都可以叫出選單。
- **快速鍵**：Control＋Option＋S 叫公仔躲起來／出來。
- **做公仔選照片**：可以從 Finder 把照片拖進「做一隻自己的公仔」視窗；選檔視窗只列圖片（png、jpg、gif、bmp）。分享短片存在「圖片／Desk Pals」，存好會在 Finder 裡選起來。
- **跳上視窗**：公仔看得到你的視窗位置，不需要任何權限。視窗標題要「螢幕錄製」權限才讀得到；沒給權限也能正常玩，只是少數看視窗標題的台詞會用 App 名稱代替。
- **搗蛋（公仔小屋 →「搗蛋」）**：
  - 下班清場是把那幾個 App「隱藏」（不是關掉），點公仔就全部叫回來；推走的假視窗是卡通畫的（Mac 不擷取視窗畫面）。
  - 購物警察要「螢幕錄製」權限才看得到網頁標題，沒給就不會哭。
  - 打字太兇（預設關）只數「每秒按了幾下」（系統的按鍵計數器），不看按了哪個鍵、不記錄任何內容。macOS 可能要「輸入監控」權限：只有你自己在小屋打開這個開關時會問一次；沒給就安靜地不觸發，不會一直跳。
  - 都不會關閉任何程式；收工前會先把推走的 App 全部叫回來。

## 跟 Claude Code 一起用

- **卡住提醒（不用設定）**：Claude Code 在問你問題 90 秒、停在某個工具 3 分鐘（多半在等你按允許）、或 5 分鐘沒回應時，公仔會跳出來敲螢幕提醒你。
- **做完通知（選用）**：把下面這段加進 `~/.claude/settings.json` 最外層的 `{ }`。已經有 `hooks` 的話，把裡面四項併進去。舊版設過的（路徑是 `…/SpideyDesktop/claude-hook.js`）不用改：舊位置留了一個小檔，會自動轉到新位置。
  ```json
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/DeskPals/claude-hook.js\" start", "timeout": 3 }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/DeskPals/claude-hook.js\" done", "timeout": 3 }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/DeskPals/claude-hook.js\" wait", "timeout": 3 }] }],
    "PostToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/DeskPals/claude-hook.js\" post", "timeout": 3 }] }]
  }
  ```

## 不想要了

在公仔或公仔櫃上按右鍵選「收工」，或在 VS Code 按 `Cmd+Shift+P` 執行收工指令。公仔櫃會離開，下次開機也不會再自動出現。

## 沒出現怎麼辦（自查）

在終端機執行下面這行，看輸出和 log 的錯誤訊息：

```
bash ~/Library/Application\ Support/DeskPals/desk-pals.sh; cat ~/Library/Logs/desk-pals.log
```

- 出現 `swiftc not found`：Command Line Tools 沒裝好，重跑 `xcode-select --install`。
- 出現 `error:` 開頭的編譯錯誤：跟你的 macOS／Xcode 版本有關，請開 issue 附上 log。
