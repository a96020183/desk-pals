# 公仔櫃 Desk Pals：Mac 安裝說明（目前只有 Spidey）

一隻像素小蜘蛛人，會在整個 Mac 螢幕上走來走去、跳到視窗上、噴絲擺盪。點他會撒嬌；平日 18:00 以後會黑化，催你下班。

> ⚠️ **不提供 Mac 支援。** 作者沒有 Mac，這版只在雲端的 Mac 機器上編譯、短跑過，沒有在真的 MacBook 上長時間用過。**裝不起來或用起來怪怪的，請自己處理**（最下面有自查方法），不要回頭找作者。

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

第一次啟動時會在背景編譯，大約 30 秒到 1 分鐘，之後他就會出現在螢幕上。以後開機會自動出現，不用開 VS Code。

## 怎麼玩

- **點他**：抱抱、講好話；連點會好癢、頭暈。
- **按住拖曳**：把他丟出去。
- **按右鍵（或 Control＋點）**：選單，可以抱抱、敲螢幕、擺盪、倒吊、丟球給他、看你們的感情等級、收工。
- **右下角的蜘蛛網是他的窩**：把他拖進去會被網子鎖住、乖乖待著；拖出來就自由了。
- **Control＋Option＋S**：叫他躲起來／出來。
- **越常互動感情越好**：等級升上去會戴圍巾、毛帽、愛心眼鏡、皇冠。
- **節日**：聖誕節、農曆新年、你的生日（VS Code 設定 `spideyPet.birthday`，格式 `MM-DD`）會換造型。
- **VS Code 裡**：側邊欄也有一隻；存檔會比讚、程式出錯會有蜘蛛感應、打字很快會跳舞加油、在終端機 `git push` tag 成功會放煙火。

## 跟 Claude Code 一起用

- **卡住提醒（不用設定）**：Claude Code 在問你問題 90 秒、停在某個工具 3 分鐘（多半在等你按允許）、或 5 分鐘沒回應時，他會跳出來敲螢幕提醒你。VS Code 裡的 Claude 和終端機的 Claude CLI 都算。
- **做完通知（選用）**：把下面這段加進 `~/.claude/settings.json` 最外層的 `{ }`，Claude 做完或在等你時他也會提醒。已經有 `hooks` 的話，把裡面四項併進去。
  ```json
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/SpideyDesktop/claude-hook.js\" start", "timeout": 3 }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/SpideyDesktop/claude-hook.js\" done", "timeout": 3 }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/SpideyDesktop/claude-hook.js\" wait", "timeout": 3 }] }],
    "PostToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "node \"$HOME/Library/Application Support/SpideyDesktop/claude-hook.js\" post", "timeout": 3 }] }]
  }
  ```

## 不想要了

在 VS Code 按 `Cmd+Shift+P`，執行「Spidey：收工（關掉整個螢幕版）」。他會離開，下次開機也不會再自動出現。

## 沒出現怎麼辦（自查）

在終端機執行下面這行，看輸出和 log 的錯誤訊息自己排除：

```
bash ~/Library/Application\ Support/SpideyDesktop/spidey-desktop.sh test; cat ~/Library/Logs/spidey-desktop.log
```

- 出現 `swiftc not found`：Command Line Tools 沒裝好，重跑 `xcode-select --install`。
- 出現 `error:` 開頭的編譯錯誤：跟你的 macOS／Xcode 版本有關，請自行修改 `~/Library/Application Support/SpideyDesktop/SpideyDesktop.swift` 後再執行上面那行。
