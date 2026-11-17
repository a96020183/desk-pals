# 上架與簽章（給維護者）

獨立版現在每次推送都會自動打包好，**不用任何帳號、憑證**。下面這些全部是**公開版**（只有原創的續命小隊＋使用者自己做的公仔，見下一段），上架、公開下載就用這些：

| 檔案 | 現在的狀態 | 使用者第一次打開會看到 |
|---|---|---|
| `DeskPals-Setup-<版號>.exe`（Windows 安裝程式） | 未簽章 | SmartScreen「Windows 已保護您的電腦」→ 要按「其他資訊 → 仍要執行」 |
| `DeskPals-<版號>.msix`（Microsoft Store 用） | 未簽章、身分是佔位值 | 不能直接安裝；填好身分後上傳 Partner Center，由 Microsoft 簽 |
| `DeskPals-<版號>.dmg`（Mac） | ad-hoc 簽章、未公證 | 「無法打開」→ 系統設定「仍要打開」（DMG 裡附了說明） |
| `desk-pals-<版號>-win32-x64.vsix`、`-win32-arm64.vsix`（Windows，附 `DeskPals.exe`） | exe 跟安裝程式同一支：設了簽章 secret 就是簽過的 | — |
| `desk-pals-<版號>.vsix`（通用版，Mac 用） | — | — |

下面每一段都是「之後想做再做」：做完把值填進 GitHub，**程式和建置腳本都不用改**，下一次建置就會自動簽章／換上正式身分。

GitHub 的位置：repo →「Settings」→「Secrets and variables」→「Actions」。**Secrets**（加密、看不到內容）放密碼和憑證；**Variables**（明文）放不機密的身分字串。

| 名稱 | 種類 | 用在 | 從哪來 |
|---|---|---|---|
| `MSIX_IDENTITY_NAME` | Variable | MSIX | Partner Center → 產品身分識別 → Package/Identity/Name |
| `MSIX_PUBLISHER` | Variable | MSIX | 同上 → Package/Identity/Publisher（`CN=XXXXXXXX-…`） |
| `MSIX_PUBLISHER_DISPLAY_NAME` | Variable | MSIX | 同上 → Package/Properties/PublisherDisplayName |
| `WINDOWS_SIGN_PFX_BASE64` | Secret | exe、安裝程式（含解除安裝程式） | 程式碼簽章憑證 `.pfx` 轉 base64 |
| `WINDOWS_SIGN_PASSWORD` | Secret | 同上 | `.pfx` 的密碼 |
| `MACOS_CERT_P12_BASE64` | Secret | `.app`、DMG | 「Developer ID Application」憑證匯出的 `.p12` 轉 base64 |
| `MACOS_CERT_PASSWORD` | Secret | 同上 | `.p12` 的密碼 |
| `APPLE_ID` | Secret | 公證 | 開發者帳號的 Apple ID（email） |
| `APPLE_TEAM_ID` | Secret | 公證 | developer.apple.com →「Membership」的 Team ID（10 碼） |
| `APPLE_APP_PASSWORD` | Secret | 公證 | appleid.apple.com →「登入與安全性」→「App 專用密碼」 |
| `MAC_BUNDLE_ID` | Variable（可不設） | `.app` | 預設 `io.github.a96020183.deskpals`；要改就趁第一次正式發版前改（改了使用者要重新允許權限） |
| `GA4_MEASUREMENT_ID` | Variable（可不設） | 公開版的匿名統計（exe、MSIX、安裝程式、vsix、`.app`） | GA4 →「管理 → 資料串流」→ 網頁串流的「評估 ID」（`G-` 開頭） |
| `GA4_API_SECRET` | Secret（可不設） | 同上 | 同一個資料串流 →「Measurement Protocol API 密鑰」→ 建立 |

**匿名統計**（只有公開版；個人版完全不送）：兩個都設了，打包時 `tools/variant.py` 會寫成 `pals/ga4.txt` 跟著 exe（內嵌）、vsix、`.app` 一起出去；沒設＝那一版不回報，程式裡沒有寫死任何 ID。只送 `lineup_pick`（第一次設定選了哪一櫃）和 `day7_active`（滿 7 天第一次打開時開著哪一櫃），每次的 client_id 都是新的亂數；小屋選單可以關。細節見 `extension/desktop/DeskPals.Stats.cs` 開頭，測試是 `test/desktop-store.js`（只送到本機假端點）。注意：api_secret 一定會跟著程式發出去（GA4 Measurement Protocol 的做法就是這樣），別人拿到可以往這個資料串流灌假資料，但看不到任何資料；被灌了就到 GA4 換一把新的密鑰。

轉 base64：Windows PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.pfx")) | Set-Clipboard`；Mac `base64 -i cert.p12 | pbcopy`，貼進 Secret。

---

## 公開版與個人版（上架只能用公開版）

經典一櫃（Spidey、小波、史迪仔、人魚漢頓）、天線寶寶一櫃、皮克敏一櫃是別人的角色。自己玩沒問題，但**放上 Microsoft Store、Steam、Mac 公開下載，等於公開散布**，商店的智慧財產權規定會擋，也可能收到版權方通知。所以建置分成兩種：

| | 公開版（上架、公開下載） | 個人版（只給自己） |
|---|---|---|
| 有哪些公仔 | 續命小隊（原創）＋自己做的公仔（我的櫃） | 全部（加上經典一櫃、天線寶寶一櫃、皮克敏一櫃） |
| 檔名 | `DeskPals-Setup-<版號>.exe`、`DeskPals-<版號>.msix`、`DeskPals-<版號>.dmg`、`desk-pals-<版號>.vsix` | 都帶 `-personal`：`DeskPals-Setup-<版號>-personal.exe`、`desk-pals-<版號>-personal.vsix`（Mac：`DeskPals-<版號>-personal.dmg`） |
| CI artifact | `desk-pals-windows`、`desk-pals-mac`（GitHub Release 只附這兩個裡的檔案） | `personal-build-windows`（測試截圖在 `personal-*-result`）；**不會**附到 Release |
| 本機打包 | `build.ps1`、`build_app.sh`、`build_vsix.py --public`（預設） | `build.ps1 -Variant personal`、`VARIANT=personal build_app.sh`、`build_vsix.py --personal` |

**公開版怎麼來的**：不是另一份程式碼，是 `tools/variant.py` 每次從原始碼「減掉」粉絲作品產生的（輸出在 `build/public/extension`）：

1. 整個檔案不帶：`extension/desktop/DeskPals.Fan.cs`、`DeskPals.Pikmin.cs`、`mac/src/58_fan.swift`、`50_pikmin.swift`（粉絲角色的像素圖、台詞、動作、串場都在這幾個檔）。
2. 共用程式碼裡碰到粉絲角色的地方用註解標記：`// <fan>`…`// </fan>` 整段拿掉、行尾 `//@fan` 那一行拿掉、`// <public> …` 公開版才有的那一行（例如沒選過櫃子時回到續命小隊）。側邊欄 `pet.html`、`extension.js` 也一樣；`package.json` 的角色、櫃子選項由 `variant.py` 直接過濾。標記都是註解，個人版編譯出來的程式跟沒標記時一模一樣。
3. 留下來的註解裡提到粉絲角色的，整段註解拿掉（擴充套件會帶原始碼，所以連註解也不能有）。
4. **guard**：最後把公開版的原始碼、編好的 `DeskPals.exe`（字串常數是 UTF-16，識別字是 UTF-8，兩種都掃）、Mac 執行檔、`.msix`／`.vsix`（打開來掃裡面每個檔）、DMG 裡的 `.app` 掃一遍：角色名字（中英文）、id（`spidey`、`stitch`、`hangyodon`、`tinky`、`dipsy`、`laalaa`、`pkred`…；`po` 太短，只抓 `"po"`、`Po(` 這種寫法）、口頭禪（Thwip、Eh-oh、Ohana、噗咿…）、版權方名字，出現任何一個就建置失敗。Release 步驟發版前也會再掃一次、並確認沒有 `-personal` 的檔案。
   - 沒有放行清單：資料夾、socket、pipe、LaunchAgent、環境變數都叫 DeskPals／desk-pals（Windows `%LOCALAPPDATA%\DeskPals`、Mac `~/Library/Application Support/DeskPals`、`desk-pals.sock`、`local.desk-pals`、`DESKPALS_*`）。舊版「Spidey 小夥伴」的名稱只出現在個人版的升級接手程式（`DeskPals.Fan.cs`、`58_fan.swift`）裡；舊使用者都是個人版，公開版沒有舊安裝要接手。

自己檢查：`python -I tools/variant.py public`（產生並掃公開版）、`python -I tools/variant.py guard <檔案或資料夾…>`（掃任何檔案，例如下載下來的 Release）。

**改程式時**：新的粉絲角色內容放進上面那幾個檔；共用程式碼要分角色寫的地方記得標 `// <fan>`／`//@fan`。忘了標的話，公開版的 guard 或編譯會失敗（CI 會編譯、試跑兩個版本），不會不小心發出去。

---

## Microsoft Store（MSIX，免費）

個人開發者註冊**免費**。上架之後由 Microsoft 簽章、透過 Store 安裝和更新，使用者不會看到 SmartScreen 警告。

1. **註冊**：到 [Partner Center](https://partner.microsoft.com/dashboard/registration) 用 Microsoft 帳號註冊「個人（Individual）」開發者，驗證身分（要上傳證件）。
2. **保留名稱**：「應用程式與遊戲」→「新產品」→「MSIX 或 PWA 應用程式」→ 保留 `公仔櫃 Desk Pals`。名字被用掉了、或想用別的名字的話，`packaging/windows/msix/AppxManifest.xml` 裡兩個「公仔櫃 Desk Pals」（`<DisplayName>` 和 `uap:VisualElements DisplayName`）要改成一模一樣的名字。
3. **抄身分**：這個 App 的「產品管理」→「產品身分識別（Product identity）」，把三個值填到 GitHub **Variables**：
   - `Package/Identity/Name` → `MSIX_IDENTITY_NAME`（例如 `12345YourName.DeskPals`）
   - `Package/Identity/Publisher` → `MSIX_PUBLISHER`（`CN=` 開頭的一串）
   - `Package/Properties/PublisherDisplayName` → `MSIX_PUBLISHER_DISPLAY_NAME`
4. **重新建置**：GitHub「Actions」→「build」→「Run workflow」（或推一個 commit）。從 Artifacts 的 `desk-pals-windows` 拿 `DeskPals-<版號>.msix`（公開版；**不要**用 `personal-build-windows` 裡的任何檔案）。建置記錄裡沒有出現「MSIX identity is a placeholder」就對了。
5. **送審**（「開始提交」）：
   - **套件**：上傳 `.msix`。版本號來自 `extension/package.json`（`0.8.0` → `0.8.0.0`），每次送審都要比上一次大。
   - **受限功能說明**（只剩 `runFullTrust`），可以照抄：
     > Desk Pals is a classic Win32 (.NET Framework, WinForms) desktop companion that draws pixel characters on top of the user's desktop, so it needs runFullTrust. It does not require administrator rights and does not install drivers or services.
     
     0.10.1 起**不再宣告** `unvirtualizedResources`（Store 很少核准）：Store 版在 `%LOCALAPPDATA%\DeskPals` 新建的檔案會放進它自己的私人資料夾（解除安裝時一起清掉），已經存在的檔案（VS Code 擴充套件那份）讀得到、改了會改原檔——所以設定大致上各自一份。VS Code 擴充套件改用 Store 版的執行別名 `%LOCALAPPDATA%\Microsoft\WindowsApps\DeskPals.exe` 判斷「裝了 Store 版」，照樣只連過去、不另外開一份、不建開機捷徑。Claude Code hooks 用的 `%LOCALAPPDATA%\DeskPals\claude-hook.js` 要靠 VS Code 擴充套件放（Store 版寫的那份只有它自己看得到）。
   - **商店資訊（繁體中文）**：說明（README 開頭幾段可以用）、截圖至少一張（`docs/hero.png`、`docs/squad.png`、`docs/custom.png`；Store 要 1366×768 以上）、隱私權政策網址（照片、行事曆都只在本機處理；公開版另有可以關掉的匿名統計——政策裡要寫到，寫一頁說明放在 GitHub Pages 就可以）。
   - **年齡分級**：填問卷（沒有暴力、沒有使用者互動、沒有購買）。
   - **定價**：免費。
6. Store 版的開機自動啟動是 MSIX 的 StartupTask（第一次打開後生效）。第一次設定第二頁有「開機時自動出現」勾選（沒勾＝`StartupTask.Disable()`），之後小屋選單、「設定 → 應用程式 → 啟動」都能開關。「啟動」資料夾裡指著自家 `DeskPals.exe`／`desk-pals.ps1` 的舊捷徑會被拿掉（泡泡會說），別的捷徑不動。
7. 公開版的搗蛋四個都預設關，第一次打開某一個時先跳說明（`DeskPals.Mischief.cs` 的 `MisAskForm`）；從舊版升級的使用者維持原本的開關。

另一條路：Partner Center 也收「EXE／MSI 安裝程式」（直接上架 `DeskPals-Setup-<版號>.exe`），但那條**要先有程式碼簽章憑證**（下一段），而且更新要自己處理，所以先走 MSIX。

## Windows 程式碼簽章（安裝程式、exe；要花錢，可以不做）

只在「不經過 Store、直接給人下載安裝程式」時需要，目的是拿掉 SmartScreen 警告。

- 建置已經接好：有 `WINDOWS_SIGN_PFX_BASE64`＋`WINDOWS_SIGN_PASSWORD` 就用 `signtool` 簽 `DeskPals.exe`、安裝程式和裡面的解除安裝程式（SHA-256、加時間戳）；沒有就跳過。本機打包也一樣：設環境變數 `DESKPALS_SIGN_PFX`（.pfx 路徑）、`DESKPALS_SIGN_PASSWORD`。
- 現在的憑證規定（2023 年起）：OV／EV 程式碼簽章憑證的私鑰都要放在硬體金鑰或雲端 HSM，**大部分新買的憑證拿不到 .pfx 檔**。所以實務上是這幾種：
  - **Azure Artifact Signing（原 Trusted Signing）**：約 US$10／月，微軟的雲端簽章，SmartScreen 信任度最好。個人開發者有開放的國家有限，申請前先確認你的地區可以。
  - **雲端簽章的 CA**（SSL.com eSigner、DigiCert KeyLocker、Certum 等）：一年約 US$100–400，各家有自己的 signtool 外掛。
  - **開源專案**：repo 公開的話，可以申請 SignPath Foundation 的免費簽章。
  
  用雲端簽章時，把 `packaging/windows/build.ps1` 裡 `Sign-File` 那一行指令換成該服務的指令（只有那裡，安裝程式的 `/Sdpsign=` 用同一套參數）。
- 新憑證剛開始用時，SmartScreen 還是可能警告一陣子（要累積下載量），EV／Azure 比較快。

## Apple Developer（US$99／年）：Mac 簽章＋公證

做完之後 DMG 下載下來雙擊就能開，不用去系統設定按「仍要打開」。

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/)（個人，US$99／年）。
2. 在 Mac 的 Xcode →「Settings」→「Accounts」→ 你的帳號 →「Manage Certificates…」→「＋」→「**Developer ID Application**」。（沒有 Xcode：developer.apple.com →「Certificates」→「＋」→「Developer ID Application」，用「鑰匙圈存取」產生 CSR 上傳。）
3. 「鑰匙圈存取」→「我的憑證」→ 對「Developer ID Application: 你的名字 (TEAMID)」按右鍵 →「輸出」→ 存成 `.p12`、設一個密碼。
4. 填 GitHub Secrets：`MACOS_CERT_P12_BASE64`、`MACOS_CERT_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD`（App 專用密碼，不是 Apple ID 密碼）。
5. 重新建置。建置會：hardened runtime 簽 `.app` → 送公證 → staple → 做 DMG → 簽 DMG → 再送公證 → staple。DMG 裡的「第一次打開請看我」說明檔也會自動拿掉。

只填憑證、不填三個 `APPLE_*`：會簽章但不公證（使用者還是會被擋一次，訊息比較友善）。Mac App Store 是另一回事（要沙盒，公仔櫃要看別的視窗的位置，沙盒裡做不到），不建議。

## Steam（Steamworks，US$100／款）

1. 到 [Steamworks](https://partner.steamgames.com/) 註冊，填稅務和銀行資料、驗證身分，付 Steam Direct 費用 **US$100**（這款賣超過 US$1,000 後會退回；免費 App 也要付）。之後拿到 App ID 和 Depot ID（Windows、Mac 各一個 depot）。
2. 建置產物怎麼對應：
   - **Windows depot**：不是放安裝程式，是放「裝好之後的資料夾」內容：`DeskPals.exe`、`claude-hook.js`、`ci-watch.js`（就是公開版的 `dist/DeskPals.exe` 加 `build/public/extension/desktop/` 那兩個 js；不要用 `-personal` 的檔案）。啟動選項：執行檔 `DeskPals.exe`，作業系統 Windows。
   - **Mac depot**：放 `Desk Pals.app`（從 DMG 裡拿；建議先完成上面的公證）。啟動選項：`Desk Pals.app`，作業系統 macOS。
   - 用 SteamPipe（`steamcmd` + `app_build_<AppID>.vdf`）上傳，Steamworks 文件「上傳到 Steam」有範本；上傳後在「SteamPipe → 組建」把組建設到 default 分支。
3. 注意：
   - Steam 版**沒有開機自動啟動**（開機啟動是安裝程式／Store／Mac App 第一次打開時設的；Steam 直接放檔案）。要的話之後在公仔小屋加一個開關。
   - Steam 版和 VS Code 擴充套件不會自動互相認得（`standalone.json` 是安裝程式寫的）；同時開的話也只會跑一個（同一個 pipe），不會打架。
   - 商店頁要：膠囊圖（各種尺寸）、至少 5 張截圖、預告片（建議）、說明、分級問卷；審核通常 3–5 個工作天，上架前至少要有「即將推出」頁面兩週。
   - 一樣只能用公開版（見最上面）。

## 發版（GitHub Release）

1. 改 `extension/package.json` 的 `version`（例如 `0.8.0`）→ commit → 推上 main。安裝程式、MSIX、DMG、vsix 的版號都跟著它。
2. 打 tag 並推上去：`git tag v0.8.0`、`git push origin v0.8.0`。
3. 「build」跑完會自動多一個 release 步驟：檢查 tag 和 `package.json` 的版號一致，再掃一次同人字眼、確認沒有 `-personal` 的檔案，建 GitHub Release，附上公開版的 `DeskPals-Setup-0.8.0.exe`、`DeskPals-0.8.0.dmg`、`desk-pals-0.8.0.vsix`、`DeskPals-0.8.0.msix`，說明自動產生。個人版只在那次建置的 `personal-build-windows` artifact（90 天後 GitHub 會自動刪掉）。

## 本機自己打包

- Windows：`powershell -NoProfile -File packaging\windows\build.ps1`（公開版，產出在 `dist\`）。需要：Python＋Pillow（`pip install pillow`）、[Inno Setup 6](https://jrsoftware.org/isdl.php)、Windows SDK（makeappx／makepri；沒有的話那一步會略過）。`-Steps exe` 只編 exe。個人版：加 `-Variant personal`（預設只打 exe＋安裝程式，檔名帶 `-personal`）。
- Mac：`packaging/mac/build_app.sh`（公開版，產出在 `dist/`）。需要：Xcode Command Line Tools、Python 3＋Pillow。個人版：`VARIANT=personal packaging/mac/build_app.sh`。
- VS Code：`python -I build_vsix.py`（公開版＋個人版都打；`--public`／`--personal` 只打一種）。

測 exe 不要直接雙擊（會在你的桌面上跑起來、跟你正在用的那份搶同一個 pipe）：用 `DESKPALS_OFFSCREEN=1`、`DESKPALS_DATA_DIR=<暫存資料夾>`、`--pipe <自己取的名字>` 跑，再用 `.github/smoke.js` 驅動。
