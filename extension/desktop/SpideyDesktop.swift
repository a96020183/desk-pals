// Spidey 桌面版（macOS）：整個螢幕亂跑的像素小蜘蛛人。Windows 版 SpideyDesktop.cs 的移植。
// 獨立程式（LaunchAgent 開機啟動、整台電腦都有他）；睡覺／休息提醒看整台電腦的鍵盤滑鼠。
// VS Code 擴充套件／Claude hook 透過 unix socket 送 save / errors / hi / config / act / where / quit /
// claude / tag / typing / birthday。
// 平日 18:00～隔天 06:00 黑化（黑色戰衣＋催下班）。
// 內部所有邏輯都用 Quartz 座標（左上原點、以主螢幕為準、y 往下），畫到 NSWindow 時才轉 Cocoa；
// 所有 NSView 都 isFlipped = true，所以畫圖座標跟 Windows 版一樣是左上原點。
// 編譯：xcrun swiftc -O SpideyDesktop.swift -o SpideyDesktop（由 spidey-desktop.sh 代勞）
import AppKit
import Foundation
import Carbon

// MARK: - 基本工具

struct Box: Equatable {
    var l: Double
    var t: Double
    var r: Double
    var b: Double
    var w: Double { return r - l }
    var h: Double { return b - t }
    func contains(_ px: Double, _ py: Double) -> Bool { return px >= l && px < r && py >= t && py < b }
}

func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return v < lo ? lo : (v > hi ? hi : v) }
func ease(_ v0: Double) -> Double { let v = clampD(v0, 0, 1); return v * v * (3 - 2 * v) }

func primaryHeight() -> Double {
    guard let s = NSScreen.screens.first else { return 0 }
    return Double(s.frame.height)
}
func toQuartz(_ r: NSRect) -> Box {
    let ph = primaryHeight()
    return Box(l: Double(r.minX), t: ph - Double(r.maxY), r: Double(r.maxX), b: ph - Double(r.minY))
}
func toCocoa(_ b: Box) -> NSRect {
    let ph = primaryHeight()
    return NSRect(x: CGFloat(b.l), y: CGFloat(ph - b.b), width: CGFloat(b.w), height: CGFloat(b.h))
}
func cursorQ() -> (x: Double, y: Double) {
    let p = NSEvent.mouseLocation
    return (x: Double(p.x), y: primaryHeight() - Double(p.y))
}

func col(_ hex: UInt32) -> CGColor {
    return CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                   green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                   blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1)
}
// 跟 C# 的 Color.FromArgb(a, r, g, b) 同順序
func argb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> CGColor {
    return CGColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: CGFloat(a) / 255.0)
}
func nscol(_ hex: UInt32) -> NSColor {
    return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                   green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                   blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1)
}

func strokeLine(_ ctx: CGContext, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: CGFloat(x1), y: CGFloat(y1)))
    ctx.addLine(to: CGPoint(x: CGFloat(x2), y: CGFloat(y2)))
    ctx.strokePath()
}

// 系統閒置秒數（整台電腦最後一次鍵盤／滑鼠）
func systemIdleSeconds() -> Double {
    let anyInput = CGEventType(rawValue: ~0)!
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
}

// 固定種子的亂數（窩的網每次長得一樣）
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

let appDir = NSHomeDirectory() + "/Library/Application Support/SpideyDesktop"
let logPath = NSHomeDirectory() + "/Library/Logs/spidey-desktop.log"
var logCount = 0
func logLine(_ s: String) {
    logCount += 1
    if logCount > 60 { return }
    let line = ISO8601DateFormatter().string(from: Date()) + " " + s + "\n"
    guard let d = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: logPath) {
        _ = fh.seekToEndOfFile()
        fh.write(d)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: d, attributes: nil)
    }
}

func readText(_ path: String) -> String? {
    return try? String(contentsOfFile: path, encoding: .utf8)
}
func writeText(_ path: String, _ s: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)
    try? s.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: - 其他 App 的視窗

struct WinInfo {
    var h: UInt32       // CGWindowID
    var pid: pid_t
    var l: Double
    var t: Double
    var r: Double
    var b: Double
    var z: Int          // 0 = 最前面
}

struct Plat {
    var h: UInt32
    var top: Double
    var left: Double
    var right: Double
    var winLeft: Double
}

func boundsOf(_ info: [String: Any]) -> Box? {
    guard let d = info[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: d as CFDictionary) else { return nil }
    return Box(l: Double(r.minX), t: Double(r.minY), r: Double(r.maxX), b: Double(r.maxY))
}

// 單一視窗目前的框；不在畫面上（縮到 Dock、關掉、換到別的桌面）回 nil
func windowBox(_ id: UInt32) -> Box? {
    guard id != 0,
          let arr = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]],
          let info = arr.first else { return nil }
    let onscreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
    if !onscreen { return nil }
    return boundsOf(info)
}

// MARK: - 透明視窗

// 視窗層級（由下到上）：窩 → 煙火 → 他／球／小蛛網 → 鎖住的網子 → 泡泡
let levelNest = NSWindow.Level.floating
let levelPet = NSWindow.Level.statusBar
let levelNet = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
let levelBubble = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

func makePanel(clickThrough: Bool, level: NSWindow.Level) -> OverlayPanel {
    let p = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
    p.isReleasedWhenClosed = false
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = false
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    if clickThrough { p.ignoresMouseEvents = true }   // 會點的視窗不設：保留「透明像素點擊穿透」的預設行為
    p.hidesOnDeactivate = false
    p.becomesKeyOnlyIfNeeded = true
    p.level = level   // 最後設（isFloatingPanel 之類的屬性會改掉 level，所以不用它）
    return p
}

final class PetView: NSView {
    weak var pet: Pet?
    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let pet = pet else { return }
        ctx.clear(bounds)
        pet.paint(ctx)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { pet?.showMenu(event, in: self); return }
        pet?.mouseDown()
    }
    override func mouseUp(with event: NSEvent) { pet?.mouseUp() }
    override func rightMouseDown(with event: NSEvent) { pet?.showMenu(event, in: self) }
}

final class BubbleView: NSView {
    var text = ""
    var alert = false
    var dark = false
    let font: NSFont = NSFont(name: "PingFangTC-Semibold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }

    func set(_ s: String, _ a: Bool, _ d: Bool) {
        if s != text || a != alert || d != dark { text = s; alert = a; dark = d; needsDisplay = true }
    }
    func measure() -> (w: Double, h: Double) {
        let s = (text as NSString).size(withAttributes: [.font: font])
        return (w: ceil(Double(s.width)) + 22, h: ceil(Double(s.height)) + 12 + 7)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        let w = Double(bounds.width), h = Double(bounds.height) - 7
        let line = alert ? col(0xC95454) : (dark ? col(0x7B6BC4) : col(0x2A2F45))
        let fg = alert ? (dark ? nscol(0xFF8A8A) : nscol(0xA83232)) : (dark ? nscol(0xEEEBF8) : nscol(0x2A2F45))
        let fill = dark ? col(0x16171F) : col(0xFFFFFF)
        func rect(_ c: CGColor, _ rx: Double, _ ry: Double, _ rw: Double, _ rh: Double) {
            ctx.setFillColor(c)
            ctx.fill(CGRect(x: CGFloat(rx), y: CGFloat(ry), width: CGFloat(rw), height: CGFloat(rh)))
        }
        // 像素風方框（切角）＋往下的小尾巴
        rect(line, 2, 0, w - 4, h)
        rect(line, 0, 2, w, h - 4)
        rect(line, 1, 1, w - 2, h - 2)
        rect(fill, 3, 2, w - 6, h - 4)
        rect(fill, 2, 3, w - 4, h - 6)
        let cx = floor(w / 2)
        for i in 0..<7 { let d = Double(i); rect(line, cx - 7 + d, h - 2 + d, 14 - 2 * d, 1) }
        for i in 0..<5 { let d = Double(i); rect(fill, cx - 5 + d, h - 2 + d, 10 - 2 * d, 1) }
        ctx.setShouldAntialias(true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let ts = (text as NSString).size(withAttributes: attrs)
        let px = (w - Double(ts.width)) / 2, py = (h - Double(ts.height)) / 2
        (text as NSString).draw(at: NSPoint(x: CGFloat(px), y: CGFloat(py)), withAttributes: attrs)
    }
}

// 右下角的窩：在「右牆」和「地板」之間的一張圓網（框絲、放射絲、中心加固圈、空白區、捕捉螺旋、露珠）。
// 背後那層：框絲＋放射絲＋中心（沒鎖時連捕捉螺旋一起畫）；前面那層（netOnly）：鎖住時，捕捉螺旋由外往內織到他前面。
final class NestView: NSView {
    var hot = false
    var over = false
    var dark = false
    var lock = 0.0          // 0～1：前面那層螺旋織到哪
    var k = 1.0
    var netOnly = false
    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }

    // ---- 幾何：四分之一橢圓的框（中心在螢幕角落），網心偏向角落 ----
    var cx = 0.0, cy = 0.0, rx = 0.0, ry = 0.0, hx = 0.0, hy = 0.0
    var ang: [Double] = []
    var len: [Double] = []

    func build(_ w: Double, _ h: Double) {
        cx = w - 1; cy = h - 1; rx = w * 0.97; ry = h * 0.95
        hx = w * 0.68; hy = h * 0.64
        var rng = SeededRandom(seed: 7)   // 固定種子：每次長得一樣，但帶一點不規則
        let n = 22
        ang = []
        len = []
        for i in 0..<n {
            let a = Double.pi * 2 * Double(i) / Double(n) + (rng.next() - 0.5) * 0.12
            ang.append(a)
            len.append(rayLen(cos(a), sin(a)))
        }
    }

    // 從網心往 (dx,dy) 射出，碰到「右牆／地板／外框弧」的距離
    func rayLen(_ dx: Double, _ dy: Double) -> Double {
        var best = 1e9
        if dx > 1e-6 { best = min(best, (cx - hx) / dx) }
        if dy > 1e-6 { best = min(best, (cy - hy) / dy) }
        let px = (hx - cx) / rx, py = (hy - cy) / ry, qx = dx / rx, qy = dy / ry
        let qa = qx * qx + qy * qy, qb = 2 * (px * qx + py * qy), qc = px * px + py * py - 1
        let disc = qb * qb - 4 * qa * qc
        if disc >= 0 {
            let tt = (-qb + disc.squareRoot()) / (2 * qa)
            if tt > 0 { best = min(best, tt) }
        }
        return max(4, best - 1.5)
    }

    func at(_ i: Int, _ d: Double) -> (x: Double, y: Double) {
        return (x: hx + cos(ang[i]) * d, y: hy + sin(ang[i]) * d)
    }

    func addLine(_ ctx: CGContext, _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
        ctx.move(to: CGPoint(x: CGFloat(a.x), y: CGFloat(a.y)))
        ctx.addLine(to: CGPoint(x: CGFloat(b.x), y: CGFloat(b.y)))
    }

    // 兩點之間微微往網心下垂的絲（三次貝茲）
    func addSag(_ ctx: CGContext, _ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ amt: Double) {
        var mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2
        mx += (hx - mx) * amt
        my += (hy - my) * amt
        ctx.move(to: CGPoint(x: CGFloat(a.x), y: CGFloat(a.y)))
        ctx.addCurve(to: CGPoint(x: CGFloat(b.x), y: CGFloat(b.y)),
                     control1: CGPoint(x: CGFloat((a.x + 2 * mx) / 3), y: CGFloat((a.y + 2 * my) / 3)),
                     control2: CGPoint(x: CGFloat((b.x + 2 * mx) / 3), y: CGFloat((b.y + 2 * my) / 3)))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let w = Double(bounds.width), h = Double(bounds.height)
        if w < 8 || h < 8 { return }
        build(w, h)
        ctx.setShouldAntialias(true)
        ctx.setLineCap(.round)
        let n = ang.count
        let silkC: CGColor = over ? argb(240, 255, 120, 165) : (hot ? argb(235, 255, 175, 200)
            : (dark ? argb(225, 214, 204, 255) : argb(235, 255, 255, 255)))
        let shadeC: CGColor = dark ? argb(110, 30, 20, 60) : argb(95, 50, 60, 90)
        let wR = max(1.1, 1.25 * k), wS = max(0.9, 0.95 * k)
        // 兩次：先畫一層淡陰影，再畫銀白絲 → 深色、淺色背景都看得到
        for pass in 0..<2 {
            let c: CGColor = pass == 0 ? shadeC : silkC
            let radialW: Double = pass == 0 ? wR + 1.4 : wR
            let spiralW: Double = pass == 0 ? wS + 1.2 : wS
            ctx.setStrokeColor(c)
            if !netOnly {
                ctx.setLineWidth(CGFloat(radialW))
                ctx.beginPath()
                // 框絲：沿著放射絲的端點連成的弧（貼牆、貼地的那幾段省略）
                for i in 0..<n {
                    let j = (i + 1) % n
                    let a = at(i, len[i]), b = at(j, len[j])
                    let onEdge = (a.x >= cx - 3 && b.x >= cx - 3) || (a.y >= cy - 3 && b.y >= cy - 3)
                    if !onEdge { addSag(ctx, a, b, 0.03) }
                }
                // 放射絲
                for i in 0..<n { addLine(ctx, at(i, 0), at(i, len[i])) }
                ctx.strokePath()
                // 中心加固圈（約五圈）
                ctx.setLineWidth(CGFloat(spiralW))
                ctx.beginPath()
                for ring in 1...5 {
                    let d = (2.2 + Double(ring) * 2.0) * k
                    for i in 0..<n {
                        let j = (i + 1) % n
                        addLine(ctx, at(i, min(d, len[i])), at(j, min(d, len[j])))
                    }
                }
                ctx.strokePath()
            }
            // 捕捉螺旋：從外往內一圈圈（鎖住時在前面那層畫、帶動畫；沒鎖時畫在背後那層）
            let drawSpiral = netOnly ? lock > 0.001 : lock <= 0.001
            if drawSpiral {
                ctx.setLineWidth(CGFloat(spiralW))
                drawSpiralPath(ctx, netOnly ? lock : 1, pass == 1)
            }
        }
        if over && !netOnly {
            heart(ctx, floor(w * 0.42), floor(h * 0.30), max(2, floor(2 * k)), argb(255, 255, 111, 156))
            heart(ctx, floor(w * 0.70), floor(h * 0.18), max(1, floor(1.4 * k)), argb(255, 255, 143, 176))
        }
    }

    func drawSpiralPath(_ ctx: CGContext, _ prog: Double, _ dew: Bool) {
        let n = ang.count
        let f0 = 0.30, f1 = 0.96   // 中間留空白區，外圈貼近框
        let total = 12 * n
        let shown = Int(ceil(Double(total) * max(0, min(1, prog))))
        var rng = SeededRandom(seed: 11)
        var drops: [(x: Double, y: Double, r: Double)] = []
        ctx.beginPath()
        if shown > 0 {
            for s0 in 0..<shown {
                // 由外往內：s0=0 是最外圈
                let s = total - 1 - s0
                let i = s % n, j = (i + 1) % n
                let fa = f0 + (f1 - f0) * Double(s) / Double(total)
                let fb = f0 + (f1 - f0) * Double(s + 1) / Double(total)
                let a = at(i, len[i] * fa), b = at(j, len[j] * fb)
                addSag(ctx, a, b, 0.035)
                if dew && rng.next() < 0.10 {
                    let rr = (1.1 + rng.next() * 0.9) * k
                    drops.append((x: a.x, y: a.y, r: rr))
                }
            }
        }
        ctx.strokePath()
        for d in drops {
            ctx.setFillColor(argb(150, 120, 170, 230))
            ctx.fillEllipse(in: CGRect(x: CGFloat(d.x - d.r - 0.6), y: CGFloat(d.y - d.r - 0.6), width: CGFloat(2 * d.r + 1.2), height: CGFloat(2 * d.r + 1.2)))
            ctx.setFillColor(argb(235, 255, 255, 255))
            ctx.fillEllipse(in: CGRect(x: CGFloat(d.x - d.r), y: CGFloat(d.y - d.r), width: CGFloat(2 * d.r), height: CGFloat(2 * d.r)))
        }
    }

    func heart(_ ctx: CGContext, _ x: Double, _ y: Double, _ q: Double, _ c: CGColor) {
        let art: [String] = [".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..."]
        ctx.setShouldAntialias(false)
        ctx.setFillColor(c)
        for (r, row) in art.enumerated() {
            for (i, ch) in row.enumerated() where ch == "p" {
                ctx.fill(CGRect(x: CGFloat(x + Double(i) * q), y: CGFloat(y + Double(r) * q), width: CGFloat(q), height: CGFloat(q)))
            }
        }
        ctx.setShouldAntialias(true)
    }
}

// 黏在視窗角落的小蜘蛛網
final class WebView: NSView {
    var right = false
    var lw = 1.0
    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(true)
        let s = Double(bounds.width)
        let ox: Double = right ? s - 1 : 0
        let sx: Double = right ? -1 : 1
        let rings: [Double] = [0.32, 0.58, 0.84]
        let spokes = 5
        ctx.setStrokeColor(col(0x8E97B0))
        ctx.setLineWidth(CGFloat(lw))
        let len = s - lw - 1
        var pts: [[(x: Double, y: Double)]] = []
        for i in 0..<spokes {
            let a = Double.pi / 2 * Double(i) / Double(spokes - 1)
            let dx = cos(a), dy = sin(a)
            strokeLine(ctx, ox, 0, ox + sx * dx * len, dy * len)
            var ring: [(x: Double, y: Double)] = []
            for rr in rings { ring.append((x: ox + sx * dx * len * rr, y: dy * len * rr)) }
            pts.append(ring)
        }
        for j in 0..<rings.count {
            for i in 0..<(spokes - 1) {
                let a = pts[i][j], b = pts[i + 1][j]
                // 往角落微微下垂，比較像網
                let mx = (a.x + b.x) / 2 + (ox - (a.x + b.x) / 2) * 0.12
                let my = (a.y + b.y) / 2 * 0.88
                strokeLine(ctx, a.x, a.y, mx, my)
                strokeLine(ctx, mx, my, b.x, b.y)
            }
        }
    }
}

final class Web {
    let h: UInt32
    let right: Bool
    let born: Double
    let side: Double
    let panel: OverlayPanel
    let view: WebView
    var box: Box? = nil
    init(h: UInt32, right: Bool, side: Double, lw: Double, born: Double) {
        self.h = h; self.right = right; self.side = side; self.born = born
        panel = makePanel(clickThrough: true, level: levelPet)
        view = WebView(frame: NSRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
        view.right = right
        view.lw = lw
        panel.contentView = view
    }
    func close() { panel.orderOut(nil); panel.close() }
}

// 接球用的小球（點得到：點一下就把球丟出去）
final class BallView: NSView {
    weak var pet: Pet?
    var ps = 3.0
    static let artRows: [String] = ["..kkkk..", ".kTTTTk.", "kTTWTTTk", "kTWTTTTk", "kTTTTWTk", "kTTTWTTk", ".kTTTTk.", "..kkkk.."]
    static let art: [[Character]] = BallView.artRows.map { (s: String) -> [Character] in Array(s) }
    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        for (r, row) in BallView.art.enumerated() {
            for (i, c) in row.enumerated() where c != "." {
                let fill: CGColor = c == "k" ? col(0x2A2F45) : (c == "T" ? col(0xD9E84A) : col(0xFFFFFF))
                ctx.setFillColor(fill)
                ctx.fill(CGRect(x: CGFloat(Double(i) * ps), y: CGFloat(Double(r) * ps), width: CGFloat(ps), height: CGFloat(ps)))
            }
        }
    }
    override func mouseDown(with event: NSEvent) { pet?.ballClicked() }
}

// 上版煙火（蓋住一整個螢幕、點得穿）
final class FxView: NSView {
    // x, y, vx, vy, 年齡, 壽命, 顏色, 種類(0 火箭 / 1 火花)
    var parts: [[Double]] = []
    var plan: [[Double]] = []   // 時間, x, 目標 y, 顏色
    var k = 1.0
    var t = 0.0
    var active = false
    static let palette: [CGColor] = {
        let hx: [UInt32] = [0xFF5A5A, 0xFFD84A, 0x5AD1FF, 0xFF8FD8, 0x8CFF8C, 0xFFA64A]
        return hx.map { col($0) }
    }()
    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }

    func rnd() -> Double { return Double.random(in: 0..<1) }
    func R(_ a: Double, _ b: Double) -> Double { return a + rnd() * (b - a) }
    func colorIndex() -> Double { return Double(Int.random(in: 0..<FxView.palette.count)) }

    func start(_ w: Double, _ h: Double) {
        parts = []
        plan = []
        t = 0
        active = true
        for i in 0..<10 {
            plan.append([0.32 * Double(i) + R(0, 0.2), R(0.12, 0.88) * w, R(0.12, 0.45) * h, colorIndex()])
        }
    }

    func step(_ dt: Double) {
        if !active { return }
        t += dt
        let h = Double(bounds.height)
        var i = plan.count - 1
        while i >= 0 {
            let q = plan[i]
            if t >= q[0] {
                parts.append([q[1], h, 0, -(h - q[2]) / 0.45, 0, 0.45, q[3], 0])
                plan.remove(at: i)
            }
            i -= 1
        }
        var born: [[Double]] = []
        var j = parts.count - 1
        while j >= 0 {
            var p = parts[j]
            p[4] += dt
            var dead = false
            if p[7] == 0 {
                p[1] += p[3] * dt
                if p[4] >= p[5] {
                    let n = 40
                    for m in 0..<n {
                        let a = Double.pi * 2 * Double(m) / Double(n) + R(-0.1, 0.1)
                        let sp = R(170, 380) * k
                        let ci: Double = rnd() < 0.7 ? p[6] : colorIndex()
                        born.append([p[0], p[1], cos(a) * sp, sin(a) * sp, 0, R(0.7, 1.15), ci, 1])
                    }
                    dead = true
                }
            } else {
                p[3] += 260 * k * dt
                p[2] *= pow(0.35, dt)
                p[3] *= pow(0.6, dt)
                p[0] += p[2] * dt
                p[1] += p[3] * dt
                if p[4] > p[5] { dead = true }
            }
            if dead { parts.remove(at: j) } else { parts[j] = p }
            j -= 1
        }
        parts.append(contentsOf: born)
        if plan.isEmpty && parts.isEmpty { active = false }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        for p in parts {
            let fading = p[7] == 1 && p[4] > p[5] * 0.7
            if fading && Int(floor(p[4] * 24)) % 2 == 0 { continue }   // 快消失時閃爍
            // 十字星形火花，前半段大、後半段小
            let big: Bool = p[7] == 0 || p[4] < p[5] * 0.45
            let q = floor(max(2, (big ? 2.4 : 1.5) * k))
            let hq = floor(q / 2)
            let px = floor(p[0]), py = floor(p[1])
            let ci = max(0, min(FxView.palette.count - 1, Int(p[6])))
            ctx.setFillColor(FxView.palette[ci])
            ctx.fill(CGRect(x: CGFloat(px - hq), y: CGFloat(py - hq - q), width: CGFloat(q), height: CGFloat(3 * q)))
            ctx.fill(CGRect(x: CGFloat(px - hq - q), y: CGFloat(py - hq), width: CGFloat(3 * q), height: CGFloat(q)))
        }
    }
}

final class Client {
    let fd: Int32
    init(fd: Int32) { self.fd = fd }
}

// Claude 卡住偵測：每個對話紀錄檔的提醒狀態（只在背景佇列存取）
final class StuckInfo {
    var episode = 0.0
    var alerts = 0
    var nextAt = Date.distantPast
}

// MARK: - 寵物本體

final class Pet: NSObject {
    // ---- 像素圖（跟 Windows / 側邊欄版同一隻）----
    static func px(_ a: [String]) -> [[Character]] { return a.map { Array($0) } }
    static let HEAD = Pet.px(["...kkkkkk...", "..krrrrrrk..", ".krRrrrrRrk.", ".krrrRRrrrk.", ".kwwkrrkwwk.", ".kwwwkkwwwk.", ".krwwrrwwrk.", "..krrRRrrk.."])
    static let SLEEPY = Pet.px([".krrrrrrrrk.", ".kkkkrrkkkk.", ".krrrrrrrrk."])
    static let HAPPY = Pet.px([".krkrrrrkrk.", ".kkrkrrkrkk.", ".kprrrrrrpk."])
    static let DIZZY = Pet.px([".kkwkrrkwkk.", ".kwkwkkwkwk.", ".kkwkrrkwkk."])
    static let STAR = Pet.px([".y.", "yyy", ".y."])
    // 配件（12 格寬的格線座標）
    static let SCARF = Pet.px(["..YYYYYYYY..", "......YY....", "......Y....."])
    static let BEANIE = Pet.px([".....WW.....", "....PPPP....", "...PPPPPP...", "..WWWWWWWW.."])
    static let CROWN = Pet.px(["...Y.YY.Y...", "...YYYYYY...", "...YPYYPY..."])
    static let SANTA = Pet.px(["........WW..", ".....SSSS...", "....SSSSSS..", "...WWWWWWWW."])
    static let GLASSES = Pet.px(["..P.P..P.P..", "..PPPkkPPP..", "...P....P..."])
    static let ENVELOPE = Pet.px(["SSS", "SYS", "SSS", "SSS"])
    static let CAKE = Pet.px([".Y..", "PPPP", "WWWW", "PPPP"])
    static let FLAKE = Pet.px([".B.", "BBB", ".B."])
    static let BODY = Pet.px(["...kkkkkk...", "..kbrrrrbk..", ".kbbrkkrbbk.", ".krbrrrrbrk.", "..kbbbbbbk.."])
    static let ARMS_UP = Pet.px(["kr.kkkkkk.rk", "kbkbrrrrbkbk", ".kbbrkkrbbk.", "..kbrrrrbk..", "..kbbbbbbk.."])
    static let ARMS_HUG = Pet.px(["...kkkkkk...", ".kkbrrrrbkk.", "krrrkkkkrrrk", ".kkbrrrrbkk.", "..kbbbbbbk.."])
    static let LEGS_A = Pet.px(["..kbbkkbbk..", "..krrkkrrk..", "..kkk..kkk.."])
    static let LEGS_B = Pet.px(["..kbbkkbbk..", ".krrk..krrk.", ".kkk....kkk."])
    static let HEART = Pet.px([".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..."])
    static let ZZ = Pet.px(["kkkk", "..k.", ".k..", "kkkk"])

    static let LV: [Int] = [0, 0, 15, 50, 120, 250, 500]     // Lv1..Lv6 需要的好感度
    static let UNLOCK: [String] = ["", "", "黃圍巾", "小毛帽", "愛心眼鏡", "金色胸章", "小皇冠"]
    static let PATS_HI: [String] = ["能遇到你真好", "我最喜歡你了 ♥", "今天也要一起喔", "有你在，每天都很開心", "我們是最佳拍檔！"]
    static let CNY: [String] = ["2027-02-06", "2028-01-26", "2029-02-13", "2030-02-03", "2031-01-23", "2032-02-11"]

    static let TALK = ["嗨！今天也一起寫 code 吧", "能力越強，bug 越少！", "蜘蛛感應：你存檔了嗎？", "要不要喝口水？", "整個螢幕都是我的地盤！", "這個視窗頂端風景不錯", "Thwip! 🕸"]
    static let SAVE = ["存好了！👍", "存檔成功，帥！", "Thwip! 已存檔", "穩穩的 👍"]
    // 點他：情緒價值
    static let PATS = ["你今天也很棒！", "累了就休息一下，我陪你", "有我在，bug 不敢來", "我一直都在喔 ♥", "你寫的 code 很帥",
                       "辛苦了，摸摸頭", "不管怎樣我都站你這邊", "今天也謝謝你陪我", "慢慢來，你可以的", "嘿嘿，再摸一下", "你笑起來一定很好看", "有你在我就很安心"]
    static let PATS_D = ["……摸夠了就下班。", "我是擔心你才一直催你。", "你已經很努力了，剩下的明天再說。", "回家好好吃飯，聽到沒？",
                         "哼，就讓你摸一下。", "我不是在撒嬌，是在叫你下班。"]
    static let HUGS = ["抱抱～", "給你一個蜘蛛抱抱 ♥", "辛苦了，抱一下", "(つ´ω`)つ ♥"]
    static let KNOCK = ["叩叩！你在看我嗎？👀", "嘿～螢幕外面的你！", "我可以出去玩嗎？叩叩", "你今天也很努力喔！"]
    // 黑化（平日下班後）台詞
    static let TALK_D = ["都幾點了還不下班？", "老闆不會多給你加班費的。", "……你還在？", "這個 bug 明天還會在，你不用在。", "下班。現在。", "你的床在等你。我也在等你關機。"]
    static let SAVE_D = ["存了就快走。", "存好了。可以關機了吧？", "……存檔。然後下班。"]
    static let HUGS_D = ["……只抱一下。然後下班。", "抱完就回家，聽到沒？", "(つ﹏⊂) 回家啦"]
    static let KNOCK_D = ["叩、叩。下班了沒？", "我在螢幕裡面都看到了，你還在加班。", "再不關機我要黑掉你的螢幕喔（騙你的）"]
    static let NEWWIN_D = ["又開新視窗？想加班？", "……這個也明天再看。", "不准再開了。"]
    static let NEWWIN = ["新視窗！Thwip!", "我來看看這是什麼～", "噴個絲黏上去！"]

    static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let mdFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd"
        return f
    }()

    let S: Double = 4          // 一格像素 = 4pt
    let k: Double
    let SW: Double
    let SH: Double
    let socketPath: String
    let pal: [Character: CGColor]
    let palDark: [Character: CGColor]
    let halo = col(0xFFFFFF)
    let haloDark = col(0xC8C0EC)

    let petPanel: OverlayPanel
    let petView: PetView
    let bubblePanel: OverlayPanel
    let bubbleView: BubbleView
    var webs: [Web] = []
    var hearts: [[Double]] = []          // [x 偏移, 年齡]
    let clientsLock = NSLock()
    var clients: [Client] = []
    var timer: Timer? = nil
    var hotKeyRef: EventHotKeyRef? = nil

    var screens: [(work: Box, frame: Box)] = []
    var wins: [WinInfo] = []                 // 所有看得到的視窗，前面的在前
    var cands: [UInt32: WinInfo] = [:]      // 夠大的「正經視窗」
    var plats: [Plat] = []                   // 可以站的視窗頂端（扣掉被擋住的段）
    var known: Set<UInt32>? = nil

    var lastT = 0.0, nextScan = 0.0, cursorStill = 0.0, seekCd = 20.0, hoverCd = 0.0, newWinCd = 3.0, fgCd = 8.0, lateCd = 120.0
    var lastFg: UInt32 = 0
    var dark = false
    var sysIdle = false
    var darkChecked = -1
    var restMin = 50.0, idleMin = 5.0, sessionStart = 0.0
    var sc = 1.0, gt = 0.0, knock = 0.0      // 敲螢幕：放大倍率、計時、敲的晃動
    var afterGlass = ""
    var lastCursor: (x: Double, y: Double) = (x: -1, y: -1)
    var hidden = false
    var sleepMode = false
    var forceDark: Int = ProcessInfo.processInfo.environment["SPIDEY_FORCE_DARK"] == "1" ? 1 : -1

    // ---- 寵物狀態 ----
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, t = 0.0, anim = 0.0, sense = 0.0, z = 0.0
    var dir = 1
    var state = "air"
    var ax = 0.0, ay = 0.0, L = 0.0, th = 0.0, om = 0.0   // 絲的錨點／擺盪
    var targetL = 0.0
    var hangPhase = 0
    var wallSide = 0, climbDir = 0
    var shootT = 0.0
    var nextAct = ""
    var zipH: UInt32 = 0
    var zipRight = false
    var seekX = 0.0
    var supH: UInt32 = 0                      // 正站在哪個視窗上（0＝螢幕底）
    var supL = 0.0, supR = 0.0, supWinL = 0.0
    var goClimb = false
    var bubble = ""
    var bt = 0.0
    var bubbleAlert = false
    var dragging = false, dragSaid = false
    var dragStart: (x: Double, y: Double) = (x: 0, y: 0)
    var grabDx = 0.0, grabDy = 0.0, dragMoved = 0.0, lastMx = 0.0, lastMy = 0.0, lastMt = 0.0, dvx = 0.0, dvy = 0.0
    var curBox: Box? = nil
    var bubbleBox: Box? = nil
    var clickTimes: [Double] = []
    var sparks: [[Double]] = []               // [x, y, vx, vy, 年齡]（Quartz 座標）
    var patsToday = 0
    var patsDate = ""
    var dizzyOnLand = false

    // ---- 窩 ----
    var caged = false                          // 在窩裡
    var lockVal = 0.0                          // 網子動畫 0→1
    var nestPanel: OverlayPanel? = nil         // 窩（在他後面）
    var nestView: NestView? = nil
    var netPanel: OverlayPanel? = nil          // 網子（鎖住時在他前面）
    var netView: NestView? = nil
    var nestBox: Box? = nil
    var reelT = 0.0, reelX = 0.0, reelY = 0.0  // 噴絲後被拉到弧線上的過渡

    // ---- 好感度 ----
    var xp = 0
    var lastPatDay = ""
    var saveXpCd = 0.0
    var ballXp = 0

    // ---- 節日 ----
    var seasonNow = ""
    var birthday = ""
    var flakes: [[Double]] = []                // 聖誕節的雪：x, y, vx, 年齡

    // ---- 躲起來 ----
    var userHidden = false
    var fsNow = false

    // ---- 接球 ----
    var ballPanel: OverlayPanel? = nil
    var ballView: BallView? = nil
    var ballBox: Box? = nil
    var ballSize = 24.0
    var ballOn = false, fetching = false
    var ballX = 0.0, ballY = 0.0, ballVX = 0.0, ballVY = 0.0, ballIdle = 0.0, catchCd = 0.0

    // ---- 煙火、跳舞、Claude ----
    var fxPanel: OverlayPanel? = nil
    var fxView: FxView? = nil
    var danceCd = 30.0, waitCd = 0.0
    var typingStreak = 0
    var claudeStart: [String: Double] = [:]
    var stuckLine: String? = nil
    var stuckRepeat = 0.0
    let claudeQueue = DispatchQueue(label: "spidey.claude-watch")
    var stuck: [String: StuckInfo] = [:]       // 只在 claudeQueue 上存取

    init(socketPath: String) {
        self.socketPath = socketPath
        k = 4.0 / 3.0
        SW = 12 * 4
        SH = 16 * 4
        var p: [Character: CGColor] = ["k": col(0x2A2F45), "r": col(0xD84A4A), "R": col(0xA83A3A), "b": col(0x3D5FAE), "w": col(0xFFFFFF), "p": col(0xFF6F9C), "y": col(0xFFD84A)]
        var pd: [Character: CGColor] = ["k": col(0x0B0B10), "r": col(0x2C2E3B), "R": col(0x1B1C26), "b": col(0x3E4055), "w": col(0xF6F6FA), "p": col(0xB04A6E), "y": col(0xB9A7FF)]
        // 配件顏色黑化時也不變
        let acc: [Character: CGColor] = ["S": col(0xE23B3B), "W": col(0xFFFFFF), "Y": col(0xF5C842), "P": col(0xFF8FB0), "B": col(0xB8D6FF)]
        for (key, value) in acc { p[key] = value; pd[key] = value }
        pal = p
        palDark = pd
        petPanel = makePanel(clickThrough: false, level: levelPet)
        petView = PetView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel = makePanel(clickThrough: true, level: levelBubble)
        bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        super.init()
        petView.pet = self
        petPanel.contentView = petView
        bubblePanel.contentView = bubbleView
        loadPats()
        if let txt = readText(nestFile()) {
            caged = txt.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }
        loadBond()
        seasonNow = season()
        dark = darkNow()
        darkChecked = Calendar.current.component(.minute, from: Date())
        refreshScreens()
        let c = cursorQ()
        let wa = WA(c.x, c.y)
        x = clampD(c.x - SW / 2, wa.l, wa.r - SW)
        y = wa.t + 4
    }

    func now() -> Double { return ProcessInfo.processInfo.systemUptime }

    func start() {
        startServer()
        lastT = now()
        scan(lastT)
        sessionStart = lastT
        if caged { let nb = nest(); x = nb.l + nb.w / 2 - SW / 2; y = nb.b - SH; setState("walk", 2) }
        say(greeting(), 3.5)
        if daysSincePat() >= 2 { say(dark ? "……你好幾天沒摸我了。哼。" : "你最近都不理我…摸摸我好不好 🥺", 4.5) }
        registerHotKey()
        startClaudeWatch()
        render()
        petPanel.orderFrontRegardless()
        let tm = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    // ================= 主迴圈 =================
    func tick() {
        let n = now()
        let dt = min(0.05, n - lastT)
        lastT = n
        if n >= nextScan { nextScan = n + 0.3; scan(n) }
        if hidden { return }
        if !(dragging && dragUpdate(n, dt)) { watch(dt); step(dt) }
        updateBall(dt)
        if let fv = fxView, fv.active {
            fv.step(dt)
            if !fv.active { fxPanel?.orderOut(nil) }
        }
        render()
    }

    func grounded() -> Bool {
        return state == "walk" || state == "idle" || state == "sleep" || state == "hug" || state == "seek" || state == "dizzy"
            || state == "tug" || state == "fetch" || state == "dance" || state == "kick"
    }
    func setState(_ s: String, _ dur: Double) { state = s; t = dur }
    func say(_ s: String, _ sec: Double, _ alert: Bool = false) { bubble = s; bt = sec; bubbleAlert = alert }
    func rnd() -> Double { return Double.random(in: 0..<1) }
    func R(_ a: Double, _ b: Double) -> Double { return a + rnd() * (b - a) }
    func pick(_ a: [String]) -> String { return a.randomElement() ?? "" }
    func pick(_ normal: [String], _ darkSet: [String]) -> String { return pick(dark ? darkSet : normal) }

    // 平日 18:00 之後到隔天 06:00
    static func isDarkTime(_ d: Date) -> Bool {
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        if h >= 18 {
            let wd = cal.component(.weekday, from: d)          // 1 = 星期日
            return wd >= 2 && wd <= 6
        }
        if h < 6 {
            let yd = cal.component(.weekday, from: d.addingTimeInterval(-86400))
            return yd >= 2 && yd <= 6
        }
        return false
    }
    func darkNow() -> Bool { return forceDark >= 0 ? forceDark == 1 : Pet.isDarkTime(Date()) }

    func jump(_ jvx: Double, _ jvy: Double) { vx = jvx; vy = jvy; supH = 0; setState("air", 0) }
    func hop() { jump(Double(dir) * 60 * k, -260 * k) }
    func goSleep() { z = 0; setState("sleep", 1e9) }
    func wakeIfSleep() { sleepMode = false; if state == "sleep" { setState("walk", 2) } }
    func addHeart() { if hearts.count < 8 { hearts.append([R(-12, 12) * k, 0]) } }

    // ---------- 窩（困龍區）：狀態存在 nest.txt ----------
    func nestFile() -> String { return appDir + "/nest.txt" }
    func saveNest() { writeText(nestFile(), caged ? "1" : "0") }

    // 整個桌面最右邊那台螢幕（同樣靠右取最下面）的右下角
    func nest() -> Box {
        var wa = screens[0].work
        for s in screens {
            let r0 = s.work
            if r0.r > wa.r || (r0.r == wa.r && r0.b > wa.b) { wa = r0 }
        }
        let w = max(SW * 3, floor(170 * k)), h = max(SH * 2 + 8, floor(118 * k))
        return Box(l: wa.r - w - 6, t: wa.b - h, r: wa.r - 6, b: wa.b)
    }

    func inNest(_ px: Double, _ py: Double) -> Bool {
        let nb = nest(), m = 20 * k
        return Box(l: nb.l - m, t: nb.t - m, r: nb.r + m, b: nb.b + m).contains(px, py)
    }

    func updateNest() {
        if nestPanel == nil {
            let bp = makePanel(clickThrough: true, level: levelNest)
            let bv = NestView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            bv.k = k
            bv.netOnly = false
            bp.contentView = bv
            let np = makePanel(clickThrough: true, level: levelNet)
            let nv = NestView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            nv.k = k
            nv.netOnly = true
            np.contentView = nv
            nestPanel = bp; nestView = bv; netPanel = np; netView = nv
        }
        guard let bp = nestPanel, let bv = nestView, let np = netPanel, let nv = netView else { return }
        let nb = nest()
        let hot = dragging && state == "drag"
        let over = hot && inNest(x + SW / 2, y + SH / 2)
        let lk = (lockVal * 100).rounded() / 100
        for v in [bv, nv] {
            if v.hot != hot || v.over != over || v.dark != dark || v.lock != lk {
                v.hot = hot; v.over = over; v.dark = dark; v.lock = lk
                v.needsDisplay = true
            }
        }
        if hidden {
            if bp.isVisible { bp.orderOut(nil) }
            if np.isVisible { np.orderOut(nil) }
            return
        }
        if nestBox != nb {
            nestBox = nb
            bp.setFrame(toCocoa(nb), display: true)
            np.setFrame(toCocoa(nb), display: true)
        }
        if !bp.isVisible { bp.orderFrontRegardless() }
        // 由下到上：窩 → 他 → 網子 → 泡泡（靠視窗層級排；網子點得穿，點他照樣有反應）
        let net = lk > 0.001 && !hot
        if net { if !np.isVisible { np.orderFrontRegardless() } }
        else if np.isVisible { np.orderOut(nil) }
    }

    // 拋物線跳到某一點（腳落在 footY）
    func ballisticTo(_ tx: Double, _ footY: Double) {
        let cx = x + SW / 2, foot = y + SH, g = 900 * k
        let top = WA(cx, y)
        var apex = max(min(foot, footY) - R(60, 130) * k, top.t + SH + 2)
        if apex >= foot { apex = foot - 10 }
        if apex >= footY { apex = footY - 10 }
        let vy0 = -(2 * g * (foot - apex)).squareRoot()
        let tt = -vy0 / g + (2 * (footY - apex) / g).squareRoot()
        let vx0 = (tx - cx) / tt
        dir = vx0 >= 0 ? 1 : -1
        jump(vx0, vy0)
    }

    func goNest(_ announce: Bool) {
        caged = true; saveNest()
        let nb = nest()
        if announce { say(dark ? "……好，我待在窩裡。你也早點回家。" : "好～我在窩裡乖乖待著 ♥", 2.2) }
        if grounded() || state == "glass" { sc = 1; ballisticTo(nb.l + nb.w / 2, nb.b) }
    }

    func leaveNest() {
        caged = false; saveNest()
        say(dark ? "……放我出來了？那我要去催你下班了。" : "自由了！出去玩囉～", 1.8)
        if grounded() { let nb = nest(); ballisticTo(nb.l - R(120, 320) * k, nb.b) }
    }

    // ---------- 點他：每日摸摸次數（pats.txt）----------
    func patsFile() -> String { return appDir + "/pats.txt" }
    func todayString() -> String { return Pet.dayFmt.string(from: Date()) }

    func loadPats() {
        guard let txt = readText(patsFile()) else { return }
        let a = txt.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map { String($0) }
        if a.count == 2 && a[0] == todayString() { patsDate = a[0]; patsToday = Int(a[1]) ?? 0 }
    }

    func bumpPats() {
        let today = todayString()
        if today != patsDate { patsDate = today; patsToday = 0 }
        patsToday += 1
        writeText(patsFile(), patsDate + " " + String(patsToday))
    }

    func burst(_ n: Int) {
        let cx = x + SW / 2, cy = y + SH * 0.35
        for _ in 0..<n {
            let a = rnd() * Double.pi * 2, sp = R(120, 260) * k
            sparks.append([cx, cy, cos(a) * sp, sin(a) * sp - 120 * k, 0])
        }
    }

    // 點他一下（沒拖動）
    func pat() {
        let n = now()
        clickTimes.append(n)
        clickTimes.removeAll { n - $0 > 1.3 }
        let combo = clickTimes.count
        bumpPats()
        lastPatDay = todayString()
        if patsToday <= 30 { addXp(1) } else { saveBond() }
        burst(combo >= 3 ? 10 : 6)
        if state == "sleep" {
            wakeIfSleep()
            hug(dark ? "……是你啊。我沒睡，只是在等你下班。" : "嗯…是你呀 ♥ 我醒了", 2.4)
            return
        }
        if combo >= 5 {
            if grounded() { setState("dizzy", 1.6) } else { dizzyOnLand = true }
            say(dark ? "別、別再點了……頭好暈" : "頭暈了 @@ 你好愛我喔", 2)
            return
        }
        if combo >= 3 {
            say(dark ? "……好癢。不准笑。" : "哈哈哈好癢～", 1.6)
            addHeart()
            if grounded() && state != "dizzy" { jump(Double(dir) * 40 * k, -330 * k) }
            return
        }
        if patsToday % 10 == 0 {
            hug(dark ? "今天第 \(patsToday) 次了……我才沒有很開心。" : "今天第 \(patsToday) 次摸我了，我好開心 ♥", 3)
            addHeart(); addHeart(); addHeart()
            return
        }
        let line: String = !dark && level() >= 4 && rnd() < 0.4 ? pick(Pet.PATS_HI) : pick(Pet.PATS, Pet.PATS_D)
        if grounded() { hug(line, 2.6) }
        else { say(line, 2.2); addHeart() }
    }

    // ---------- 好感度（bond.txt：「xp 最後摸摸日」）----------
    func bondFile() -> String { return appDir + "/bond.txt" }
    func loadBond() {
        guard let txt = readText(bondFile()) else { return }
        let a = txt.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map { String($0) }
        if a.count >= 1 { xp = Int(a[0]) ?? 0 }
        if a.count > 1 { lastPatDay = a[1] }
    }
    func saveBond() { writeText(bondFile(), String(xp) + " " + lastPatDay) }
    func level() -> Int {
        var lv = 1
        for i in 2..<Pet.LV.count where xp >= Pet.LV[i] { lv = i }
        return lv
    }
    func addXp(_ n: Int) {
        let before = level()
        xp += n
        saveBond()
        let after = level()
        if after > before {
            let name = Pet.UNLOCK[after]
            hug(dark ? "……好感度 Lv\(after)。解鎖「\(name)」。我、我才沒有很高興。" : "好感度升到 Lv\(after) 了！解鎖「\(name)」♥", 4)
            addHeart(); addHeart(); addHeart(); burst(14)
        }
    }
    func daysSincePat() -> Int {
        guard let d = Pet.dayFmt.date(from: lastPatDay) else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
    }
    func showBond() {
        let lv = level()
        var got: [String] = []
        if lv >= 2 { for i in 2...lv { got.append(Pet.UNLOCK[i]) } }
        let next = lv < 6 ? "（\(xp)/\(Pet.LV[lv + 1])）" : "（\(xp)，滿級！）"
        let tail = got.isEmpty ? "　多摸摸我就會升級喔" : "　已解鎖：" + got.joined(separator: "、")
        say("好感度 Lv\(lv)" + next + tail, 4.5)
        addHeart()
    }

    // ---------- 節日 ----------
    func season() -> String {
        let n = Date()
        let cal = Calendar.current
        if birthday.count == 5 && Pet.mdFmt.string(from: n) == birthday { return "birthday" }
        for c in Pet.CNY {
            guard let d = Pet.dayFmt.date(from: c) else { continue }
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: n)).day ?? 999
            if diff >= -5 && diff <= 14 { return "cny" }
        }
        let mo = cal.component(.month, from: n), dd = cal.component(.day, from: n)
        if mo == 12 && dd <= 26 { return "xmas" }
        if mo == 1 && dd == 1 { return "newyear" }
        if mo == 10 && dd == 31 { return "halloween" }
        if cal.component(.weekday, from: n) == 6 && cal.component(.hour, from: n) >= 15 && !dark { return "friday" }
        return ""
    }
    func seasonLine() -> String? {
        switch seasonNow {
        case "birthday": return pick(["生日快樂！🎂 今天你最大！", "祝你生日快樂～我做了蛋糕給你", "今天是你的日子，什麼都不准煩惱 ♥"])
        case "cny": return pick(["新年快樂！恭喜發財 🧧", "紅包拿來～（騙你的，這個給你）", "新的一年也一起加油！"])
        case "xmas": return pick(["聖誕快樂！🎄", "我想要的聖誕禮物，就是你準時下班", "叮叮噹～叮叮噹～ ❄"])
        case "newyear": return "新年快樂！今年也請多多指教 ✨"
        case "halloween": return pick(["不給糖就搗蛋！🎃", "我今天扮成……蜘蛛人（本來就是）"])
        case "friday": return pick(["週五了！！撐住！", "小週末～今天準時下班好不好", "再一下下就週末了 ✨"])
        default: return nil
        }
    }

    // ---------- 躲起來（快速鍵 Ctrl+Option+S；Mac 不偵測分享螢幕）----------
    func toggleHide() {
        userHidden = !userHidden
        applyHidden()
        if !userHidden && !hidden { say(dark ? "……我回來了。" : "我回來了～", 1.6) }
    }
    func applyHidden() {
        let want = fsNow || userHidden
        if want == hidden { return }
        hidden = want
        if want {
            petPanel.orderOut(nil)
            bubblePanel.orderOut(nil)
            for f in webs { f.panel.orderOut(nil) }
            nestPanel?.orderOut(nil)
            netPanel?.orderOut(nil)
            ballPanel?.orderOut(nil)
            if let fv = fxView, fv.active { fv.active = false; fxPanel?.orderOut(nil) }
        } else {
            petPanel.orderFrontRegardless()
        }
    }

    // Carbon 全域快速鍵：不需要「輔助使用」權限
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let ud = userData else { return OSStatus(noErr) }
            let target = Unmanaged<Pet>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { target.toggleHide() }
            return OSStatus(noErr)
        }, 1, &spec, me, nil)
        if installed != OSStatus(noErr) { logLine("hotkey handler install failed \(installed)"); return }
        let hkID = EventHotKeyID(signature: OSType(0x5350_4459), id: UInt32(7))   // 'SPDY'
        let mods = UInt32(controlKey) | UInt32(optionKey)
        let st = RegisterEventHotKey(UInt32(kVK_ANSI_S), mods, hkID, GetApplicationEventTarget(), OptionBits(0), &hotKeyRef)
        if st != OSStatus(noErr) { logLine("hotkey Ctrl+Option+S is taken (\(st))") }
    }

    // ---------- 接球 ----------
    func startBall() {
        if caged { say("我在窩裡，先放我出去才能接球～", 1.8); return }
        if ballPanel == nil {
            let ps = max(2, floor(S * 3 / 4))
            ballSize = 8 * ps
            let bp = makePanel(clickThrough: false, level: levelPet)
            let bv = BallView(frame: NSRect(x: 0, y: 0, width: CGFloat(ballSize), height: CGFloat(ballSize)))
            bv.ps = ps
            bv.pet = self
            bp.contentView = bv
            ballPanel = bp
            ballView = bv
        }
        let c = cursorQ()
        ballX = c.x
        ballY = c.y - 20 * k
        ballOn = true
        ballClicked()
    }

    func ballClicked() {
        ballVX = (rnd() < 0.5 ? -1 : 1) * R(350, 800) * k
        ballVY = -R(500, 800) * k
        ballIdle = 0; fetching = true; catchCd = 0.4
        wakeIfSleep()
        if grounded() && !caged { setState("fetch", 15) }
        say(dark ? "……好啦，陪你玩一下。" : pick(["球！我來了！", "等我～", "這次一定接到！"]), 1.2)
    }

    func endBall(_ text: String) {
        ballOn = false; fetching = false
        ballPanel?.orderOut(nil)
        if state == "fetch" { setState("idle", 1) }
        say(text, 2)
    }

    func updateBall(_ dt: Double) {
        if !ballOn { return }
        guard let bp = ballPanel else { return }
        let g = 900 * k, r = ballSize / 2, prevBottom = ballY + r
        ballVY += g * dt; ballX += ballVX * dt; ballY += ballVY * dt
        let wa = WA(ballX, ballY)
        if !inside(ballX - r, ballY) && ballX - r < wa.l { ballX = wa.l + r; ballVX = abs(ballVX) * 0.6 }
        if !inside(ballX + r, ballY) && ballX + r > wa.r { ballX = wa.r - r; ballVX = -abs(ballVX) * 0.6 }
        if ballY - r < wa.t { ballY = wa.t + r; ballVY = abs(ballVY) * 0.5 }
        if ballVY > 0 {
            var best = wa.b
            for p in plats where ballX >= p.left && ballX <= p.right && prevBottom <= p.top + 1 && ballY + r >= p.top && p.top < best { best = p.top }
            if ballY + r >= best {
                ballY = best - r
                if ballVY > 140 * k { ballVY = -ballVY * 0.55; ballVX *= 0.85 }
                else { ballVY = 0; ballVX *= pow(0.15, dt) }
            }
        }
        ballIdle += dt
        if catchCd > 0 { catchCd -= dt }
        if ballIdle > 25 && abs(ballVX) < 8 && ballVY == 0 { endBall(dark ? "……不玩了？那就下班吧。" : "不玩了嗎？好吧～下次再玩 ⚾"); return }
        let scx = x + SW / 2, scy = y + SH / 2
        if fetching && catchCd <= 0 && state != "drag" && abs(ballX - scx) < SW * 0.6 + r && abs(ballY - scy) < SH * 0.6 + r { catchBall() }
        let bl = floor(ballX - r), btp = floor(ballY - r)
        let nb = Box(l: bl, t: btp, r: bl + ballSize, b: btp + ballSize)
        if ballBox != nb { ballBox = nb; bp.setFrame(toCocoa(nb), display: false) }
        if !bp.isVisible { bp.orderFrontRegardless() }
    }

    func catchBall() {
        catchCd = 1.0; fetching = false
        if ballXp < 20 { ballXp += 2; addXp(2) }
        burst(6)
        say(dark ? "……接到了。還你。" : pick(["接到了！還你～", "好球！傳回去！", "嘿嘿，我很厲害吧"]), 1.8)
        // 踢回滑鼠的方向，等你再點球
        let c = cursorQ()
        ballVX = clampD((c.x - ballX) * 1.1, -900 * k, 900 * k)
        ballVY = -R(450, 650) * k
        ballY = min(ballY, y - 4 * k)
        if grounded() { setState("kick", 0.5) }
    }

    func fetch(_ dt: Double) {
        if !ballOn || !fetching { setState("idle", 1); return }
        let cx = x + SW / 2, foot = y + SH, r = ballSize / 2, dxb = ballX - cx
        let resting = ballVY == 0 && abs(ballVX) < 30 * k
        let sameLevel = abs(ballY + r - foot) < 40 * k
        if resting && !sameLevel { ballisticTo(ballX, ballY + r); return }
        if abs(dxb) > 6 {
            dir = dxb > 0 ? 1 : -1
            if moveOnGround(dt, 125 * k) { return }
        } else if ballY < y && ballVY > 0 && ballY > y - 160 * k {
            jump(0, -380 * k)
            return
        }
        if t < 0 { fetching = false; setState("idle", 1); say("球跑太遠了啦～", 1.6) }
    }

    // ---------- 煙火、跳舞、Claude ----------
    func bob() -> Double { return state == "dance" ? abs(sin(anim * 8)) * 6 * k : 0 }

    func celebrate(_ env: String) {
        if hidden { return }
        wakeIfSleep()
        if fxPanel == nil {
            let fp = makePanel(clickThrough: true, level: levelNest)
            let fv = FxView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            fv.k = k
            fp.contentView = fv
            fxPanel = fp
            fxView = fv
        }
        if let fp = fxPanel, let fv = fxView {
            let area = WA(x + SW / 2, y + SH / 2)
            fp.setFrame(toCocoa(area), display: false)
            fv.start(area.w, area.h)
            fp.orderFrontRegardless()
        }
        let line: String = dark ? "上版成功……那現在可以下班了吧？🎆"
            : (env == "prod" ? "上正式機了！🎉 辛苦了！" : (env == "dev" ? "測試機上版成功！🎆" : "上版成功！🎆"))
        if grounded() { setState("dance", 3.5) }
        say(line, 4); addXp(5); burst(10); addHeart(); addHeart()
    }

    func onClaude(_ ev: String, _ sid: String) {
        let n = now()
        if ev == "start" { claudeStart[sid] = n; return }
        if hidden { return }
        let idle = systemIdleSeconds()
        if ev == "done" {
            let elapsed: Double = claudeStart[sid].map { n - $0 } ?? 0
            claudeStart.removeValue(forKey: sid)
            if elapsed < 45 && idle < 30 { return }   // 很快就做完、你也在看 → 不吵你
            wakeIfSleep()
            let text = dark ? "Claude 做完了。你也該收工了。" : "Claude 做完了！快來看 👀"
            if grounded() { startGlass(text) } else { say(text, 4) }
            burst(8); addXp(1)
        } else if ev == "wait" {
            if waitCd > 0 { return }
            waitCd = 20
            wakeIfSleep()
            let text = dark ? "Claude 在等你回答。快點回完快點下班。" : "Claude 在等你回答喔～ 👋"
            if idle >= 30 && grounded() { startGlass(text) }
            else { say(text, 3); if grounded() { jump(0, -260 * k) } }
        }
    }

    // ---------- Claude 卡住偵測（看 ~/.claude/projects 的對話紀錄，不需要 hooks）----------
    // 最後一筆是「Claude 叫了工具」→ 3 分鐘沒新紀錄＝在等你按允許，或指令跑很久（問你問題時 90 秒）
    // 最後一筆是「你的訊息／工具結果」→ 5 分鐘沒回應＝Claude 卡住
    // （Windows 版另外檢查 claude／node 程序在不在；Mac 版省略）
    static func claudeProjectsDir() -> String {
        var cfg = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
        if cfg.isEmpty { cfg = NSHomeDirectory() + "/.claude" }
        return (cfg as NSString).appendingPathComponent("projects")
    }

    func startClaudeWatch() {
        claudeQueue.asyncAfter(deadline: .now() + 20) { [weak self] in self?.claudeWatchTick() }
    }

    func claudeWatchTick() {
        claudeWatchOnce()
        claudeQueue.asyncAfter(deadline: .now() + 15) { [weak self] in self?.claudeWatchTick() }
    }

    static func modDate(_ path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    // 在 claudeQueue 上跑
    func claudeWatchOnce() {
        let fm = FileManager.default
        let root = Pet.claudeProjectsDir()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return }
        guard let pdirs = try? fm.contentsOfDirectory(atPath: root) else { return }
        let nowD = Date()
        var seen = Set<String>()
        for pname in pdirs {
            let pdir = (root as NSString).appendingPathComponent(pname)
            guard let files = try? fm.contentsOfDirectory(atPath: pdir) else { continue }
            for fname in files where fname.hasSuffix(".jsonl") {
                let full = (pdir as NSString).appendingPathComponent(fname)
                guard let mtime = Pet.modDate(full) else { continue }
                var act = mtime
                if nowD.timeIntervalSince(act) > 40 * 60 { continue }
                seen.insert(full)
                let si: StuckInfo
                if let existing = stuck[full] { si = existing } else { si = StuckInfo(); stuck[full] = si }
                if nowD.timeIntervalSince(act) < 85 {
                    if si.alerts > 0 {
                        si.alerts = 0
                        DispatchQueue.main.async { [weak self] in self?.onClaudeUnstuck() }
                    }
                    continue
                }
                // 子代理人還在寫 → 主對話沒卡
                let sub = (pdir as NSString).appendingPathComponent((fname as NSString).deletingPathExtension)
                if let en = fm.enumerator(atPath: sub) {
                    while let rel = en.nextObject() as? String {
                        let p2 = (sub as NSString).appendingPathComponent(rel)
                        if let m2 = Pet.modDate(p2), m2 > act { act = m2 }
                    }
                }
                let quiet = nowD.timeIntervalSince(act)
                if quiet < 85 { continue }
                guard let st = Pet.claudeState(full), st.kind != "idle" else { si.alerts = 0; continue }
                let ask = st.tool == "AskUserQuestion" || st.tool == "ExitPlanMode"
                let limit: Double = st.kind == "tool" ? (ask ? 90 : 180) : 300
                if quiet < limit { continue }
                let ep = act.timeIntervalSince1970
                if si.episode != ep { si.episode = ep; si.alerts = 0 }
                if si.alerts >= 3 || (si.alerts > 0 && Date() < si.nextAt) { continue }
                si.alerts += 1
                si.nextAt = Date().addingTimeInterval(600)
                let mins = max(1, Int((quiet / 60).rounded()))
                let kind = st.kind
                let tool = st.tool
                let title = st.title
                let toolName = tool ?? ""
                DispatchQueue.main.async { [weak self] in
                    logLine("claude stuck: \(kind) \(toolName) \(mins)min \(fname)")
                    self?.onClaudeStuck(kind, tool, title, mins)
                }
            }
        }
        for key in Array(stuck.keys) where !seen.contains(key) { stuck.removeValue(forKey: key) }
    }

    static func jsonObj(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d, options: []) else { return nil }
        return o as? [String: Any]
    }

    // 讀對話紀錄最後一段，找最後一筆主對話：kind = idle／model／tool（nil＝看不出來）
    static func claudeState(_ file: String) -> (kind: String, tool: String?, title: String?)? {
        guard let fh = FileHandle(forReadingAtPath: file) else { return nil }
        let size = fh.seekToEndOfFile()
        let tailBytes: UInt64 = 768 * 1024
        let start: UInt64 = size > tailBytes ? size - tailBytes : 0
        fh.seek(toFileOffset: start)
        let data = fh.readDataToEndOfFile()
        fh.closeFile()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0 {
            if let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) } else { text = "" }
        }
        let lines = text.components(separatedBy: "\n")
        var kind: String? = nil
        var tool: String? = nil
        var title: String? = nil
        if lines.isEmpty { return nil }
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let l = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if l.utf8.count < 2 { continue }
            if title == nil && l.hasPrefix("{\"type\":\"ai-title\"") {
                if let td = Pet.jsonObj(l) { title = td["aiTitle"] as? String }
                if kind != nil { break }
                continue
            }
            if kind != nil {
                if i < lines.count - 400 { break }
                continue
            }
            if !l.contains("\"isSidechain\":false") { continue }
            guard let d = Pet.jsonObj(l) else { continue }
            let type = d["type"] as? String ?? ""
            if type != "user" && type != "assistant" { continue }
            if let meta = d["isMeta"] as? Bool, meta { continue }
            guard let m = d["message"] as? [String: Any] else { continue }
            let content: Any? = m["content"]
            if type == "assistant" {
                let sr = m["stop_reason"] as? String
                if sr == "tool_use" {
                    kind = "tool"
                    if let arr = content as? [Any] {
                        for o in arr {
                            if let c = o as? [String: Any], (c["type"] as? String) == "tool_use" { tool = c["name"] as? String }
                        }
                    }
                } else {
                    kind = sr == nil ? "model" : "idle"
                }
            } else {
                var first: String? = content as? String
                if first == nil, let arr = content as? [Any], let c = arr.first as? [String: Any] {
                    let ctype = c["type"] as? String ?? ""
                    if ctype == "text" {
                        first = c["text"] as? String
                    } else if ctype == "tool_result" {
                        let tc: Any? = c["content"]
                        first = tc as? String
                        if first == nil, let tca = tc as? [Any], let c2 = tca.first as? [String: Any] { first = c2["text"] as? String }
                    }
                }
                let f = String((first ?? "").drop(while: { $0.isWhitespace }))
                let idlePrefixes = ["[Request interrupted", "<command-name>", "<local-command", "<bash-input>", "<bash-stdout>", "<bash-stderr>"]
                kind = idlePrefixes.contains(where: { f.hasPrefix($0) }) ? "idle" : "model"
            }
        }
        guard let kd = kind else { return nil }
        return (kind: kd, tool: tool, title: title)
    }

    func onClaudeStuck(_ kind: String, _ tool: String?, _ title: String?, _ mins: Int) {
        if fsNow { return }   // 全螢幕時不跳出來
        if userHidden { userHidden = false; applyHidden() }
        if hidden { return }
        wakeIfSleep()
        var who = "Claude"
        if let ti = title, !ti.isEmpty {
            who = "Claude（" + (ti.count > 14 ? String(ti.prefix(14)) + "…" : ti) + "）"
        }
        let text: String
        if tool == "AskUserQuestion" || tool == "ExitPlanMode" {
            text = dark ? who + " 在問你問題。回完就下班。" : who + " 在問你問題，等你回答喔～ 🙋"
        } else if kind == "tool" {
            text = dark ? who + " 停了 \(mins) 分鐘。去按一下，然後下班。"
                : who + " 停在「" + (tool ?? "工具") + "」\(mins) 分鐘了，是不是在等你按允許？"
        } else {
            text = dark ? who + " 卡住 \(mins) 分鐘了。去看一眼，看完就下班。"
                : who + " 好像卡住了…\(mins) 分鐘沒動靜，去看看？ 🕷️"
        }
        sense = 2.8   // 蜘蛛感應
        if grounded() && state != "glass" { startGlass(text) } else { say(text, 5, true) }
        stuckLine = text
        stuckRepeat = 3.5   // 敲完玻璃再講一次、講久一點
    }

    func onClaudeUnstuck() {
        if hidden { return }
        stuckLine = nil
        say(dark ? "Claude 動了。" : "Claude 又動起來了！👍", 2)
    }

    func hug(_ text: String, _ sec: Double) {
        if grounded() { setState("hug", sec) }
        say(text, sec)
        addHeart(); addHeart()
    }

    // 滑鼠：停在他身上 → 抱抱；停在他附近同一高度 → 跑過去抱滑鼠
    func watch(_ dt: Double) {
        if let sl = stuckLine {
            stuckRepeat -= dt
            if stuckRepeat <= 0 { say(sl, 6, true); stuckLine = nil }
        }
        seekCd -= dt; hoverCd -= dt; newWinCd -= dt; fgCd -= dt; lateCd -= dt; danceCd -= dt; waitCd -= dt; saveXpCd -= dt
        let c = cursorQ()
        if c.x == lastCursor.x && c.y == lastCursor.y { cursorStill += dt } else { cursorStill = 0; lastCursor = c }
        if !grounded() || state == "hug" || sleepMode || state == "sleep" { return }
        let cx = x + SW / 2
        let onMe = c.x >= x && c.x <= x + SW && c.y >= y && c.y <= y + SH
        if onMe && cursorStill > 1.2 && hoverCd <= 0 { hoverCd = 12; hug("你在摸我嗎？抱抱～", 2.4); return }
        if !caged && !fetching && state != "seek" && seekCd <= 0 && cursorStill > 2.5 && !onMe
            && c.y > y - 40 * k && c.y < y + SH + 8 && abs(c.x - cx) < 380 * k && abs(c.x - cx) > 8 {
            seekX = c.x; seekCd = R(45, 100); setState("seek", 8); say("那是什麼？", 1.2)
        }
    }

    func step(_ dt: Double) {
        anim += dt; t -= dt
        if bt > 0 { bt -= dt }
        if sense > 0 { sense -= dt }
        var i = hearts.count - 1
        while i >= 0 { hearts[i][1] += dt; if hearts[i][1] > 1.6 { hearts.remove(at: i) }; i -= 1 }
        var j = sparks.count - 1
        while j >= 0 {
            sparks[j][3] += 420 * k * dt
            sparks[j][0] += sparks[j][2] * dt
            sparks[j][1] += sparks[j][3] * dt
            sparks[j][4] += dt
            if sparks[j][4] > 0.75 { sparks.remove(at: j) }
            j -= 1
        }
        if seasonNow == "xmas" && rnd() < dt * 3 {
            flakes.append([x + SW / 2 + R(-70, 70) * k, y - R(30, 90) * k, R(-12, 12) * k, 0])
        }
        var f = flakes.count - 1
        while f >= 0 {
            flakes[f][1] += 38 * k * dt
            flakes[f][0] += (flakes[f][2] + sin(flakes[f][3] * 3) * 10 * k) * dt
            flakes[f][3] += dt
            if flakes[f][3] > 2.2 { flakes.remove(at: f) }
            f -= 1
        }
        followFast()
        do {
            // 在窩裡而且落地 → 噴網鎖住；離開窩 → 網子收回（在窩裡跳一下不收網）
            let settled = caged && state != "drag" && (state != "air" || y + SH > nest().t)
            let target: Double = settled ? 1 : 0
            let prevLock = lockVal
            lockVal = target > lockVal ? min(target, lockVal + dt / 0.6) : max(target, lockVal - dt / 0.3)
            if prevLock < 0.5 && lockVal >= 0.5 && target == 1 { say("Thwip! Thwip! 被網住了～", 1.4) }
            if prevLock > 0.5 && lockVal <= 0.5 && target == 0 && !caged { say("啪！", 0.8) }
        }
        let cx = x + SW / 2, midY = y + SH / 2
        let wa = WA(cx, midY)
        switch state {
        case "walk":
            if sleepMode { goSleep(); break }
            if moveOnGround(dt, 40 * k) { break }
            if t < 0 { decide(wa) }
        case "seek": seek(dt)
        case "idle":
            let cp = cursorQ()
            if abs(cp.x - cx) > 20 { dir = cp.x > cx ? 1 : -1 }
            if sleepMode { goSleep() } else if t < 0 { setState("walk", R(3, 6)) }
        case "fetch": fetch(dt)
        case "dance": if t < 0 { setState("idle", R(1, 2)) }
        case "kick": if t < 0 { setState("idle", R(1.5, 3)) }
        case "tug":
            // 抓著網子搖
            if floor(anim * 10) != floor((anim - dt) * 10) {
                let nudge: Double = Int(floor(anim * 10)) % 2 == 0 ? 2 : -2
                x += nudge * k
            }
            if t < 0 { setState("idle", R(1, 2)) }
        case "dizzy":
            if floor(anim * 8) != floor((anim - dt) * 8) { dir = -dir }
            if t < 0 { setState("idle", 1); say(dark ? "……沒事。" : "好、好了，我沒事 ♥", 1.4) }
        case "hug":
            if rnd() < dt * 2.5 { addHeart() }
            if t < 0 { setState("walk", R(2, 4)) }
        case "sleep":
            z += dt
            if t < 0 { setState("walk", 3) }
        case "air": air(dt)
        case "swing": swing(dt, wa)
        case "hang": hang(dt, wa)
        case "climb": climb(dt, wa)
        case "shoot": shoot(dt)
        case "zip": zip(dt)
        case "glass": glass(dt)
        case "peek": peek(dt, wa)
        default: break
        }
    }

    // 回傳 true＝離開地面或換狀態了
    func moveOnGround(_ dt: Double, _ speed: Double) -> Bool {
        let nx = x + Double(dir) * speed * dt, ncx = nx + SW / 2, midY = y + SH / 2
        if caged {
            let nb = nest()
            if nx < nb.l + 4 { x = nb.l + 4; dir = 1; return false }
            if nx + SW > nb.r - 4 { x = nb.r - 4 - SW; dir = -1; return false }
            x = nx; y = nb.b - SH
            return false
        }
        if supH != 0 {
            if ncx < supL || ncx > supR {
                if state == "walk" && !goClimb && rnd() < 0.55 {
                    let right = ncx > supR
                    dir = -dir
                    if rnd() < 0.3 { spinWeb(supH, right) }
                    return false
                }
                x = nx
                jump(Double(dir) * speed * 1.4, -140 * k)
                return true
            }
            x = nx
            return false
        }
        let lead = dir > 0 ? nx + SW - 1 : nx
        if !inside(lead, midY) {
            if state == "walk" && (goClimb || rnd() < 0.35) { startClimb(dir); return true }
            dir = -dir
            return false
        }
        let floorY = WA(ncx, midY).b - SH
        if floorY > y + 2 { x = nx; jump(Double(dir) * speed, 0); return true }
        if floorY < y - 2 { dir = -dir; return false }
        x = nx; y = floorY
        return false
    }

    func decide(_ wa: Box) {
        goClimb = false
        if fetching && ballOn { setState("fetch", 15); return }
        let r = rnd(), cx = x + SW / 2
        if caged {
            // 窩裡：發呆、散步、抱抱、打盹、偶爾敲敲螢幕
            if r < 0.35 { setState("idle", R(2, 5)) }
            else if r < 0.72 { dir = rnd() < 0.5 ? -1 : 1; setState("walk", R(2, 5)) }
            else if r < 0.80 { hug(pick(Pet.HUGS, Pet.HUGS_D), 2.2) }
            else if r < 0.86 { goSleep(); t = R(6, 14) }
            else if r < 0.88 { startGlass(pick(Pet.KNOCK, Pet.KNOCK_D)) }
            else if r < 0.92 { jump(0, -260 * k) }
            else if r < 0.97 {
                setState("tug", 1.8)
                say(dark ? "……把我關起來也沒用，你還是要下班。" : pick(["放我出去嘛～", "這張網好黏喔", "我會乖乖的，放我出去好不好 ♥"]), 2.2)
            }
            else { dir = -dir; setState("walk", R(2, 4)) }
            return
        }
        if r < 0.20 { setState("idle", R(1.5, 4)) }
        else if r < 0.48 { if !jumpToPlatform() { hop() } }
        else if r < 0.62 { if !shootTo("swing") { hop() } }
        else if r < 0.70 { _ = shootTo("hang") }
        else if r < 0.75 { goClimb = true; dir = cx < (wa.l + wa.r) / 2 ? -1 : 1; setState("walk", 30) }
        else if r < 0.80 { hug(pick(Pet.HUGS, Pet.HUGS_D), 2.2) }
        else if r < (dark ? 0.84 : 0.815) { startGlass(pick(Pet.KNOCK, Pet.KNOCK_D)) }
        else if r < 0.86 && lateCd <= 0, let ll = lateLine() { lateCd = dark ? 240 : 600; say(ll, 3.5); setState("idle", 3.5) }
        else if r < 0.90, let sl = seasonLine() { say(sl, 3); setState("idle", 3) }
        else { dir = rnd() < 0.5 ? -1 : 1; setState("walk", R(3, 6)) }
    }

    func seek(_ dt: Double) {
        let c = cursorQ()
        let cx = x + SW / 2
        if abs(c.x - seekX) > 4 {
            if c.y > y - 60 * k && c.y < y + SH + 20 { seekX = c.x }
            else { setState("walk", 2); say("咦，跑掉了…", 1.4); return }
        }
        if abs(seekX - cx) < 6 { hug("抓到你的滑鼠了！抱抱 ♥", 3); return }
        dir = seekX > cx ? 1 : -1
        if moveOnGround(dt, 95 * k) { return }
        let ncx = x + SW / 2
        if (dir > 0 && ncx > seekX) || (dir < 0 && ncx < seekX) { x = seekX - SW / 2 }
        if t < 0 { setState("walk", 2) }
    }

    func jumpToPlatform() -> Bool {
        if !grounded() || caged { return false }
        let cx = x + SW / 2, foot = y + SH
        var opts: [(Double, Double)] = []
        for p in plats {
            if p.h == supH && abs(p.top - foot) < 2 { continue }
            let tx = p.left + SW / 2 + rnd() * max(0, p.right - p.left - SW)
            let dx = tx - cx, dy = p.top - foot
            if abs(dx) < 40 * k || abs(dx) > 900 * k || dy < -600 * k { continue }
            opts.append((tx, p.top))
        }
        if supH != 0 {
            let wa = WA(cx, y)
            opts.append((clampD(cx + R(-400, 400) * k, wa.l + SW, wa.r - SW), wa.b))
        }
        guard let o = opts.randomElement() else { return false }
        let g = 900 * k
        let top = WA(cx, y)
        var apex = max(min(foot, o.1) - R(50, 130) * k, top.t + SH + 2)
        if apex >= foot { apex = foot - 10 }
        if apex >= o.1 { apex = o.1 - 10 }
        let vy0 = -(2 * g * (foot - apex)).squareRoot()
        let tt = -vy0 / g + (2 * (o.1 - apex) / g).squareRoot()
        let vx0 = (o.0 - cx) / tt
        dir = vx0 > 0 ? 1 : -1
        jump(vx0, vy0)
        if rnd() < 0.3 { say("跳～", 0.8) }
        return true
    }

    // ---- 噴絲：錨點一定是真的東西（視窗底邊／角，找不到才用螢幕頂）----
    func pointVisible(_ w: WinInfo, _ px: Double, _ py: Double) -> Bool {
        for o in wins {
            if o.z >= w.z { break }
            if px >= o.l && px < o.r && py >= o.t && py < o.b { return false }
        }
        return true
    }

    func findAnchor(_ vertical: Bool) -> (Double, Double)? {
        let cx = x + SW / 2, hy = y
        let wa = WA(cx, y + SH / 2)
        var opts: [(Double, Double)] = []
        for w in cands.values {
            if w.b > hy - 70 * k || w.b < wa.t + 10 { continue }
            let px: Double
            if vertical {
                if cx < w.l + 6 || cx > w.r - 6 { continue }
                px = cx
            } else {
                px = clampD(cx + Double(dir) * R(60, 220) * k, w.l + 6, w.r - 6)
                if abs(px - cx) > 300 * k { continue }
            }
            if !pointVisible(w, px, w.b - 2) { continue }
            opts.append((px, w.b))
        }
        if !opts.isEmpty && rnd() < 0.85 { return opts.randomElement() }
        let dist = hy - wa.t
        if dist < 90 * k { return nil }
        if vertical { return (cx, wa.t) }
        return (clampD(cx + Double(dir) * min(dist * 0.6, 260 * k), wa.l + 10, wa.r - 10), wa.t)
    }

    func shootTo(_ mode: String) -> Bool {
        if !grounded() || caged { return false }
        guard let a = findAnchor(mode == "hang") else { return false }
        ax = a.0; ay = a.1
        dir = ax >= x + SW / 2 ? 1 : -1
        nextAct = mode; shootT = 0
        setState("shoot", 1)
        say("Thwip!", 0.8)
        return true
    }

    func shoot(_ dt: Double) {
        shootT += dt
        if shootT < 0.18 { return }
        supH = 0
        if nextAct == "swing" {
            let hx = x + SW / 2, hy = y
            let swa = WA(hx, y + SH / 2)
            let maxL = (swa.b - SH) - ay - 24 * k   // 最低點要離地，不然一盪就撞地鬆手
            L = min(((hx - ax) * (hx - ax) + (hy - ay) * (hy - ay)).squareRoot(), maxL)
            if L < 36 * k { jump(Double(dir) * 60 * k, -300 * k); return }
            th = asin(clampD((hx - ax) / L, -0.95, 0.95))
            if abs(th) < 0.5 { th = 0.9 * (hx < ax ? -1 : 1) }
            om = 0
            reelT = 0.18; reelX = x; reelY = y   // 被絲拉到弧線上
            setState("swing", 3.2)
        } else if nextAct == "hang" {
            let wa = WA(ax, y + SH / 2)
            targetL = max(10, min(wa.h * R(0.15, 0.4), wa.b - SH - 10 - ay))
            hangPhase = 0; L = 0
            setState("hang", 99)
        } else {
            setState("zip", 3)
        }
    }

    func swing(_ dt: Double, _ wa: Box) {
        om = (om - (900 * k / L) * sin(th) * dt) * 0.997
        th += om * dt
        let hx = ax + L * sin(th), hy = ay + L * cos(th), floorY = wa.b - SH
        x = hx - SW / 2; y = min(hy, floorY)
        if reelT > 0 {
            let f = ease(1 - reelT / 0.18)
            x = reelX + (x - reelX) * f; y = reelY + (y - reelY) * f
            reelT -= dt
        }
        let vxs = L * cos(th) * om
        if abs(vxs) > 5 { dir = vxs > 0 ? 1 : -1 }
        if t < 0 || hy > floorY + 1 {
            jump(vxs * 0.8, -L * sin(th) * om * 0.8)
            if rnd() < 0.4 { say("呀呼～", 0.9) }
        }
    }

    func hang(_ dt: Double, _ wa: Box) {
        x = ax - SW / 2
        if hangPhase == 0 {
            y -= 700 * k * dt   // 收絲往上拉
            if y <= ay + 4 { y = ay + 4; hangPhase = 1; L = 0; t = 5; say("倒吊看世界～", 2) }
            return
        }
        L = min(targetL, L + 160 * k * dt)
        y = ay + 4 + L + sin(anim * 2.4) * 4 * k
        if t < 0 { jump(0, 0) }
    }

    func zip(_ dt: Double) {
        // 被絲拉向新視窗的頂角，拉到就站上去
        let tx = ax - SW / 2, ty = ay - SH
        let dx = tx - x, dy = ty - y, d = (dx * dx + dy * dy).squareRoot(), sp = 1100 * k * dt
        if dx != 0 { dir = dx > 0 ? 1 : -1 }
        if d > sp && t > 0 { x += dx / d * sp; y += dy / d * sp; return }
        x = tx; y = ty
        for p in plats where p.h == zipH && ax >= p.left - 2 && ax <= p.right + 2 && abs(p.top - ay) < 3 {
            setSupport(p)
            setState("idle", 1.6)
            addWeb(zipH, zipRight)
            say("黏好了！", 1.4)
            return
        }
        jump(0, 0)
    }

    // ---- 第四面牆 ----
    func startGlass(_ text: String) {
        if !grounded() { say(text, 2.5); return }
        let wa = WA(x + SW / 2, y + SH / 2)
        if y + SH - 3.2 * SH < wa.t { say(text, 2.5); return }   // 上面空間不夠放大
        afterGlass = text; gt = 0; sc = 1; knock = 0
        setState("glass", 99)
    }

    func glass(_ dt: Double) {
        let prev = gt
        gt += dt
        let cp = cursorQ()
        dir = cp.x >= x + SW / 2 ? 1 : -1
        if gt < 0.5 { sc = 1 + 2 * ease(gt / 0.5) }
        else if gt < 3.4 {
            sc = 3
            if prev < 0.55 && gt >= 0.55 { say(afterGlass, 2.8) }
            if floor(gt * 2.2) != floor(prev * 2.2) { knock = 0.12 }
        }
        else if gt < 3.9 { sc = 3 - 2 * ease((gt - 3.4) / 0.5) }
        else { sc = 1; setState("idle", 1.2) }
        if knock > 0 { knock -= dt }
    }

    func peek(_ dt: Double, _ wa: Box) {
        // 躲到螢幕外，只露半個身體偷看
        let prev = gt
        gt += dt
        dir = -wallSide
        let hideX = wallSide < 0 ? wa.l - SW * 0.55 : wa.r - SW * 0.45
        let inX = wallSide < 0 ? wa.l : wa.r - SW
        x = gt < 0.4 ? inX + (hideX - inX) * ease(gt / 0.4) : hideX
        if prev <= 0.4 && gt > 0.4 { say("躲貓貓～", 1.2) }
        if t < 0 { x = inX; say("找到我了嗎？嘿嘿", 1.6); climbDir = 1; setState("climb", 99) }
    }

    func hourNow() -> Int { return Calendar.current.component(.hour, from: Date()) }

    func lateLine() -> String? {
        let h = hourNow()
        if dark { return h >= 21 || h < 5 ? "這麼晚了。關機，睡覺。" : "下班時間早就過了喔。" }
        if h >= 23 || h < 5 { return "很晚了耶，早點休息好不好 🌙" }
        if h == 12 { return "午餐吃了沒？" }
        if h == 15 { return "下午茶時間～喝口水吧" }
        return nil
    }

    func greeting() -> String {
        if let sl = seasonLine(), seasonNow != "friday" { return sl }
        if dark { return "……下班時間了。你為什麼還開著電腦？" }
        let h = hourNow()
        if h >= 23 || h < 5 { return "這麼晚還在寫？我陪你 🌙" }
        if h < 11 { return "早安！今天也一起加油 ☀" }
        if h < 14 { return "午安～吃飯了沒？我出來陪你" }
        if h >= 18 { return "晚上了，辛苦啦，我陪你" }
        return "我出來玩啦！整個螢幕都是我的 🕸"
    }

    func appLine(_ pid: pid_t) -> String {
        let app = NSRunningApplication(processIdentifier: pid)
        let bid = (app?.bundleIdentifier ?? "").lowercased()
        let name = (app?.localizedName ?? "").lowercased()
        let browser = bid.contains("chrome") || bid == "com.apple.safari" || bid.contains("edgemac") || bid.contains("firefox")
        let code = bid.hasPrefix("com.microsoft.vscode")
        let excel = bid == "com.microsoft.excel", ppt = bid == "com.microsoft.powerpoint", word = bid == "com.microsoft.word"
        let chat = bid.contains("teams") || bid.contains("slack") || bid == "jp.naver.line.mac" || name == "line"
        if dark {
            if code { return "還在寫 code？下班了啦。" }
            if chat { return "下班了還回訊息？明天再說。" }
            if excel || ppt || word { return "這份明天做也不會怎樣。" }
            return "……你在做什麼？不是該下班了嗎。"
        }
        if browser { return "又在逛網頁？帶我一起看～" }
        if code { return "回來寫 code 啦！我陪你" }
        if excel { return "在算數字喔，加油！" }
        if ppt { return "在做簡報？我幫你盯排版" }
        if word { return "在寫文件～慢慢來" }
        if chat { return "有人找你嗎？" }
        if bid == "com.apple.finder" { return "在找檔案？" }
        return "你在用這個呀？我也來看看"
    }

    // 噴絲把自己拉到某個視窗頂端
    func zipToWindow(_ w: WinInfo, _ text: String) -> Bool {
        if !grounded() || sleepMode || state == "hug" || caged || fetching { return false }
        let cx = x + SW / 2
        var target: Plat? = nil
        var tx = 0.0, bestD = Double.greatestFiniteMagnitude
        for p in plats where p.h == w.h {
            for e in [p.left + SW / 2 + 2, p.right - SW / 2 - 2] {
                let d = abs(e - cx)
                if d < bestD { bestD = d; tx = e; target = p }
            }
        }
        guard let tp = target else { return false }
        if supH == w.h { say(text, 2); return true }
        ax = tx; ay = tp.top; zipH = w.h; zipRight = tx > (w.l + w.r) / 2
        dir = ax >= cx ? 1 : -1
        nextAct = "zip"; shootT = 0
        setState("shoot", 1)
        say(text, 2)
        return true
    }

    func startClimb(_ side: Int) {
        wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = 0
        setState("climb", R(2, 7))
    }

    func climb(_ dt: Double, _ wa: Box) {
        x = wallSide < 0 ? wa.l : wa.r - SW
        if climbDir < 0 {
            y -= 50 * k * dt
            if y <= wa.t + 4 || t < 0 {
                y = max(y, wa.t + 4)
                let cr = rnd()
                if cr < 0.45 { jump(-Double(wallSide) * R(200, 350) * k, -R(150, 300) * k); say("喝！", 0.8) }
                else if cr < 0.75 { gt = 0; setState("peek", R(2.5, 4)) }
                else { climbDir = 1 }
            }
        } else {
            y += 70 * k * dt
            if y >= wa.b - SH { y = wa.b - SH; dir = -wallSide; setState("walk", R(2, 5)) }
        }
    }

    func air(_ dt: Double) {
        let g = 900 * k, prevFoot = y + SH
        vy += g * dt; x += vx * dt; y += vy * dt
        var cx = x + SW / 2
        let midY = y + SH / 2
        let wa = WA(cx, midY)
        if !inside(x, midY) && x < wa.l { x = wa.l; vx = -vx * 0.5 }
        if !inside(x + SW - 1, midY) && x + SW > wa.r { x = wa.r - SW; vx = -vx * 0.5 }
        if caged {
            let nb = nest()
            if y + SH > nb.t {
                if x < nb.l + 4 { x = nb.l + 4; vx = abs(vx) * 0.4 }
                if x + SW > nb.r - 4 { x = nb.r - 4 - SW; vx = -abs(vx) * 0.4 }
            }
        }
        cx = x + SW / 2
        if y < wa.t { y = wa.t; if vy < 0 { vy = 0 } }
        if abs(vx) > 1 { dir = vx > 0 ? 1 : -1 }
        if vy <= 0 { return }
        var best = wa.b
        var bp: Plat? = nil
        for p in plats where cx >= p.left && cx <= p.right && prevFoot <= p.top + 1 && y + SH >= p.top && p.top < best {
            best = p.top; bp = p
        }
        if y + SH >= best {
            y = best - SH; vx = 0; vy = 0
            if let p = bp { setSupport(p) } else { supH = 0 }
            if sleepMode { goSleep() }
            else if dizzyOnLand { dizzyOnLand = false; setState("dizzy", 1.6) }
            else if fetching && ballOn { setState("fetch", 15) }
            else { setState("walk", R(2, 5)) }
        }
    }

    func setSupport(_ p: Plat) { supH = p.h; supL = p.left; supR = p.right; supWinL = p.winLeft }

    // 站著的那個視窗被拖動 → 跟著走
    func followFast() {
        if supH == 0 || !grounded() { return }
        guard let r = windowBox(supH) else { jump(0, 0); say("哇！地板不見了", 1.2); return }
        let dl = r.l - supWinL
        if dl != 0 { x += dl; supL += dl; supR += dl; supWinL = r.l }
        y = r.t - SH
    }

    // ---- 拖曳 ----
    func mouseDown() {
        if state == "glass" || state == "peek" { return }
        let p = cursorQ()
        if p.x < x - 6 || p.x > x + SW + 6 || p.y < y - 6 || p.y > y + SH + 6 { return }
        dragging = true; dragSaid = false; dragStart = p; dragMoved = 0
        grabDx = p.x - x; grabDy = p.y - y
        lastMx = p.x; lastMy = p.y; lastMt = now(); dvx = 0; dvy = 0
    }

    func mouseUp() { if dragging { endDrag() } }

    // 回傳 true＝正在拖（不跑一般邏輯）
    func dragUpdate(_ n: Double, _ dt: Double) -> Bool {
        if (NSEvent.pressedMouseButtons & 1) == 0 { endDrag(); return false }
        let p = cursorQ()
        let mdt = n - lastMt
        if mdt > 0.001 { dvx = dvx * 0.5 + 0.5 * (p.x - lastMx) / mdt; dvy = dvy * 0.5 + 0.5 * (p.y - lastMy) / mdt }
        lastMx = p.x; lastMy = p.y; lastMt = n
        dragMoved = max(dragMoved, abs(p.x - dragStart.x) + abs(p.y - dragStart.y))
        if dragMoved <= 6 { return false }
        if state != "drag" { state = "drag"; supH = 0; sleepMode = false }
        x = p.x - grabDx; y = p.y - grabDy
        anim += dt
        if bt > 0 { bt -= dt }
        if !dragSaid { dragSaid = true; say("哇啊——放我下來！", 1.5) }
        return true
    }

    func endDrag() {
        dragging = false
        if state != "drag" {
            pat()
            return
        }
        if inNest(x + SW / 2, y + SH / 2) {
            // 放進窩裡
            let nb = nest()
            x = clampD(x, nb.l + 4, nb.r - 4 - SW)
            let was = caged
            caged = true; saveNest()
            jump(0, 0)
            if !was { say(dark ? "……好，我待在窩裡。你也早點回家。" : "好～我在窩裡乖乖待著 ♥", 2.2) }
            addHeart()
            return
        }
        if caged { caged = false; saveNest(); say(dark ? "……放我出來了？那我要去催你下班了。" : "自由了！", 1.4) }
        let lim = 2200 * k
        jump(clampD(dvx, -lim, lim), clampD(dvy, -lim, lim))
        if abs(dvx) + abs(dvy) > 900 * k { say("咻——", 0.9) }
    }

    // ---- 選單 ----
    func showMenu(_ event: NSEvent, in view: NSView) {
        let m = NSMenu()
        let items: [(String, String)] = [("抱抱 ♥", "hug"), ("打招呼", "hi"), ("敲敲螢幕", "knock"), ("噴絲擺盪", "swing"),
                                         ("倒吊", "hang"), ("跳到別的視窗上", "jump"), ("去爬牆", "climb"), ("睡覺", "sleep"),
                                         ("丟球給他 ⚾", "ball"), ("我們的感情 ♥", "bond"), ("躲起來（⌃⌥S）", "hide"),
                                         (caged ? "出去玩（離開窩）" : "回窩裡待著", caged ? "free" : "nest")]
        for (title, a) in items {
            let it = NSMenuItem(title: title, action: #selector(menuAct(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = a
            m.addItem(it)
        }
        m.addItem(NSMenuItem.separator())
        let q = NSMenuItem(title: "收工（關掉桌面版）", action: #selector(menuQuit(_:)), keyEquivalent: "")
        q.target = self
        m.addItem(q)
        NSMenu.popUpContextMenu(m, with: event, for: view)
    }

    @objc func menuAct(_ sender: NSMenuItem) {
        if let a = sender.representedObject as? String { act(a) }
    }
    @objc func menuQuit(_ sender: NSMenuItem) { quitAll() }

    // 選單、VS Code 指令、測試共用（socket 訊息 "act <名稱>"）
    func act(_ a: String) {
        if a != "sleep" { wakeIfSleep() }
        switch a {
        case "hi":
            if grounded() { jump(0, -260 * k) }
            say(dark ? "……嗨。下班了嗎？" : "嗨！我是你的 Spidey 👋", 2.4)
        case "hug": hug(pick(Pet.HUGS, Pet.HUGS_D), 2.4)
        case "pat": pat()
        case "ball": startBall()
        case "bond": showBond()
        case "hide": toggleHide()
        case "fireworks": celebrate("dev")
        case "nest": if !caged { goNest(true) }
        case "free": if caged { leaveNest() }
        case "knock": startGlass(pick(Pet.KNOCK, Pet.KNOCK_D))
        case "swing": if !shootTo("swing") { say(caged ? "我在窩裡，先把我放出去～" : "這裡太低了，甩不起來", 1.6) }
        case "hang": if !shootTo("hang") { say(caged ? "我在窩裡，先把我放出去～" : "上面沒地方黏", 1.6) }
        case "jump": if !jumpToPlatform() { say(caged ? "我在窩裡，先把我放出去～" : "附近沒有可以跳的視窗", 1.6) }
        case "climb":
            if caged { say("我在窩裡，先把我放出去～", 1.6) }
            else if grounded() {
                goClimb = true
                let cx = x + SW / 2
                let wa = WA(cx, y)
                dir = cx < (wa.l + wa.r) / 2 ? -1 : 1
                setState("walk", 30)
            }
        case "sleep":
            if grounded() { goSleep(); t = 8; say(dark ? "……你也該睡了。" : "晚安…", 1.2) }
        case "dark": forceDark = 1; darkChecked = -1; checkDark()
        case "light": forceDark = 0; darkChecked = -1; checkDark()
        case "auto": forceDark = -1; darkChecked = -1; checkDark()
        default: break
        }
    }

    // ================= 掃描視窗 =================
    func refreshScreens() {
        var list: [(work: Box, frame: Box)] = []
        for s in NSScreen.screens { list.append((work: toQuartz(s.visibleFrame), frame: toQuartz(s.frame))) }
        if list.isEmpty { list.append((work: Box(l: 0, t: 0, r: 1440, b: 900), frame: Box(l: 0, t: 0, r: 1440, b: 900))) }
        screens = list
    }

    func scan(_ n: Double) {
        refreshScreens()
        let myPid = ProcessInfo.processInfo.processIdentifier
        var nw: [WinInfo] = []
        var nc: [UInt32: WinInfo] = [:]
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
                let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
                let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
                if layer != 0 || pid == myPid || alpha <= 0.01 || num == 0 { continue }
                guard let r = boundsOf(info), r.w >= 4, r.h >= 4 else { continue }
                let w = WinInfo(h: num, pid: pid, l: r.l, t: r.t, r: r.r, b: r.b, z: nw.count)
                nw.append(w)
                if r.w >= 160 && r.h >= 80 { nc[num] = w }   // 拿不到標題（要螢幕錄影權限），只看大小
            }
        }

        var np: [Plat] = []
        for w in nc.values {
            let wa = WA((w.l + w.r) / 2, w.t + 1)
            if w.t - wa.t < SH + 4 || w.t >= wa.b - 4 { continue }
            var segs: [(Double, Double)] = [(max(w.l, wa.l) + 4, min(w.r, wa.r) - 4)]
            var i = 0
            while i < w.z && !segs.isEmpty {
                let f = nw[i]
                if f.t <= w.t - 1 && f.b > w.t - 1 { segs = Pet.cut(segs, f.l, f.r) }
                i += 1
            }
            for s in segs where s.1 - s.0 >= SW {
                np.append(Plat(h: w.h, top: w.t, left: s.0, right: s.1, winLeft: w.l))
            }
        }
        wins = nw; cands = nc; plats = np

        // 站的那段被別的視窗蓋住 → 掉下來
        if supH != 0 && grounded() {
            let cx = x + SW / 2
            var found: Plat? = nil
            for p in plats where p.h == supH && cx >= p.left - 2 && cx <= p.right + 2 { found = p; break }
            if let b = found { supL = b.left; supR = b.right } else { jump(0, 0) }
        }

        // 新視窗／對話框跳出來 → 噴絲黏上去
        if var kn = known {
            var fresh: WinInfo? = nil
            for (h, w) in nc where !kn.contains(h) { kn.insert(h); fresh = w }
            kn = kn.filter { nc[$0] != nil }
            known = kn
            if let f = fresh, newWinCd <= 0 && !hidden && !dragging { reactNewWindow(f) }
        } else {
            known = Set(nc.keys)
        }

        // 你切到哪個 App／視窗，他常常跟過去
        var fgWin: WinInfo? = nil
        if let front = NSWorkspace.shared.frontmostApplication {
            let fpid = front.processIdentifier
            for w in wins where w.pid == fpid { fgWin = w; break }
            let fgw = fgWin?.h ?? 0
            if fgw != lastFg {
                lastFg = fgw
                if fgCd <= 0 && !hidden && !dragging && rnd() < 0.55, let fw = cands[fgw] {
                    if zipToWindow(fw, appLine(fpid)) { fgCd = R(20, 40) }
                }
            }
        }

        systemActivity(n)
        checkDark()
        updateWebs(n)
        fullscreenCheck(fgWin)
        updateNest()
    }

    // 整台電腦的鍵盤滑鼠：太久沒動 → 睡覺；回來 → 敲螢幕迎接；連續用太久 → 提醒休息
    func systemActivity(_ n: Double) {
        let idle = systemIdleSeconds()
        if !sysIdle && idle > idleMin * 60 {
            sysIdle = true
            sleepMode = true
            if grounded() && state != "hug" && state != "glass" { goSleep() }
        } else if sysIdle && idle < 2 {
            sysIdle = false
            sessionStart = n
            let was = state == "sleep"
            wakeIfSleep()
            if was { startGlass(dark ? "……你回來了。是要來關機的吧？" : "你回來啦！我等你好久 ♥") }
        }
        if !sysIdle && n - sessionStart >= restMin * 60 {
            sessionStart = n
            wakeIfSleep()
            let m = restMin == restMin.rounded() ? String(Int(restMin)) : String(restMin)
            hug(dark ? "連續 " + m + " 分鐘了。站起來。然後下班。" : "已經連續用 " + m + " 分鐘了，起來喝水伸展一下吧 🥤", 8)
        }
    }

    func checkDark() {
        let minute = Calendar.current.component(.minute, from: Date())
        if minute == darkChecked { return }
        darkChecked = minute
        seasonNow = season()
        let d = darkNow()
        if d == dark { return }
        dark = d
        if d { sense = 2.5; startGlass("……下班時間到了。") } else { say("早安，我又變回來了 ☀", 3) }
    }

    static func cut(_ segs: [(Double, Double)], _ a: Double, _ b: Double) -> [(Double, Double)] {
        var res: [(Double, Double)] = []
        for s in segs {
            if b <= s.0 || a >= s.1 { res.append(s); continue }
            if a > s.0 { res.append((s.0, a - 1)) }
            if b < s.1 { res.append((b + 1, s.1)) }
        }
        return res
    }

    func reactNewWindow(_ w: WinInfo) {
        if !grounded() || sleepMode || state == "hug" { return }
        newWinCd = 6; fgCd = max(fgCd, 6)
        if !zipToWindow(w, pick(Pet.NEWWIN, Pet.NEWWIN_D)) { say("有新視窗！👀", 1.5) }
    }

    // ---- 蜘蛛網 ----
    func spinWeb(_ h: UInt32, _ right: Bool) {
        guard let w = cands[h] else { return }
        let edge = right ? supR : supL, corner = right ? w.r : w.l
        if abs(edge - corner) > 12 { return }   // 只在真正的視窗角落織
        addWeb(h, right)
        setState("idle", 1.4)
        say("在這裡織個網～", 1.6)
    }

    func addWeb(_ h: UInt32, _ right: Bool) {
        for f in webs where f.h == h && f.right == right { return }
        if webs.count >= 4 { webs[0].close(); webs.remove(at: 0) }
        let web = Web(h: h, right: right, side: floor(34 * k), lw: max(1, k.rounded()), born: now())
        webs.append(web)
        placeWeb(web)
    }

    func placeWeb(_ f: Web) {
        var ok = false
        if !hidden, let w = cands[f.h] {
            ok = pointVisible(w, f.right ? w.r - 3 : w.l + 3, w.t + 3)
            if ok {
                let left = f.right ? w.r - f.side : w.l
                let nb = Box(l: left, t: w.t, r: left + f.side, b: w.t + f.side)
                if f.box != nb { f.box = nb; f.panel.setFrame(toCocoa(nb), display: true) }
                if !f.panel.isVisible { f.panel.orderFrontRegardless() }
            }
        }
        if !ok && f.panel.isVisible { f.panel.orderOut(nil) }
    }

    func updateWebs(_ n: Double) {
        var i = webs.count - 1
        while i >= 0 {
            let f = webs[i]
            let gone = n - f.born > 150 || (cands[f.h] == nil && windowBox(f.h) == nil)
            if gone { f.close(); webs.remove(at: i) } else { placeWeb(f) }
            i -= 1
        }
    }

    // 全螢幕簡報／影片時自動躲起來
    func fullscreenCheck(_ fg: WinInfo?) {
        var fs = false
        if let w = fg {
            let cx = (w.l + w.r) / 2, cy = (w.t + w.b) / 2
            var fr = screens[0].frame
            for s in screens where s.frame.contains(cx, cy) { fr = s.frame; break }
            fs = w.l <= fr.l && w.t <= fr.t && w.r >= fr.r && w.b >= fr.b
        }
        fsNow = fs
        applyHidden()
    }

    // ================= 螢幕幾何 =================
    func WA(_ px: Double, _ py: Double) -> Box {
        var best = screens[0].work
        var bd = Double.greatestFiniteMagnitude
        for s in screens {
            let r = s.work
            if r.contains(px, py) { return r }
            let dx = max(0, max(r.l - px, px - r.r)), dy = max(0, max(r.t - py, py - r.b))
            if dx * dx + dy * dy < bd { bd = dx * dx + dy * dy; best = r }
        }
        return best
    }

    func inside(_ px: Double, _ py: Double) -> Bool {
        for s in screens where s.work.contains(px, py) { return true }
        return false
    }

    // ================= 畫 =================
    func silkVisible() -> Bool { return state == "swing" || state == "hang" || state == "zip" || state == "shoot" }

    func render() {
        var l = x, tp = y, r = x + SW, b = y + SH
        if sc > 1 { let cxs = x + SW / 2; l = cxs - SW * sc / 2; r = cxs + SW * sc / 2; tp = y + SH - SH * sc - 4 * k }
        if silkVisible() { l = min(l, ax); r = max(r, ax); tp = min(tp, ay); b = max(b, ay) }
        if state == "sleep" { r = max(r, x + SW + 26 * k); tp = min(tp, y - 36 * k) }
        if sense > 0 { l = min(l, x + SW / 2 - 50 * k); r = max(r, x + SW / 2 + 50 * k); tp = min(tp, y - 14 * k) }
        if !hearts.isEmpty { l = min(l, x - 14 * k); r = max(r, x + SW + 14 * k); tp = min(tp, y - 90 * k) }
        for sp in sparks { l = min(l, sp[0]); r = max(r, sp[0]); tp = min(tp, sp[1]); b = max(b, sp[1]) }
        for fl in flakes { l = min(l, fl[0]); r = max(r, fl[0]); tp = min(tp, fl[1]); b = max(b, fl[1]) }
        let hatTop: Double = (sc > 1 ? y + SH - SH * sc - 5 * S * sc : y - 5 * S) - bob()   // 帽子
        tp = min(tp, hatTop)
        let pad = 6 + floor(5 * k) + 3 * S                                                 // 紅包、蛋糕在身體旁邊
        let nb = Box(l: floor(l) - pad, t: floor(tp) - pad, r: ceil(r) + pad, b: ceil(b) + pad)
        if curBox != nb { curBox = nb; petPanel.setFrame(toCocoa(nb), display: false) }
        petView.needsDisplay = true
        updateBubble()
        if nestPanel != nil && (dragging || (lockVal > 0 && lockVal < 1)) { updateNest() }
    }

    func updateBubble() {
        if bt <= 0 || bubble.isEmpty {
            if bubblePanel.isVisible { bubblePanel.orderOut(nil) }
            return
        }
        bubbleView.set(bubble, bubbleAlert, dark)
        let sz = bubbleView.measure()
        let wa = WA(x + SW / 2, y + SH / 2)
        let above = y + SH - SH * sc - (state == "sleep" ? 30 * k : 0) - (hearts.isEmpty ? 0 : 24 * k)
        var bx = floor(x + SW / 2 - sz.w / 2), by = floor(above - sz.h - 2)
        if state == "hang" && hangPhase == 1 { by = floor(y + SH + 6) }
        bx = max(wa.l, min(wa.r - sz.w, bx))
        by = max(wa.t, min(wa.b - sz.h, by))
        let nb = Box(l: bx, t: by, r: bx + sz.w, b: by + sz.h)
        if bubbleBox != nb { bubbleBox = nb; bubblePanel.setFrame(toCocoa(nb), display: true) }
        if !bubblePanel.isVisible { bubblePanel.orderFrontRegardless() }
    }

    func frame() -> [[Character]] {
        let sleep = state == "sleep", hugging = state == "hug"
        let dancingUp = state == "dance" && Int(floor(anim * 4)) % 2 == 0
        let armsUp = state == "glass" || state == "tug" || state == "kick" || dancingUp || state == "swing" || state == "air"
            || state == "climb" || state == "drag" || state == "shoot" || state == "zip"
            || (state == "hang" && hangPhase == 0) || (state == "idle" && bt > 0)
        let step = ((state == "walk" || state == "climb") && Int(floor(anim * 6)) % 2 == 1)
            || (state == "seek" && Int(floor(anim * 11)) % 2 == 1)
            || (state == "drag" && Int(floor(anim * 12)) % 2 == 1)
            || (state == "fetch" && Int(floor(anim * 11)) % 2 == 1)
            || (state == "dance" && Int(floor(anim * 4)) % 2 == 1)
        var rows = Pet.HEAD
        let face: [[Character]]? = sleep ? Pet.SLEEPY : (hugging ? Pet.HAPPY : (state == "dizzy" ? Pet.DIZZY : nil))
        if let fc = face {
            rows[4] = fc[0]; rows[5] = fc[1]; rows[6] = fc[2]
        } else {
            // 眼睛跟著滑鼠
            let cp = cursorQ()
            let dx = cp.x - (x + SW / 2)
            var off = state == "glass" ? 0 : (dx < -30 ? -1 : (dx > 30 ? 1 : 0))
            if dir < 0 { off = -off }   // 圖會左右翻，先反過來
            rows[5][3 + off] = "k"
            rows[5][8 + off] = "k"
        }
        rows.append(contentsOf: hugging ? Pet.ARMS_HUG : (armsUp ? Pet.ARMS_UP : Pet.BODY))
        rows.append(contentsOf: step ? Pet.LEGS_B : Pet.LEGS_A)
        if dark && !hugging && rows[10][5] == "k" && rows[10][6] == "k" { rows[10][5] = "w"; rows[10][6] = "w" }
        if !hugging && level() >= 5 && rows[10][5] != "r" && rows[10][6] != "r" { rows[10][5] = "Y"; rows[10][6] = "Y" }   // 金色胸章
        return rows
    }

    func drawPix(_ ctx: CGContext, _ rows: [[Character]], _ bx: Double, _ by: Double, _ ps: Double, _ fx: Bool, _ fy: Bool, _ withHalo: Bool) {
        let p = dark ? palDark : pal
        let hb = dark ? haloDark : halo
        let hw = max(1, floor(ps / 3))
        let h = rows.count
        for pass in (withHalo ? 0 : 1)..<2 {
            if pass == 0 { ctx.setFillColor(hb) }
            for ry in 0..<h {
                let row = rows[ry]
                for rx in 0..<row.count {
                    let c = row[rx]
                    if c == "." { continue }
                    let px = bx + Double(fx ? row.count - 1 - rx : rx) * ps
                    let py = by + Double(fy ? h - 1 - ry : ry) * ps
                    if pass == 0 {
                        ctx.fill(CGRect(x: CGFloat(px - hw), y: CGFloat(py - hw), width: CGFloat(ps + 2 * hw), height: CGFloat(ps + 2 * hw)))
                    } else {
                        ctx.setFillColor(p[c] ?? hb)
                        ctx.fill(CGRect(x: CGFloat(px), y: CGFloat(py), width: CGFloat(ps), height: CGFloat(ps)))
                    }
                }
            }
        }
    }

    // 配件：art 放在 12×16 身體格線的 (col,row)，跟著身體左右／上下翻
    func drawAcc(_ ctx: CGContext, _ art: [[Character]], _ col0: Int, _ row0: Int, _ bx0: Double, _ by0: Double, _ ps: Double, _ fx: Bool, _ fy: Bool, _ withHalo: Bool) {
        let aw = art[0].count, ah = art.count
        let c = fx ? 12 - col0 - aw : col0
        let r = fy ? 16 - row0 - ah : row0
        drawPix(ctx, art, bx0 + Double(c) * ps, by0 + Double(r) * ps, ps, fx, fy, withHalo)
    }

    func drawAccessories(_ ctx: CGContext, _ bx0: Double, _ by0: Double, _ ps: Double, _ fx: Bool, _ fy: Bool) {
        let lv = level()
        let normalFace = state != "sleep" && state != "hug" && state != "dizzy"
        if lv >= 2 { drawAcc(ctx, Pet.SCARF, 0, 8, bx0, by0, ps, fx, fy, false) }
        if lv >= 4 && normalFace { drawAcc(ctx, Pet.GLASSES, 0, 4, bx0, by0, ps, fx, fy, false) }
        let hat: [[Character]]? = seasonNow == "xmas" ? Pet.SANTA : (lv >= 6 ? Pet.CROWN : (lv >= 3 ? Pet.BEANIE : nil))
        if let ht = hat { drawAcc(ctx, ht, 0, -ht.count, bx0, by0, ps, fx, fy, true) }
        if seasonNow == "cny" { drawAcc(ctx, Pet.ENVELOPE, 11, 9, bx0, by0, ps, fx, fy, true) }
        if seasonNow == "birthday" { drawAcc(ctx, Pet.CAKE, 11, 8, bx0, by0, ps, fx, fy, true) }
    }

    func paint(_ ctx: CGContext) {
        guard let box = curBox else { return }
        let ox = box.l, oy = box.t
        let lw = max(2, (1.5 * k).rounded())

        if silkVisible() {
            ctx.setShouldAntialias(true)
            let hx = x + SW / 2 - ox, hy = y + 3 * k - oy
            var axo = ax - ox, ayo = ay - oy
            if state == "shoot" {
                let p = min(1, shootT / 0.18)
                axo = hx + (axo - hx) * p; ayo = hy + (ayo - hy) * p
            }
            let silk = dark ? col(0x6A5F9E) : col(0x9AA3BC)
            ctx.setStrokeColor(silk)
            ctx.setLineWidth(CGFloat(lw))
            strokeLine(ctx, hx, hy, axo, ayo)
            ctx.setStrokeColor(dark ? col(0x14141C) : col(0x4A526E))
            ctx.setLineWidth(CGFloat(max(1, floor(lw / 2))))
            strokeLine(ctx, hx, hy, axo, ayo)
            if state != "shoot" || shootT >= 0.18 {
                // 黏住的地方：一小團絲
                let s = 5 * k
                ctx.setStrokeColor(silk)
                ctx.setLineWidth(CGFloat(lw))
                strokeLine(ctx, axo - s, ayo, axo + s, ayo)
                strokeLine(ctx, axo, ayo - s, axo, ayo + s)
                strokeLine(ctx, axo - s * 0.7, ayo - s * 0.7, axo + s * 0.7, ayo + s * 0.7)
                strokeLine(ctx, axo - s * 0.7, ayo + s * 0.7, axo + s * 0.7, ayo - s * 0.7)
            }
        }

        ctx.setShouldAntialias(false)
        let fy = state == "hang" && hangPhase == 1
        let sbx: Double, sby: Double, sps: Double, sfy: Bool
        if sc > 1.001 {
            sps = (S * sc).rounded()
            let shake = knock > 0 ? -3 * k : 0
            sbx = (x + SW / 2 - 6 * sps).rounded() - ox
            sby = (y + SH - 16 * sps + shake).rounded() - oy
            sfy = false
        } else {
            sps = S
            sbx = x.rounded() - ox
            sby = (y - bob()).rounded() - oy
            sfy = fy
        }
        drawPix(ctx, frame(), sbx, sby, sps, dir < 0, sfy, true)
        drawAccessories(ctx, sbx, sby, sps, dir < 0, sfy)
        let fps = max(1, floor(S / 3))
        for fl in flakes { drawPix(ctx, Pet.FLAKE, floor(fl[0]) - ox - fps, floor(fl[1]) - oy - fps, fps, false, false, false) }

        if sense > 0 && !fy {
            ctx.setShouldAntialias(true)
            ctx.setStrokeColor(dark ? col(0x9B7BFF) : col(0xC95454))
            ctx.setLineWidth(CGFloat(2 * k))
            let cx = x + SW / 2 - ox, cy = y + 10 * k - oy, wob = sin(anim * 30) * 1.5 * k
            for s in [-1.0, 1.0] {
                for i in 0..<3 {
                    let d = Double(i)
                    strokeLine(ctx, cx + s * (22 + d * 5 + wob) * k, cy + (-10 + d * 6) * k,
                               cx + s * (30 + d * 5 + wob) * k, cy + (-16 + d * 8) * k)
                }
            }
            ctx.setShouldAntialias(false)
        }

        if state == "sleep" {
            let ps = max(2, floor(S / 2))
            for i in 0..<3 {
                let p = (z * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                if p > 0.85 { continue }
                drawPix(ctx, Pet.ZZ, floor(x + SW - 4 * k + p * 16 * k) - ox, floor(y - 2 * k - p * 30 * k) - oy, ps, false, false, false)
            }
        }

        let hp = max(2, floor(S / 2))
        let ssz = max(2, floor(S / 2))
        for sp in sparks where sp[4] < 0.6 || Int(floor(sp[4] * 20)) % 2 == 0 {   // 快消失時閃一閃
            drawPix(ctx, Pet.STAR, floor(sp[0] - 1.5 * ssz) - ox, floor(sp[1] - 1.5 * ssz) - oy, ssz, false, false, false)
        }
        for h in hearts {
            let age = h[1]
            let hx = floor(x + SW / 2 + h[0] + sin(age * 6 + h[0]) * 3 * k - 3.5 * hp) - ox
            let hy = floor(y - 8 * k - age * 45 * k - 6 * hp) - oy
            drawPix(ctx, Pet.HEART, hx, hy, hp, false, false, true)
        }
    }

    // ================= socket（跟 VS Code／Claude hook 溝通）=================
    func startServer() {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { logLine("socket() failed errno \(errno)"); return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        if bytes.count >= cap { logLine("socket path too long: \(socketPath)"); close(fd); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, len) }
        }
        if rc != 0 { logLine("bind failed errno \(errno)"); close(fd); return }
        chmod(socketPath, 0o600)
        if Darwin.listen(fd, 8) != 0 { logLine("listen failed errno \(errno)"); close(fd); return }
        let th = Thread { [weak self] in self?.acceptLoop(fd) }
        th.start()
    }

    func acceptLoop(_ lfd: Int32) {
        while true {
            let c = Darwin.accept(lfd, nil, nil)
            if c < 0 {
                if errno == EINTR { continue }
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            var one: Int32 = 1
            _ = setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let client = Client(fd: c)
            clientsLock.lock(); clients.append(client); clientsLock.unlock()
            let th = Thread { [weak self] in self?.clientLoop(client) }
            th.start()
        }
    }

    func clientLoop(_ c: Client) {
        var buf = [UInt8](repeating: 0, count: 1024)
        var pending: [UInt8] = []
        while true {
            let n = read(c.fd, &buf, buf.count)
            if n <= 0 { break }
            pending.append(contentsOf: buf[0..<n])
            while let idx = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[0..<idx], as: UTF8.self)
                pending.removeSubrange(0...idx)
                DispatchQueue.main.async { [weak self] in self?.onMsg(c, line) }
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clientsLock.lock()
            self.clients.removeAll { $0 === c }
            self.clientsLock.unlock()
            close(c.fd)
        }
    }

    func send(_ c: Client, _ s: String) {
        let d = Array(s.utf8)
        _ = d.withUnsafeBytes { raw in write(c.fd, raw.baseAddress, raw.count) }
    }

    func onMsg(_ c: Client, _ line: String) {
        let p = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map { String($0) }
        guard let cmd = p.first else { return }
        switch cmd {
        case "hello": break
        case "save":
            if saveXpCd <= 0 { saveXpCd = 120; addXp(1) }
            wakeIfSleep()
            say(pick(Pet.SAVE, Pet.SAVE_D), 2)
            if grounded() { jump(0, -300 * k) }
        case "errors":
            var n = 0, prev = 0
            if p.count >= 3 { n = Int(p[1]) ?? 0; prev = Int(p[2]) ?? 0 }
            if n > prev {
                wakeIfSleep()
                sense = 2.8
                say(dark ? "\(n) 個錯誤……明天再修，回家。" : "蜘蛛感應！有 \(n) 個錯誤", 3, true)
                if state == "walk" { setState("idle", 3) }
            } else if n == 0 {
                wakeIfSleep()
                addXp(2)
                hug(dark ? "錯誤清完了。那就可以下班了吧。" : "錯誤都清光了，抱一個！", 2.6)
            }
        case "config":
            if p.count >= 3, let rm = Double(p[1]), let im = Double(p[2]) { restMin = max(1, rm); idleMin = max(1, im) }
        case "hi": act("hi")
        case "claude": if p.count >= 2 { onClaude(p[1], p.count >= 3 ? p[2] : "x") }
        case "tag": celebrate(p.count >= 3 ? p[2] : "")
        case "birthday":
            birthday = p.count >= 2 ? p[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            seasonNow = season()
        case "typing":
            if p.count >= 2, let chars = Int(p[1]) {
                typingStreak = chars >= 30 ? typingStreak + 1 : 0
                if typingStreak >= 2 && danceCd <= 0 && grounded() && state != "hug" && state != "sleep" && !hidden {
                    danceCd = 150
                    setState("dance", 4)
                    say(dark ? "打這麼快是想快點下班吧？加油。" : pick(["你打字好快！加油加油 ♪", "手指在冒煙了！🔥", "衝衝衝～我幫你打氣！"]), 2.5)
                }
            }
        case "act": if p.count >= 2 { act(p[1]) }
        case "where":
            let mode = dark ? "dark" : "light"
            send(c, "pos \(Int(x)) \(Int(y)) \(state) \(mode) \(plats.count)\n")
        case "quit": quitAll()
        default: break
        }
    }

    func quitAll() {
        clientsLock.lock()
        let cs = clients
        clientsLock.unlock()
        for c in cs { send(c, "bye\n") }
        for f in webs { f.close() }
        nestPanel?.orderOut(nil)
        netPanel?.orderOut(nil)
        ballPanel?.orderOut(nil)
        fxPanel?.orderOut(nil)
        if let hk = hotKeyRef { UnregisterEventHotKey(hk) }
        unlink(socketPath)
        NSApp.terminate(nil)
    }
}

// MARK: - 進入點

signal(SIGPIPE, SIG_IGN)
let cmdArgs = CommandLine.arguments
let sockPath = cmdArgs.count > 1 ? cmdArgs[1] : appDir + "/spidey.sock"
let sockDir = (sockPath as NSString).deletingLastPathComponent
try? FileManager.default.createDirectory(atPath: sockDir, withIntermediateDirectories: true, attributes: nil)

// 單一實例：拿不到鎖就代表已經有一隻在跑
let lockFD = open(sockDir + "/spidey.lock", O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    logLine("already running")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let pet = Pet(socketPath: sockPath)
pet.start()
app.run()
