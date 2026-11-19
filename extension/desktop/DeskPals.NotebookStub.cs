// Desk Pals：小本子要用、但由 work-sources 分支（工作功能、設定視窗）提供的兩個方法——這裡先暫代。
// work-sources 併進來時：把這個檔刪掉，改用那邊真的 OpenWorkSettings()／WorkSourceOn()（簽名照這裡，見 v011 SPEC 2b）。
namespace DeskPals
{
    using System;

    partial class World
    {
        // 小本子的「來源」按鈕、空白頁的「接上」：打開工作設定（Jira、GitLab、GitHub、CI、行事曆）
        public void OpenWorkSettings()
        {
            App.LogAlways("notebook: OpenWorkSettings (stub)");
            NbSay("工作設定還在做，快好了");
        }

        // 空白頁那張清單：這個來源接上了沒（claude｜school｜calendar｜github｜gitlab｜jira）
        public bool WorkSourceOn(string key)
        {
            if (key == "claude") return true;   // Claude Code／Codex：讀本機紀錄，一直都在
            if (key == "school") { if (!studyLoaded) LoadStudy(); return haveSchool; }
            return false;
        }
    }
}
