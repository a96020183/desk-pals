// ================= 角色資料（Pal）=================
// 每個角色：id、名字、調色盤（白天／夜晚）、像素圖零件、台詞、移動風格、夜晚風格、球種、配件錨點。
// 像素圖是 12 格寬（也可以更寬，會置中）× 16 格高的字元格；'.' 是透明。
// 共用字元：k 外框、p 愛心粉、y 星星黃、w 白；配件用 S W Y P B（每個角色都會有）。
// C# 582–1571
import Foundation

final class Pal
{
    var Id: String! = nil, Name: String! = nil, Move: String! = nil, BallKind: String! = nil, NightStyle: String! = nil
    var NightBubble: Int = 0
    var Accent: Color = Color.Empty, Panel: Color = Color.Empty, Halo: Color = Color.Empty, HaloNight: Color = Color.Empty
    let Day = Dict<Character, Color>(), Night = Dict<Character, Color>()
    let Art = Dict<String, [String]>()
    let Lines = Dict<String, [String]>()
    var FaceRow: Int = 4                       // SLEEPY／HAPPY／DIZZY 這些臉蓋掉 FaceRow～FaceRow+2
    var EyeRow: Int = 5, EyeL: Int = 3, EyeR: Int = 8    // 眼珠跟著滑鼠（EyeRow < 0：不跟）
    var HatRow: Int = 0, HatCol: Int = 0, ScarfRow: Int = 8, GlassRow: Int = 4, BadgeRow: Int = 10, BadgeCol: Int = 5, BadgeFrom: Int = 107   // 107 = 'k'
    var SideRow: Int = 9                       // 紅包、蛋糕的高度
    var Speed: Double = 40                     // 走路速度（×k）
    var KeepAntenna: Bool = false              // 帽子戴上後把天線重畫在帽子上面（小波）
    var TopRows: Int = 0
    var NoGlasses: Bool = false                // 眼睛太開，眼鏡戴不上（史迪仔）                           // 頭頂超出 16 格框的列數（小波的天線）
    // <fan>
    // 天線寶寶一櫃（丁丁、迪西、拉拉）用的；經典一櫃的角色都是預設值
    var Tubby: Bool = false                    // 丁丁／迪西／拉拉（小波另外寫）
    var TummyRow: Double = 10.5                // 肚子電視的中心在第幾列
    var AntRows: Int = -1                      // 戴帽子時露在帽子上面的天線列數（-1＝TopRows-1，小波）
    var AntThrough: Bool = false               // 天線從帽子中間穿出來（不墊高；丁丁太高了）
    // </fan>
    var HeadTop: Int = -1                      // 頭頂外框那一列在 16 格框的第幾列
    var BodyTop: Int = 8                       // 身體第一列在 16 格框的第幾列
    //@@BODY Pal

    static func C(_ rgb: Int) -> Color { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }
    func Col(_ c: Character, _ day: Int, _ night: Int) { Day[c] = Pal.C(day); Night[c] = Pal.C(night) }
    func Say(_ key: String, _ lines: String...) { Lines[key] = lines }

    static var all: List<Pal>! = nil
    static var All: List<Pal> {
        if all == nil {
            let l = List<Pal>()
            // <fan>
            for x in [Spidey(), Po(), Stitch(), Hangyodon(), Tinky(), Dipsy(), LaaLaa()] { l.Add(x) }
            // </fan>
            l.AddRange(PikminPals())   //@fan
            l.AddRange(OrigPals())
            l.AddRange(CuPals())
            all = l
        }
        return all
    }
    static func Get(_ id: String!) -> Pal!
    {
        for p in All { if p.Id == id { return p } }
        return nil
    }

    // ---- 兩櫃：經典（Spidey、小波、史迪仔、人魚漢頓）／天線寶寶（丁丁、迪西、拉拉、小波；大格是小波）----
    static let Classic = "classic", Teletubbies = "teletubbies"   //@fan
    static let Fallback = Classic                      // 找不到的櫃子、還沒選過：回到這一櫃 //@fan
    // <public> static let Fallback = Original
    static func NormLineup(_ s: String!) -> String { let t = s == nil ? "" : s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); return t == Teletubbies || t == Pikmin || IsSquad(t) || (t == Mine && HasCustom()) ? t : Fallback }   //@fan
    // <public> static func NormLineup(_ s: String!) -> String { let t = s == nil ? "" : s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); return IsSquad(t) || (t == Mine && HasCustom()) ? t : Fallback }
    static func LineupIds(_ lineup: String!) -> [String]
    {
        if NormLineup(lineup) == Pikmin { return PikminIds }   // 皮克敏一櫃：大格是休息花（50_pikmin.swift）   //@fan
        if IsSquad(NormLineup(lineup)) { return SqLineupIds(NormLineup(lineup)) }   // 圖片公仔櫃（續命小隊、窩伴小世界：pals/lineups.txt；櫃子有空格就放你自己做的公仔）
        if NormLineup(lineup) == Mine { return MineIds() }                       // 我的櫃：自己做的公仔（53_custom.swift）
        return NormLineup(lineup) == Teletubbies ? ["tinky", "dipsy", "laalaa", "po"] : ["spidey", "po", "stitch", "hangyodon"]   //@fan
        // <public> return SqLineupIds(Original)
    }
    static func Lineup(_ lineup: String!) -> List<Pal>
    {
        let l = List<Pal>()
        for id in LineupIds(lineup) { if Get(id) != nil { l.Add(Get(id)) } }
        return l
    }
    // 這一櫃預設放在大格的（經典一櫃照用最久的那隻）
    static func LineupFav(_ lineup: String!) -> String! { let n = NormLineup(lineup); return n == Teletubbies ? "po" : (IsSquad(n) ? SqIds(n)[0] : nil) }   //@fan
    // <public> static func LineupFav(_ lineup: String!) -> String! { let n = NormLineup(lineup); return IsSquad(n) ? SqIds(n)[0] : nil }
    // 設定視窗、小屋「換一櫃」列出來的櫃子：圖片公仔櫃照 pals/lineups.txt（之後新增一櫃圖片公仔：加一個資料夾、lineups.txt 加一行）
    static var Lineups: [String] { var l: [String] = SqLineupList(); l.append(contentsOf: [Classic, Teletubbies, Pikmin]); return l }   //@fan
    // <public> static var Lineups: [String] { return SqLineupList() }
    static func LineupName(_ lineup: String) -> String { let n = NormLineup(lineup); return IsSquad(n) ? SqName(n) : (n == Teletubbies ? "天線寶寶一櫃" : (n == Pikmin ? "皮克敏一櫃" : (n == Mine ? "我的櫃" : "經典一櫃"))) }   //@fan
    // <public> static func LineupName(_ lineup: String) -> String { let n = NormLineup(lineup); return n == Mine ? "我的櫃" : SqName(n) }

    func Shared()
    {
        for d in [Day, Night]
        {
            d["S"] = Pal.C(0xE23B3B); d["W"] = Color.White; d["Y"] = Pal.C(0xF5C842); d["P"] = Pal.C(0xFF8FB0); d["B"] = Pal.C(0xB8D6FF)
            if !d.ContainsKey("p") { d["p"] = Pal.C(0xFF6F9C) }
            if !d.ContainsKey("y") { d["y"] = Pal.C(0xFFD84A) }
            if !d.ContainsKey("w") { d["w"] = Color.White }
            d["1"] = Pal.C(0xD9A55B); d["2"] = Pal.C(0xA8743A)   // 木頭（球棒、搖椅、烏克麗麗）
            d["3"] = Pal.C(0xF4F1EA)                          // 棒球白
            d["4"] = Pal.C(0xE03A3A)                          // 棒球縫線
            d["5"] = Pal.C(0xA0703F); d["6"] = Pal.C(0x6E4524)   // 手套皮革
            d["7"] = Pal.C(0x8E97B0); d["8"] = Pal.C(0xFFFFFF)   // 絲、閃光
        }
        if Lines.ContainsKey("talk") && !Lines.ContainsKey("talk_d") { Lines["talk_d"] = Lines["talk"] }
    }

    // 把幾段零件疊成一張圖（每段寬度不同時置中補齊）
    static func Stack(_ parts: [String]...) -> [String]
    {
        var rows: [String] = []
        var w = 0
        for p in parts { for r in p { w = max(w, r.utf16.count) } }
        for p in parts {
            for r in p
            {
                let n = r.utf16.count
                let l = (w - n) / 2
                rows.append(String(repeating: ".", count: l) + r + String(repeating: ".", count: w - n - l))
            }
        }
        return rows
    }

}
