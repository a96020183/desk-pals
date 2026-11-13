# Spidey 小夥伴

一隻像素小蜘蛛人桌面寵物，Windows 和 Mac 都能用。他會在整個螢幕上走來走去、跳到視窗上、噴絲擺盪；點他會撒嬌；平日 18:00 以後會黑化，催你下班；Claude Code 卡住時會跳出來提醒你。

> 個人粉絲作品，非商業用途，與 Marvel 無關。

## 安裝

同一個 `.vsix` 同時支援 Windows 和 Mac，在 VS Code 安裝後會自動判斷系統。

- Windows：見 [Windows安裝說明.md](Windows安裝說明.md)
- Mac：見 [Mac安裝說明.md](Mac安裝說明.md)（不提供 Mac 支援）

`.vsix` 可以從 [Actions](../../actions) 最新一次成功的建置下載（Artifacts 裡的 `spidey-pet-vsix`），或自己打包：

```
python build_vsix.py
```

## 結構

| 路徑 | 內容 |
|---|---|
| `extension/extension.js` | VS Code 擴充：側邊欄、狀態列、啟動桌面版 |
| `extension/media/pet.html` | 側邊欄裡的那一隻 |
| `extension/desktop/SpideyDesktop.cs` | Windows 桌面版（由 `spidey-desktop.ps1` 用 PowerShell 編譯執行） |
| `extension/desktop/SpideyDesktop.swift` | Mac 桌面版（由 `spidey-desktop.sh` 用 swiftc 編譯執行） |
| `extension/desktop/claude-hook.js` | Claude Code hooks 用的通知腳本 |
| `build_vsix.py` | 打包成 `.vsix` |

每次推送都會在雲端的 Windows 和 Mac 上各編譯、試跑一次。
