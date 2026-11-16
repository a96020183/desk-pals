# Porting DeskPals.cs → Swift (macOS)

Goal: a faithful macOS port of `extension/desktop/DeskPals.cs` (Windows, C# 5, WinForms + GDI+ + Win32)
so the full figure shelf (both lineups, all pets, all scenes, all practical features) runs on a Mac.
Behaviour, timings, pixel art, colours, lines of dialogue (Traditional Chinese) must match the C# exactly
unless the platform forces a difference.

## Layout

```
mac/
  PORTING.md            this file
  assemble.py           concatenates src/*.swift (sorted) → extension/desktop/DeskPals.swift and splices class bodies
  src/
    00_compat.swift     C#/.NET compat shim (List, Dict, DateTime, TimeSpan, Math, Random, String helpers, File/Path/Directory, Environment, Stopwatch, Regex, JSON …)
    01_drawing.swift    System.Drawing shim (Color, Point/PointF/Size/SizeF/Rectangle/RectangleF, Bitmap, Graphics, SolidBrush, Pen, Font, GraphicsPath, LinearGradientBrush, TextRenderer, StringFormat …)
    02_forms.swift      WinForms shim on AppKit (Form, Timer, MouseEventArgs, Cursor, Screen, ContextMenuStrip/ToolStripMenuItem, TextBox/Label/Button/RadioButton, MessageBox …)
    10_platform.swift   port of C# lines 1–581 (App, W, OverlayForm, BubbleForm, BallForm, FxForm, FlashForm, CobwebForm, PetForm, MenuHost) + main entry
    20_pal.swift        C# 582–1571   (Pal)
    30_pet_a.swift      C# 1572–2696  (Pet partial #1 — owns `final class Pet` declaration)
    31_pet_b.swift      C# 2697–3980  (Pet partials: specials, Spidey/Po/Stitch/Hangyodon moves, Teletubbies)
    32_pet_draw.swift   C# 3981–5406  (Fr, Pet drawing, ShelfForm, Pet shelf drawing)
    40_world_a.swift    C# 5407–6819  (World partial #1 — owns `final class World` declaration; scan, shelf mgmt, pipe/socket server, commands)
    41_world_b.swift    C# 6820–8107  (Claude/Codex watch, scenes/Cue, SpriteForm, props)
    42_world_c.swift    C# 8108–9616  (notices, reminders, system stats, downloads, tickets, misc)
    43_ui.swift         C# last section, from "公仔小屋（蛋的右鍵）" to the end (World: features/小屋 menu/只要一隻/設定;
                        Pet.IconPic; Pix pixel helpers; PixelMenu; SetupForm)
    50_pikmin.swift     DeskPals.Pikmin.cs（皮克敏一櫃：Pal／Pet／ShelfForm／World partials；DeskPals.cs 裡的一行 hook 對應到各檔的一行 hook）
    51_original.swift   DeskPals.Original.cs（續命小隊：Pal 資料＋像素圖／Pet「orig」狀態／ShelfForm 方格紙背板／World 串場；hook 同上）
    52_study.swift      DeskPals.Study.cs（讀書小幫手：Ics／School／World 提醒與設定／ExamForm／StudySettingsForm／Pet.DrawCapIcon）
    53_custom.swift     DeskPals.Custom.cs（CuMeta／CuSprite／CuStore／我的櫃／Pet 姿勢與個性／World 選單與 pipe）
    54_custom_lines.swift DeskPals.CustomLines.cs（六種個性的台詞，script 產生）
    55_custom_image.swift DeskPals.CustomImage.cs（CuCut／CuImg：解碼、去背、像素化）
    56_custom_make.swift  DeskPals.CustomMake.cs（CuMaker 做公仔視窗、拖放、開檔／存檔、`custom …` 測試指令）
    57_share.swift      DeskPals.Share.cs（分享短片 GIF89a 編碼器、`.deskpal` 匯出匯入）
    58_fan.swift        DeskPals.Fan.cs（經典一櫃、天線寶寶一櫃的 Pal 資料、專屬動作、串場；個人版才有）
    59_mischief.swift   DeskPals.Mischief.cs（搗蛋：搶游標、下班清場、購物警察、打字太兇；MisSys／MisFake）
    03_shim_custom_a.swift / 04_shim_custom_b.swift  做公仔用到的 shim（Matrix、ColorMatrix 像素處理、拖放、NSOpenPanel／NSSavePanel）
```
(Line numbers above are from the first port and drift as the C# grows — find your range by the section comments.)

Each file owns exactly one line range. Read only your range (plus whatever else you need for reference — grep freely).
The output `extension/desktop/DeskPals.swift` is one file, compiled by `xcrun swiftc -O DeskPals.swift -o DeskPals`.
Build check: `python3 mac/assemble.py && cd extension/desktop && xcrun swiftc -O DeskPals.swift -o /tmp/dp-$USER-check 2>&1 | head -200`
(while other parts are unfinished you will see errors about names from other files — ignore those, fix your own).

## Golden rule: keep the C# shape

Port line-by-line. Keep every type, field, method, local, parameter and constant **name exactly as in C#**
(PascalCase methods stay PascalCase: `Say`, `SetState`, `FillRectangle`). Other files call your members by
their C# names, so renaming anything breaks the build. Keep comments (translate nothing — Chinese comments stay).
Keep the same order of members. Don't "improve", refactor, or merge logic.

### Functions
- All parameters are unlabeled: `void Say(string s, double secs)` → `func Say(_ s: String, _ secs: Double)`. Call sites look like C#: `Say("hi", 1.5)`.
- Overloads stay overloads (Swift resolves by type/arity). Optional/default params keep defaults.
- `out`/`ref` params → `inout` (`_ r: inout RECT`), call with `&`. Declare the variable first with a default.
- Methods returning values: `@discardableResult` when C# callers ignore the result.
- `static` stays `static`. `public/private/readonly` → drop access modifiers (everything internal); `readonly` field → `var` is fine (or `let` if initialised inline and never assigned).
- Properties `{ get { … } set { … } }` → computed properties with same name.
- Delegates/lambdas: `delegate { … }` / `() => …` → Swift closures. `Action` → `() -> Void`, `Action<T>` → `(T) -> Void`, `Func<T>` → `() -> T`.
- Events (`event Action Kicked; Kicked += h; if (Kicked != null) Kicked();`) → `var Kicked: (() -> Void)? = nil`, `Kicked = h` (if C# subscribes several handlers, use an array `[() -> Void]` and append).
- Avoid `self.` capture issues: in escaping closures use `[weak self]` only if needed; plain strong capture is OK (objects live for the app's lifetime).

### Types
| C# | Swift |
|---|---|
| `int`, `long`, `uint`, `byte`, `short` | `Int` (use `Int` everywhere; `UInt32` only for platform APIs) |
| `double`, `float` | `Double` (**float is Double too**; `1.5f` → `1.5`) |
| `bool` / `string` / `char` | `Bool` / `String` / `Character` (`'k'` → `"k"` typed as Character where needed) |
| `IntPtr` | `IntPtr` (= `typealias IntPtr = Int`, `IntPtr.Zero` = 0) — on mac it holds a CGWindowID |
| `T[]` never mutated after creation (art, tables) | `[T]` |
| `T[]` whose elements are mutated through a shared reference (e.g. `double[]` particles stored in a List and changed in place) | `Arr<T>` (reference type, `Arr<Double>([1,2,3])`, `.Length`, subscript) |
| `T[,]` | `[[T]]` (or `Arr<Arr<T>>` if mutated via alias) |
| `List<T>` | `List<T>` (shim **class**, reference semantics: `Add, AddRange, Insert, Remove, RemoveAt, RemoveAll, Clear, Contains, IndexOf, Count, Find, Exists, Sort, ToArray, subscript`, `for x in list` works) |
| `Dictionary<K,V>` | `Dict<K,V>` (shim class: `subscript` get (traps like C# if missing → use `TryGetValue`)/set, `ContainsKey, TryGetValue(k, &v), Remove, Keys, Values, Count, Clear`, iteration yields `KeyValuePair` with `.Key/.Value`) |
| `HashSet<T>` | `HashSet<T>` shim class (`Add` returns Bool, `Contains, Remove, Count, Clear`) |
| `StringBuilder` | `StringBuilder` shim (`Append, AppendLine, ToString, Length`) |
| class-typed field/var that can be null | implicitly-unwrapped optional `T!` so `x == nil` checks and member access both work (`null` → `nil`) |
| struct (`Point`, `Rectangle`, `DateTime`…) | Swift struct (value semantics match) |
| `x as T` / `x is T` | `x as? T` / `x is T` |
| `(int)d` (double → int) | `CInt(d)` (shim: truncates toward zero like C#, never traps on NaN/huge) |
| `(double)i`, `(float)i` | `Double(i)` |
| `d % m` on doubles | `%` works (shim defines `%` for Double = truncatingRemainder) |
| `a ? b : c`, `??` | same |
| `string.IsNullOrEmpty(s)` | `string.IsNullOrEmpty(s)` (shim provides `enum string` with static helpers `IsNullOrEmpty, Join, Format, Empty`) — or `(s ?? "").isEmpty` |
| `s.Length, s.IndexOf, s.Substring, s.StartsWith, s.EndsWith, s.Contains, s.Replace, s.Split, s.Trim, s.ToLower, s.ToUpper, s.PadLeft, s[i]` | same names via String extensions in the shim (`s[i]` → Character, O(1) for ASCII) |
| `x.ToString()` / `ToString("0.0")` / `ToString("D2")` | `.ToString()` / `.ToString("0.0")` shim extensions on Int/Double |
| `Math.Max/Min/Abs/Sin/Cos/Sqrt/Pow/Floor/Ceiling/Round/Atan2/PI/Sign/Exp/Log` | `Math.…` shim, overloaded for Int and Double (`Math.Max(1, 2)` → Int, mixed → write `Double(i)` yourself) |
| `int.Parse / int.TryParse / double.TryParse` | `int.Parse(s)`, `int.TryParse(s, &v)`, `double.TryParse(s, &v)` (shim `enum int`, `enum double`) |
| `try { … } catch { … }` | `do { … }` + `try?` on throwing calls. **Swift traps on index-out-of-range / nil unwrap where C# would throw-and-catch**: inside a C# try block, add explicit guards so the code can't crash. |
| `lock (o) { … }` | `lock(o) { … }` shim (NSLock-based helper) |
| `using (var x = …) { … }` | `do { let x = …; … }` (no Dispose needed; shim `Dispose()` exists as no-op) |
| `foreach (var x in xs)` | `for x in xs` |
| `for (int i = 0; i < n; i++)` | `var i = 0; while i < n { …; i += 1 }` or `for i in 0..<n` **only when n ≥ 0 and loop doesn't mutate i** (Swift ranges trap when upper < lower — use `stride(from:to:by:)` or the shim `Loop(a, b)` which yields nothing when b ≤ a) |
| `switch` with string cases | `switch` (add `default: break`) |
| `goto`, `checked/unchecked` | restructure minimally |
| `const` / `static readonly` | `static let` |
| `Environment.TickCount` / `Stopwatch` | shim |
| `Thread`, `ThreadPool.QueueUserWorkItem` | shim `Thread(closure).Start()` / `ThreadPool.QueueUserWorkItem { }` (background); UI updates via `BeginInvoke { }` (= `DispatchQueue.main.async`) |

Integer arithmetic: Swift will NOT mix Int and Double. Wherever C# relied on implicit promotion, wrap with `Double(...)`.
Integer division and `%` on ints behave as in C# (truncation). Keep that (don't "fix" `w / 2`).
Big arithmetic expressions can hit "expression too complex": split into `let` temps with explicit types.

## Drawing (01_drawing.swift)
Same API as System.Drawing, coordinates **top-left origin, y down, in points** (= Windows pixels at 100%).
`Bitmap(w, h)` is backed by a CGContext at the screen backing scale (crisp on Retina) but its logical size is `w×h`.
`Graphics.FromImage(bmp)`, `g.Clear(c)`, `g.FillRectangle(brush, x, y, w, h)` (Int or Double overloads, and `Rectangle`/`RectangleF`),
`FillEllipse, DrawEllipse, DrawLine, DrawRectangle, DrawArc, FillPolygon, FillPath, DrawPath, DrawString, MeasureString, DrawImage, DrawImageUnscaled,
TranslateTransform, ScaleTransform, RotateTransform, Save/Restore (GraphicsState), SetClip/ResetClip, SmoothingMode, InterpolationMode, PixelOffsetMode, TextRenderingHint, CompositingMode`.
`Color.FromArgb(r,g,b)`, `Color.FromArgb(a,r,g,b)`, `Color.FromArgb(a, color)`, `.R .G .B .A`, `Color.White/Black/Transparent/Empty/Magenta…`.
`SolidBrush(color)` (+ `.Color` settable), `Pen(color, width)`, `Brushes.White`, `Pens.Black`, `Font(name, size, FontStyle.Bold)` ("Microsoft JhengHei UI"/"Segoe UI"/"Consolas" are mapped to PingFang TC / SF / Menlo),
`TextRenderer.MeasureText/DrawText` with `TextFormatFlags`. `GraphicsPath` (`AddArc, AddLine, AddRectangle, AddEllipse, AddPolygon, CloseFigure, StartFigure`). `LinearGradientBrush(p1, p2, c1, c2)` / `(rect, c1, c2, LinearGradientMode/angle)`, `ColorBlend` if used.
`OverlayForm.KEY` (magenta) means "transparent": `g.Clear(KEY)` and fills with KEY clear to transparent on mac.

## Forms (02_forms.swift)
`Form` wraps an `NSPanel` (borderless, non-activating, transparent, all spaces, floating level). Same members:
`Left, Top, Width, Height, Location, Size, ClientSize, Bounds, Visible, Show(), Hide(), Close(), Invalidate(), Refresh(), Opacity, BackColor, TransparencyKey, Cursor, TopMost, ShowInTaskbar, StartPosition, FormBorderStyle, Handle (IntPtr), IsHandleCreated, IsDisposed, BeginInvoke { }, Invoke { }, Controls.Add(...)`.
Override points (Swift `override func`): `OnPaint(_ e: PaintEventArgs)` (`e.Graphics`), `OnPaintBackground`, `OnMouseDown/OnMouseUp/OnMouseMove/OnMouseLeave/OnMouseEnter(_ e: MouseEventArgs)` (`e.Button` is `MouseButtons.Left/Right`, `e.X, e.Y, e.Location`), `OnKeyDown(_ e: KeyEventArgs)`, `OnShown`, `OnFormClosing`, `SetVisibleCore`, `WndProc` (no-op on mac).
`Timer` (WinForms timer on main run loop: `Interval`, `Tick` closure, `Start()`, `Stop()`, `Enabled`). `Cursor.Position` (global, top-left origin). `Control.MouseButtons`, `Control.ModifierKeys`.
`Screen.AllScreens / PrimaryScreen / FromPoint / FromRectangle` with `.Bounds` and `.WorkingArea` (top-left origin, menu bar & Dock excluded from WorkingArea).
`ContextMenuStrip` + `ToolStripMenuItem(text)` (`Click` closure, `Checked`, `CheckOnClick`, `Enabled`, `DropDownItems`) + `ToolStripSeparator` + `ToolStripLabel` (section header) — the app no longer shows these natively: `World.ShowMenu` renders them with `PixelMenu` (both platforms).
`Activated` / `Deactivate` fire when a Form's panel becomes / resigns key. `_overlayKeyable` (override in a borderless Form) = a non-activating panel that can still become key (C#: CreateParams without `WS_EX_NOACTIVATE`) — used by PixelMenu for Esc/arrow keys and close-on-Deactivate.
`Application.Exit()`, `Application.DoEvents()`.

## Platform differences (decisions)
- Pipe → Unix domain socket. Path is passed as argv[1] (default `~/Library/Application Support/DeskPals/desk-pals.sock`). Same line protocol. `claude-hook.js` and the VS Code extension already speak this.
- Window list (EnumWindows / GetWindowRect / class names / titles / IsIconic / foreground / z-order) → `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)`, layer 0 only, skip our own PID, owner name in place of class name, `kCGWindowName` as title when available (may be empty without Screen Recording permission — code must cope). Front-to-back order = z-order. Foreground window = frontmost app's first layer-0 window (`NSWorkspace.shared.frontmostApplication`). See existing `extension/desktop/SpideyDesktop.swift` (≈ line 2100) for working code.
- Full-screen detection: a layer-0 window of the frontmost app covering a whole screen.
- Hotkey Ctrl+Alt+S (RegisterHotKey) → Carbon `RegisterEventHotKey` Control+Option+S (see SpideyDesktop.swift ≈ line 1128).
- Idle seconds → `CGEventSource.secondsSinceLastEventType`.
- Right-click menus: both platforms use the custom-drawn `PixelMenu` (no more TrackPopupMenuEx / NSMenu). Click-outside = World timer polls `Control.MouseButtons` (global on both); Windows also activates the menu and closes it on `Deactivate`, mac makes it key (non-activating) and closes on resign-key. ForceForeground/SetForegroundWindow → `NSApp.activate(ignoringOtherApps: true)` (dialogs only).
- Memory/CPU (GlobalMemoryStatusEx / PerformanceCounter) → `host_statistics64` / `host_processor_info` (or `vm_stat`/`sysctl`).
- FileSystemWatcher on ~/Downloads → `DispatchSource.makeFileSystemObjectSource` on the directory + diff listing (or poll every 2 s).
- `Process.Start(url)` → `NSWorkspace.shared.open(URL)`. `Process.GetProcessesByName("x")` → shim using `NSWorkspace.runningApplications` + `pgrep -x`/`sysctl` (Codex CLI is a node process: match on argv via `ps -axo comm,args`).
- HttpWebRequest/TcpClient → `URLSession` (synchronous wrapper with semaphore is fine on background threads) / `Network` or plain BSD socket connect with timeout.
- Data dir: `DESKPALS_DATA_DIR` env, else `~/Library/Application Support/DeskPals`. Old Spidey (mac SpideyDesktop.swift) bond data: migrate if present (see SpideyDesktop.swift for its file names).
- Fonts: Microsoft JhengHei UI → "PingFang TC"; Segoe UI Emoji → "Apple Color Emoji"; Consolas → "Menlo".
- DPI: Windows used physical pixels and `dpi/96`. On mac use points and treat dpi as 96 (k = 1 ⇒ same sizes as Windows at 100%). Scale `S` stays as C# computes it from 96.
- Log file: `~/Library/Logs/desk-pals.log` (App.Log / App.LogAlways).
- Offscreen test mode (`DESKPALS_OFFSCREEN=1`, `snap` command → PNG) must keep working: it's how we test.
- `DESKPALS_ISOLATED`, preview sheet entry points must keep working (`DeskPals --preview out.png [night]`, `--preview-shelf`, `--preview-tubbies`).

## Splicing class bodies (assemble.py)
Swift extensions can't hold stored instance properties, designated inits or overrides. C# `partial class Pet` / `partial class World`
are spread across files, so:
- The owner file declares the class and puts `//@@BODY Pet` on its own line inside the class body.
- Any file (including the owner) may contribute body members with
  ```swift
  //@@IN Pet
  var foo = 0
  var bar: Pet! = nil
  //@@END
  ```
  at top level. assemble.py moves those lines into the class body at the `//@@BODY` marker.
- Methods go in plain `extension Pet { … }` blocks (static stored properties are allowed in extensions too).
- Nested C# classes (`class StuckInfo` inside World) → top-level `final class World_StuckInfo` is NOT allowed (names must match) — declare them as nested types inside an extension: `extension World { final class StuckInfo { … } }`.

## Done criteria for a part
- Every member of your C# range has a Swift counterpart with the same name and semantics.
- No `TODO`s that drop behaviour. Where mac truly can't do something, implement the closest equivalent and leave a `// mac:` comment.
- Your part has no errors of its own when assembled and compiled (errors referencing names owned by other parts are fine while they're in progress).

## 續命小隊（original lineup）— ported (`mac/src/51_original.swift`)

`extension/desktop/DeskPals.Original.cs` holds the original lineup 「續命小隊」: 半糖 boba / 醒醒 coffee / 糰糰 onigiri / 貼貼 sticky
— `Pal` data (art is generated from the design source `tools/original_art/final_art.py` into the `像素圖` block; every pal has
HEAD / HEAD_UP / BODY / BODY_UP / BODY_HUG / LEGS_* plus `F_<face>` rows merged into the stacked frame at `FaceRow`, keeping non-'.'
pixels of the head), the `Pet` behaviour (state `"orig"` + `oAct`, like Pikmin's `"pik"`), a grid-paper `ShelfForm` background and
the `World` scenes. DeskPals.cs only has one-line hooks (`P.Orig`, `OrigLineup`, `StartLineup()`); grep `Orig` to find them — every
one has a Swift counterpart in the core parts (same count: 56 lines).
When the art changes: re-run `export_cs.py` for the C#, then convert the `像素圖` block the same way (`p.Col('x', …)` → `p.Col("x", …)`,
`new string[] { … };` → `[ … ]`) — the strings must stay byte-identical.
Mac differences (all marked `// mac:`):
- `World.StartLineup()` is `static` (it runs in `World.init` before `super.init`).
- Fresh install = no `lineup.txt`, `out.txt`, `profile.txt`, `usage.txt` in the data dir → `original` (writes `lineup.txt`), same as
  Windows. Windows treats an existing `%LOCALAPPDATA%\SpideyDesktop` folder as "upgraded from old Spidey"; on mac
  `~/Library/Application Support/SpideyDesktop` also held the program and socket in 0.5–0.8, so the mac checks for the old
  Spidey data files `bond.txt` / `pats.txt` in it instead (the files `Migrate()` copies). Both go through `World.LegacyDir()`.
- `OrigPairScene` skips a pair scene when one of the two pets is missing (C# throws inside `Begin` and the exception is swallowed by `Later`).

## 讀書小幫手 — ported (`mac/src/52_study.swift`)

Same names and behaviour as `DeskPals.Study.cs`; hooks in 40/41/42/43 (`StudyTick`, `StudyMsg`, `ExamNear`/`AddStudyMenus`, focus wording,
`StudyPriority`, `StudyFlavor`, `MeetingLike`, `StudyClicked`, `WeekTomatoNote`/`StudyWrapParts`, 讀書小幫手設定…, `StudySnap`,
`Ticket.Kind`/`CourseLine`/`CheckClock(url, what)`/`AddTicketMenus(items, kind)`/`TicketForm(w, accent, kind)`/`BadgeIsCourse`→`DrawCapIcon`).
Mac differences (all marked `// mac:`):
- Time zones: `TimeZone(identifier:)` takes IANA names directly; Windows names from Outlook exports are mapped back through the same
  `IanaToWin` table. `ConvertTimeToUtc` mirrors .NET: a wall time in the spring-forward gap fails (→ retried +1 h like C#), an ambiguous
  fall-back time resolves to standard time. The VTIMEZONE fixed-offset, `UTC`/`Z` and floating = local rules are unchanged.
- Regexes: the `RegexOptions.ECMAScript` patterns are written with explicit ASCII classes (`(?<![A-Za-z0-9_])…(?![A-Za-z0-9_])`, `[0-9]`,
  `[ \t\n\x0B\f\r]`) because `NSRegularExpression` has no ECMAScript mode.
- ICS fetch: `URLSession` on the fetch thread (20 s idle timeout, ≤ 4 redirects, stops at 8 MB of bytes), cache `school-<md5>.ics` via CryptoKit MD5.
- Settings window: the URL box is a multi-line `NSTextField` (Return inserts a newline; no scroll bar).
- `test/desktop-study.js` takes a unix socket path on Mac; CI runs it with `TZ=Asia/Taipei`.

## 自己做的公仔、分享短片、.deskpal — ported (`mac/src/53_custom.swift` … `57_share.swift`)

The table below is the porting map that was used (C# file → Mac approach). CI drives the whole flow offscreen with `.github/custom-smoke.js`
(a generated test image → maker → finish → icon, `.deskpal` export, share GIF).

| C# file | What it is | Mac notes |
|---|---|---|
| `DeskPals.CustomImage.cs` | `CuImg`: decode (EXIF orientation), auto background removal (border k-means → region grow → soft alpha + decontamination → keep main component), brush strokes, crop, pixel-art conversion (median-cut palette, outline), smooth resample, head/hip line guess | Pure pixel math on `int[]` ARGB — port 1:1. Image decode → `CGImageSource` (honour `kCGImagePropertyOrientation`); `LockBits`/`Marshal.Copy` → `CGContext` bitmap buffers. |
| `DeskPals.Custom.cs` | `CuMeta` (meta.json), `CuSprite` (stand bitmap + head/body/leg parts, sheet frames, template PNG), `CuStore` (data dir `custom/<id>/`), `Pal.MakeCu`, lineup `mine` (`custom/mine.txt`), Pet pose/rig renderer (`CuPoseNow`, `CuCompose` = GDI+ `Matrix` transforms onto a small canvas, `CuBlit` = halo via 8 tinted offset draws + night `ColorMatrix`), persona behaviours (cat/dog…), World menus/pipe (`custom …`) | `Matrix` → `CGAffineTransform` (same prepend order: translate·rotate·scale); `ColorMatrix` tint → draw the canvas as a mask filled with the halo colour (`clip(to:mask:)`), night → multiply blend; NearestNeighbor ↔ `interpolationQuality = .none`. |
| `DeskPals.CustomMake.cs` | `CuMaker` form (4 steps, all self-drawn like `SetupForm`; real `TextBox` for the name so IME works), drag-drop, `OpenFileDialog`/`SaveFileDialog`, offscreen `PaintTo`, test pipe commands | `OpenFileDialog` → `NSOpenPanel` (allowedContentTypes png/jpeg/gif/bmp; `.deskpal`), `SaveFileDialog` → `NSSavePanel`; drag-drop → `registerForDraggedTypes([.fileURL])` on the window's content view. |
| `DeskPals.CustomLines.cs` | six personas × full dialogue key set (Po's keys + `x_*` keys) | Pure data — port 1:1 (or generate). |
| `DeskPals.Share.cs` | share clip: scripted frames rendered offscreen via `Pet.ShareDraw` (no screen capture), own GIF89a encoder (median cut + LZW, frame deltas); `.deskpal` = JSON `{deskpal:1, meta, source:<base64 PNG>}` export/import with validation | Port the encoder 1:1 (or use `CGImageDestination` with `kUTTypeGIF`). Output folder `~/Pictures/Desk Pals`; clipboard → `NSPasteboard` with both a file URL and the caption string; "open folder" → `NSWorkspace.activateFileViewerSelecting`. |

Hooks in DeskPals.cs are one-liners (`P.Cu ? … : …`, `if (P.Cu) { CuXxx(); return; }`), next to the existing `P.Pik` hooks — port them in the same places.
`SetupForm` changed: two steps (選公仔 with the "把你家的貓狗變成桌面公仔" hero card + 匯入, 怎麼擺 with 只要一隻 first); the old 你是？(student/work) step and `World.Student` are gone; first run with no `mode.txt` defaults to 只要一隻.

## 搗蛋 — ported (`mac/src/59_mischief.swift`)

Same names and rules as `DeskPals.Mischief.cs`. Everything that touches the real machine goes through `MisSys`; offscreen mode
(`DESKPALS_OFFSCREEN=1`) always uses `MisFake` (records calls, fake cursor／windows／key counter／clock), unless `DESKPALS_MISCHIEF_REAL=1`.
CI drives it with `test/desktop-mischief.js` (same script on both platforms). Hooks in the core parts are one-liners (grep `Mis`):
`Pet.Step` → `MisStep`, `Watch`／`Free` → `MisBusy`, `PaintPet` → `MisDraw`, `TickInner` → `MisTick`, `OnMsg` default → `MisMsg`,
`Act` → `"mischief"`, `Start` → `MisStart`, `QuitAll` → `MisQuit`, `NoticeClicked` → `MisClicked`, `Feat`／`SaveFeatures`／`SetFeat` →
`MisFeatureList`／`MisDefaultOff`／`MisFeatChanged`, `HouseMenu` → `MisHouseMenu`, `Snap` → `MisSnapWins`／`MisSnapCursor`.
Mac differences (all marked `// mac:`):
- Cursor: `SetCursorPos` → `CGWarpMouseCursorPosition` (posts no events) + `CGAssociateMouseAndMouseCursorPosition(1)`.
  "Did the user move": `GetLastInputInfo` → `CGEventSource.secondsSinceLastEventType` turned into a ms timestamp (compared with ±40 ms, same as C#).
- 下班清場: minimize → hide the whole app (`NSRunningApplication.hide`, one window per app, up to 3), restore → `unhide` (+ `activate` for the front one).
  No window capture (needs Screen Recording; `CGWindowListCreateImage` is obsoleted): the fake window is always the drawn cartoon window.
- 打字太兇: low-level keyboard hook → `CGEventSource.counterForEventType(.combinedSessionState, .keyUp)` (a count only). Input Monitoring
  is requested (`IOHIDRequestAccess`) only when the user turns the switch on in the 小屋 menu — never at startup, never from VS Code pushes.
- `MisWin.Pid` (mac only) — the app to hide／unhide.
- Long `+`／`?:` string chains are split (`MisFlags()`) so the Swift type checker doesn't time out.

## 公開版（`python3 mac/assemble.py --public`）

公開版（上架、公開下載）不帶粉絲作品：`50_pikmin.swift`、`58_fan.swift` 整個檔案不組進去，其他檔案裡跟 C# 一樣的標記照 `tools/variant.py`
的規則處理（`// <fan>`…`// </fan>` 整段拿掉、行尾 `//@fan` 那行拿掉、`// <public> …` 換上）。C# 那邊加了標記的地方，Swift 對應的地方也要標；
Swift 沒有 C# 的 `else` 單獨一行的寫法問題，但拿掉 `if` 之後剩下的 `{ … }` 會變成 closure，要寫成 `do { … }`。
輸出 `build/public/extension/desktop/DeskPals.swift`（不進 repo）；CI 會編譯它並跑離屏測試。


## 舊版「Spidey 小夥伴」升級接手（`DeskPals.Fan.cs` ↔ `58_fan.swift`，個人版才有）

`World.LegacyTakeOver()`（`Start()` 裡 `Migrate()` 之後，行尾 `//@fan`）：舊資料夾（Windows `%LOCALAPPDATA%\SpideyDesktop`、Mac
`~/Library/Application Support/SpideyDesktop`）存在才做事 → 叫舊的收工（Windows pipe `spidey-pet-<帳號>`、Mac 舊資料夾裡的 `spidey.sock`）、
拿掉舊的開機啟動（Windows「啟動」資料夾的 `Spidey 小夥伴.lnk`、Mac `~/Library/LaunchAgents/local.spidey-pet.plist`）、舊程式檔和舊 log，
把舊位置的 `claude-hook.js` 換成轉發到 `<DataDir>/claude-hook.js` 的小檔（`~/.claude/settings.json` 的 hooks 可能指著它，settings.json 不動）。
資料只複製不搬走（`Migrate()` 照舊）。測試用 `DESKPALS_LEGACY_DIR`／`DESKPALS_AUTOSTART_DIR`／`DESKPALS_LEGACY_PIPE`（Windows）指到假的；
離屏模式沒指定就完全不碰真的。CI：`.github/legacy-upgrade.js`（upgrade／fresh 兩種）。