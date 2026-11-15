// 44_student.swift — student-first shortcuts for the existing focus, quiet and reminder tools.
import Foundation

extension World {
    // Student tools live under the existing pet/house helper menu. Keep actions small,
    // reversible and user-started; no automatic nagging or hidden schedule collection.
    func AddHelpers(_ items: ToolStripItemCollection) {
        if Student {
            items.Add(ToolStripLabel("學生小隊｜讀書、作業、休息"))
            let focus = ToolStripMenuItem("開啟讀書衝刺")
            focus.DropDownItems.Add("25 分鐘｜先開始一小段 🍅", nil) { self.StartFocus(25) }
            focus.DropDownItems.Add("50 分鐘｜寫報告／讀一章", nil) { self.StartFocus(50) }
            focus.DropDownItems.Add("90 分鐘｜考前長時段", nil) { self.StartFocus(90) }
            if focusOn {
                focus.DropDownItems.Add(ToolStripSeparator())
                focus.DropDownItems.Add("結束這段專注", nil) { self.StopFocus(false) }
            }
            items.Add(focus)

            let quiet = ToolStripMenuItem("幫我安靜一下")
            quiet.DropDownItems.Add("30 分鐘｜上課或短讀書", nil) { self.StartQuiet(30) }
            quiet.DropDownItems.Add("60 分鐘｜專心寫作業", nil) { self.StartQuiet(60) }
            quiet.DropDownItems.Add("120 分鐘｜考前／報告時段", nil) { self.StartQuiet(120) }
            if quietOn {
                quiet.DropDownItems.Add(ToolStripSeparator())
                quiet.DropDownItems.Add("關閉安靜模式", nil) { self.StopQuiet() }
            }
            items.Add(quiet)
            items.Add(ToolStripSeparator())
        }

        items.Add("提醒我上課／交作業…", nil) { self.ShowReminderForm() }
        AddReminderMenus(items)
    }
}
