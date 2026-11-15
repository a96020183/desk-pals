// ===== 00_compat.swift — C#/.NET runtime shim (see mac/PORTING.md) =====
// Keeps .NET names and argument shapes so line-by-line ported C# compiles in Swift.
// All overloads are unlabeled. Strings index in UTF-16 code units like C#.
import Foundation
import AppKit
import Darwin

// MARK: - Basic types / helpers

typealias IntPtr = Int
typealias byte = UInt8

extension Int {
    static let Zero = 0
    func ToInt32() -> Int { return Int(Int32(truncatingIfNeeded: self)) }
    func ToInt64() -> Int { return self }
}

/// `(int)d` → `CInt(d)`: truncates toward zero like C#, never traps (NaN → 0, huge → clamp).
/// (A callable value, not a func, so it shadows Swift's own `CInt` = Int32 type.)
struct CIntConverter {
    @inline(__always) func callAsFunction(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= 9.2e18 { return Int.max }
        if d <= -9.2e18 { return Int.min }
        return Int(d)
    }
    @inline(__always) func callAsFunction(_ i: Int) -> Int { return i }
}
let CInt = CIntConverter()

/// C# `%` on doubles (fmod semantics, sign of dividend).
@inline(__always) func % (lhs: Double, rhs: Double) -> Double { return lhs.truncatingRemainder(dividingBy: rhs) }
@inline(__always) func %= (lhs: inout Double, rhs: Double) { lhs = lhs.truncatingRemainder(dividingBy: rhs) }

/// `for (int i = a; i < b; i++)` without trapping when b < a.
@inline(__always) func Loop(_ a: Int, _ b: Int) -> Range<Int> { return a < b ? a..<b : a..<a }

protocol IDisposable: AnyObject { func Dispose() }
extension IDisposable { func Dispose() {} }

// MARK: - Exceptions

class Exception: Error, CustomStringConvertible {
    let _message: String
    let InnerException: Error?
    init() { _message = "Exception of type 'System.Exception' was thrown."; InnerException = nil }
    init(_ message: String) { _message = message; InnerException = nil }
    init(_ message: String, _ inner: Error?) { _message = message; InnerException = inner }
    var description: String { return "\(type(of: self)): \(_message)" }
}
class SystemException: Exception {}
class IOException: SystemException {}
class FileNotFoundException: IOException {}
class DirectoryNotFoundException: IOException {}
class ArgumentException: SystemException {}
class ArgumentNullException: ArgumentException {}
class ArgumentOutOfRangeException: ArgumentException {}
class FormatException: SystemException {}
class InvalidOperationException: SystemException {}
class KeyNotFoundException: SystemException {}
class NotSupportedException: SystemException {}
class TimeoutException: SystemException {}
class UnauthorizedAccessException: SystemException {}
class WebException: InvalidOperationException {}

extension Error {
    /// `ex.Message`
    var Message: String {
        if let e = self as? Exception { return e._message }
        let ns = self as NSError
        return ns.localizedDescription
    }
    func ToString() -> String {
        if let e = self as? Exception { return e.description }
        return "\(self)"
    }
}

// MARK: - Enums used by string / number APIs

enum StringComparison { case CurrentCulture, CurrentCultureIgnoreCase, InvariantCulture, InvariantCultureIgnoreCase, Ordinal, OrdinalIgnoreCase }
enum StringSplitOptions { case None, RemoveEmptyEntries }
enum MidpointRounding { case ToEven, AwayFromZero }

struct CultureInfo {
    let Name: String
    static let InvariantCulture = CultureInfo(Name: "")
    static let CurrentCulture = CultureInfo(Name: "zh-TW")
    static let CurrentUICulture = CultureInfo(Name: "zh-TW")
    init(Name: String) { self.Name = Name }
    init(_ name: String) { self.Name = name }
}

struct NumberStyles: OptionSet {
    let rawValue: Int
    static let None = NumberStyles([])
    static let AllowLeadingWhite = NumberStyles(rawValue: 1)
    static let AllowTrailingWhite = NumberStyles(rawValue: 2)
    static let AllowLeadingSign = NumberStyles(rawValue: 4)
    static let AllowTrailingSign = NumberStyles(rawValue: 8)
    static let AllowParentheses = NumberStyles(rawValue: 16)
    static let AllowDecimalPoint = NumberStyles(rawValue: 32)
    static let AllowThousands = NumberStyles(rawValue: 64)
    static let AllowExponent = NumberStyles(rawValue: 128)
    static let AllowCurrencySymbol = NumberStyles(rawValue: 256)
    static let AllowHexSpecifier = NumberStyles(rawValue: 512)
    static let Integer: NumberStyles = [.AllowLeadingWhite, .AllowTrailingWhite, .AllowLeadingSign]
    static let HexNumber: NumberStyles = [.AllowLeadingWhite, .AllowTrailingWhite, .AllowHexSpecifier]
    static let Number: NumberStyles = [.Integer, .AllowTrailingSign, .AllowDecimalPoint, .AllowThousands]
    static let Float: NumberStyles = [.Integer, .AllowDecimalPoint, .AllowExponent]
    static let `Any`: NumberStyles = [.Number, .AllowParentheses, .AllowExponent, .AllowCurrencySymbol]
}

// MARK: - Static helper "types" (string.IsNullOrEmpty, int.TryParse …)

private func csTrimWS(_ s: String) -> String { return s.Trim() }

enum string {
    static let Empty = ""
    static func IsNullOrEmpty(_ s: String?) -> Bool { return s == nil || s!.isEmpty }
    static func IsNullOrWhiteSpace(_ s: String?) -> Bool { return s == nil || s!.Trim().isEmpty }
    static func Join(_ sep: String, _ parts: [String]) -> String { return parts.joined(separator: sep) }
    static func Join(_ sep: String, _ parts: [String?]) -> String { return parts.map { $0 ?? "" }.joined(separator: sep) }
    static func Join(_ sep: String, _ parts: List<String>) -> String { return parts.items.joined(separator: sep) }
    static func Join(_ sep: String, _ parts: [Any]) -> String { return parts.map { csToString($0) }.joined(separator: sep) }
    static func Concat(_ parts: String?...) -> String { return parts.map { $0 ?? "" }.joined() }
    static func Equals(_ a: String?, _ b: String?) -> Bool { return a == b }
    static func Equals(_ a: String?, _ b: String?, _ cmp: StringComparison) -> Bool {
        if a == nil || b == nil { return a == nil && b == nil }
        return csStrEq(a!, b!, cmp)
    }
    /// Ordinal UTF-16 comparison (returns <0, 0, >0 like C#).
    static func CompareOrdinal(_ a: String?, _ b: String?) -> Int {
        if a == nil { return b == nil ? 0 : -1 }
        if b == nil { return 1 }
        var ia = a!.utf16.makeIterator(), ib = b!.utf16.makeIterator()
        while true {
            let ca = ia.next(), cb = ib.next()
            if ca == nil { return cb == nil ? 0 : -1 }
            if cb == nil { return 1 }
            if ca! != cb! { return Int(ca!) - Int(cb!) }
        }
    }
    static func Compare(_ a: String?, _ b: String?) -> Int {
        if a == nil { return b == nil ? 0 : -1 }
        if b == nil { return 1 }
        return a! < b! ? -1 : (a! == b! ? 0 : 1)
    }
    static func Compare(_ a: String?, _ b: String?, _ cmp: StringComparison) -> Int {
        switch cmp {
        case .Ordinal: return CompareOrdinal(a, b)
        case .OrdinalIgnoreCase, .CurrentCultureIgnoreCase, .InvariantCultureIgnoreCase:
            return CompareOrdinal(a?.uppercased(), b?.uppercased())
        default: return Compare(a, b)
        }
    }
    /// `string.Format("{0} {1:0.0}", a, b)` — supports {n}, {n,align}, {n:fmt}.
    static func Format(_ fmt: String, _ args: Any?...) -> String { return csFormat(fmt, args) }
}

private func csStrEq(_ a: String, _ b: String, _ cmp: StringComparison) -> Bool {
    switch cmp {
    case .OrdinalIgnoreCase, .CurrentCultureIgnoreCase, .InvariantCultureIgnoreCase:
        return a.compare(b, options: [.caseInsensitive, .literal]) == .orderedSame
    default: return a == b
    }
}

/// C#-style ToString of an arbitrary value (used by Format / Join / StringBuilder).
func csToString(_ v: Any?) -> String {
    guard let v = v else { return "" }
    if let s = v as? String { return s }
    if let d = v as? Double { return d.ToString() }
    if let i = v as? Int { return String(i) }
    if let b = v as? Bool { return b ? "True" : "False" }
    if let c = v as? Character { return String(c) }
    if let e = v as? Error { return e.ToString() }
    let m = Mirror(reflecting: v)
    if m.displayStyle == .optional { if let c = m.children.first { return csToString(c.value) }; return "" }
    return "\(v)"
}

private func csFormat(_ fmt: String, _ args: [Any?]) -> String {
    var out = ""
    let chars = Array(fmt)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "{" {
            if i + 1 < chars.count && chars[i + 1] == "{" { out.append("{"); i += 2; continue }
            var j = i + 1
            var spec = ""
            while j < chars.count && chars[j] != "}" { spec.append(chars[j]); j += 1 }
            i = j + 1
            var f: String? = nil
            var body = spec
            if let ci = spec.firstIndex(of: ":") { f = String(spec[spec.index(after: ci)...]); body = String(spec[..<ci]) }
            var align = 0
            if let ai = body.firstIndex(of: ",") { align = Int(body[body.index(after: ai)...].trimmingCharacters(in: .whitespaces)) ?? 0; body = String(body[..<ai]) }
            let idx = Int(body.trimmingCharacters(in: .whitespaces)) ?? 0
            let a: Any? = idx < args.count ? args[idx] : nil
            var s: String
            if let f = f {
                if let d = a as? Double { s = d.ToString(f) }
                else if let n = a as? Int { s = n.ToString(f) }
                else if let dt = a as? DateTime { s = dt.ToString(f) }
                else { s = csToString(a) }
            } else { s = csToString(a) }
            if align > 0 && s.count < align { s = String(repeating: " ", count: align - s.count) + s }
            if align < 0 && s.count < -align { s += String(repeating: " ", count: -align - s.count) }
            out += s
        } else if c == "}" {
            if i + 1 < chars.count && chars[i + 1] == "}" { i += 2 } else { i += 1 }
            out.append("}")
        } else { out.append(c); i += 1 }
    }
    return out
}

private func csParseInt(_ s: String?, _ min: Int, _ max: Int) -> Int? {
    guard let s = s else { return nil }
    var t = s.Trim()
    if t.hasPrefix("+") { t.removeFirst() ; if t.hasPrefix("-") || t.hasPrefix("+") { return nil } }
    guard let v = Int(t) else { return nil }
    if v < min || v > max { return nil }
    return v
}

private func csParseDouble(_ s: String?) -> Double? {
    guard let s = s else { return nil }
    let t = s.Trim()
    if t.isEmpty { return nil }
    if t == "NaN" { return Double.nan }
    if t == "Infinity" || t == "∞" { return Double.infinity }
    if t == "-Infinity" || t == "-∞" { return -Double.infinity }
    // reject hex / nan / inf spellings Swift would accept
    for u in t.utf8 { if !((u >= 48 && u <= 57) || u == 43 || u == 45 || u == 46 || u == 101 || u == 69) { return nil } }
    return Double(t)
}

enum int {
    static let MaxValue = Int(Int32.max)
    static let MinValue = Int(Int32.min)
    /// Non-throwing: returns 0 on bad input (C# would throw FormatException).
    static func Parse(_ s: String?) -> Int { return csParseInt(s, MinValue, MaxValue) ?? 0 }
    static func Parse(_ s: String?, _ style: NumberStyles) -> Int {
        if style.contains(.AllowHexSpecifier) { return Int((s ?? "").Trim(), radix: 16) ?? 0 }
        return Parse(s)
    }
    @discardableResult static func TryParse(_ s: String?, _ v: inout Int) -> Bool {
        if let r = csParseInt(s, MinValue, MaxValue) { v = r; return true }
        v = 0; return false
    }
    @discardableResult static func TryParse(_ s: String?, _ style: NumberStyles, _ c: CultureInfo, _ v: inout Int) -> Bool {
        if style.contains(.AllowHexSpecifier) {
            if let r = Int((s ?? "").Trim(), radix: 16) { v = r; return true }
            v = 0; return false
        }
        return TryParse(s, &v)
    }
}

enum long {
    static let MaxValue = Int.max
    static let MinValue = Int.min
    static func Parse(_ s: String?) -> Int { return csParseInt(s, Int.min, Int.max) ?? 0 }
    @discardableResult static func TryParse(_ s: String?, _ v: inout Int) -> Bool {
        if let r = csParseInt(s, Int.min, Int.max) { v = r; return true }
        v = 0; return false
    }
}
typealias uint = long
typealias short = int

enum double {
    static let NaN = Double.nan
    static let MaxValue = Double.greatestFiniteMagnitude
    static let MinValue = -Double.greatestFiniteMagnitude
    static let Epsilon = Double.leastNonzeroMagnitude
    static let PositiveInfinity = Double.infinity
    static let NegativeInfinity = -Double.infinity
    static func IsNaN(_ d: Double) -> Bool { return d.isNaN }
    static func IsInfinity(_ d: Double) -> Bool { return d.isInfinite }
    static func IsPositiveInfinity(_ d: Double) -> Bool { return d == Double.infinity }
    static func IsNegativeInfinity(_ d: Double) -> Bool { return d == -Double.infinity }
    /// Non-throwing: returns 0 on bad input.
    static func Parse(_ s: String?) -> Double { return csParseDouble(s) ?? 0 }
    static func Parse(_ s: String?, _ c: CultureInfo) -> Double { return csParseDouble(s) ?? 0 }
    @discardableResult static func TryParse(_ s: String?, _ v: inout Double) -> Bool {
        if let r = csParseDouble(s) { v = r; return true }
        v = 0; return false
    }
    @discardableResult static func TryParse(_ s: String?, _ style: NumberStyles, _ c: CultureInfo, _ v: inout Double) -> Bool {
        return TryParse(s, &v)
    }
}
typealias float = double

enum bool {
    static func Parse(_ s: String?) -> Bool { return (s ?? "").Trim().lowercased() == "true" }
    @discardableResult static func TryParse(_ s: String?, _ v: inout Bool) -> Bool {
        let t = (s ?? "").Trim().lowercased()
        if t == "true" { v = true; return true }
        if t == "false" { v = false; return true }
        v = false; return false
    }
}

enum char {
    private static func sc(_ c: Character) -> Unicode.Scalar { return c.unicodeScalars.first ?? " " }
    /// A Character holding a non-BMP scalar is what C# sees as a surrogate pair; `s[i]` returns that
    /// whole character for both halves, so both checks report true for it.
    static func IsHighSurrogate(_ c: Character) -> Bool { return sc(c).value > 0xFFFF }
    static func IsLowSurrogate(_ c: Character) -> Bool { return sc(c).value > 0xFFFF }
    static func IsSurrogate(_ c: Character) -> Bool { return sc(c).value > 0xFFFF }
    static func IsDigit(_ c: Character) -> Bool { return sc(c).properties.numericType == .decimal }
    static func IsLetter(_ c: Character) -> Bool { return sc(c).properties.isAlphabetic }
    static func IsLetterOrDigit(_ c: Character) -> Bool { return IsLetter(c) || IsDigit(c) }
    static func IsWhiteSpace(_ c: Character) -> Bool { return sc(c).properties.isWhitespace }
    static func IsUpper(_ c: Character) -> Bool { return sc(c).properties.isUppercase }
    static func IsLower(_ c: Character) -> Bool { return sc(c).properties.isLowercase }
    static func IsPunctuation(_ c: Character) -> Bool { return c.isPunctuation }
    static func IsControl(_ c: Character) -> Bool { return sc(c).properties.generalCategory == .control }
    static func ToUpper(_ c: Character) -> Character { return Character(String(c).uppercased()) }
    static func ToLower(_ c: Character) -> Character { return Character(String(c).lowercased()) }
    static let MaxValue: Character = "\u{FFFF}"
}

// MARK: - String extensions (UTF-16 semantics like C#)

extension String {
    @inline(__always) private var _isASCIIFast: Bool { return utf8.count == utf16.count }

    var Length: Int { return utf16.count }

    /// `s[i]` → Character. O(1) for ASCII strings.
    subscript(_ i: Int) -> Character {
        let u8 = utf8
        if u8.count == utf16.count {
            if let b = u8.withContiguousStorageIfAvailable({ $0[i] }) { return Character(Unicode.Scalar(b)) }
            return Character(Unicode.Scalar(u8[u8.index(u8.startIndex, offsetBy: i)]))
        }
        let u = utf16
        let idx = u.index(u.startIndex, offsetBy: i)
        let unit = u[idx]
        if UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) {
            let si = idx.samePosition(in: unicodeScalars) ?? unicodeScalars.index(before: idx.samePosition(in: unicodeScalars) ?? unicodeScalars.endIndex)
            return Character(unicodeScalars[si])
        }
        return Character(Unicode.Scalar(unit)!)
    }

    @inline(__always) private func u16Index(_ i: Int) -> String.Index {
        let u = utf16
        let n = u.count
        return u.index(u.startIndex, offsetBy: Swift.max(0, Swift.min(i, n)))
    }
    @inline(__always) private func u16Offset(_ i: String.Index) -> Int { return utf16.distance(from: utf16.startIndex, to: i) }

    func Substring(_ start: Int) -> String {
        if start <= 0 { return self }
        return String(self[u16Index(start)...])
    }
    func Substring(_ start: Int, _ length: Int) -> String {
        let a = u16Index(start)
        let b = u16Index(start + Swift.max(0, length))
        return String(self[a..<b])
    }

    private func csIndexOf(_ s: String, _ start: Int, _ cmp: StringComparison, _ backwards: Bool) -> Int {
        if s.isEmpty { return backwards ? Swift.max(0, Length - 1) : Swift.max(0, Swift.min(start, Length)) }
        var opts: String.CompareOptions = [.literal]
        if cmp == .OrdinalIgnoreCase || cmp == .CurrentCultureIgnoreCase || cmp == .InvariantCultureIgnoreCase { opts.insert(.caseInsensitive) }
        if backwards { opts.insert(.backwards) }
        let range: Range<String.Index> = backwards ? startIndex..<endIndex : u16Index(start)..<endIndex
        if let r = self.range(of: s, options: opts, range: range) { return u16Offset(r.lowerBound) }
        return -1
    }
    func IndexOf(_ s: String) -> Int { return csIndexOf(s, 0, .Ordinal, false) }
    func IndexOf(_ s: String, _ start: Int) -> Int { return csIndexOf(s, start, .Ordinal, false) }
    func IndexOf(_ s: String, _ cmp: StringComparison) -> Int { return csIndexOf(s, 0, cmp, false) }
    func IndexOf(_ s: String, _ start: Int, _ cmp: StringComparison) -> Int { return csIndexOf(s, start, cmp, false) }
    func IndexOf(_ c: Character) -> Int { return IndexOf(c, 0) }
    func IndexOf(_ c: Character, _ start: Int) -> Int {
        if c.isASCII, let a = c.asciiValue, _isASCIIFast {
            let r: Int? = utf8.withContiguousStorageIfAvailable { buf -> Int in
                var i = Swift.max(0, start)
                while i < buf.count { if buf[i] == a { return i }; i += 1 }
                return -1
            }
            if let r = r { return r }
        }
        return csIndexOf(String(c), start, .Ordinal, false)
    }
    func IndexOfAny(_ cs: [Character]) -> Int {
        var best = -1
        for c in cs { let i = IndexOf(c); if i >= 0 && (best < 0 || i < best) { best = i } }
        return best
    }
    func LastIndexOf(_ s: String) -> Int { return csIndexOf(s, 0, .Ordinal, true) }
    func LastIndexOf(_ s: String, _ cmp: StringComparison) -> Int { return csIndexOf(s, 0, cmp, true) }
    func LastIndexOf(_ c: Character) -> Int { return csIndexOf(String(c), 0, .Ordinal, true) }
    func LastIndexOfAny(_ cs: [Character]) -> Int {
        var best = -1
        for c in cs { let i = LastIndexOf(c); if i > best { best = i } }
        return best
    }

    func StartsWith(_ s: String) -> Bool { return utf8.starts(with: s.utf8) }
    func StartsWith(_ s: String, _ cmp: StringComparison) -> Bool {
        if cmp == .Ordinal || cmp == .CurrentCulture || cmp == .InvariantCulture { return StartsWith(s) }
        return range(of: s, options: [.anchored, .caseInsensitive, .literal]) != nil
    }
    func StartsWith(_ c: Character) -> Bool { return first == c }
    func EndsWith(_ s: String) -> Bool { return utf8.reversed().starts(with: s.utf8.reversed()) }
    func EndsWith(_ s: String, _ cmp: StringComparison) -> Bool {
        if cmp == .Ordinal || cmp == .CurrentCulture || cmp == .InvariantCulture { return EndsWith(s) }
        return range(of: s, options: [.anchored, .backwards, .caseInsensitive, .literal]) != nil
    }
    func EndsWith(_ c: Character) -> Bool { return last == c }
    func Contains(_ s: String) -> Bool { return s.isEmpty || range(of: s, options: .literal) != nil }
    func Contains(_ s: String, _ cmp: StringComparison) -> Bool { return csIndexOf(s, 0, cmp, false) >= 0 }
    func Contains(_ c: Character) -> Bool { return IndexOf(c) >= 0 }
    func Equals(_ s: String?) -> Bool { return self == s }
    func Equals(_ s: String?, _ cmp: StringComparison) -> Bool { return s != nil && csStrEq(self, s!, cmp) }
    func CompareTo(_ s: String?) -> Int { return string.Compare(self, s) }

    func Replace(_ a: String, _ b: String?) -> String {
        if a.isEmpty { return self }
        return replacingOccurrences(of: a, with: b ?? "", options: .literal)
    }
    func Replace(_ a: Character, _ b: Character) -> String { return Replace(String(a), String(b)) }

    func Insert(_ i: Int, _ s: String) -> String {
        let idx = u16Index(i)
        return String(self[..<idx]) + s + String(self[idx...])
    }
    func Remove(_ i: Int) -> String { return String(self[..<u16Index(i)]) }
    func Remove(_ i: Int, _ n: Int) -> String { return String(self[..<u16Index(i)]) + String(self[u16Index(i + n)...]) }

    // --- Split (on Unicode scalars, so "\r\n" splits on '\n' like C#) ---
    private func csSplit(_ seps: [Unicode.Scalar], _ opt: StringSplitOptions) -> [String] {
        let sepSet = seps.isEmpty ? nil : Set(seps)
        var out: [String] = []
        let allASCII = seps.allSatisfy { $0.isASCII }
        if allASCII && sepSet != nil {
            let bytes = Set(seps.map { UInt8($0.value) })
            let done: Bool = utf8.withContiguousStorageIfAvailable { buf -> Bool in
                var st = 0
                var i = 0
                while i <= buf.count {
                    if i == buf.count || bytes.contains(buf[i]) {
                        if !(opt == .RemoveEmptyEntries && i == st) {
                            out.append(String(decoding: UnsafeBufferPointer(rebasing: buf[st..<i]), as: UTF8.self))
                        }
                        st = i + 1
                    }
                    i += 1
                }
                return true
            } ?? false
            if done { return out }
            out = []
        }
        var cur = String.UnicodeScalarView()
        for sc in unicodeScalars {
            let isSep = sepSet == nil ? sc.properties.isWhitespace : sepSet!.contains(sc)
            if isSep {
                if !(opt == .RemoveEmptyEntries && cur.isEmpty) { out.append(String(cur)) }
                cur = String.UnicodeScalarView()
            } else { cur.append(sc) }
        }
        if !(opt == .RemoveEmptyEntries && cur.isEmpty) { out.append(String(cur)) }
        return out
    }
    private static func scalars(_ cs: [Character]) -> [Unicode.Scalar] { return cs.compactMap { $0.unicodeScalars.first } }
    func Split(_ seps: Character...) -> [String] { return csSplit(String.scalars(seps), .None) }
    func Split(_ seps: [Character]) -> [String] { return csSplit(String.scalars(seps), .None) }
    func Split(_ seps: [Character], _ opt: StringSplitOptions) -> [String] { return csSplit(String.scalars(seps), opt) }
    func Split(_ sep: Character, _ opt: StringSplitOptions) -> [String] { return csSplit(String.scalars([sep]), opt) }
    func Split(_ seps: [String], _ opt: StringSplitOptions) -> [String] {
        var parts: [String] = [self]
        for sep in seps where !sep.isEmpty {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return opt == .RemoveEmptyEntries ? parts.filter { !$0.isEmpty } : parts
    }
    func Split(_ sep: String, _ opt: StringSplitOptions) -> [String] { return Split([sep], opt) }

    // --- Trim ---
    private func csTrim(_ chars: [Character]?, _ start: Bool, _ end: Bool) -> String {
        let set: Set<Unicode.Scalar>? = chars == nil || chars!.isEmpty ? nil : Set(String.scalars(chars!))
        let v = unicodeScalars
        var a = v.startIndex, b = v.endIndex
        @inline(__always) func trimmable(_ s: Unicode.Scalar) -> Bool { return set == nil ? s.properties.isWhitespace : set!.contains(s) }
        if start { while a < b && trimmable(v[a]) { a = v.index(after: a) } }
        if end { while b > a && trimmable(v[v.index(before: b)]) { b = v.index(before: b) } }
        if a == v.startIndex && b == v.endIndex { return self }
        return String(v[a..<b])
    }
    func Trim() -> String { return csTrim(nil, true, true) }
    func Trim(_ chars: Character...) -> String { return csTrim(chars, true, true) }
    func Trim(_ chars: [Character]) -> String { return csTrim(chars, true, true) }
    func TrimStart() -> String { return csTrim(nil, true, false) }
    func TrimStart(_ chars: Character...) -> String { return csTrim(chars, true, false) }
    func TrimStart(_ chars: [Character]) -> String { return csTrim(chars, true, false) }
    func TrimEnd() -> String { return csTrim(nil, false, true) }
    func TrimEnd(_ chars: Character...) -> String { return csTrim(chars, false, true) }
    func TrimEnd(_ chars: [Character]) -> String { return csTrim(chars, false, true) }

    func ToLower() -> String { return lowercased() }
    func ToUpper() -> String { return uppercased() }
    func ToLowerInvariant() -> String { return lowercased() }
    func ToUpperInvariant() -> String { return uppercased() }
    func PadLeft(_ n: Int) -> String { return PadLeft(n, " ") }
    func PadLeft(_ n: Int, _ c: Character) -> String { let l = Length; return l >= n ? self : String(repeating: c, count: n - l) + self }
    func PadRight(_ n: Int) -> String { return PadRight(n, " ") }
    func PadRight(_ n: Int, _ c: Character) -> String { let l = Length; return l >= n ? self : self + String(repeating: c, count: n - l) }
    func ToCharArray() -> [Character] { return Array(self) }
    func ToString() -> String { return self }
    var IsEmpty: Bool { return isEmpty }

    /// `new string('.', n)` → `String('.', n)`
    init(_ c: Character, _ count: Int) { self = String(repeating: c, count: Swift.max(0, count)) }
}

extension Character {
    func ToString() -> String { return String(self) }
    func CompareTo(_ o: Character) -> Int { return self < o ? -1 : (self == o ? 0 : 1) }
    /// `(int)c` → `c.Code`
    var Code: Int { return Int(unicodeScalars.first?.value ?? 0) }
    init(_ code: Int) { self = Character(Unicode.Scalar(UInt32(Swift.max(0, code))) ?? " ") }
}

extension Optional where Wrapped == String {
    /// Lets `s.Length` style code compile on String? / String! (nil → 0).
    var Length: Int { return self?.utf16.count ?? 0 }
}

// MARK: - Number formatting (ToString(fmt))

/// Formats |x| with `dec` decimals using .NET Framework rounding (15 significant digits, then half away from zero).
private func csFixed(_ x: Double, _ dec: Int) -> String {
    let ax = Swift.abs(x)
    if ax.isNaN { return "NaN" }
    if ax.isInfinite { return "Infinity" }
    let s15 = String(format: "%.14e", ax)  // d.dddddddddddddde±XX → 15 significant digits
    guard let eIdx = s15.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return String(format: "%.\(dec)f", ax) }
    let mant = s15[..<eIdx].replacingOccurrences(of: ".", with: "")
    let exp = Int(s15[s15.index(after: eIdx)...]) ?? 0
    var digits = mant.map { Int($0.asciiValue! - 48) }  // value = 0.d1d2d3… × 10^(exp+1)
    var pointPos = exp + 1                                  // digits before decimal point
    // number of digits to keep = pointPos + dec
    let keep = pointPos + dec
    if keep < 0 { return dec > 0 ? "0." + String(repeating: "0", count: dec) : "0" }
    if keep < digits.count {
        let roundUp = digits[keep] >= 5
        digits = Array(digits[0..<keep])
        if roundUp {
            var i = digits.count - 1
            var carry = true
            while carry && i >= 0 { digits[i] += 1; if digits[i] == 10 { digits[i] = 0; i -= 1 } else { carry = false } }
            if carry { digits.insert(1, at: 0); pointPos += 1 }
        }
    }
    while digits.count < pointPos + dec { digits.append(0) }
    var intPart = ""
    if pointPos <= 0 { intPart = "0" } else { intPart = digits[0..<pointPos].map { String($0) }.joined() }
    var frac = ""
    if dec > 0 {
        if pointPos < 0 { frac = String(repeating: "0", count: Swift.min(dec, -pointPos)) + digits.map { String($0) }.joined() }
        else { frac = digits[pointPos...].map { String($0) }.joined() }
        frac = String(frac.prefix(dec))
        while frac.count < dec { frac += "0" }
    }
    // strip leading zeros in int part (keep one)
    while intPart.count > 1 && intPart.hasPrefix("0") { intPart.removeFirst() }
    return dec > 0 ? intPart + "." + frac : intPart
}

private func csGroup(_ intPart: String) -> String {
    var out = ""
    let cs = Array(intPart)
    for (i, c) in cs.enumerated() {
        if i > 0 && (cs.count - i) % 3 == 0 { out.append(",") }
        out.append(c)
    }
    return out
}

private func csFormatDouble(_ x: Double, _ fmt: String) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if fmt.isEmpty || fmt == "G" || fmt == "g" || fmt == "R" || fmt == "r" { return x.ToString() }
    let f0 = fmt.first!
    let rest = String(fmt.dropFirst())
    if f0.isLetter, rest.allSatisfy({ $0.isNumber }) {
        let n = Int(rest)
        switch f0 {
        case "F", "f":
            let s = csFixed(x, n ?? 2); return (x < 0 && s.contains(where: { $0 != "0" && $0 != "." })) ? "-" + s : s
        case "N", "n":
            let s = csFixed(x, n ?? 2)
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            var r = csGroup(String(parts[0]))
            if parts.count > 1 { r += "." + parts[1] }
            return (x < 0 && s.contains(where: { $0 != "0" && $0 != "." })) ? "-" + r : r
        case "P", "p":
            return csFormatDouble(x * 100, "N\(n ?? 2)") + " %"
        case "E", "e":
            return String(format: "%.\(n ?? 6)\(f0 == "E" ? "E" : "e")", x)
        case "G", "g":
            if let n = n, n > 0 { return String(format: "%.\(n)G", x) }
            return x.ToString()
        case "D", "d", "X", "x":
            return CInt(x).ToString(fmt)
        default: break
        }
    }
    // custom format: [prefix]0…0[.0…0#…#][suffix], optional ',' grouping, optional '%'
    let chars = Array(fmt)
    var prefix = "", suffix = ""
    var i = 0
    while i < chars.count && !"0#.,".contains(chars[i]) { prefix.append(chars[i]); i += 1 }
    var j = chars.count
    while j > i && !"0#.,".contains(chars[j - 1]) { j -= 1 }
    for k in j..<chars.count { suffix.append(chars[k]) }
    let core = String(chars[i..<j])
    var v = x
    if fmt.contains("%") { v *= 100 }
    let group = core.contains(",") && core.contains(where: { $0 == "0" || $0 == "#" })
    let coreNoComma = core.replacingOccurrences(of: ",", with: "")
    let ip: Substring, fp: Substring
    if let dot = coreNoComma.firstIndex(of: ".") { ip = coreNoComma[..<dot]; fp = coreNoComma[coreNoComma.index(after: dot)...] } else { ip = Substring(coreNoComma); fp = "" }
    let minInt = ip.filter { $0 == "0" }.count
    let minDec = fp.filter { $0 == "0" }.count
    let maxDec = fp.count
    var s = csFixed(v, maxDec)
    // trim optional (#) decimals
    if maxDec > minDec, let dot = s.firstIndex(of: ".") {
        var frac = String(s[s.index(after: dot)...])
        while frac.count > minDec && frac.hasSuffix("0") { frac.removeLast() }
        s = String(s[..<dot]) + (frac.isEmpty ? "" : "." + frac)
    }
    var intPart: String, fracPart: String?
    if let dot = s.firstIndex(of: ".") { intPart = String(s[..<dot]); fracPart = String(s[s.index(after: dot)...]) } else { intPart = s; fracPart = nil }
    if intPart == "0" && minInt == 0 { intPart = "" }
    while intPart.count < minInt { intPart = "0" + intPart }
    if group { intPart = csGroup(intPart) }
    var r = intPart + (fracPart != nil ? "." + fracPart! : "")
    if r.isEmpty { r = "0" }
    let isZero = !r.contains(where: { $0 >= "1" && $0 <= "9" })
    if v < 0 && !isZero { r = "-" + r }
    return prefix + r + suffix.replacingOccurrences(of: "%", with: "%")
}

extension Int {
    func ToString() -> String { return String(self) }
    func ToString(_ c: CultureInfo) -> String { return String(self) }
    func ToString(_ fmt: String, _ c: CultureInfo) -> String { return ToString(fmt) }
    func ToString(_ fmt: String) -> String {
        if fmt.isEmpty || fmt == "G" || fmt == "g" { return String(self) }
        let f0 = fmt.first!
        let rest = String(fmt.dropFirst())
        if f0.isLetter, rest.allSatisfy({ $0.isNumber }) {
            let n = Int(rest) ?? 0
            switch f0 {
            case "X", "x":
                let u = UInt64(bitPattern: Int64(self))
                var s = String(self < 0 && self >= Int(Int32.min) ? UInt64(UInt32(truncatingIfNeeded: self)) : u, radix: 16, uppercase: f0 == "X")
                while s.count < n { s = "0" + s }
                return s
            case "D", "d":
                var s = String(Swift.abs(self))
                while s.count < n { s = "0" + s }
                return self < 0 ? "-" + s : s
            case "N", "n", "F", "f", "P", "p", "E", "e":
                return csFormatDouble(Double(self), fmt)
            default: break
            }
        }
        return csFormatDouble(Double(self), fmt)
    }
    func CompareTo(_ o: Int) -> Int { return self < o ? -1 : (self == o ? 0 : 1) }
    func Equals(_ o: Int) -> Bool { return self == o }
}

extension Double {
    /// C# (.NET Framework) default formatting: up to 15 significant digits, no trailing ".0".
    func ToString() -> String {
        if isNaN { return "NaN" }
        if isInfinite { return self > 0 ? "Infinity" : "-Infinity" }
        if self == 0 { return "0" }
        var s = String(format: "%.15G", self)
        if s.contains("E") {
            // .NET: 1E+20, 1E-05
            let parts = s.components(separatedBy: "E")
            var m = parts[0]
            if m.contains(".") { while m.hasSuffix("0") { m.removeLast() }; if m.hasSuffix(".") { m.removeLast() } }
            var e = parts[1]
            let sign = e.hasPrefix("-") ? "-" : "+"
            e = e.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
            while e.count < 2 { e = "0" + e }
            s = m + "E" + sign + e
        }
        return s
    }
    func ToString(_ fmt: String) -> String { return csFormatDouble(self, fmt) }
    func ToString(_ fmt: String, _ c: CultureInfo) -> String { return csFormatDouble(self, fmt) }
    func ToString(_ c: CultureInfo) -> String { return ToString() }
    func CompareTo(_ o: Double) -> Int {
        if self < o { return -1 }
        if self > o { return 1 }
        if self == o { return 0 }
        if isNaN { return o.isNaN ? 0 : -1 }
        return 1
    }
    func Equals(_ o: Double) -> Bool { return self == o || (isNaN && o.isNaN) }
}

extension Bool {
    /// C# prints booleans capitalised.
    func ToString() -> String { return self ? "True" : "False" }
    func CompareTo(_ o: Bool) -> Int { return self == o ? 0 : (self ? 1 : -1) }
}

// MARK: - .NET List.Sort / Array.Sort (introsort — reproduces .NET's (unstable) order exactly)

private func csFloorLog2(_ n: Int) -> Int { var r = 0; var n = n; while n >= 1 { r += 1; n /= 2 }; return r }

func csIntroSort<T>(_ keys: inout [T], _ left: Int, _ length: Int, _ cmp: (T, T) -> Int) {
    if length < 2 { return }
    csIntroSortRange(&keys, left, length + left - 1, 2 * csFloorLog2(keys.count), cmp)
}
private func csSwapIfGreater<T>(_ k: inout [T], _ cmp: (T, T) -> Int, _ a: Int, _ b: Int) {
    if a != b && cmp(k[a], k[b]) > 0 { k.swapAt(a, b) }
}
private func csIntroSortRange<T>(_ k: inout [T], _ lo0: Int, _ hi0: Int, _ depth0: Int, _ cmp: (T, T) -> Int) {
    var hi = hi0
    let lo = lo0
    var depth = depth0
    while hi > lo {
        let size = hi - lo + 1
        if size <= 16 {
            if size == 1 { return }
            if size == 2 { csSwapIfGreater(&k, cmp, lo, hi); return }
            if size == 3 { csSwapIfGreater(&k, cmp, lo, hi - 1); csSwapIfGreater(&k, cmp, lo, hi); csSwapIfGreater(&k, cmp, hi - 1, hi); return }
            // insertion sort
            var i = lo
            while i < hi {
                var j = i
                let t = k[i + 1]
                while j >= lo && cmp(t, k[j]) < 0 { k[j + 1] = k[j]; j -= 1 }
                k[j + 1] = t
                i += 1
            }
            return
        }
        if depth == 0 { csHeapSort(&k, lo, hi, cmp); return }
        depth -= 1
        // pick pivot and partition
        let mid = lo + ((hi - lo) >> 1)
        csSwapIfGreater(&k, cmp, lo, mid)
        csSwapIfGreater(&k, cmp, lo, hi)
        csSwapIfGreater(&k, cmp, mid, hi)
        let pivot = k[mid]
        k.swapAt(mid, hi - 1)
        var l = lo, r = hi - 1
        while l < r {
            l += 1; while cmp(k[l], pivot) < 0 { l += 1 }
            r -= 1; while cmp(pivot, k[r]) < 0 { r -= 1 }
            if l >= r { break }
            k.swapAt(l, r)
        }
        if l != hi - 1 { k.swapAt(l, hi - 1) }
        let p = l
        csIntroSortRange(&k, p + 1, hi, depth, cmp)
        hi = p - 1
    }
}
private func csHeapSort<T>(_ k: inout [T], _ lo: Int, _ hi: Int, _ cmp: (T, T) -> Int) {
    let n = hi - lo + 1
    var i = n / 2
    while i >= 1 { csDownHeap(&k, i, n, lo, cmp); i -= 1 }
    i = n
    while i > 1 { k.swapAt(lo, lo + i - 1); csDownHeap(&k, 1, i - 1, lo, cmp); i -= 1 }
}
private func csDownHeap<T>(_ k: inout [T], _ i0: Int, _ n: Int, _ lo: Int, _ cmp: (T, T) -> Int) {
    var i = i0
    let d = k[lo + i - 1]
    while i <= n / 2 {
        var child = 2 * i
        if child < n && cmp(k[lo + child - 1], k[lo + child]) < 0 { child += 1 }
        if !(cmp(d, k[lo + child - 1]) < 0) { break }
        k[lo + i - 1] = k[lo + child - 1]
        i = child
    }
    k[lo + i - 1] = d
}

/// Equality used by List.Contains/IndexOf/Remove for element types that aren't statically Equatable:
/// classes compare by reference (C# default), Equatable values by ==.
private func csOpenEq<E: Equatable>(_ a: E, _ b: Any) -> Bool { return (b as? E) == a }
@inline(__always) func csEquals<T>(_ a: T, _ b: T) -> Bool {
    if T.self is AnyClass { return (a as AnyObject) === (b as AnyObject) }
    if let ea = a as? any Equatable { return csOpenEq(ea, b) }
    return false
}

// MARK: - Collections

struct KeyValuePair<K, V> {
    var Key: K
    var Value: V
    init(_ k: K, _ v: V) { Key = k; Value = v }
}

final class List<T>: Sequence {
    var items: [T]
    init() { items = [] }
    init(_ capacity: Int) { items = []; items.reserveCapacity(Swift.max(0, capacity)) }
    init(_ a: [T]) { items = a }
    init(_ other: List<T>) { items = other.items }
    init<S: Sequence>(_ s: S) where S.Element == T { items = Array(s) }

    var Count: Int { return items.count }
    var Capacity: Int { get { return items.capacity } set { items.reserveCapacity(newValue) } }
    subscript(_ i: Int) -> T {
        get { return items[i] }
        set { items[i] = newValue }
    }
    func makeIterator() -> IndexingIterator<[T]> { return items.makeIterator() }

    func Add(_ x: T) { items.append(x) }
    func AddRange(_ xs: [T]) { items.append(contentsOf: xs) }
    func AddRange(_ xs: List<T>) { items.append(contentsOf: xs.items) }
    func AddRange(_ xs: Arr<T>) { items.append(contentsOf: xs.a) }
    func Insert(_ i: Int, _ x: T) { items.insert(x, at: i) }
    func InsertRange(_ i: Int, _ xs: [T]) { items.insert(contentsOf: xs, at: i) }
    func RemoveAt(_ i: Int) { items.remove(at: i) }
    func RemoveRange(_ i: Int, _ n: Int) { if n > 0 { items.removeSubrange(i..<(i + n)) } }
    @discardableResult func RemoveAll(_ pred: (T) -> Bool) -> Int {
        let before = items.count
        items.removeAll(where: pred)
        return before - items.count
    }
    func Clear() { items.removeAll(keepingCapacity: true) }

    func IndexOf(_ x: T) -> Int {
        var i = 0
        for y in items { if csEquals(y, x) { return i }; i += 1 }
        return -1
    }
    func LastIndexOf(_ x: T) -> Int {
        var i = items.count - 1
        while i >= 0 { if csEquals(items[i], x) { return i }; i -= 1 }
        return -1
    }
    func Contains(_ x: T) -> Bool { return IndexOf(x) >= 0 }
    @discardableResult func Remove(_ x: T) -> Bool {
        let i = IndexOf(x)
        if i < 0 { return false }
        items.remove(at: i)
        return true
    }

    func Find(_ pred: (T) -> Bool) -> T? { return items.first(where: pred) }
    func FindLast(_ pred: (T) -> Bool) -> T? { return items.last(where: pred) }
    func FindIndex(_ pred: (T) -> Bool) -> Int { return items.firstIndex(where: pred) ?? -1 }
    func FindLastIndex(_ pred: (T) -> Bool) -> Int { return items.lastIndex(where: pred) ?? -1 }
    func FindAll(_ pred: (T) -> Bool) -> List<T> { return List<T>(items.filter(pred)) }
    func Exists(_ pred: (T) -> Bool) -> Bool { return items.contains(where: pred) }
    func TrueForAll(_ pred: (T) -> Bool) -> Bool { return items.allSatisfy(pred) }
    func ForEach(_ f: (T) -> Void) { for x in items { f(x) } }
    func GetRange(_ i: Int, _ n: Int) -> List<T> { return List<T>(Array(items[i..<(i + n)])) }
    func Reverse() { items.reverse() }
    func ToArray() -> [T] { return items }
    /// .NET Comparison<T> sort (same unstable introsort as .NET, so ties land in the same order).
    func Sort(_ cmp: (T, T) -> Int) { csIntroSort(&items, 0, items.count, cmp) }
    var First: T? { return items.first }
    var Last: T? { return items.last }
}

extension List where T: Equatable {
    func IndexOf(_ x: T) -> Int { return items.firstIndex(of: x) ?? -1 }
    func Contains(_ x: T) -> Bool { return items.contains(x) }
    @discardableResult func Remove(_ x: T) -> Bool {
        if let i = items.firstIndex(of: x) { items.remove(at: i); return true }
        return false
    }
}
extension List where T: Comparable {
    func Sort() { csIntroSort(&items, 0, items.count) { $0 < $1 ? -1 : ($0 == $1 ? 0 : 1) } }
}

/// Dictionary with .NET's enumeration order (insertion order; removed slots are reused LIFO).
final class Dict<K: Hashable, V>: Sequence {
    private var keys_: [K?] = []
    private var vals_: [V?] = []
    private var index: [K: Int] = [:]
    private var free: [Int] = []

    init() {}
    init(_ capacity: Int) { index.reserveCapacity(capacity) }
    init(_ other: Dict<K, V>) { for kv in other { self[kv.Key] = kv.Value } }

    var Count: Int { return index.count }
    subscript(_ k: K) -> V {
        get {
            guard let i = index[k] else { fatalError("KeyNotFoundException: \(k)") }
            return vals_[i]!
        }
        set {
            if let i = index[k] { vals_[i] = newValue; return }
            if let f = free.popLast() { keys_[f] = k; vals_[f] = newValue; index[k] = f }
            else { keys_.append(k); vals_.append(newValue); index[k] = keys_.count - 1 }
        }
    }
    func Add(_ k: K, _ v: V) { self[k] = v }
    func ContainsKey(_ k: K) -> Bool { return index[k] != nil }
    @discardableResult func TryGetValue(_ k: K, _ v: inout V) -> Bool {
        if let i = index[k] { v = vals_[i]!; return true }
        return false
    }
    @discardableResult func TryGetValue(_ k: K, _ v: inout V?) -> Bool {
        if let i = index[k] { v = vals_[i]!; return true }
        v = nil; return false
    }
    /// Swift-style lookup (nil if missing).
    func Get(_ k: K) -> V? { if let i = index[k] { return vals_[i] }; return nil }
    @discardableResult func Remove(_ k: K) -> Bool {
        guard let i = index.removeValue(forKey: k) else { return false }
        keys_[i] = nil; vals_[i] = nil
        free.append(i)
        return true
    }
    func Clear() { keys_.removeAll(); vals_.removeAll(); index.removeAll(); free.removeAll() }
    var Keys: [K] { return keys_.compactMap { $0 } }
    var Values: [V] {
        var out: [V] = []
        out.reserveCapacity(index.count)
        for i in 0..<keys_.count where keys_[i] != nil { out.append(vals_[i]!) }
        return out
    }
    func makeIterator() -> AnyIterator<KeyValuePair<K, V>> {
        let ks = keys_, vs = vals_
        var i = 0
        return AnyIterator {
            while i < ks.count {
                defer { i += 1 }
                if let k = ks[i] { return KeyValuePair(k, vs[i]!) }
            }
            return nil
        }
    }
}
extension Dict where V: Equatable {
    func ContainsValue(_ v: V) -> Bool { return Values.contains(v) }
}

final class HashSet<T: Hashable>: Sequence {
    private let d = Dict<T, Bool>()
    init() {}
    init(_ xs: [T]) { for x in xs { d[x] = true } }
    init(_ xs: List<T>) { for x in xs { d[x] = true } }
    init<S: Sequence>(_ xs: S) where S.Element == T { for x in xs { d[x] = true } }
    var Count: Int { return d.Count }
    @discardableResult func Add(_ x: T) -> Bool { if d.ContainsKey(x) { return false }; d[x] = true; return true }
    func Contains(_ x: T) -> Bool { return d.ContainsKey(x) }
    @discardableResult func Remove(_ x: T) -> Bool { return d.Remove(x) }
    func Clear() { d.Clear() }
    @discardableResult func RemoveWhere(_ pred: (T) -> Bool) -> Int {
        var n = 0
        for k in d.Keys where pred(k) { d.Remove(k); n += 1 }
        return n
    }
    func UnionWith<S: Sequence>(_ xs: S) where S.Element == T { for x in xs { Add(x) } }
    func ExceptWith<S: Sequence>(_ xs: S) where S.Element == T { for x in xs { Remove(x) } }
    func ToArray() -> [T] { return d.Keys }
    func makeIterator() -> IndexingIterator<[T]> { return d.Keys.makeIterator() }
}

/// Reference-semantics array (C# `T[]` mutated through shared references).
final class Arr<T>: Sequence {
    var a: [T]
    init(_ a: [T]) { self.a = a }
    init(_ count: Int, _ fill: T) { a = Array(repeating: fill, count: Swift.max(0, count)) }
    var Length: Int { return a.count }
    var Count: Int { return a.count }
    subscript(_ i: Int) -> T {
        get { return a[i] }
        set { a[i] = newValue }
    }
    func ToArray() -> [T] { return a }
    func Clone() -> Arr<T> { return Arr<T>(a) }
    func makeIterator() -> IndexingIterator<[T]> { return a.makeIterator() }
}
extension Arr where T == Double { convenience init(_ count: Int) { self.init(count, 0.0) } }
extension Arr where T == Int { convenience init(_ count: Int) { self.init(count, 0) } }
extension Arr where T == Bool { convenience init(_ count: Int) { self.init(count, false) } }

extension Array {
    var Length: Int { return count }
    var Count: Int { return count }
    func ToArray() -> [Element] { return self }
    func Clone() -> [Element] { return self }
    /// `Array.Sort(arr, comparison)` → `Array.Sort(&arr, cmp)`
    static func Sort(_ a: inout [Element], _ cmp: (Element, Element) -> Int) { csIntroSort(&a, 0, a.count, cmp) }
    static func Reverse(_ a: inout [Element]) { a.reverse() }
    static func Copy(_ src: [Element], _ dst: inout [Element], _ n: Int) { for i in 0..<Swift.max(0, n) { dst[i] = src[i] } }
    static func IndexOf(_ a: [Element], _ x: Element) -> Int where Element: Equatable { return a.firstIndex(of: x) ?? -1 }
    static func Exists(_ a: [Element], _ pred: (Element) -> Bool) -> Bool { return a.contains(where: pred) }
    static func Find(_ a: [Element], _ pred: (Element) -> Bool) -> Element? { return a.first(where: pred) }
    static func FindIndex(_ a: [Element], _ pred: (Element) -> Bool) -> Int { return a.firstIndex(where: pred) ?? -1 }
}
extension Array where Element: Comparable {
    static func Sort(_ a: inout [Element]) { csIntroSort(&a, 0, a.count) { $0 < $1 ? -1 : ($0 == $1 ? 0 : 1) } }
}
extension Array where Element: Equatable {
    func IndexOf(_ x: Element) -> Int { return firstIndex(of: x) ?? -1 }
    func Contains(_ x: Element) -> Bool { return contains(x) }
}

final class StringBuilder: CustomStringConvertible {
    var s: String
    init() { s = "" }
    init(_ str: String) { s = str }
    init(_ capacity: Int) { s = ""; s.reserveCapacity(capacity) }
    var Length: Int {
        get { return s.utf16.count }
        set { if newValue < s.utf16.count { s = s.Substring(0, newValue) } else { s += String(repeating: "\0", count: newValue - s.utf16.count) } }
    }
    @discardableResult func Append(_ x: String?) -> StringBuilder { if let x = x { s += x }; return self }
    @discardableResult func Append(_ c: Character) -> StringBuilder { s.append(c); return self }
    @discardableResult func Append(_ c: Character, _ n: Int) -> StringBuilder { s += String(repeating: c, count: Swift.max(0, n)); return self }
    @discardableResult func Append(_ i: Int) -> StringBuilder { s += String(i); return self }
    @discardableResult func Append(_ d: Double) -> StringBuilder { s += d.ToString(); return self }
    @discardableResult func Append(_ b: Bool) -> StringBuilder { s += b.ToString(); return self }
    @discardableResult func AppendLine() -> StringBuilder { s += Environment.NewLine; return self }
    @discardableResult func AppendLine(_ x: String?) -> StringBuilder { s += (x ?? "") + Environment.NewLine; return self }
    @discardableResult func AppendFormat(_ f: String, _ args: Any?...) -> StringBuilder { s += csFormat(f, args); return self }
    @discardableResult func Insert(_ i: Int, _ x: String) -> StringBuilder { s = s.Insert(i, x); return self }
    @discardableResult func Remove(_ i: Int, _ n: Int) -> StringBuilder { s = s.Remove(i, n); return self }
    @discardableResult func Replace(_ a: String, _ b: String) -> StringBuilder { s = s.Replace(a, b); return self }
    @discardableResult func Clear() -> StringBuilder { s = ""; return self }
    func ToString() -> String { return s }
    var description: String { return s }
}

// MARK: - Math / Random

enum Math {
    static let PI = Double.pi
    static let E = M_E
    @inline(__always) static func Max(_ a: Int, _ b: Int) -> Int { return a > b ? a : b }
    @inline(__always) static func Max(_ a: Double, _ b: Double) -> Double { if a.isNaN { return a }; return a > b ? a : b }
    @inline(__always) static func Max(_ a: Int, _ b: Double) -> Double { return Max(Double(a), b) }
    @inline(__always) static func Max(_ a: Double, _ b: Int) -> Double { return Max(a, Double(b)) }
    @inline(__always) static func Min(_ a: Int, _ b: Int) -> Int { return a < b ? a : b }
    @inline(__always) static func Min(_ a: Double, _ b: Double) -> Double { if a.isNaN { return a }; return a < b ? a : b }
    @inline(__always) static func Min(_ a: Int, _ b: Double) -> Double { return Min(Double(a), b) }
    @inline(__always) static func Min(_ a: Double, _ b: Int) -> Double { return Min(a, Double(b)) }
    @inline(__always) static func Abs(_ a: Int) -> Int { return a < 0 ? -a : a }
    @inline(__always) static func Abs(_ a: Double) -> Double { return Swift.abs(a) }
    @inline(__always) static func Sign(_ a: Int) -> Int { return a > 0 ? 1 : (a < 0 ? -1 : 0) }
    @inline(__always) static func Sign(_ a: Double) -> Int { return a > 0 ? 1 : (a < 0 ? -1 : 0) }
    @inline(__always) static func Sin(_ a: Double) -> Double { return Foundation.sin(a) }
    @inline(__always) static func Cos(_ a: Double) -> Double { return Foundation.cos(a) }
    @inline(__always) static func Tan(_ a: Double) -> Double { return Foundation.tan(a) }
    @inline(__always) static func Asin(_ a: Double) -> Double { return Foundation.asin(a) }
    @inline(__always) static func Acos(_ a: Double) -> Double { return Foundation.acos(a) }
    @inline(__always) static func Atan(_ a: Double) -> Double { return Foundation.atan(a) }
    @inline(__always) static func Atan2(_ y: Double, _ x: Double) -> Double { return Foundation.atan2(y, x) }
    @inline(__always) static func Sinh(_ a: Double) -> Double { return Foundation.sinh(a) }
    @inline(__always) static func Cosh(_ a: Double) -> Double { return Foundation.cosh(a) }
    @inline(__always) static func Tanh(_ a: Double) -> Double { return Foundation.tanh(a) }
    @inline(__always) static func Sqrt(_ a: Double) -> Double { return a.squareRoot() }
    @inline(__always) static func Pow(_ a: Double, _ b: Double) -> Double { return Foundation.pow(a, b) }
    @inline(__always) static func Exp(_ a: Double) -> Double { return Foundation.exp(a) }
    @inline(__always) static func Log(_ a: Double) -> Double { return Foundation.log(a) }
    @inline(__always) static func Log(_ a: Double, _ b: Double) -> Double { return Foundation.log(a) / Foundation.log(b) }
    @inline(__always) static func Log10(_ a: Double) -> Double { return Foundation.log10(a) }
    @inline(__always) static func Floor(_ a: Double) -> Double { return a.rounded(.down) }
    @inline(__always) static func Ceiling(_ a: Double) -> Double { return a.rounded(.up) }
    @inline(__always) static func Truncate(_ a: Double) -> Double { return a.rounded(.towardZero) }
    /// Banker's rounding, like .NET's default.
    @inline(__always) static func Round(_ a: Double) -> Double { return a.rounded(.toNearestOrEven) }
    static func Round(_ a: Double, _ mode: MidpointRounding) -> Double { return mode == .AwayFromZero ? a.rounded(.toNearestOrAwayFromZero) : a.rounded(.toNearestOrEven) }
    static func Round(_ a: Double, _ digits: Int) -> Double {
        let m = Foundation.pow(10.0, Double(digits))
        return (a * m).rounded(.toNearestOrEven) / m
    }
    static func Round(_ a: Double, _ digits: Int, _ mode: MidpointRounding) -> Double {
        let m = Foundation.pow(10.0, Double(digits))
        return Round(a * m, mode) / m
    }
    @inline(__always) static func Clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { return v < lo ? lo : (v > hi ? hi : v) }
    @inline(__always) static func Clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return v < lo ? lo : (v > hi ? hi : v) }
    @inline(__always) static func IEEERemainder(_ a: Double, _ b: Double) -> Double { return Foundation.remainder(a, b) }
}

/// System.Random — same algorithm as .NET Framework (Knuth subtractive), so seeded sequences match Windows.
final class Random {
    private var seedArray = [Int](repeating: 0, count: 56)
    private var inext = 0
    private var inextp = 21
    private static let MBIG = Int(Int32.max)
    private static let MSEED = 161803398
    private static var counter = 0

    convenience init() {
        Random.counter &+= 1
        self.init(Int(Int32(truncatingIfNeeded: Int(arc4random()) ^ Random.counter)))
    }
    init(_ seed: Int) {
        let s32 = Int(Int32(truncatingIfNeeded: seed))
        let subtraction = s32 == Int(Int32.min) ? Int(Int32.max) : Swift.abs(s32)
        var mj = Random.MSEED - subtraction
        seedArray[55] = mj
        var mk = 1
        for i in 1..<55 {
            let ii = (21 * i) % 55
            seedArray[ii] = mk
            mk = mj - mk
            if mk < 0 { mk += Random.MBIG }
            mj = seedArray[ii]
        }
        for _ in 1..<5 {
            for i in 1..<56 {
                seedArray[i] -= seedArray[1 + (i + 30) % 55]
                // emulate Int32 wraparound
                seedArray[i] = Int(Int32(truncatingIfNeeded: seedArray[i]))
                if seedArray[i] < 0 { seedArray[i] += Random.MBIG }
            }
        }
        inext = 0
        inextp = 21
    }
    private func InternalSample() -> Int {
        var locINext = inext + 1
        var locINextp = inextp + 1
        if locINext >= 56 { locINext = 1 }
        if locINextp >= 56 { locINextp = 1 }
        var ret = seedArray[locINext] - seedArray[locINextp]
        if ret == Random.MBIG { ret -= 1 }
        if ret < 0 { ret += Random.MBIG }
        seedArray[locINext] = ret
        inext = locINext
        inextp = locINextp
        return ret
    }
    private func Sample() -> Double { return Double(InternalSample()) * (1.0 / Double(Random.MBIG)) }
    private func GetSampleForLargeRange() -> Double {
        var result = InternalSample()
        if InternalSample() % 2 == 0 { result = -result }
        var d = Double(result)
        d += Double(Int32.max - 1)
        d /= 2.0 * Double(UInt32(Int32.max)) - 1
        return d
    }
    func Next() -> Int { return InternalSample() }
    func Next(_ maxValue: Int) -> Int { return maxValue <= 0 ? 0 : Int(Sample() * Double(maxValue)) }
    func Next(_ minValue: Int, _ maxValue: Int) -> Int {
        if minValue >= maxValue { return minValue }
        let range = maxValue - minValue
        if range <= Int(Int32.max) { return Int(Sample() * Double(range)) + minValue }
        return Int(GetSampleForLargeRange() * Double(range)) + minValue
    }
    func NextDouble() -> Double { return Sample() }
    func NextBytes(_ buf: inout [UInt8]) { for i in 0..<buf.count { buf[i] = UInt8(InternalSample() % 256) } }
}

// MARK: - Time: DateTime / TimeSpan / Stopwatch

enum DayOfWeek: Int, Comparable {
    case Sunday = 0, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday
    static func < (a: DayOfWeek, b: DayOfWeek) -> Bool { return a.rawValue < b.rawValue }
    func ToString() -> String { return "\(self)" }
}
enum DateTimeKind { case Unspecified, Utc, Local }
struct DateTimeStyles: OptionSet {
    let rawValue: Int
    static let None = DateTimeStyles([])
    static let AllowLeadingWhite = DateTimeStyles(rawValue: 1)
    static let AllowTrailingWhite = DateTimeStyles(rawValue: 2)
    static let AllowInnerWhite = DateTimeStyles(rawValue: 4)
    static let AllowWhiteSpaces = DateTimeStyles(rawValue: 7)
    static let NoCurrentDateDefault = DateTimeStyles(rawValue: 8)
    static let AdjustToUniversal = DateTimeStyles(rawValue: 16)
    static let AssumeLocal = DateTimeStyles(rawValue: 32)
    static let AssumeUniversal = DateTimeStyles(rawValue: 64)
    static let RoundtripKind = DateTimeStyles(rawValue: 128)
}

private let TicksPerMillisecond = 10_000
private let TicksPerSecond = 10_000_000
private let TicksPerMinute = 600_000_000
private let TicksPerHour = 36_000_000_000
private let TicksPerDay = 864_000_000_000
private let UnixEpochTicks = 621_355_968_000_000_000
private let DaysToMonth365 = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]
private let DaysToMonth366 = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366]

struct TimeSpan: Comparable, Hashable, CustomStringConvertible {
    var Ticks: Int
    init(_ ticks: Int) { Ticks = ticks }
    init(_ h: Int, _ m: Int, _ s: Int) { Ticks = (h * 3600 + m * 60 + s) * TicksPerSecond }
    init(_ d: Int, _ h: Int, _ m: Int, _ s: Int) { Ticks = (d * 86400 + h * 3600 + m * 60 + s) * TicksPerSecond }
    init(_ d: Int, _ h: Int, _ m: Int, _ s: Int, _ ms: Int) { Ticks = ((d * 86400 + h * 3600 + m * 60 + s) * 1000 + ms) * TicksPerMillisecond }
    static let Zero = TimeSpan(0)
    static let MaxValue = TimeSpan(Int.max)
    static let MinValue = TimeSpan(Int.min)
    /// .NET Framework rounds FromX values to whole milliseconds.
    private static func interval(_ v: Double, _ scaleMs: Double) -> TimeSpan {
        if v.isNaN { return Zero }
        let ms = v * scaleMs + (v >= 0 ? 0.5 : -0.5)
        return TimeSpan(CInt(ms) * TicksPerMillisecond)
    }
    static func FromMilliseconds(_ v: Double) -> TimeSpan { return interval(v, 1) }
    static func FromSeconds(_ v: Double) -> TimeSpan { return interval(v, 1000) }
    static func FromMinutes(_ v: Double) -> TimeSpan { return interval(v, 60_000) }
    static func FromHours(_ v: Double) -> TimeSpan { return interval(v, 3_600_000) }
    static func FromDays(_ v: Double) -> TimeSpan { return interval(v, 86_400_000) }
    static func FromTicks(_ t: Int) -> TimeSpan { return TimeSpan(t) }
    var TotalMilliseconds: Double { return Double(Ticks) / Double(TicksPerMillisecond) }
    var TotalSeconds: Double { return Double(Ticks) / Double(TicksPerSecond) }
    var TotalMinutes: Double { return Double(Ticks) / Double(TicksPerMinute) }
    var TotalHours: Double { return Double(Ticks) / Double(TicksPerHour) }
    var TotalDays: Double { return Double(Ticks) / Double(TicksPerDay) }
    var Days: Int { return Ticks / TicksPerDay }
    var Hours: Int { return (Ticks / TicksPerHour) % 24 }
    var Minutes: Int { return (Ticks / TicksPerMinute) % 60 }
    var Seconds: Int { return (Ticks / TicksPerSecond) % 60 }
    var Milliseconds: Int { return (Ticks / TicksPerMillisecond) % 1000 }
    func Add(_ o: TimeSpan) -> TimeSpan { return TimeSpan(Ticks + o.Ticks) }
    func Subtract(_ o: TimeSpan) -> TimeSpan { return TimeSpan(Ticks - o.Ticks) }
    func Duration() -> TimeSpan { return TimeSpan(Swift.abs(Ticks)) }
    func Negate() -> TimeSpan { return TimeSpan(-Ticks) }
    func CompareTo(_ o: TimeSpan) -> Int { return Ticks.CompareTo(o.Ticks) }
    static func + (a: TimeSpan, b: TimeSpan) -> TimeSpan { return TimeSpan(a.Ticks + b.Ticks) }
    static func - (a: TimeSpan, b: TimeSpan) -> TimeSpan { return TimeSpan(a.Ticks - b.Ticks) }
    static prefix func - (a: TimeSpan) -> TimeSpan { return TimeSpan(-a.Ticks) }
    static func < (a: TimeSpan, b: TimeSpan) -> Bool { return a.Ticks < b.Ticks }
    func ToString() -> String {
        let neg = Ticks < 0
        let t = Swift.abs(Ticks)
        let d = t / TicksPerDay, h = (t / TicksPerHour) % 24, m = (t / TicksPerMinute) % 60, s = (t / TicksPerSecond) % 60, f = t % TicksPerSecond
        var r = (neg ? "-" : "") + (d > 0 ? "\(d)." : "") + h.ToString("00") + ":" + m.ToString("00") + ":" + s.ToString("00")
        if f > 0 { r += "." + f.ToString("0000000") }
        return r
    }
    var description: String { return ToString() }
}

private func csDaysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    let tbl = leap ? DaysToMonth366 : DaysToMonth365
    let y1 = y - 1
    return y1 * 365 + y1 / 4 - y1 / 100 + y1 / 400 + tbl[Swift.max(0, Swift.min(12, m - 1))] + d - 1
}

private func csNowUtcTicks() -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_REALTIME, &ts)
    return UnixEpochTicks + ts.tv_sec * TicksPerSecond + ts.tv_nsec / 100
}
/// Local-time offset (ticks) for a UTC instant given in ticks.
private func csOffsetForUtc(_ utcTicks: Int) -> Int {
    let secs = Double(utcTicks - UnixEpochTicks) / Double(TicksPerSecond)
    return TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: secs)) * TicksPerSecond
}

struct DateTime: Comparable, Hashable, CustomStringConvertible {
    var Ticks: Int
    var Kind: DateTimeKind

    init(_ ticks: Int) { Ticks = ticks; Kind = .Unspecified }
    init(_ ticks: Int, _ kind: DateTimeKind) { Ticks = ticks; Kind = kind }
    init(_ y: Int, _ m: Int, _ d: Int) { Ticks = csDaysFromCivil(y, m, d) * TicksPerDay; Kind = .Unspecified }
    init(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) {
        Ticks = csDaysFromCivil(y, m, d) * TicksPerDay + (h * 3600 + mi * 60 + s) * TicksPerSecond; Kind = .Unspecified
    }
    init(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ kind: DateTimeKind) {
        self.init(y, m, d, h, mi, s); Kind = kind
    }
    init(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ ms: Int) {
        self.init(y, m, d, h, mi, s); Ticks += ms * TicksPerMillisecond
    }
    init(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ ms: Int, _ kind: DateTimeKind) {
        self.init(y, m, d, h, mi, s, ms); Kind = kind
    }

    static var UtcNow: DateTime { return DateTime(csNowUtcTicks(), .Utc) }
    static var Now: DateTime { let u = csNowUtcTicks(); return DateTime(u + csOffsetForUtc(u), .Local) }
    static var Today: DateTime { return Now.Date }
    static let MinValue = DateTime(0, .Unspecified)
    static let MaxValue = DateTime(3_155_378_975_999_999_999, .Unspecified)
    static let UnixEpoch = DateTime(UnixEpochTicks, .Utc)

    static func IsLeapYear(_ y: Int) -> Bool { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
    static func DaysInMonth(_ y: Int, _ m: Int) -> Int { let t = IsLeapYear(y) ? DaysToMonth366 : DaysToMonth365; return t[m] - t[m - 1] }
    static func SpecifyKind(_ d: DateTime, _ k: DateTimeKind) -> DateTime { return DateTime(d.Ticks, k) }

    // --- calendar parts ---
    private func ymd() -> (Int, Int, Int, Int) {   // year, month, day, dayOfYear(0-based)
        var n = Ticks / TicksPerDay
        let y400 = n / 146097; n -= y400 * 146097
        var y100 = n / 36524; if y100 == 4 { y100 = 3 }; n -= y100 * 36524
        let y4 = n / 1461; n -= y4 * 1461
        var y1 = n / 365; if y1 == 4 { y1 = 3 }
        let year = y400 * 400 + y100 * 100 + y4 * 4 + y1 + 1
        n -= y1 * 365
        let leap = y1 == 3 && (y4 != 24 || y100 == 3)
        let days = leap ? DaysToMonth366 : DaysToMonth365
        var m = (n >> 5) + 1
        while n >= days[m] { m += 1 }
        return (year, m, n - days[m - 1] + 1, n)
    }
    var Year: Int { return ymd().0 }
    var Month: Int { return ymd().1 }
    var Day: Int { return ymd().2 }
    var DayOfYear: Int { return ymd().3 + 1 }
    var Hour: Int { return (Ticks / TicksPerHour) % 24 }
    var Minute: Int { return (Ticks / TicksPerMinute) % 60 }
    var Second: Int { return (Ticks / TicksPerSecond) % 60 }
    var Millisecond: Int { return (Ticks / TicksPerMillisecond) % 1000 }
    var DayOfWeek: DayOfWeek { return DeskPalsDayOfWeek(rawValue: (Ticks / TicksPerDay + 1) % 7)! }
    var Date: DateTime { return DateTime(Ticks - Ticks % TicksPerDay, Kind) }
    var TimeOfDay: TimeSpan { return TimeSpan(Ticks % TicksPerDay) }

    // --- arithmetic ---
    private func addMs(_ v: Double, _ scale: Double) -> DateTime {
        let ms = v * scale + (v >= 0 ? 0.5 : -0.5)
        return DateTime(Ticks + CInt(ms) * TicksPerMillisecond, Kind)
    }
    func AddTicks(_ t: Int) -> DateTime { return DateTime(Ticks + t, Kind) }
    func AddMilliseconds(_ v: Double) -> DateTime { return addMs(v, 1) }
    func AddSeconds(_ v: Double) -> DateTime { return addMs(v, 1000) }
    func AddMinutes(_ v: Double) -> DateTime { return addMs(v, 60_000) }
    func AddHours(_ v: Double) -> DateTime { return addMs(v, 3_600_000) }
    func AddDays(_ v: Double) -> DateTime { return addMs(v, 86_400_000) }
    func AddMilliseconds(_ v: Int) -> DateTime { return DateTime(Ticks + v * TicksPerMillisecond, Kind) }
    func AddSeconds(_ v: Int) -> DateTime { return DateTime(Ticks + v * TicksPerSecond, Kind) }
    func AddMinutes(_ v: Int) -> DateTime { return DateTime(Ticks + v * TicksPerMinute, Kind) }
    func AddHours(_ v: Int) -> DateTime { return DateTime(Ticks + v * TicksPerHour, Kind) }
    func AddDays(_ v: Int) -> DateTime { return DateTime(Ticks + v * TicksPerDay, Kind) }
    func AddMonths(_ months: Int) -> DateTime {
        let (y0, m0, d0, _) = ymd()
        var i = m0 - 1 + months
        var y = y0
        if i >= 0 { y += i / 12; i = i % 12 } else { y += (i - 11) / 12; i = 11 + (i + 1) % 12 }
        let m = i + 1
        let d = Swift.min(d0, DateTime.DaysInMonth(y, m))
        return DateTime(csDaysFromCivil(y, m, d) * TicksPerDay + Ticks % TicksPerDay, Kind)
    }
    func AddYears(_ v: Int) -> DateTime { return AddMonths(v * 12) }
    func Add(_ t: TimeSpan) -> DateTime { return DateTime(Ticks + t.Ticks, Kind) }
    func Subtract(_ d: DateTime) -> TimeSpan { return TimeSpan(Ticks - d.Ticks) }
    func Subtract(_ t: TimeSpan) -> DateTime { return DateTime(Ticks - t.Ticks, Kind) }
    func CompareTo(_ o: DateTime) -> Int { return Ticks.CompareTo(o.Ticks) }
    func Equals(_ o: DateTime) -> Bool { return Ticks == o.Ticks }

    func ToUniversalTime() -> DateTime {
        if Kind == .Utc { return self }
        // local wall-clock → UTC (two-step to get the offset right around DST changes)
        let guess = Ticks - csOffsetForUtc(Ticks)
        let off = csOffsetForUtc(guess)
        return DateTime(Ticks - off, .Utc)
    }
    func ToLocalTime() -> DateTime {
        if Kind == .Local { return self }
        return DateTime(Ticks + csOffsetForUtc(Ticks), .Local)
    }
    /// Foundation Date for this instant.
    var NSDateValue: Foundation.Date {
        let u = ToUniversalTime()
        return Foundation.Date(timeIntervalSince1970: Double(u.Ticks - UnixEpochTicks) / Double(TicksPerSecond))
    }
    init(_ date: Foundation.Date) {
        let u = UnixEpochTicks + Int((date.timeIntervalSince1970 * Double(TicksPerSecond)).rounded())
        self.init(u + csOffsetForUtc(u), .Local)
    }

    static func - (a: DateTime, b: DateTime) -> TimeSpan { return TimeSpan(a.Ticks - b.Ticks) }
    static func - (a: DateTime, b: TimeSpan) -> DateTime { return DateTime(a.Ticks - b.Ticks, a.Kind) }
    static func + (a: DateTime, b: TimeSpan) -> DateTime { return DateTime(a.Ticks + b.Ticks, a.Kind) }
    static func < (a: DateTime, b: DateTime) -> Bool { return a.Ticks < b.Ticks }
    static func == (a: DateTime, b: DateTime) -> Bool { return a.Ticks == b.Ticks }
    func hash(into h: inout Hasher) { h.combine(Ticks) }

    // --- formatting ---
    private static let MonthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let DayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    func ToString() -> String { return ToString("yyyy/M/d HH:mm:ss") }
    func ToString(_ c: CultureInfo) -> String { return ToString() }
    func ToString(_ fmt: String, _ c: CultureInfo) -> String { return ToString(fmt) }
    func ToString(_ fmt0: String) -> String {
        var fmt = fmt0
        switch fmt0 {
        case "": fmt = "yyyy/M/d HH:mm:ss"
        case "s": fmt = "yyyy'-'MM'-'dd'T'HH':'mm':'ss"
        case "o", "O": fmt = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fffffffK"
        case "u": fmt = "yyyy'-'MM'-'dd HH':'mm':'ss'Z'"
        case "d": fmt = "yyyy/M/d"
        case "D": fmt = "yyyy'年'M'月'd'日'"
        case "t": fmt = "HH:mm"
        case "T": fmt = "HH:mm:ss"
        case "g": fmt = "yyyy/M/d HH:mm"
        case "G": fmt = "yyyy/M/d HH:mm:ss"
        case "M", "m": fmt = "M'月'd'日'"
        case "y", "Y": fmt = "yyyy'年'M'月'"
        default: break
        }
        let (y, mo, d, _) = ymd()
        let h = Hour, mi = Minute, s = Second
        let frac = Ticks % TicksPerSecond
        let cs = Array(fmt)
        var out = ""
        var i = 0
        func run(_ c: Character) -> Int { var n = 0; while i + n < cs.count && cs[i + n] == c { n += 1 }; return n }
        func pad(_ v: Int, _ n: Int) -> String { var s = String(v); while s.count < n { s = "0" + s }; return s }
        while i < cs.count {
            let c = cs[i]
            switch c {
            case "y":
                let n = run(c); i += n
                out += n <= 2 ? pad(y % 100, n) : pad(y, n)
            case "M":
                let n = run(c); i += n
                out += n >= 4 ? DateTime.MonthNames[mo - 1] : (n == 3 ? String(DateTime.MonthNames[mo - 1].prefix(3)) : pad(mo, n))
            case "d":
                let n = run(c); i += n
                let dow = (Ticks / TicksPerDay + 1) % 7
                out += n >= 4 ? DateTime.DayNames[dow] : (n == 3 ? String(DateTime.DayNames[dow].prefix(3)) : pad(d, n))
            case "H": let n = run(c); i += n; out += pad(h, Swift.min(n, 2))
            case "h": let n = run(c); i += n; out += pad(h % 12 == 0 ? 12 : h % 12, Swift.min(n, 2))
            case "m": let n = run(c); i += n; out += pad(mi, Swift.min(n, 2))
            case "s": let n = run(c); i += n; out += pad(s, Swift.min(n, 2))
            case "f", "F":
                let n = Swift.min(run(c), 7); i += n
                var fs = pad(frac, 7)
                fs = String(fs.prefix(n))
                if c == "F" { while fs.hasSuffix("0") { fs.removeLast() } }
                out += fs
            case "t":
                let n = run(c); i += n
                let ap = h < 12 ? "AM" : "PM"
                out += n == 1 ? String(ap.prefix(1)) : ap
            case "K":
                i += 1
                if Kind == .Utc { out += "Z" }
                else if Kind == .Local {
                    let off = csOffsetForUtc(ToUniversalTime().Ticks) / TicksPerMinute
                    out += (off < 0 ? "-" : "+") + pad(Swift.abs(off) / 60, 2) + ":" + pad(Swift.abs(off) % 60, 2)
                }
            case "z":
                let n = run(c); i += n
                let off = csOffsetForUtc(ToUniversalTime().Ticks) / TicksPerMinute
                let sign = off < 0 ? "-" : "+"
                if n == 1 { out += sign + String(Swift.abs(off) / 60) }
                else if n == 2 { out += sign + pad(Swift.abs(off) / 60, 2) }
                else { out += sign + pad(Swift.abs(off) / 60, 2) + ":" + pad(Swift.abs(off) % 60, 2) }
            case "'", "\"":
                i += 1
                while i < cs.count && cs[i] != c { out.append(cs[i]); i += 1 }
                i += 1
            case "\\":
                if i + 1 < cs.count { out.append(cs[i + 1]) }
                i += 2
            default:
                out.append(c); i += 1
            }
        }
        return out
    }
    var description: String { return ToString() }

    // --- parsing ---
    private static let MonthAbbr = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let rxISO = try! NSRegularExpression(pattern: "^(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})(?:(?:[ T]+)(\\d{1,2}):(\\d{1,2})(?::(\\d{1,2})(?:[.,](\\d+))?)?)?\\s*(Z|GMT|UTC|[+-]\\d{1,2}(?::?\\d{2})?)?$", options: [.caseInsensitive])
    private static let rxRFC = try! NSRegularExpression(pattern: "^(?:[A-Za-z]{3},?\\s+)?(\\d{1,2})[ -]([A-Za-z]{3})[ -](\\d{2,4})\\s+(\\d{1,2}):(\\d{2})(?::(\\d{2}))?\\s*(GMT|UTC|Z|[+-]\\d{4})?$", options: [])
    private static let rxTime = try! NSRegularExpression(pattern: "^(\\d{1,2}):(\\d{1,2})(?::(\\d{1,2}))?$", options: [])
    private static let rxMDY = try! NSRegularExpression(pattern: "^(\\d{1,2})/(\\d{1,2})/(\\d{4})(?:\\s+(\\d{1,2}):(\\d{1,2})(?::(\\d{1,2}))?)?$", options: [])

    private static func grp(_ m: NSTextCheckingResult, _ i: Int, _ s: NSString) -> String? {
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : s.substring(with: r)
    }

    private static func parseCore(_ s0: String?, _ styles: DateTimeStyles) -> DateTime? {
        guard let s0 = s0 else { return nil }
        let s = s0.Trim()
        if s.isEmpty { return nil }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        var y = 0, mo = 0, d = 0, h = 0, mi = 0, sec = 0, fracTicks = 0
        var tz: String? = nil
        if let m = rxISO.firstMatch(in: s, options: [], range: full) {
            y = Int(grp(m, 1, ns)!)!; mo = Int(grp(m, 2, ns)!)!; d = Int(grp(m, 3, ns)!)!
            h = Int(grp(m, 4, ns) ?? "0") ?? 0; mi = Int(grp(m, 5, ns) ?? "0") ?? 0; sec = Int(grp(m, 6, ns) ?? "0") ?? 0
            if let f = grp(m, 7, ns) { var f7 = String(f.prefix(7)); while f7.count < 7 { f7 += "0" }; fracTicks = Int(f7) ?? 0 }
            tz = grp(m, 8, ns)
        } else if let m = rxRFC.firstMatch(in: s, options: [], range: full) {
            d = Int(grp(m, 1, ns)!)!
            guard let mi0 = MonthAbbr.firstIndex(of: grp(m, 2, ns)!.lowercased()) else { return nil }
            mo = mi0 + 1
            y = Int(grp(m, 3, ns)!)!; if y < 100 { y += y < 50 ? 2000 : 1900 }
            h = Int(grp(m, 4, ns)!)!; mi = Int(grp(m, 5, ns)!)!; sec = Int(grp(m, 6, ns) ?? "0") ?? 0
            tz = grp(m, 7, ns)
        } else if let m = rxMDY.firstMatch(in: s, options: [], range: full) {
            mo = Int(grp(m, 1, ns)!)!; d = Int(grp(m, 2, ns)!)!; y = Int(grp(m, 3, ns)!)!
            h = Int(grp(m, 4, ns) ?? "0") ?? 0; mi = Int(grp(m, 5, ns) ?? "0") ?? 0; sec = Int(grp(m, 6, ns) ?? "0") ?? 0
        } else if let m = rxTime.firstMatch(in: s, options: [], range: full) {
            let today = styles.contains(.AssumeUniversal) ? DateTime.UtcNow : DateTime.Now
            y = today.Year; mo = today.Month; d = today.Day
            h = Int(grp(m, 1, ns)!)!; mi = Int(grp(m, 2, ns)!)!; sec = Int(grp(m, 3, ns) ?? "0") ?? 0
        } else { return nil }
        if mo < 1 || mo > 12 || d < 1 || y < 1 || y > 9999 || d > DateTime.DaysInMonth(y, mo) || h > 23 || mi > 59 || sec > 59 { return nil }
        var t = csDaysFromCivil(y, mo, d) * TicksPerDay + (h * 3600 + mi * 60 + sec) * TicksPerSecond + fracTicks
        if let tz = tz {
            var offMin = 0
            let u = tz.uppercased()
            if u != "Z" && u != "GMT" && u != "UTC" {
                let sign = u.hasPrefix("-") ? -1 : 1
                let digits = u.filter { $0.isNumber }
                if digits.count <= 2 { offMin = (Int(digits) ?? 0) * 60 }
                else { let v = Int(digits) ?? 0; offMin = (v / 100) * 60 + v % 100 }
                offMin *= sign
            }
            t -= offMin * TicksPerMinute   // now UTC
            if styles.contains(.AdjustToUniversal) { return DateTime(t, .Utc) }
            if styles.contains(.RoundtripKind) && (u == "Z") { return DateTime(t, .Utc) }
            return DateTime(t + csOffsetForUtc(t), .Local)
        }
        if styles.contains(.AssumeUniversal) {
            if styles.contains(.AdjustToUniversal) { return DateTime(t, .Utc) }
            return DateTime(t + csOffsetForUtc(t), .Local)
        }
        if styles.contains(.AssumeLocal) {
            let dt = DateTime(t, .Local)
            return styles.contains(.AdjustToUniversal) ? dt.ToUniversalTime() : dt
        }
        return DateTime(t, .Unspecified)
    }

    /// Non-throwing: returns DateTime.MinValue on bad input (C# would throw FormatException).
    static func Parse(_ s: String?) -> DateTime { return parseCore(s, .None) ?? MinValue }
    static func Parse(_ s: String?, _ c: CultureInfo) -> DateTime { return parseCore(s, .None) ?? MinValue }
    static func Parse(_ s: String?, _ c: CultureInfo, _ st: DateTimeStyles) -> DateTime { return parseCore(s, st) ?? MinValue }
    @discardableResult static func TryParse(_ s: String?, _ v: inout DateTime) -> Bool {
        if let r = parseCore(s, .None) { v = r; return true }
        v = MinValue; return false
    }
    @discardableResult static func TryParse(_ s: String?, _ c: CultureInfo, _ st: DateTimeStyles, _ v: inout DateTime) -> Bool {
        if let r = parseCore(s, st) { v = r; return true }
        v = MinValue; return false
    }
}
typealias DeskPalsDayOfWeek = DayOfWeek

final class Stopwatch {
    private var startNs: UInt64 = 0
    private var accumNs: UInt64 = 0
    private(set) var IsRunning = false
    static let Frequency = 1_000_000_000
    static let IsHighResolution = true
    private static func nowNs() -> UInt64 { return clock_gettime_nsec_np(CLOCK_MONOTONIC) }
    static func GetTimestamp() -> Int { return Int(nowNs()) }
    static func StartNew() -> Stopwatch { let s = Stopwatch(); s.Start(); return s }
    init() {}
    func Start() { if !IsRunning { startNs = Stopwatch.nowNs(); IsRunning = true } }
    func Stop() { if IsRunning { accumNs += Stopwatch.nowNs() - startNs; IsRunning = false } }
    func Reset() { accumNs = 0; IsRunning = false }
    func Restart() { accumNs = 0; startNs = Stopwatch.nowNs(); IsRunning = true }
    private var ns: UInt64 { return accumNs + (IsRunning ? Stopwatch.nowNs() - startNs : 0) }
    var Elapsed: TimeSpan { return TimeSpan(Int(ns / 100)) }
    var ElapsedMilliseconds: Int { return Int(ns / 1_000_000) }
    var ElapsedTicks: Int { return Int(ns) }
}

// MARK: - Environment

enum Environment {
    enum SpecialFolder { case LocalApplicationData, ApplicationData, CommonApplicationData, UserProfile, Desktop, DesktopDirectory, MyDocuments, Personal, MyPictures, MyMusic, MyVideos, Startup, Programs, ProgramFiles, System, Windows, Fonts, Templates, InternetCache, Cookies, History, Recent, SendTo, StartMenu }
    static var NewLine: String { return "\n" }
    /// ms since boot (incl. sleep), wrapped to Int32 like .NET.
    static var TickCount: Int { return Int(Int32(truncatingIfNeeded: Int(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000))) }
    static var TickCount64: Int { return Int(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }
    static func GetEnvironmentVariable(_ name: String) -> String? { return ProcessInfo.processInfo.environment[name] }
    static func SetEnvironmentVariable(_ name: String, _ value: String?) {
        if let v = value { setenv(name, v, 1) } else { unsetenv(name) }
    }
    static func GetFolderPath(_ f: SpecialFolder) -> String {
        let home = NSHomeDirectory()
        switch f {
        case .LocalApplicationData, .ApplicationData: return home + "/Library/Application Support"
        case .CommonApplicationData: return "/Library/Application Support"
        case .UserProfile: return home
        case .Desktop, .DesktopDirectory: return home + "/Desktop"
        case .MyDocuments, .Personal: return home + "/Documents"
        case .MyPictures: return home + "/Pictures"
        case .MyMusic: return home + "/Music"
        case .MyVideos: return home + "/Movies"
        case .Fonts: return home + "/Library/Fonts"
        case .InternetCache: return home + "/Library/Caches"
        case .ProgramFiles, .Programs: return "/Applications"
        case .System, .Windows: return "/System"
        default: return ""
        }
    }
    static var UserName: String { return NSUserName() }
    static var MachineName: String { return ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? "" }
    static var ProcessorCount: Int { return ProcessInfo.processInfo.activeProcessorCount }
    static var SystemDirectory: String { return "/System" }
    static var CurrentDirectory: String { return FileManager.default.currentDirectoryPath }
    static var ProcessId: Int { return Int(getpid()) }
    static var Is64BitProcess: Bool { return true }
    static var OSVersion: String { return ProcessInfo.processInfo.operatingSystemVersionString }
    static func GetCommandLineArgs() -> [String] { return CommandLine.arguments }
    static func Exit(_ code: Int) -> Never { exit(Int32(code)) }
}

// MARK: - IO

enum SearchOption { case TopDirectoryOnly, AllDirectories }
enum FileMode { case CreateNew, Create, Open, OpenOrCreate, Truncate, Append }
enum FileAccess { case Read, Write, ReadWrite }
struct FileShare: OptionSet {
    let rawValue: Int
    static let None = FileShare([])
    static let Read = FileShare(rawValue: 1)
    static let Write = FileShare(rawValue: 2)
    static let ReadWrite = FileShare(rawValue: 3)
    static let Delete = FileShare(rawValue: 4)
    static let Inheritable = FileShare(rawValue: 16)
}
enum SeekOrigin { case Begin, Current, End }

class Encoding {
    static let UTF8: Encoding = UTF8Encoding(false)
    static let ASCII: Encoding = Encoding()
    static let Unicode: Encoding = Encoding()
    static var Default: Encoding { return UTF8 }
    func GetBytes(_ s: String) -> [UInt8] { return Array(s.utf8) }
    func GetByteCount(_ s: String) -> Int { return s.utf8.count }
    func GetString(_ b: [UInt8]) -> String { return String(decoding: b, as: Swift.UTF8.self) }
    func GetString(_ b: [UInt8], _ index: Int, _ count: Int) -> String {
        let lo = Swift.max(0, Swift.min(index, b.count)), hi = Swift.max(lo, Swift.min(index + count, b.count))
        return String(decoding: b[lo..<hi], as: Swift.UTF8.self)
    }
    func GetString(_ b: [Int], _ index: Int, _ count: Int) -> String {
        let lo = Swift.max(0, Swift.min(index, b.count)), hi = Swift.max(lo, Swift.min(index + count, b.count))
        return String(decoding: b[lo..<hi].map { UInt8(truncatingIfNeeded: $0) }, as: Swift.UTF8.self)
    }
    func GetString(_ b: [Int]) -> String { return GetString(b, 0, b.count) }
}
final class UTF8Encoding: Encoding {
    let emitBOM: Bool
    init(_ encoderShouldEmitUTF8Identifier: Bool) { emitBOM = encoderShouldEmitUTF8Identifier }
    override convenience init() { self.init(true) }
}

private func csDecodeText(_ d: Data) -> String {
    var bytes = [UInt8](d)
    if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { bytes.removeFirst(3) }
    return String(decoding: bytes, as: UTF8.self)
}
private func csIOError(_ path: String, _ what: String) -> IOException {
    let e = errno
    let msg = String(cString: strerror(e))
    if e == ENOENT { return FileNotFoundException("\(what) '\(path)': \(msg)") }
    return IOException("\(what) '\(path)': \(msg)")
}

enum File {
    static func Exists(_ path: String?) -> Bool {
        guard let p = path, !p.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && !isDir.boolValue
    }
    static func ReadAllText(_ path: String) throws -> String {
        guard let d = FileManager.default.contents(atPath: path) else { throw FileNotFoundException("Could not find file '\(path)'.") }
        return csDecodeText(d)
    }
    static func ReadAllText(_ path: String, _ e: Encoding) throws -> String { return try ReadAllText(path) }
    static func ReadAllLines(_ path: String) throws -> [String] {
        var lines = try ReadAllText(path).Split("\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if lines.last == "" { lines.removeLast() }
        return lines
    }
    static func ReadAllBytes(_ path: String) throws -> [UInt8] {
        guard let d = FileManager.default.contents(atPath: path) else { throw FileNotFoundException("Could not find file '\(path)'.") }
        return [UInt8](d)
    }
    static func WriteAllBytes(_ path: String, _ b: [UInt8]) throws {
        if !FileManager.default.createFile(atPath: path, contents: Data(b)) { throw csIOError(path, "Cannot write") }
    }
    static func WriteAllText(_ path: String, _ s: String?) throws {
        if !FileManager.default.createFile(atPath: path, contents: Data((s ?? "").utf8)) { throw csIOError(path, "Cannot write") }
    }
    static func WriteAllText(_ path: String, _ s: String?, _ e: Encoding) throws { try WriteAllText(path, s) }
    static func WriteAllLines(_ path: String, _ lines: [String]) throws { try WriteAllText(path, lines.map { $0 + "\n" }.joined()) }
    static func AppendAllText(_ path: String, _ s: String?) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd < 0 { throw csIOError(path, "Cannot append") }
        defer { close(fd) }
        let bytes = Array((s ?? "").utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBytes { p in write(fd, p.baseAddress! + off, bytes.count - off) }
            if n <= 0 { throw csIOError(path, "Cannot append") }
            off += n
        }
    }
    static func AppendAllText(_ path: String, _ s: String?, _ e: Encoding) throws { try AppendAllText(path, s) }
    static func Copy(_ src: String, _ dst: String) throws { try Copy(src, dst, false) }
    static func Copy(_ src: String, _ dst: String, _ overwrite: Bool) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst) {
            if !overwrite { throw IOException("The file '\(dst)' already exists.") }
            try fm.removeItem(atPath: dst)
        }
        try fm.copyItem(atPath: src, toPath: dst)
    }
    static func Move(_ src: String, _ dst: String) throws { try FileManager.default.moveItem(atPath: src, toPath: dst) }
    static func Delete(_ path: String) throws {
        if !FileManager.default.fileExists(atPath: path) { return }
        try FileManager.default.removeItem(atPath: path)
    }
    /// Missing file → 1601-01-01 UTC (like .NET).
    static func GetLastWriteTimeUtc(_ path: String) -> DateTime {
        var st = stat()
        if stat(path, &st) != 0 { return DateTime(1601, 1, 1, 0, 0, 0, .Utc) }
        return DateTime(UnixEpochTicks + st.st_mtimespec.tv_sec * TicksPerSecond + st.st_mtimespec.tv_nsec / 100, .Utc)
    }
    static func GetLastWriteTime(_ path: String) -> DateTime { return GetLastWriteTimeUtc(path).ToLocalTime() }
    static func SetLastWriteTimeUtc(_ path: String, _ t: DateTime) {
        try? FileManager.default.setAttributes([.modificationDate: t.NSDateValue], ofItemAtPath: path)
    }
}

private func csGlob(_ name: String, _ pattern: String) -> Bool {
    if pattern == "*" || pattern == "*.*" { return true }
    return fnmatch(pattern, name, 0) == 0
}
private func csListDir(_ path: String) -> [String] {
    return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
}
private func csIsDir(_ path: String) -> Bool {
    var st = stat()
    return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
}
private func csIsFile(_ path: String) -> Bool {
    var st = stat()
    if stat(path, &st) != 0 { return false }
    return (st.st_mode & S_IFMT) == S_IFREG
}
private func csEnum(_ path: String, _ pattern: String, _ opt: SearchOption, _ files: Bool) -> [String] {
    var out: [String] = []
    var stack = [path]
    while let dir = stack.popLast() {
        let names = csListDir(dir)
        var subdirs: [String] = []
        for n in names {
            let full = Path.Combine(dir, n)
            let isDir = csIsDir(full)
            if isDir { subdirs.append(full) }
            if (files ? (!isDir && csIsFile(full)) : isDir) && csGlob(n, pattern) { out.append(full) }
        }
        if opt == .AllDirectories { stack.append(contentsOf: subdirs.reversed()) }
    }
    return out
}

enum Directory {
    static func Exists(_ path: String?) -> Bool {
        guard let p = path, !p.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
    }
    @discardableResult static func CreateDirectory(_ path: String) throws -> DirectoryInfo {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return DirectoryInfo(path)
    }
    static func Delete(_ path: String) throws { try FileManager.default.removeItem(atPath: path) }
    static func Delete(_ path: String, _ recursive: Bool) throws { try FileManager.default.removeItem(atPath: path) }
    /// Non-throwing (missing dir → empty). Sorted by name.
    static func GetDirectories(_ path: String) -> [String] { return csEnum(path, "*", .TopDirectoryOnly, false) }
    static func GetDirectories(_ path: String, _ pattern: String) -> [String] { return csEnum(path, pattern, .TopDirectoryOnly, false) }
    static func GetDirectories(_ path: String, _ pattern: String, _ opt: SearchOption) -> [String] { return csEnum(path, pattern, opt, false) }
    static func GetFiles(_ path: String) -> [String] { return csEnum(path, "*", .TopDirectoryOnly, true) }
    static func GetFiles(_ path: String, _ pattern: String) -> [String] { return csEnum(path, pattern, .TopDirectoryOnly, true) }
    static func GetFiles(_ path: String, _ pattern: String, _ opt: SearchOption) -> [String] { return csEnum(path, pattern, opt, true) }
    static func EnumerateFiles(_ path: String) -> [String] { return GetFiles(path) }
    static func EnumerateFiles(_ path: String, _ pattern: String) -> [String] { return GetFiles(path, pattern) }
    static func EnumerateFiles(_ path: String, _ pattern: String, _ opt: SearchOption) -> [String] { return GetFiles(path, pattern, opt) }
    static func EnumerateDirectories(_ path: String) -> [String] { return GetDirectories(path) }
    static func GetLastWriteTimeUtc(_ path: String) -> DateTime { return File.GetLastWriteTimeUtc(path) }
    static func GetCurrentDirectory() -> String { return FileManager.default.currentDirectoryPath }
}

enum Path {
    static let DirectorySeparatorChar: Character = "/"
    static let AltDirectorySeparatorChar: Character = "/"
    static let PathSeparator: Character = ":"
    private static func isSep(_ c: Character) -> Bool { return c == "/" || c == "\\" }
    static func Combine(_ a: String, _ b: String) -> String {
        if b.isEmpty { return a }
        if a.isEmpty || b.hasPrefix("/") { return b }
        return a.hasSuffix("/") ? a + b : a + "/" + b
    }
    static func Combine(_ a: String, _ b: String, _ c: String) -> String { return Combine(Combine(a, b), c) }
    static func Combine(_ a: String, _ b: String, _ c: String, _ d: String) -> String { return Combine(Combine(Combine(a, b), c), d) }
    static func GetTempPath() -> String { let t = NSTemporaryDirectory(); return t.hasSuffix("/") ? t : t + "/" }
    static func GetTempFileName() -> String {
        let p = Combine(GetTempPath(), "tmp" + String(UInt32.random(in: 0...0xFFFFF), radix: 16).uppercased() + ".tmp")
        FileManager.default.createFile(atPath: p, contents: nil)
        return p
    }
    static func GetRandomFileName() -> String { return String(UInt64.random(in: 0...UInt64.max), radix: 36) + ".tmp" }
    static func GetFileName(_ p: String?) -> String {
        guard let p = p else { return "" }
        if let i = p.lastIndex(where: isSep) { return String(p[p.index(after: i)...]) }
        return p
    }
    static func GetExtension(_ p: String?) -> String {
        let n = GetFileName(p)
        if let i = n.lastIndex(of: "."), i != n.index(before: n.endIndex) { return String(n[i...]) }
        return ""
    }
    static func HasExtension(_ p: String?) -> Bool { return !GetExtension(p).isEmpty }
    static func GetFileNameWithoutExtension(_ p: String?) -> String {
        let n = GetFileName(p)
        if let i = n.lastIndex(of: ".") { return String(n[..<i]) }
        return n
    }
    static func ChangeExtension(_ p: String, _ ext: String?) -> String {
        let n = GetFileName(p)
        var base = p
        if let i = n.lastIndex(of: ".") { base = String(p.dropLast(n.distance(from: i, to: n.endIndex))) }
        guard let e = ext else { return base }
        return base + (e.hasPrefix(".") ? e : "." + e)
    }
    /// Returns "" for a root or a bare file name (C# returns null for root).
    static func GetDirectoryName(_ p: String?) -> String {
        guard let p = p, !p.isEmpty else { return "" }
        guard let i = p.lastIndex(where: isSep) else { return "" }
        if i == p.startIndex { return p.count == 1 ? "" : "/" }
        return String(p[..<i])
    }
    static func GetPathRoot(_ p: String?) -> String { return (p ?? "").hasPrefix("/") ? "/" : "" }
    static func IsPathRooted(_ p: String?) -> Bool { return (p ?? "").hasPrefix("/") }
    static func GetFullPath(_ p: String) -> String {
        let e = (p as NSString).expandingTildeInPath
        let abs = e.hasPrefix("/") ? e : Combine(FileManager.default.currentDirectoryPath, e)
        return (abs as NSString).standardizingPath
    }
    static func GetInvalidFileNameChars() -> [Character] { return ["/", "\0", ":"] }
}

final class FileInfo {
    let FullName: String
    private(set) var Exists = false
    private(set) var Length = 0
    private(set) var LastWriteTimeUtc = DateTime(1601, 1, 1, 0, 0, 0, .Utc)
    init(_ path: String) {
        FullName = path
        Refresh()
    }
    func Refresh() {
        var st = stat()
        if stat(FullName, &st) == 0 && (st.st_mode & S_IFMT) != S_IFDIR {
            Exists = true
            Length = Int(st.st_size)
            LastWriteTimeUtc = DateTime(UnixEpochTicks + st.st_mtimespec.tv_sec * TicksPerSecond + st.st_mtimespec.tv_nsec / 100, .Utc)
        } else { Exists = false; Length = 0 }
    }
    var Name: String { return Path.GetFileName(FullName) }
    var Extension: String { return Path.GetExtension(FullName) }
    var DirectoryName: String { return Path.GetDirectoryName(FullName) }
    var Directory: DirectoryInfo { return DirectoryInfo(DirectoryName) }
    var LastWriteTime: DateTime { return LastWriteTimeUtc.ToLocalTime() }
    func Delete() throws { try File.Delete(FullName) }
}

final class DirectoryInfo {
    let FullName: String
    init(_ path: String) { FullName = path }
    var Name: String { return Path.GetFileName(FullName) }
    var Exists: Bool { return Directory.Exists(FullName) }
    var Parent: DirectoryInfo? { let d = Path.GetDirectoryName(FullName); return d.isEmpty ? nil : DirectoryInfo(d) }
    var LastWriteTimeUtc: DateTime { return File.GetLastWriteTimeUtc(FullName) }
    func Create() throws { try Directory.CreateDirectory(FullName) }
    func EnumerateFiles() -> [FileInfo] { return GetFiles("*", .TopDirectoryOnly) }
    func EnumerateFiles(_ pattern: String) -> [FileInfo] { return GetFiles(pattern, .TopDirectoryOnly) }
    func EnumerateFiles(_ pattern: String, _ opt: SearchOption) -> [FileInfo] { return GetFiles(pattern, opt) }
    func GetFiles() -> [FileInfo] { return GetFiles("*", .TopDirectoryOnly) }
    func GetFiles(_ pattern: String) -> [FileInfo] { return GetFiles(pattern, .TopDirectoryOnly) }
    func GetFiles(_ pattern: String, _ opt: SearchOption) -> [FileInfo] { return csEnum(FullName, pattern, opt, true).map { FileInfo($0) } }
    func GetDirectories() -> [DirectoryInfo] { return csEnum(FullName, "*", .TopDirectoryOnly, false).map { DirectoryInfo($0) } }
    func EnumerateDirectories() -> [DirectoryInfo] { return GetDirectories() }
}

/// Free space of the volume holding `path`. Name = volume name (closest thing to "C:\").
final class DriveInfo {
    let RootDirectory: String
    init(_ path: String) { RootDirectory = path.isEmpty ? "/" : path }
    private var values: URLResourceValues? {
        return try? URL(fileURLWithPath: RootDirectory).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeLocalizedNameKey])
    }
    var Name: String { return values?.volumeLocalizedName ?? RootDirectory }
    var VolumeLabel: String { return Name }
    var IsReady: Bool { return values != nil }
    var AvailableFreeSpace: Int {
        if let v = values { if let i = v.volumeAvailableCapacityForImportantUsage, i > 0 { return Int(i) }; return v.volumeAvailableCapacity ?? 0 }
        return 0
    }
    var TotalFreeSpace: Int { return AvailableFreeSpace }
    var TotalSize: Int { return values?.volumeTotalCapacity ?? 0 }
}

/// Base stream (subclass for sockets etc.: override Read/Write/Flush/Close).
class Stream: IDisposable {
    func Read(_ buf: inout [UInt8], _ offset: Int, _ count: Int) throws -> Int { return 0 }
    func Write(_ buf: [UInt8], _ offset: Int, _ count: Int) throws {}
    func Flush() {}
    func Close() {}
    func Dispose() { Close() }
    var Length: Int { return 0 }
    var Position: Int { get { return 0 } set {} }
    var CanRead: Bool { return true }
    var CanWrite: Bool { return true }
    @discardableResult func Seek(_ offset: Int, _ origin: SeekOrigin) -> Int { return 0 }
    /// [Int] buffer variants (C# byte[] ported as [Int]).
    func Read(_ buf: inout [Int], _ offset: Int, _ count: Int) throws -> Int {
        var tmp = [UInt8](repeating: 0, count: Swift.max(0, count))
        let n = try Read(&tmp, 0, count)
        for i in 0..<Swift.max(0, n) { buf[offset + i] = Int(tmp[i]) }
        return n
    }
    func Write(_ buf: [Int], _ offset: Int, _ count: Int) throws {
        try Write(buf[offset..<(offset + count)].map { UInt8(truncatingIfNeeded: $0) }, 0, count)
    }
    func ReadByte() throws -> Int { var b = [UInt8](repeating: 0, count: 1); return try Read(&b, 0, 1) == 1 ? Int(b[0]) : -1 }
    func WriteByte(_ b: Int) throws { try Write([UInt8(truncatingIfNeeded: b)], 0, 1) }
}

final class FileStream: Stream {
    private var fd: Int32
    let Name: String
    init(_ path: String, _ mode: FileMode, _ access: FileAccess, _ share: FileShare) throws {
        Name = path
        var flags: Int32
        switch access { case .Read: flags = O_RDONLY; case .Write: flags = O_WRONLY; case .ReadWrite: flags = O_RDWR }
        switch mode {
        case .CreateNew: flags |= O_CREAT | O_EXCL
        case .Create: flags |= O_CREAT | O_TRUNC
        case .Open: break
        case .OpenOrCreate: flags |= O_CREAT
        case .Truncate: flags |= O_TRUNC
        case .Append: flags |= O_CREAT | O_APPEND
        }
        fd = open(path, flags, 0o644)
        super.init()
        if fd < 0 { throw csIOError(path, "Cannot open") }
    }
    convenience init(_ path: String, _ mode: FileMode) throws {
        try self.init(path, mode, mode == .Open ? .Read : .ReadWrite, .Read)
    }
    convenience init(_ path: String, _ mode: FileMode, _ access: FileAccess) throws {
        try self.init(path, mode, access, .Read)
    }
    deinit { if fd >= 0 { close(fd) } }
    override func Read(_ buf: inout [UInt8], _ offset: Int, _ count: Int) throws -> Int {
        if fd < 0 || count <= 0 { return 0 }
        let n = buf.withUnsafeMutableBytes { p in read(fd, p.baseAddress! + offset, Swift.min(count, p.count - offset)) }
        if n < 0 { throw csIOError(Name, "Read failed") }
        return n
    }
    override func Write(_ buf: [UInt8], _ offset: Int, _ count: Int) throws {
        if fd < 0 { throw IOException("Stream closed") }
        var off = offset
        let end = offset + count
        while off < end {
            let n = buf.withUnsafeBytes { p in write(fd, p.baseAddress! + off, end - off) }
            if n <= 0 { throw csIOError(Name, "Write failed") }
            off += n
        }
    }
    override var Length: Int {
        var st = stat()
        return fd >= 0 && fstat(fd, &st) == 0 ? Int(st.st_size) : 0
    }
    override var Position: Int {
        get { return fd >= 0 ? Int(lseek(fd, 0, SEEK_CUR)) : 0 }
        set { if fd >= 0 { lseek(fd, off_t(newValue), SEEK_SET) } }
    }
    @discardableResult override func Seek(_ offset: Int, _ origin: SeekOrigin) -> Int {
        if fd < 0 { return 0 }
        let w: Int32 = origin == .Begin ? SEEK_SET : (origin == .Current ? SEEK_CUR : SEEK_END)
        return Int(lseek(fd, off_t(offset), w))
    }
    override func Flush() { if fd >= 0 { fsync(fd) } }
    override func Close() { if fd >= 0 { close(fd); fd = -1 } }
}

final class StreamReader: IDisposable {
    let BaseStream: Stream
    private var buf: [UInt8] = []
    private var pos = 0
    private var eof = false
    init(_ s: Stream) { BaseStream = s }
    init(_ s: Stream, _ e: Encoding) { BaseStream = s }
    convenience init(_ path: String) throws { self.init(try FileStream(path, .Open, .Read, .ReadWrite)) }
    convenience init(_ path: String, _ e: Encoding) throws { try self.init(path) }
    private func fill() throws -> Bool {
        if eof { return false }
        if pos > 0 && pos >= buf.count { buf.removeAll(keepingCapacity: true); pos = 0 }
        var tmp = [UInt8](repeating: 0, count: 4096)
        let n = try BaseStream.Read(&tmp, 0, tmp.count)
        if n <= 0 { eof = true; return false }
        buf.append(contentsOf: tmp[0..<n])
        return true
    }
    /// nil at end of stream. Splits on \n, \r\n or \r.
    func ReadLine() throws -> String? {
        while true {
            var i = pos
            while i < buf.count {
                let b = buf[i]
                if b == 10 || b == 13 {
                    if b == 13 && i + 1 >= buf.count && !eof { break }   // need to see if \n follows
                    let line = String(decoding: buf[pos..<i], as: UTF8.self)
                    pos = i + 1
                    if b == 13 && pos < buf.count && buf[pos] == 10 { pos += 1 }
                    if pos == 1 && line.hasPrefix("\u{FEFF}") { return String(line.dropFirst()) }
                    return line
                }
                i += 1
            }
            if !(try fill()) {
                if pos >= buf.count { return nil }
                let line = String(decoding: buf[pos..<buf.count], as: UTF8.self)
                pos = buf.count
                if line.hasSuffix("\r") { return String(line.dropLast()) }
                return line
            }
        }
    }
    func ReadToEnd() throws -> String {
        while try fill() {}
        let s = String(decoding: buf[pos..<buf.count], as: UTF8.self)
        pos = buf.count
        return s
    }
    var EndOfStream: Bool { if pos < buf.count { return false }; return !((try? fill()) ?? false) }
    func Close() { BaseStream.Close() }
    func Dispose() { Close() }
}

final class StreamWriter: IDisposable {
    let BaseStream: Stream
    var AutoFlush = false
    var NewLine = "\n"
    init(_ s: Stream) { BaseStream = s }
    init(_ s: Stream, _ e: Encoding) { BaseStream = s }
    convenience init(_ path: String) throws { self.init(try FileStream(path, .Create, .Write, .Read)) }
    convenience init(_ path: String, _ append: Bool) throws { self.init(try FileStream(path, append ? .Append : .Create, .Write, .Read)) }
    func Write(_ s: String?) throws { let b = Array((s ?? "").utf8); try BaseStream.Write(b, 0, b.count); if AutoFlush { BaseStream.Flush() } }
    func WriteLine(_ s: String?) throws { try Write((s ?? "") + NewLine) }
    func WriteLine() throws { try Write(NewLine) }
    func Flush() { BaseStream.Flush() }
    func Close() { BaseStream.Close() }
    func Dispose() { Close() }
}

// MARK: - Regex (System.Text.RegularExpressions)

struct RegexOptions: OptionSet {
    let rawValue: Int
    static let None = RegexOptions([])
    static let IgnoreCase = RegexOptions(rawValue: 1)
    static let Multiline = RegexOptions(rawValue: 2)
    static let ExplicitCapture = RegexOptions(rawValue: 4)
    static let Compiled = RegexOptions(rawValue: 8)
    static let Singleline = RegexOptions(rawValue: 16)
    static let IgnorePatternWhitespace = RegexOptions(rawValue: 32)
    static let RightToLeft = RegexOptions(rawValue: 64)
    static let ECMAScript = RegexOptions(rawValue: 256)
    static let CultureInvariant = RegexOptions(rawValue: 512)
}

final class RegexGroup {
    let Success: Bool
    let Value: String
    let Index: Int
    let Length: Int
    init(_ success: Bool, _ value: String, _ index: Int, _ length: Int) { Success = success; Value = value; Index = index; Length = length }
    func ToString() -> String { return Value }
}
typealias Group = RegexGroup

final class GroupCollection: Sequence {
    let groups: [RegexGroup]
    let named: [String: RegexGroup]
    init(_ g: [RegexGroup], _ named: [String: RegexGroup]) { groups = g; self.named = named }
    var Count: Int { return groups.count }
    subscript(_ i: Int) -> RegexGroup { return i >= 0 && i < groups.count ? groups[i] : RegexGroup(false, "", 0, 0) }
    subscript(_ name: String) -> RegexGroup { if let i = Int(name) { return self[i] }; return named[name] ?? RegexGroup(false, "", 0, 0) }
    func makeIterator() -> IndexingIterator<[RegexGroup]> { return groups.makeIterator() }
}

final class RegexMatch {
    let Success: Bool
    let Value: String
    let Index: Int
    let Length: Int
    let Groups: GroupCollection
    private let regex: Regex?
    private let input: String
    init(_ r: NSTextCheckingResult?, _ input: String, _ regex: Regex?) {
        self.input = input
        self.regex = regex
        guard let r = r else { Success = false; Value = ""; Index = 0; Length = 0; Groups = GroupCollection([RegexGroup(false, "", 0, 0)], [:]); return }
        let ns = input as NSString
        var gs: [RegexGroup] = []
        for i in 0..<r.numberOfRanges {
            let rg = r.range(at: i)
            if rg.location == NSNotFound { gs.append(RegexGroup(false, "", 0, 0)) }
            else { gs.append(RegexGroup(true, ns.substring(with: rg), rg.location, rg.length)) }
        }
        Success = true
        Value = gs[0].Value; Index = gs[0].Index; Length = gs[0].Length
        var named: [String: RegexGroup] = [:]
        if let rx = regex {
            for n in rx.groupNames {
                let rg = r.range(withName: n)
                named[n] = rg.location == NSNotFound ? RegexGroup(false, "", 0, 0) : RegexGroup(true, ns.substring(with: rg), rg.location, rg.length)
            }
        }
        Groups = GroupCollection(gs, named)
    }
    static let Empty = RegexMatch(nil, "", nil)
    func NextMatch() -> RegexMatch {
        guard Success, let rx = regex else { return RegexMatch.Empty }
        return rx.Match(input, Length == 0 ? Index + 1 : Index + Length)
    }
    func ToString() -> String { return Value }
}
typealias Match = RegexMatch
typealias MatchCollection = [RegexMatch]

final class Regex {
    let ns: NSRegularExpression
    let pattern: String
    fileprivate var groupNames: [String] = []
    init(_ pattern: String) { self.pattern = pattern; ns = Regex.make(pattern, .None); groupNames = Regex.names(pattern) }
    init(_ pattern: String, _ opts: RegexOptions) { self.pattern = pattern; ns = Regex.make(pattern, opts); groupNames = Regex.names(pattern) }
    private static func make(_ p: String, _ o: RegexOptions) -> NSRegularExpression {
        var opts: NSRegularExpression.Options = []
        if o.contains(.IgnoreCase) { opts.insert(.caseInsensitive) }
        if o.contains(.Multiline) { opts.insert(.anchorsMatchLines) }
        if o.contains(.Singleline) { opts.insert(.dotMatchesLineSeparators) }
        if o.contains(.IgnorePatternWhitespace) { opts.insert(.allowCommentsAndWhitespace) }
        if o.contains(.ExplicitCapture) { opts.insert(.useUnixLineSeparators) }
        if let r = try? NSRegularExpression(pattern: p, options: opts) { return r }
        // .NET named groups (?<name>…) are ICU-compatible; anything else invalid → never matches.
        return try! NSRegularExpression(pattern: "(?!)", options: [])
    }
    private static func names(_ p: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: "\\(\\?<([A-Za-z][A-Za-z0-9]*)>", options: []) else { return [] }
        let s = p as NSString
        return rx.matches(in: p, options: [], range: NSRange(location: 0, length: s.length)).map { s.substring(with: $0.range(at: 1)) }
    }
    func Match(_ input: String?) -> RegexMatch { return Match(input, 0) }
    func Match(_ input: String?, _ startat: Int) -> RegexMatch {
        let s = input ?? ""
        let len = (s as NSString).length
        if startat > len { return RegexMatch.Empty }
        let r = ns.firstMatch(in: s, options: [], range: NSRange(location: startat, length: len - startat))
        return RegexMatch(r, s, self)
    }
    func IsMatch(_ input: String?) -> Bool {
        let s = input ?? ""
        return ns.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    func Matches(_ input: String?) -> [RegexMatch] {
        let s = input ?? ""
        return ns.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)).map { RegexMatch($0, s, self) }
    }
    /// .NET replacement syntax ($1, ${name}, $$, $0) → ICU template.
    private static func template(_ r: String) -> String {
        var out = ""
        let cs = Array(r)
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c == "\\" { out += "\\\\"; i += 1; continue }
            if c == "$" && i + 1 < cs.count {
                if cs[i + 1] == "$" { out += "\\$"; i += 2; continue }
                if cs[i + 1] == "{" , let close = cs[(i + 2)...].firstIndex(of: "}") {
                    let name = String(cs[(i + 2)..<close])
                    out += Int(name) != nil ? "$" + name : "${" + name + "}"
                    i = close + 1; continue
                }
                if cs[i + 1].isNumber { out.append("$"); i += 1; continue }
                out += "\\$"; i += 1; continue
            }
            out.append(c); i += 1
        }
        return out
    }
    func Replace(_ input: String?, _ replacement: String) -> String {
        let s = input ?? ""
        return ns.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: Regex.template(replacement))
    }
    func Replace(_ input: String?, _ evaluator: (RegexMatch) -> String) -> String {
        let s = input ?? ""
        let nsS = s as NSString
        var out = ""
        var last = 0
        for m in ns.matches(in: s, options: [], range: NSRange(location: 0, length: nsS.length)) {
            out += nsS.substring(with: NSRange(location: last, length: m.range.location - last))
            out += evaluator(RegexMatch(m, s, self))
            last = m.range.location + m.range.length
        }
        out += nsS.substring(from: last)
        return out
    }
    func Split(_ input: String?) -> [String] {
        let s = input ?? ""
        let nsS = s as NSString
        var out: [String] = []
        var last = 0
        for m in ns.matches(in: s, options: [], range: NSRange(location: 0, length: nsS.length)) {
            out.append(nsS.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(nsS.substring(from: last))
        return out
    }
    static func IsMatch(_ input: String?, _ pattern: String) -> Bool { return Regex(pattern).IsMatch(input) }
    static func IsMatch(_ input: String?, _ pattern: String, _ o: RegexOptions) -> Bool { return Regex(pattern, o).IsMatch(input) }
    static func Match(_ input: String?, _ pattern: String) -> RegexMatch { return Regex(pattern).Match(input) }
    static func Match(_ input: String?, _ pattern: String, _ o: RegexOptions) -> RegexMatch { return Regex(pattern, o).Match(input) }
    static func Matches(_ input: String?, _ pattern: String) -> [RegexMatch] { return Regex(pattern).Matches(input) }
    static func Replace(_ input: String?, _ pattern: String, _ replacement: String) -> String { return Regex(pattern).Replace(input, replacement) }
    static func Replace(_ input: String?, _ pattern: String, _ replacement: String, _ o: RegexOptions) -> String { return Regex(pattern, o).Replace(input, replacement) }
    static func Split(_ input: String?, _ pattern: String) -> [String] { return Regex(pattern).Split(input) }
    static func Escape(_ s: String) -> String { return NSRegularExpression.escapedPattern(for: s) }
}

// MARK: - JSON (System.Web.Script.Serialization.JavaScriptSerializer)

/// DeserializeObject: objects → Dict<String, Any>, arrays → [Any], strings → String, true/false → Bool,
/// integers → Int, other numbers → Double, null → NSNull (so `as? String` yields nil like C#'s null).
final class JavaScriptSerializer {
    var MaxJsonLength = Int.max
    var RecursionLimit = 100
    init() {}
    func DeserializeObject(_ s: String?) throws -> Any? {
        guard let s = s, let data = s.data(using: .utf8) else { return nil }
        let o = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JavaScriptSerializer.convert(o)
    }
    static func convert(_ o: Any) -> Any {
        if let d = o as? NSDictionary {
            let out = Dict<String, Any>()
            for (k, v) in d { out[(k as? String) ?? "\(k)"] = convert(v) }
            return out
        }
        if let a = o as? NSArray { return a.map { convert($0) } }
        if let s = o as? String { return s }
        if let n = o as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            if CFNumberIsFloatType(n) {
                let d = n.doubleValue
                return d
            }
            return n.intValue
        }
        if o is NSNull { return NSNull() }
        return o
    }
    func Serialize(_ o: Any?) -> String {
        var out = ""
        JavaScriptSerializer.write(o, &out)
        return out
    }
    private static func esc(_ s: String, _ out: inout String) {
        out.append("\"")
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "<", ">", "&", "'":
                out += String(format: "\\u%04x", u.value)
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out.append("\"")
    }
    private static func write(_ o: Any?, _ out: inout String) {
        guard let o = o, !(o is NSNull) else { out += "null"; return }
        if let s = o as? String { esc(s, &out); return }
        if let b = o as? Bool { out += b ? "true" : "false"; return }
        if let i = o as? Int { out += String(i); return }
        if let d = o as? Double { out += d.isFinite ? d.ToString() : "null"; return }
        if let d = o as? Dict<String, Any> {
            out += "{"; var first = true
            for kv in d { if !first { out += "," }; first = false; esc(kv.Key, &out); out += ":"; write(kv.Value, &out) }
            out += "}"; return
        }
        if let d = o as? Dict<String, String> {
            out += "{"; var first = true
            for kv in d { if !first { out += "," }; first = false; esc(kv.Key, &out); out += ":"; esc(kv.Value, &out) }
            out += "}"; return
        }
        if let d = o as? [String: Any] {
            out += "{"; var first = true
            for (k, v) in d.sorted(by: { $0.key < $1.key }) { if !first { out += "," }; first = false; esc(k, &out); out += ":"; write(v, &out) }
            out += "}"; return
        }
        if let l = o as? List<Any> { write(l.items, &out); return }
        if let l = o as? List<String> { write(l.items, &out); return }
        if let a = o as? [Any] {
            out += "["; var first = true
            for v in a { if !first { out += "," }; first = false; write(v, &out) }
            out += "]"; return
        }
        esc("\(o)", &out)
    }
}

// MARK: - Uri

enum UriKind { case RelativeOrAbsolute, Absolute, Relative }

final class Uri: CustomStringConvertible {
    static let UriSchemeHttp = "http"
    static let UriSchemeHttps = "https"
    static let UriSchemeFile = "file"
    static let UriSchemeMailto = "mailto"
    static let UriSchemeFtp = "ftp"
    let url: URL
    let OriginalString: String
    /// File paths ("/Users/…") become file:// URIs. Invalid input yields an empty "about:blank"-like Uri
    /// (C# would throw UriFormatException — check with Uri.TryCreate first if it matters).
    init(_ s: String) {
        OriginalString = s
        url = Uri.parse(s, .RelativeOrAbsolute) ?? URL(string: "about:blank")!
    }
    private init(_ u: URL, _ orig: String) { url = u; OriginalString = orig }
    private static func parse(_ s: String, _ kind: UriKind) -> URL? {
        let t = s.Trim()
        if t.isEmpty { return nil }
        if t.hasPrefix("/") || t.hasPrefix("~/") {
            if kind == .Relative { return nil }
            return URL(fileURLWithPath: (t as NSString).expandingTildeInPath)
        }
        var u = URL(string: t)
        if u == nil, let enc = t.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "#%"))) { u = URL(string: enc) }
        guard let url = u else { return nil }
        let hasScheme = url.scheme != nil && !(url.scheme!.isEmpty)
        if kind == .Absolute && !hasScheme { return nil }
        if kind == .Relative && hasScheme { return nil }
        if hasScheme, let sc = url.scheme?.lowercased(), (sc == "http" || sc == "https" || sc == "ftp"), (url.host ?? "").isEmpty { return nil }
        return url
    }
    @discardableResult static func TryCreate(_ s: String?, _ kind: UriKind, _ result: inout Uri?) -> Bool {
        guard let s = s, let u = parse(s, kind) else { result = nil; return false }
        result = Uri(u, s); return true
    }
    static func IsWellFormedUriString(_ s: String?, _ kind: UriKind) -> Bool { var u: Uri? = nil; return TryCreate(s, kind, &u) }
    static func EscapeDataString(_ s: String) -> String { return s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s }
    static func UnescapeDataString(_ s: String) -> String { return s.removingPercentEncoding ?? s }
    var Scheme: String { return (url.scheme ?? "").lowercased() }
    var Host: String { return url.host ?? "" }
    var Port: Int { if let p = url.port { return p }; switch Scheme { case "http": return 80; case "https": return 443; case "ftp": return 21; default: return -1 } }
    var IsFile: Bool { return Scheme == "file" }
    var IsAbsoluteUri: Bool { return url.scheme != nil }
    var LocalPath: String { return IsFile ? url.path : (url.path.removingPercentEncoding ?? url.path) }
    var AbsolutePath: String { let p = url.path; return p.isEmpty ? "/" : (url.absoluteString.contains(p) ? p : (p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p)) }
    var Query: String { if let q = url.query { return "?" + q }; return "" }
    var Fragment: String { if let f = url.fragment { return "#" + f }; return "" }
    var Authority: String { let p = url.port; return Host + (p != nil ? ":\(p!)" : "") }
    var AbsoluteUri: String {
        var s = url.absoluteString
        // .NET adds the root slash: http://host → http://host/
        if (Scheme == "http" || Scheme == "https" || Scheme == "ftp") && url.path.isEmpty {
            if let q = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s.insert("/", at: q) } else { s += "/" }
        }
        return s
    }
    func ToString() -> String { return IsFile ? url.absoluteString : (url.absoluteString.removingPercentEncoding ?? url.absoluteString) }
    var description: String { return ToString() }
}

// MARK: - Threading

/// System.Threading.Thread: `let th = Thread(PipeLoop); th.IsBackground = true; th.Start()`.
final class Thread {
    private let body: () -> Void
    var IsBackground = false
    var Name: String? = nil
    private(set) var IsAlive = false
    private let done = DispatchSemaphore(value: 0)
    init(_ body: @escaping () -> Void) { self.body = body }
    func Start() {
        IsAlive = true
        let t = Foundation.Thread { [self] in
            self.body()
            self.IsAlive = false
            self.done.signal()
        }
        t.stackSize = 8 << 20
        if let n = Name { t.name = n }
        t.start()
    }
    func Join() { done.wait(); done.signal() }
    @discardableResult func Join(_ ms: Int) -> Bool {
        let r = done.wait(timeout: .now() + .milliseconds(ms)) == .success
        if r { done.signal() }
        return r
    }
    func Abort() {}
    static func Sleep(_ ms: Int) { if ms > 0 { usleep(useconds_t(Swift.min(ms, 4_000_000) * 1000)) } }
    static func Sleep(_ t: TimeSpan) { Sleep(Int(t.TotalMilliseconds)) }
    static var IsMainThread: Bool { return Foundation.Thread.isMainThread }
}

enum ThreadPool {
    @discardableResult static func QueueUserWorkItem(_ f: @escaping () -> Void) -> Bool {
        DispatchQueue.global(qos: .utility).async { f() }
        return true
    }
    @discardableResult static func QueueUserWorkItem(_ f: @escaping (Any?) -> Void) -> Bool {
        DispatchQueue.global(qos: .utility).async { f(nil) }
        return true
    }
}

/// `lock (o) { … }` → `lock(o) { … }` (recursive, like Monitor).
@discardableResult @inline(__always)
func lock<R>(_ o: AnyObject, _ body: () throws -> R) rethrows -> R {
    objc_sync_enter(o)
    defer { objc_sync_exit(o) }
    return try body()
}

enum Monitor {
    static func Enter(_ o: AnyObject) { objc_sync_enter(o) }
    static func Exit(_ o: AnyObject) { objc_sync_exit(o) }
}

enum Interlocked {
    private static let l = NSLock()
    @discardableResult static func Increment(_ v: inout Int) -> Int { l.lock(); defer { l.unlock() }; v += 1; return v }
    @discardableResult static func Decrement(_ v: inout Int) -> Int { l.lock(); defer { l.unlock() }; v -= 1; return v }
    @discardableResult static func Add(_ v: inout Int, _ d: Int) -> Int { l.lock(); defer { l.unlock() }; v += d; return v }
    @discardableResult static func Exchange(_ v: inout Int, _ n: Int) -> Int { l.lock(); defer { l.unlock() }; let o = v; v = n; return o }
    @discardableResult static func CompareExchange(_ v: inout Int, _ n: Int, _ cmp: Int) -> Int { l.lock(); defer { l.unlock() }; let o = v; if o == cmp { v = n }; return o }
}

/// Named system mutex (single-instance guard) via flock on a file in the per-user temp dir.
/// Held until process exit (Swift may free locals early, so we keep it alive in a static list).
final class Mutex: IDisposable {
    private static var held: [Mutex] = []
    private var fd: Int32 = -1
    private(set) var owned = false
    init(_ initiallyOwned: Bool, _ name: String, _ createdNew: inout Bool) {
        let safe = name.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" }
        let path = Path.Combine(Path.GetTempPath(), "deskpals-mutex-" + String(safe) + ".lock")
        fd = open(path, O_RDWR | O_CREAT, 0o600)
        if fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0 { owned = true; createdNew = true }
        else { createdNew = false }
        Mutex.held.append(self)
    }
    convenience init(_ initiallyOwned: Bool, _ name: String) { var c = false; self.init(initiallyOwned, name, &c) }
    func ReleaseMutex() { if owned && fd >= 0 { flock(fd, LOCK_UN); owned = false } }
    @discardableResult func WaitOne() -> Bool { if !owned && fd >= 0 { owned = flock(fd, LOCK_EX) == 0 }; return owned }
    @discardableResult func WaitOne(_ ms: Int) -> Bool { if !owned && fd >= 0 { owned = flock(fd, LOCK_EX | LOCK_NB) == 0 }; return owned }
    func Dispose() {}
    func Close() {}
}

// MARK: - Process

final class ProcessStartInfo {
    var FileName: String
    var Arguments: String
    var UseShellExecute = true
    var CreateNoWindow = false
    var RedirectStandardOutput = false
    var RedirectStandardError = false
    var WorkingDirectory = ""
    var Verb = ""
    init() { FileName = ""; Arguments = "" }
    init(_ fileName: String) { FileName = fileName; Arguments = "" }
    init(_ fileName: String, _ args: String) { FileName = fileName; Arguments = args }
}

/// System.Diagnostics.Process subset (names via libproc; ProcessName has no extension, matched case-insensitively).
final class Process {
    let Id: Int
    private var _name: String?
    private var task: Foundation.Process?
    init(_ pid: Int) { Id = pid }
    var ProcessName: String {
        if let n = _name { return n }
        var buf = [CChar](repeating: 0, count: 1024)
        let r = proc_name(Int32(Id), &buf, UInt32(buf.count))
        let n = r > 0 ? String(cString: buf) : ""
        _name = n
        return n
    }
    /// CPU time used (user + system). Zero when not permitted.
    var TotalProcessorTime: TimeSpan {
        var ti = proc_taskinfo()
        let sz = Int32(MemoryLayout<proc_taskinfo>.size)
        if proc_pidinfo(Int32(Id), PROC_PIDTASKINFO, 0, &ti, sz) != sz { return TimeSpan.Zero }
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let ns = (UInt64(ti.pti_total_user) + UInt64(ti.pti_total_system)) * UInt64(tb.numer) / UInt64(Swift.max(1, tb.denom))
        return TimeSpan(Int(ns / 100))
    }
    var HasExited: Bool {
        if let t = task { return !t.isRunning }
        return kill(pid_t(Id), 0) != 0 && errno == ESRCH
    }
    var MainWindowHandle: IntPtr { return 0 }
    var MainWindowTitle: String { return "" }
    var ExitCode: Int { return Int(task?.terminationStatus ?? 0) }
    func Kill() { if let t = task { t.terminate() } else { _ = Darwin.kill(pid_t(Id), SIGTERM) } }
    func WaitForExit() { task?.waitUntilExit() }
    func Dispose() {}
    func Refresh() { _name = nil }

    private static func allPids() -> [Int32] {
        var n = proc_listallpids(nil, 0)
        if n <= 0 { return [] }
        n += 64
        var pids = [Int32](repeating: 0, count: Int(n))
        let got = proc_listallpids(&pids, n * Int32(MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(Swift.max(0, got)))).filter { $0 > 0 }
    }
    static func GetProcesses() -> [Process] { return allPids().map { Process(Int($0)) } }
    static func GetProcessesByName(_ name: String) -> [Process] {
        let want = name.lowercased()
        return GetProcesses().filter { $0.ProcessName.lowercased() == want }
    }
    static func GetProcessById(_ pid: Int) -> Process { return Process(pid) }
    static func GetCurrentProcess() -> Process { return Process(Int(getpid())) }
    @discardableResult static func Start(_ fileName: String) -> Process? { return Start(ProcessStartInfo(fileName)) }
    @discardableResult static func Start(_ fileName: String, _ args: String) -> Process? { return Start(ProcessStartInfo(fileName, args)) }
    /// UseShellExecute → NSWorkspace open (URLs, files, apps); otherwise runs the executable.
    @discardableResult static func Start(_ psi: ProcessStartInfo) -> Process? {
        let f = psi.FileName
        if psi.UseShellExecute {
            let url: URL?
            if f.hasPrefix("/") || f.hasPrefix("~") { url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath) }
            else { url = URL(string: f) ?? URL(string: f.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") }
            guard let u = url else { return nil }
            if Foundation.Thread.isMainThread { NSWorkspace.shared.open(u) }
            else { DispatchQueue.main.async { NSWorkspace.shared.open(u) } }
            return nil
        }
        let t = Foundation.Process()
        t.executableURL = URL(fileURLWithPath: f)
        t.arguments = psi.Arguments.isEmpty ? [] : psi.Arguments.components(separatedBy: " ").filter { !$0.isEmpty }
        if !psi.WorkingDirectory.isEmpty { t.currentDirectoryURL = URL(fileURLWithPath: psi.WorkingDirectory) }
        do { try t.run() } catch { return nil }
        let p = Process(Int(t.processIdentifier))
        p.task = t
        return p
    }
}

enum Console {
    static func WriteLine(_ s: String?) { print(s ?? "") }
    static func WriteLine() { print("") }
    static func Write(_ s: String?) { print(s ?? "", terminator: "") }
}

enum Debug {
    static func WriteLine(_ s: String?) {}
    static func Assert(_ c: Bool) {}
}

enum GC {
    static func Collect() {}
    static func KeepAlive(_ o: Any?) {}
}
