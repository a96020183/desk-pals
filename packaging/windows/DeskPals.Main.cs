// 公仔櫃 Desk Pals：獨立版 DeskPals.exe 的進入點（不用 VS Code）。
// 只在 packaging/windows/build.ps1 編 exe 時加進來；VS Code 擴充套件的 desk-pals.ps1（Add-Type）用不到這個檔。
// 刻意寫成 C# 5（Windows 內建的 csc.exe），使用者電腦上不用另外裝任何東西。
//
// DeskPals.exe [--pipe <名稱>] [--pet <id>] [--lineup <櫃>]   開起來（已經開著：叫它出來打招呼，然後結束）
// DeskPals.exe --quit                                          叫開著的公仔櫃收工（安裝／解除安裝／升級用），等它真的關掉
// DeskPals.exe --replace [...]                                 先叫開著的那個收工（例如 VS Code 擴充套件編的那份），再自己開起來
// DeskPals.exe --autostart <捷徑.lnk> [--pipe <名稱>]           開機捷徑改成指著這支 exe（VS Code 擴充套件用；已經是了就不動），不會開起來
// 預設 pipe＝desk-pals-<帳號>，資料夾 %LOCALAPPDATA%\DeskPals、紀錄 %TEMP%\desk-pals.log —— 跟 VS Code 擴充套件同一套，兩邊互通。
// （Microsoft Store 版的資料夾在 MSIX 裡會被虛擬化，見下面 Packaged 的說明。）
// build.ps1 編的時候參考 Windows 內建的 WinMetadata（Store 版的開機啟動 StartupTask）；找不到就定義 NO_WINRT，Store 版不顯示開機啟動的勾選。
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
            string pipe = DefaultPipe(), pet = "", lineup = "", mode = "run", lnk = "";
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                string next = i + 1 < args.Length ? args[i + 1] : "";
                if (a == "--pipe" && Safe(next)) { pipe = next; i++; }
                else if (a == "--pet" && Safe(next)) { pet = next; i++; }
                else if (a == "--lineup" && Safe(next)) { lineup = next; i++; }
                else if (a == "--quit") mode = "quit";
                else if (a == "--replace") mode = "replace";
                else if (a == "--autostart" && next.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase) && Path.IsPathRooted(next)) { mode = "autostart"; lnk = next; i++; }
                else if (a == "--version") { Console.WriteLine(Version()); return 0; }
            }
            App.Log("exe " + Version() + " " + mode + " pipe=" + pipe + " " + Thread.CurrentThread.GetApartmentState());   // STA：剪貼簿（分享短片）要

            if (mode == "quit") return QuitRunning(pipe, 15000) ? 0 : 1;
            if (mode == "autostart") return Autostart.Ensure(lnk, pipe) ? 0 : 1;
            if (mode == "replace") QuitRunning(pipe, 15000);
            else if (Send(pipe, "act show")) return 0;   // 已經開著：叫它出來，這個就不用開了

            Packaged.Setup(pipe);
            Stats.Platform = Packaged.IsPackaged() ? "win-msix" : (FromVsCode() ? "win-vscode" : "win-exe");   // 匿名回報的平台（公開版；DeskPals.Stats.cs）
            App.Run(pipe, pet, lineup);
            return 0;
        }

        static bool Safe(string s) { return s != "" && Regex.IsMatch(s, "^[A-Za-z0-9_.-]+$"); }

        // VS Code 擴充套件放的那支（%LOCALAPPDATA%\DeskPals\app\DeskPals.exe）
        static bool FromVsCode()
        {
            try
            {
                string dir = Path.GetDirectoryName(Path.GetFullPath(Assembly.GetExecutingAssembly().Location)).TrimEnd('\\');
                return dir.EndsWith("\\DeskPals\\app", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

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

    // VS Code 擴充套件附的 exe（放在 %LOCALAPPDATA%\DeskPals\app）：開機捷徑由 exe 自己建，擴充套件不用再叫 PowerShell。
    // 舊版擴充套件留下的捷徑（指著 powershell.exe ＋ desk-pals.ps1）同名，直接改成指著這支 exe；資料夾、資料都不動。
    // 用 Shell 的 IShellLinkW／IPersistFile（全程 Unicode）。不用 WScript.Shell：它存捷徑時走系統的 ANSI 字碼頁，
    // 英文 Windows（cp1252）上「公仔櫃 Desk Pals.lnk」這種中文檔名會存不了（舊版擴充套件用 PowerShell 建捷徑也是同一個問題）。
    static class Autostart
    {
        [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
        class ShellLink { }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
        interface IShellLinkW
        {
            void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
            void GetIDList(out IntPtr ppidl);
            void SetIDList(IntPtr pidl);
            void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
            void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
            void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
            void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
            void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
            void GetHotkey(out ushort pwHotkey);
            void SetHotkey(ushort wHotkey);
            void GetShowCmd(out int piShowCmd);
            void SetShowCmd(int iShowCmd);
            void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
            void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
            void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
            void Resolve(IntPtr hwnd, uint fFlags);
            void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
        }

        public static bool Ensure(string lnk, string pipe)
        {
            object o = null;
            try
            {
                string exe = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
                string args = "--pipe " + pipe;
                o = new ShellLink();
                IShellLinkW sl = (IShellLinkW)o;
                System.Runtime.InteropServices.ComTypes.IPersistFile pf = (System.Runtime.InteropServices.ComTypes.IPersistFile)o;
                if (File.Exists(lnk))
                {
                    string have = "", haveArgs = "";
                    try
                    {
                        pf.Load(lnk, 0);
                        StringBuilder sb = new StringBuilder(1024);
                        sl.GetPath(sb, sb.Capacity, IntPtr.Zero, 0x4);   // SLGP_RAWPATH
                        have = sb.ToString();
                        sb = new StringBuilder(1024);
                        sl.GetArguments(sb, sb.Capacity);
                        haveArgs = sb.ToString();
                    }
                    catch (Exception ex) { App.Log("autostart: could not read the old shortcut: " + Why(ex)); }
                    if (string.Equals(have, exe, StringComparison.OrdinalIgnoreCase) && haveArgs == args) return true;
                    App.Log("autostart: " + Path.GetFileName(have) + " -> " + exe);
                    Marshal.FinalReleaseComObject(o);
                    o = new ShellLink();   // 新的一個，不帶舊捷徑的其他設定（隱藏視窗、PowerShell 的圖示）
                    sl = (IShellLinkW)o;
                    pf = (System.Runtime.InteropServices.ComTypes.IPersistFile)o;
                }
                else App.Log("autostart: new " + exe);
                Directory.CreateDirectory(Path.GetDirectoryName(lnk));
                sl.SetPath(exe);
                sl.SetArguments(args);
                sl.SetWorkingDirectory(Path.GetDirectoryName(exe));
                sl.SetIconLocation(exe, 0);
                sl.SetDescription("公仔櫃 Desk Pals（整個螢幕的像素公仔）");
                pf.Save(lnk, true);
                if (!File.Exists(lnk)) { App.Log("autostart: saved but the shortcut is not there: " + lnk); return false; }
                return true;
            }
            catch (Exception ex) { App.Log("autostart: " + Why(ex)); return false; }
            finally { if (o != null) Marshal.FinalReleaseComObject(o); }
        }

        // 例外的真正原因（反射／COM 包了一層的話，最裡面那個）＋ HRESULT
        static string Why(Exception ex)
        {
            Exception b = ex.GetBaseException();
            string s = b.GetType().Name + " 0x" + Marshal.GetHRForException(b).ToString("X8") + ": " + b.Message;
            return b == ex ? s : s + " (via " + ex.GetType().Name + ")";
        }
    }

    // Microsoft Store（MSIX）版：
    // - 開機啟動交給 StartupTask（AppxManifest 預設開；第一次設定第二頁「開機時自動出現」看得到、可以不要，小屋選單也能開關）。
    //   「啟動」資料夾裡如果有自家的舊開機捷徑（指著 DeskPals.exe，或 powershell.exe＋desk-pals.ps1）就拿掉，並用泡泡告訴你；別人的捷徑不動。
    // - 沒有宣告 unvirtualizedResources（Store 很少核准）：%LOCALAPPDATA% 底下「新建」的檔案會被 Windows 轉到 Store 版自己的私人資料夾
    //   （解除安裝時一起清掉）；本來就存在的檔案（VS Code 擴充套件那份 %LOCALAPPDATA%\DeskPals 裡已經有的設定）讀得到、改了會直接改原檔。
    //   所以這裡寫的 standalone.json、claude-hook.js 通常只有 Store 版自己看得到 —— VS Code 擴充套件改看 Store 版的執行別名
    //   %LOCALAPPDATA%\Microsoft\WindowsApps\DeskPals.exe 來判斷「裝了 Store 版」（extension.js 的 standalone()），一樣只連過去、不另外開一份。
    //   Claude Code hooks 指著的 %LOCALAPPDATA%\DeskPals\claude-hook.js 要靠 VS Code 擴充套件放（Store 版只有它自己看得到這份）。
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

        static volatile int startup = -1;   // App.StartupState 的快取：-1 還不知道、0 關、1 開、2 在 Windows 設定裡被關掉

        public static void Setup(string pipe)
        {
            // 離屏測試：DESKPALS_FAKE_PACKAGED=1 假裝是 Store 版（只有開機啟動的勾選，什麼都不真的改）
            if (App.Offscreen && Environment.GetEnvironmentVariable("DESKPALS_FAKE_PACKAGED") == "1")
            {
                startup = 1;
                App.StartupState = delegate { return startup; };
                App.StartupEnable = delegate(bool on) { startup = on ? 1 : 0; App.Log("msix(fake): startup " + (on ? "on" : "off")); };
                return;
            }
            if (!IsPackaged()) return;   // 本機測試、安裝程式版都不是 packaged
#if !NO_WINRT
            App.StartupState = delegate { return startup; };
            App.StartupEnable = delegate(bool on) { ThreadPool.QueueUserWorkItem(delegate { StartupSet(on); }); };
            ThreadPool.QueueUserWorkItem(delegate { StartupRead(); });
#endif
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
                if (File.Exists(lnk))
                {
                    if (OurShortcut(lnk))
                    {
                        File.Delete(lnk);
                        App.Log("msix: removed our old startup shortcut (StartupTask takes over)");
                        App.StartNote = "我改用 Microsoft Store 版的開機啟動了，舊的開機捷徑已經拿掉（要關：小屋選單「開機時自動出現」）";
                    }
                    else App.Log("msix: startup shortcut is not ours, left alone");
                }
            }
            catch (Exception ex) { App.Log("msix setup: " + ex.Message); }
        }

        // 捷徑指著自家的嗎：DeskPals.exe（安裝程式版、VS Code 擴充套件放的那支），或 powershell.exe ＋ desk-pals.ps1（舊的 VS Code 擴充套件）
        static bool OurShortcut(string lnk)
        {
            try
            {
                Type t = Type.GetTypeFromProgID("WScript.Shell");
                object sh = Activator.CreateInstance(t);
                try
                {
                    object s = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { lnk });
                    Type st = s.GetType();
                    string target = (string)st.InvokeMember("TargetPath", BindingFlags.GetProperty, null, s, null) ?? "";
                    string args = (string)st.InvokeMember("Arguments", BindingFlags.GetProperty, null, s, null) ?? "";
                    Marshal.FinalReleaseComObject(s);
                    string exe = Path.GetFileName(target);
                    if (string.Equals(exe, "DeskPals.exe", StringComparison.OrdinalIgnoreCase)) return true;
                    return string.Equals(exe, "powershell.exe", StringComparison.OrdinalIgnoreCase) && args.IndexOf("desk-pals.ps1", StringComparison.OrdinalIgnoreCase) >= 0;
                }
                finally { Marshal.FinalReleaseComObject(sh); }
            }
            catch (Exception ex) { App.Log("msix: read shortcut " + ex.Message); return false; }
        }

#if !NO_WINRT
        // ---- StartupTask（WinRT，Windows 內建）：都在背景執行緒做，不卡畫面 ----
        static void StartupRead()
        {
            try { startup = Code(Task().State); App.Log("msix: startup state " + startup); }
            catch (Exception ex) { App.Log("msix: startup state " + ex.Message); }
        }
        static void StartupSet(bool on)
        {
            try
            {
                global::Windows.ApplicationModel.StartupTask t = Task();
                if (!on) t.Disable();
                else if (Code(t.State) == 0) Wait(t.RequestEnableAsync());
                startup = Code(t.State);
                App.Log("msix: startup " + (on ? "enable" : "disable") + " -> " + startup);
            }
            catch (Exception ex) { App.Log("msix: startup set " + ex.Message); }
        }
        static global::Windows.ApplicationModel.StartupTask Task() { return Wait(global::Windows.ApplicationModel.StartupTask.GetAsync("DeskPalsStartup")); }   // AppxManifest 的 TaskId
        static T Wait<T>(global::Windows.Foundation.IAsyncOperation<T> op)
        {
            for (int i = 0; i < 500 && op.Status == global::Windows.Foundation.AsyncStatus.Started; i++) Thread.Sleep(10);
            return op.GetResults();
        }
        static int Code(global::Windows.ApplicationModel.StartupTaskState s)
        {
            switch (s)
            {
                case global::Windows.ApplicationModel.StartupTaskState.Enabled:
                case global::Windows.ApplicationModel.StartupTaskState.EnabledByPolicy: return 1;
                case global::Windows.ApplicationModel.StartupTaskState.DisabledByUser:
                case global::Windows.ApplicationModel.StartupTaskState.DisabledByPolicy: return 2;
                default: return 0;
            }
        }
#endif
    }
}
