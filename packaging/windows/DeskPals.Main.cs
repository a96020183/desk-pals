// 公仔櫃 Desk Pals：獨立版 DeskPals.exe 的進入點（不用 VS Code）。
// 只在 packaging/windows/build.ps1 編 exe 時加進來；VS Code 擴充套件的 desk-pals.ps1（Add-Type）用不到這個檔。
// 刻意寫成 C# 5（Windows 內建的 csc.exe），使用者電腦上不用另外裝任何東西。
//
// DeskPals.exe [--pipe <名稱>] [--pet <id>] [--lineup <櫃>]   開起來（已經開著：叫它出來打招呼，然後結束）
// DeskPals.exe --quit                                          叫開著的公仔櫃收工（安裝／解除安裝／升級用），等它真的關掉
// DeskPals.exe --replace [...]                                 先叫開著的那個收工（例如 VS Code 擴充套件編的那份），再自己開起來
// 預設 pipe＝desk-pals-<帳號>，資料夾 %LOCALAPPDATA%\DeskPals、紀錄 %TEMP%\desk-pals.log —— 跟 VS Code 擴充套件同一套，兩邊互通。
using System;
using System.IO;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace DeskPals
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            string pipe = DefaultPipe(), pet = "", lineup = "", mode = "run";
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                string next = i + 1 < args.Length ? args[i + 1] : "";
                if (a == "--pipe" && Safe(next)) { pipe = next; i++; }
                else if (a == "--pet" && Safe(next)) { pet = next; i++; }
                else if (a == "--lineup" && Safe(next)) { lineup = next; i++; }
                else if (a == "--quit") mode = "quit";
                else if (a == "--replace") mode = "replace";
                else if (a == "--version") { Console.WriteLine(Version()); return 0; }
            }
            App.Log("exe " + Version() + " " + mode + " pipe=" + pipe);

            if (mode == "quit") return QuitRunning(pipe, 15000) ? 0 : 1;
            if (mode == "replace") QuitRunning(pipe, 15000);
            else if (Send(pipe, "act show")) return 0;   // 已經開著：叫它出來，這個就不用開了

            Packaged.Setup(pipe);
            App.Run(pipe, pet, lineup);
            return 0;
        }

        static bool Safe(string s) { return s != "" && Regex.IsMatch(s, "^[A-Za-z0-9_.-]+$"); }

        // 跟 VS Code 擴充套件、claude-hook.js 同一個名字：desk-pals-<帳號（非英數字換成 _）>
        public static string DefaultPipe()
        {
            string u = Environment.UserName;
            if (string.IsNullOrEmpty(u)) u = "me";
            return "desk-pals-" + Regex.Replace(u, "[^A-Za-z0-9_.-]", "_");
        }

        public static string Version()
        {
            object[] v = Assembly.GetExecutingAssembly().GetCustomAttributes(typeof(AssemblyInformationalVersionAttribute), false);
            return v.Length > 0 ? ((AssemblyInformationalVersionAttribute)v[0]).InformationalVersion : "dev";
        }

        // 送一行給開著的公仔櫃；沒開（或 0.8 秒內接不上）回 false
        static bool Send(string pipe, string line)
        {
            try
            {
                using (NamedPipeClientStream c = new NamedPipeClientStream(".", pipe, PipeDirection.InOut))
                {
                    c.Connect(800);
                    byte[] b = new UTF8Encoding(false).GetBytes(line + "\n");
                    c.Write(b, 0, b.Length);
                    c.Flush();
                    Thread.Sleep(150);   // 讓對方讀完再關
                }
                return true;
            }
            catch { return false; }
        }

        // 單一執行個體的 Mutex（App.Run 用的同一個）還在＝還開著
        static bool Running(string pipe)
        {
            Mutex m;
            if (Mutex.TryOpenExisting("Local\\" + pipe, out m)) { m.Dispose(); return true; }
            return false;
        }

        // 叫它收工，等它真的關掉（安裝／升級前要先放掉 exe 檔）。true＝現在沒有在跑了
        static bool QuitRunning(string pipe, int timeoutMs)
        {
            DateTime end = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            bool sent = false;
            while (DateTime.UtcNow < end)
            {
                if (!Running(pipe)) { if (sent) App.Log("exe: previous instance gone"); return true; }
                if (!sent) sent = Send(pipe, "quit");   // 剛啟動、pipe 還沒好：下一圈再試
                Thread.Sleep(200);
            }
            App.Log("exe: previous instance did not quit");
            return !Running(pipe);
        }
    }

    // Microsoft Store（MSIX）版：開機啟動交給 StartupTask，所以把 VS Code 擴充套件的開機捷徑拿掉（不然開機會先跑到舊的那份）；
    // 再留一個 standalone.json 讓擴充套件知道「裝了獨立版」，它就不會自己編一份、也不會再建開機捷徑。
    // （安裝程式版的 standalone.json 由安裝程式寫、解除安裝時刪掉。）
    static class Packaged
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern int GetCurrentPackageFullName(ref int length, StringBuilder name);

        public static bool IsPackaged()
        {
            try
            {
                int len = 0;
                return GetCurrentPackageFullName(ref len, null) != 15700;   // APPMODEL_ERROR_NO_PACKAGE
            }
            catch { return false; }   // Windows 7／8.0 沒有這個 API
        }

        public static void Setup(string pipe)
        {
            if (App.Offscreen || !IsPackaged()) return;
            try
            {
                string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string alias = Path.Combine(local, "Microsoft\\WindowsApps\\DeskPals.exe");   // AppxManifest 的 AppExecutionAlias
                Directory.CreateDirectory(World.DataDir);
                File.WriteAllText(Path.Combine(World.DataDir, "standalone.json"),
                    "{\"kind\":\"msix\",\"exe\":\"" + alias.Replace("\\", "\\\\") + "\",\"version\":\"" + Program.Version() + "\"}", new UTF8Encoding(false));
                // Claude Code hooks 的設定指著 %LOCALAPPDATA%\DeskPals\claude-hook.js（安裝說明這樣寫）：放一份過去
                foreach (string f in new string[] { "claude-hook.js", "ci-watch.js" })
                {
                    string from = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, f), to = Path.Combine(World.DataDir, f);
                    if (File.Exists(from) && (!File.Exists(to) || File.ReadAllText(to) != File.ReadAllText(from))) File.Copy(from, to, true);
                }
                string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "公仔櫃 Desk Pals.lnk");
                if (File.Exists(lnk)) { File.Delete(lnk); App.Log("msix: removed startup shortcut (StartupTask takes over)"); }
            }
            catch (Exception ex) { App.Log("msix setup: " + ex.Message); }
        }
    }
}
