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
- Pipe → Unix domain socket. Path is passed as argv[1] (default `~/Library/Application Support/SpideyDesktop/spidey.sock`). Same line protocol. `claude-hook.js` and the VS Code extension already speak this.
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

## 續命小隊（original lineup）— not ported yet

`extension/desktop/DeskPals.Original.cs` (Windows, added after the Pikmin lineup) holds the original lineup
「續命小隊」: 半糖 boba / 醒醒 coffee / 糰糰 onigiri / 貼貼 sticky — `Pal` data (art is generated from the design
source `final_art.py` into the `像素圖` block; every pal has HEAD / HEAD_UP / BODY / BODY_UP / BODY_HUG / LEGS_* plus `F_<face>`
rows that are merged into the stacked frame at `FaceRow`, keeping non-'.' pixels of the head), the `Pet` behaviour
(state `"orig"` + `oAct`, like Pikmin's `"pik"`), a grid-paper `ShelfForm` background and the `World` scenes.
DeskPals.cs only has one-line hooks (`P.Orig`, `OrigLineup`, `StartLineup()`); grep `Orig` to find them.
Port it like the Pikmin partial: one new `mac/src/` file, same names. Until then the Mac build falls back to the classic
lineup when asked for `original` (`NormLineup`), and VS Code only passes `-Lineup` when the user set it explicitly.
Note: a fresh install (no `lineup.txt`, `out.txt`, `profile.txt`, `usage.txt`, no old SpideyDesktop folder) starts in
`original` and writes `lineup.txt`.
