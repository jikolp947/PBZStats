// PBZStatsHUD - Phantom Blade Zero death/difficulty HUD (standalone, no Python).
// A tiny layered/click-through window that follows the game window and renders
// the rows written by the UE4SS Lua mod (stats.txt) at the right-middle of it.
//
// Build (Windows built-in C# compiler, no SDK needed):
//   csc.exe /nologo /target:winexe /optimize+ /out:PBZStatsHUD.exe PBZStatsHUD.cs ^
//       /r:System.dll /r:System.Drawing.dll /r:System.Core.dll
//
// Usage:
//   PBZStatsHUD.exe             run the HUD
//   PBZStatsHUD.exe --install   create data dir + register auto start
//   PBZStatsHUD.exe --uninstall remove auto start
//   PBZStatsHUD.exe --quit      stop the running instance
//   PBZStatsHUD.exe --preview   show test rows even without the game

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace PBZStatsHud
{
    internal sealed class Config
    {
        public string ProcessName = "PBZ";
        public int PollMs = 250;
        public int MarginRight = 40;
        public int OffsetY = 0;
        public int FontSize = 26;
        public int LineGap = 8;
        public int PadX = 8;
        public int PadY = 6;
        public int Gap = 26;
        public string LabelColor = "#F2F2F2";
        public string ValueColor = "#E8C36A";
        public string ShadowColor = "#000000";
        public string Lang = "auto";          // auto | zh | en
        public string DataDir = "";           // empty -> auto
        public int StaleMs = 15000;
        // Boss names differ wildly in length between languages; clamp the value
        // column so a long name cannot run off the right edge or push the
        // anchor far from the margin.
        public int MaxValueWidth = 620;

        public static Config Load(string path)
        {
            Config c = new Config();
            try
            {
                if (!File.Exists(path)) return c;
                foreach (string raw in File.ReadAllLines(path, Encoding.UTF8))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    string k = line.Substring(0, eq).Trim().ToLowerInvariant();
                    string v = line.Substring(eq + 1).Trim();
                    if (v.Length == 0) continue;
                    try
                    {
                        switch (k)
                        {
                            case "process": c.ProcessName = v; break;
                            case "poll_ms": c.PollMs = int.Parse(v); break;
                            case "margin_right": c.MarginRight = int.Parse(v); break;
                            case "offset_y": c.OffsetY = int.Parse(v); break;
                            case "font_size": c.FontSize = int.Parse(v); break;
                            case "line_gap": c.LineGap = int.Parse(v); break;
                            case "pad_x": c.PadX = int.Parse(v); break;
                            case "pad_y": c.PadY = int.Parse(v); break;
                            case "gap": c.Gap = int.Parse(v); break;
                            case "label_color": c.LabelColor = v; break;
                            case "value_color": c.ValueColor = v; break;
                            case "shadow_color": c.ShadowColor = v; break;
                            case "lang": c.Lang = v.ToLowerInvariant(); break;
                            case "max_value_width": c.MaxValueWidth = int.Parse(v); break;
                            case "data_dir": c.DataDir = v; break;
                            case "stale_ms": c.StaleMs = int.Parse(v); break;
                        }
                    }
                    catch { }
                }
            }
            catch { }
            if (c.PollMs < 60) c.PollMs = 60;
            if (c.PollMs > 5000) c.PollMs = 5000;
            return c;
        }

        public static void WriteDefault(string path)
        {
            try
            {
                if (File.Exists(path)) return;
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("# PBZStatsHUD configuration");
                sb.AppendLine("# lang: auto (follow the game) or zh / zht / en / ja / ko / fr / de / es / pt / ru / it / th / vi");
                sb.AppendLine("lang=auto");
                sb.AppendLine("margin_right=40");
                sb.AppendLine("offset_y=0");
                sb.AppendLine("font_size=26");
                sb.AppendLine("line_gap=8");
                sb.AppendLine("gap=26");
                sb.AppendLine("label_color=#F2F2F2");
                sb.AppendLine("value_color=#E8C36A");
                sb.AppendLine("shadow_color=#000000");
                sb.AppendLine("poll_ms=250");
                sb.AppendLine("stale_ms=15000");
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
            }
            catch { }
        }
    }

    internal sealed class Row
    {
        public string Label;
        public string Value;
    }

    internal sealed class Stats
    {
        public string Lang = "en";
        public string Version = "";
        public DateTime Mtime;
        public readonly Dictionary<string, List<Row>> Sets =
            new Dictionary<string, List<Row>>(StringComparer.OrdinalIgnoreCase);

        public static string Normalize(string code)
        {
            if (string.IsNullOrEmpty(code)) return "en";
            string l = code.Trim().ToLowerInvariant().Replace('_', '-');
            if (l == "auto" || l == "") return "auto";
            if (l == "zht" || l.StartsWith("zh-hant") || l.StartsWith("zh-tw") || l.StartsWith("zh-hk") || l.StartsWith("zh_hant")) return "zht";
            if (l.StartsWith("zh")) return "zh";
            if (l.StartsWith("es")) return "es";
            if (l.StartsWith("pt")) return "pt";
            if (l.StartsWith("ja") || l.StartsWith("jp")) return "ja";
            if (l.StartsWith("ko") || l.StartsWith("kr")) return "ko";
            if (l.StartsWith("fr")) return "fr";
            if (l.StartsWith("de")) return "de";
            if (l.StartsWith("ru")) return "ru";
            if (l.StartsWith("it")) return "it";
            if (l.StartsWith("th")) return "th";
            if (l.StartsWith("vi")) return "vi";
            if (l.StartsWith("en")) return "en";
            int dash = l.IndexOf('-');
            return dash > 0 ? l.Substring(0, dash) : l;
        }

        public List<Row> Pick(string want)
        {
            string l = string.IsNullOrEmpty(want) || want == "auto" ? Lang : want;
            l = Normalize(l);
            List<Row> rows;
            if (l != "auto" && Sets.TryGetValue(l, out rows) && rows.Count > 0) return rows;
            if (Sets.TryGetValue("en", out rows) && rows.Count > 0) return rows;
            if (Sets.TryGetValue("zh", out rows) && rows.Count > 0) return rows;
            foreach (KeyValuePair<string, List<Row>> kv in Sets)
                if (kv.Value.Count > 0) return kv.Value;
            return new List<Row>();
        }
    }

    internal static class Program
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunName = "PBZStatsHUD";
        private const string MutexName = @"Global\PBZStatsHUD_SingleInstance";
        private const string QuitEventName = @"Global\PBZStatsHUD_Quit";
        private const string WindowTitle = "PBZStatsHUD";

        // Version shown in the tray tooltip/balloon. The Lua mod writes the real
        // version into stats.txt ("version="), so an updated mod never leaves a
        // stale number here; this is only the fallback before the first write.
        internal const string FallbackVersion = "3.2.2";

        private static Config _cfg;
        private static string _exeDir;
        private static string _iniPath;
        private static string _dataDir;
        private static string _logPath;
        private static NotifyIcon _tray;
        private static string _trayVersion = "";
        private static ContextMenuStrip _trayMenu;
        private static ToolStripMenuItem _trayVersionItem;
        // The render loop runs on a worker thread, so it only records the version it
        // saw; the UI thread applies it. NotifyIcon must only be touched by the thread
        // that created it, otherwise the tray menu can stop responding.
        private static volatile string _pendingVersion = "";

        [STAThread]
        private static void Main(string[] args)
        {
            _exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
            _iniPath = Path.Combine(_exeDir, "PBZStatsHUD.ini");
            string flag = args.Length > 0 ? args[0].ToLowerInvariant() : "";

            EnableDpiAwareness();

            if (flag == "--install" || flag == "-install")
            {
                DoInstall();
                return;
            }
            if (flag == "--uninstall" || flag == "-uninstall")
            {
                DoUninstall();
                return;
            }
            if (flag == "--quit" || flag == "-quit")
            {
                DoQuit();
                return;
            }

            Config cfg = Config.Load(_iniPath);
            Config.WriteDefault(_iniPath);
            cfg = Config.Load(_iniPath);
            _cfg = cfg;
            _dataDir = ResolveDataDir(cfg);
            _logPath = Path.Combine(_dataDir, "hud.log");
            EnsureDir(_dataDir);
            Log("starting, data dir = " + _dataDir);

            bool created;
            Mutex mutex = new Mutex(true, MutexName, out created);
            if (!created)
            {
                Log("another instance is already running, exiting");
                return;
            }
            try
            {
                EventWaitHandle quit = new EventWaitHandle(false, EventResetMode.ManualReset, QuitEventName);
                bool preview = (flag == "--preview" || flag == "-preview");
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                // The tray icon's context menu needs a real WinForms message loop, so
                // this STA thread pumps messages and the render/poll loop runs on a
                // worker thread. (Before this the loop owned the only thread, and the
                // tray menu could be drawn but never answered clicks.)
                using (HudContext ctx = new HudContext(cfg, quit))
                {
                    Thread worker = new Thread(delegate()
                    {
                        try
                        {
                            RunLoop(cfg, quit, preview);
                        }
                        catch (Exception ex)
                        {
                            Log("run loop failed: " + ex.Message);
                        }
                        finally
                        {
                            try { quit.Set(); } catch { }
                            ctx.PostExit();
                        }
                    });
                    worker.IsBackground = true;
                    worker.Name = "pbzstats-render";
                    worker.Start();
                    Application.Run(ctx);
                }
            }
            finally
            {
                try { mutex.ReleaseMutex(); } catch { }
                mutex.Dispose();
            }
        }

        // The Lua mod writes the release version as the first line of stats.txt
        // ("version=3.2.2"). Read it before the first poll so the startup
        // notification can already show the right number.
        private static string ReadModVersion()
        {
            try
            {
                string p = Path.Combine(_dataDir, "stats.txt");
                if (File.Exists(p))
                {
                    foreach (string raw in File.ReadAllLines(p, Encoding.UTF8))
                    {
                        string line = raw.Trim();
                        if (line.StartsWith("version=", StringComparison.Ordinal))
                        {
                            string v = line.Substring(8).Trim();
                            if (v.Length > 0) return v;
                        }
                    }
                }
            }
            catch { }
            return FallbackVersion;
        }

        // A tray icon is the user's proof that the HUD is alive and the place to
        // close it: the HUD itself is a click-through window with no chrome.
        private static NotifyIcon CreateTray(Config cfg, EventWaitHandle quit)
        {
            string ver = ReadModVersion();
            _trayVersion = ver;
            NotifyIcon ni = new NotifyIcon();
            ni.Icon = System.Drawing.SystemIcons.Application;
            string trayText = "PBZStats HUD v" + ver;
            if (trayText.Length > 63) trayText = trayText.Substring(0, 63); // NotifyIcon.Text limit
            ni.Text = trayText;
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.ShowImageMargin = false;
            ToolStripMenuItem verItem = new ToolStripMenuItem("PBZStats HUD v" + ver);
            verItem.Enabled = false;
            menu.Items.Add(verItem);
            _trayMenu = menu;
            _trayVersionItem = verItem;
            // Refresh the header right before the menu opens (the worker thread may
            // have learned the real version since startup).
            menu.Opening += delegate
            {
                try
                {
                    string v = _pendingVersion;
                    if (string.IsNullOrEmpty(v)) v = _trayVersion;
                    if (!string.IsNullOrEmpty(v)) verItem.Text = "PBZStats HUD v" + v;
                }
                catch { }
            };
            ToolStripMenuItem openItem = new ToolStripMenuItem("打开数据文件夹 / Open data folder");
            openItem.Click += delegate
            {
                try { Process.Start("explorer.exe", _dataDir); } catch { }
            };
            ToolStripMenuItem quitItem = new ToolStripMenuItem("退出 HUD / Quit");
            quitItem.Click += delegate
            {
                try { quit.Set(); } catch { }
            };
            menu.Items.Add(openItem);
            menu.Items.Add(quitItem);
            ni.ContextMenuStrip = menu;
            ni.Visible = true;
            bool game = IsGameRunning(cfg.ProcessName);
            try
            {
                ni.ShowBalloonTip(3000, "PBZStats HUD v" + ver,
                    game ? "已启动，正在显示游戏数据" : "已启动，等待游戏启动",
                    ToolTipIcon.Info);
            }
            catch { }
            Log("tray icon created, game running = " + game);
            return ni;
        }

        // Owns the UI thread: a hidden host form (so the worker thread can marshal
        // updates back here), the tray icon, and a timer that applies version changes.
        private sealed class HudContext : ApplicationContext
        {
            private readonly Form _host;
            private readonly System.Windows.Forms.Timer _timer;
            private bool _exited;

            internal HudContext(Config cfg, EventWaitHandle quit)
            {
                _host = new Form();
                _host.ShowInTaskbar = false;
                _host.FormBorderStyle = FormBorderStyle.None;
                _host.StartPosition = FormStartPosition.Manual;
                _host.Location = new Point(-32000, -32000);
                _host.Size = new Size(1, 1);
                _host.Opacity = 0;
                IntPtr forced = _host.Handle; // create the handle on this thread

                try { _tray = CreateTray(cfg, quit); }
                catch (Exception ex) { Log("tray icon failed: " + ex.Message); }

                _timer = new System.Windows.Forms.Timer();
                _timer.Interval = 500;
                _timer.Tick += delegate { ApplyPendingTrayVersion(); };
                _timer.Start();
            }

            internal void PostExit()
            {
                try
                {
                    if (_host != null && _host.IsHandleCreated)
                        _host.BeginInvoke((MethodInvoker)delegate
                        {
                            if (!_exited) { _exited = true; ExitThread(); }
                        });
                }
                catch { }
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing)
                {
                    try { if (_timer != null) { _timer.Stop(); _timer.Dispose(); } } catch { }
                    try { if (_tray != null) { _tray.Visible = false; _tray.Dispose(); } } catch { }
                    try { if (_host != null) _host.Dispose(); } catch { }
                }
                base.Dispose(disposing);
            }
        }

        private static void ApplyPendingTrayVersion()
        {
            try
            {
                string v = _pendingVersion;
                if (string.IsNullOrEmpty(v) || v == _trayVersion) return;
                _trayVersion = v;
                string text = "PBZStats HUD v" + v;
                if (text.Length > 63) text = text.Substring(0, 63); // NotifyIcon.Text limit
                if (_tray != null) _tray.Text = text;
                if (_trayVersionItem != null) _trayVersionItem.Text = "PBZStats HUD v" + v;
            }
            catch { }
        }

        private static string ResolveDataDir(Config cfg)
        {
            if (!string.IsNullOrEmpty(cfg.DataDir)) return ExpandDir(cfg.DataDir) + Path.DirectorySeparatorChar;
            string lad = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            // All generated data lives in <exe>\data so players can clean it up
            // by deleting one folder.
            string dataSub = Path.Combine(_exeDir, "data");
            if (!string.IsNullOrEmpty(lad))
            {
                // Migrate very old layouts: stats.txt in %LOCALAPPDATA%\PBZStats.
                string legacy = Path.Combine(lad, "PBZStats");
                if (File.Exists(Path.Combine(legacy, "stats.txt")) &&
                    !File.Exists(Path.Combine(dataSub, "stats.txt")) &&
                    !Directory.Exists(dataSub))
                {
                    return legacy + Path.DirectorySeparatorChar;
                }
            }
            return dataSub + Path.DirectorySeparatorChar;
        }

        private static string ExpandDir(string d)
        {
            string s = Environment.ExpandEnvironmentVariables(d.Trim().TrimEnd('\\', '/'));
            if (s.StartsWith("%")) s = d;
            return s;
        }

        private static void EnsureDir(string dir)
        {
            try { if (!Directory.Exists(dir)) Directory.CreateDirectory(dir); } catch { }
        }

        private static void DoInstall()
        {
            string exe = Process.GetCurrentProcess().MainModule.FileName;
            Config cfg = Config.Load(_iniPath);
            Config.WriteDefault(_iniPath);
            cfg = Config.Load(_iniPath);
            string dataDir = _exeDir + Path.DirectorySeparatorChar;
            LogTo(dataDir, "install: exe=" + exe + " data=" + dataDir);
            // Traditional mod layout: nothing is started by Windows. main.lua
            // starts this exe when the game boots, and RunLoop exits when the
            // game closes, so no autostart entry and no external watcher.
            try
            {
                using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k != null) k.DeleteValue(RunName, false);
                }
            }
            catch { }
            if (IsGameRunning(cfg.ProcessName))
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = exe;
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.WorkingDirectory = Path.GetDirectoryName(exe);
                    Process.Start(psi);
                }
                catch { }
            }
        }

        private static void DoUninstall()
        {
            try
            {
                using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k != null) k.DeleteValue(RunName, false);
                }
            }
            catch { }
            try
            {
                EventWaitHandle q;
                if (EventWaitHandle.TryOpenExisting(QuitEventName, out q))
                {
                    q.Set();
                    q.Close();
                }
            }
            catch { }
        }

        private static void DoQuit()
        {
            try
            {
                EventWaitHandle q;
                if (EventWaitHandle.TryOpenExisting(QuitEventName, out q))
                {
                    q.Set();
                    q.Close();
                }
            }
            catch { }
        }

        private static void Log(string msg)
        {
            LogTo(_dataDir, msg);
        }

        private static void LogTo(string dir, string msg)
        {
            try
            {
                if (dir == null) return;
                EnsureDir(dir);
                File.AppendAllText(Path.Combine(dir, "hud.log"),
                    DateTime.Now.ToString("HH:mm:ss") + " " + msg + Environment.NewLine, Encoding.UTF8);
            }
            catch { }
        }

        private static void RunLoop(Config cfg, EventWaitHandle quit, bool preview)
        {
            IntPtr hwnd = Native.CreateWindowEx(
                Native.WS_EX_LAYERED | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOPMOST,
                "STATIC", WindowTitle, Native.WS_POPUP, 0, 0, 10, 10, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (hwnd == IntPtr.Zero) { Log("CreateWindowEx failed"); return; }
            Native.ShowWindow(hwnd, Native.SW_HIDE);

            string lastKey = "";
            DateTime lastStatsWrite = DateTime.MinValue;
            long nextTopmost = 0;
            Stopwatch sw = Stopwatch.StartNew();
            bool visible = false;
            List<Row> current = null;
            int curX = -99999, curY = -99999, curW = 0, curH = 0;
            DateTime absentSince = DateTime.MinValue;

            while (!quit.WaitOne(0))
            {
                bool game = preview || IsGameRunning(cfg.ProcessName);
                if (!preview && !game)
                {
                    if (absentSince == DateTime.MinValue) absentSince = DateTime.UtcNow;
                    else if ((DateTime.UtcNow - absentSince).TotalSeconds > 15) { Log("game closed, exiting"); break; }
                }
                else absentSince = DateTime.MinValue;
                IntPtr target = preview ? IntPtr.Zero : FindGameWindow(cfg.ProcessName);
                Stats data = null;
                string statsPath = Path.Combine(_dataDir, "stats.txt");
                try
                {
                    if (File.Exists(statsPath))
                    {
                        DateTime mtime = File.GetLastWriteTimeUtc(statsPath);
                        if ((DateTime.UtcNow - mtime).TotalMilliseconds <= cfg.StaleMs)
                        {
                            data = ParseStats(File.ReadAllLines(statsPath, Encoding.UTF8), lastStatsWrite);
                            lastStatsWrite = mtime;
                        }
                    }
                }
                catch { }

                if (data != null && data.Version.Length > 0 && data.Version != _pendingVersion)
                {
                    // NotifyIcon is owned by the UI thread; the tray timer applies it.
                    _pendingVersion = data.Version;
                }

                bool show = game && (data != null || preview);
                if (preview && data == null) data = PreviewStats();

                if (show)
                {
                    List<Row> rows = data.Pick(cfg.Lang);
                    string key = KeyOf(rows);
                    Rectangle win = preview ? PrimaryScreen() : WindowRect(target);
                    if (win.Width < 200) { win = PrimaryScreen(); }
                    int x, y, w, h;
                    Bitmap bmp = Layout(rows, cfg, win, out x, out y, out w, out h);
                    bool moved = (x != curX || y != curY || w != curW || h != curH);
                    if (key != lastKey || moved || !visible)
                    {
                        Native.Present(hwnd, bmp, x, y, w, h);
                        bmp.Dispose();
                        curX = x; curY = y; curW = w; curH = h;
                        lastKey = key;
                        current = rows;
                        if (!visible) { Native.ShowWindow(hwnd, Native.SW_SHOWNOACTIVATE); visible = true; }
                    }
                    else
                    {
                        bmp.Dispose();
                    }
                    if (target != IntPtr.Zero && sw.ElapsedMilliseconds > nextTopmost)
                    {
                        Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, x, y, w, h,
                            Native.SWP_NOACTIVATE | Native.SWP_NOSIZE | Native.SWP_NOMOVE);
                        nextTopmost = sw.ElapsedMilliseconds + 2000;
                    }
                }
                else if (visible)
                {
                    Native.ShowWindow(hwnd, Native.SW_HIDE);
                    visible = false;
                    lastKey = "";
                }

                if (!quit.WaitOne(cfg.PollMs)) { /* timeout */ }
            }
            Native.DestroyWindow(hwnd);
        }

        private static Rectangle PrimaryScreen()
        {
            return new Rectangle(0, 0, Native.GetSystemMetrics(Native.SM_CXSCREEN), Native.GetSystemMetrics(Native.SM_CYSCREEN));
        }

        private static bool IsGameRunning(string name)
        {
            try
            {
                Process[] ps = Process.GetProcessesByName(name);
                return ps != null && ps.Length > 0;
            }
            catch { return false; }
        }

        private static IntPtr FindGameWindow(string name)
        {
            try
            {
                Process[] ps = Process.GetProcessesByName(name);
                foreach (Process p in ps)
                {
                    IntPtr h = p.MainWindowHandle;
                    if (h != IntPtr.Zero) return h;
                }
            }
            catch { }
            return IntPtr.Zero;
        }

        private static Rectangle WindowRect(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return PrimaryScreen();
            try
            {
                Native.RECT r;
                if (Native.GetWindowRect(hwnd, out r)) return new Rectangle(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
            }
            catch { }
            return PrimaryScreen();
        }

        private static string KeyOf(List<Row> rows)
        {
            StringBuilder sb = new StringBuilder();
            foreach (Row r in rows) sb.Append(r.Label).Append('\u0001').Append(r.Value).Append('\n');
            return sb.ToString();
        }

        private static Stats ParseStats(string[] lines, DateTime lastWrite)
        {
            Stats d = new Stats();
            foreach (string raw in lines)
            {
                string line = raw.TrimEnd('\r', '\n');
                if (line.Length == 0) continue;
                if (line.StartsWith("version=")) { d.Version = line.Substring(8).Trim(); continue; }
                if (line.StartsWith("lang=")) { d.Lang = Stats.Normalize(line.Substring(5)); continue; }
                int p = line.IndexOf('|');
                if (p <= 0) continue;
                string kind = line.Substring(0, p);
                string rest = line.Substring(p + 1);
                if (kind == "lang")
                {
                    d.Lang = rest.Trim().ToLowerInvariant();
                    continue;
                }
                if (!kind.StartsWith("row_")) continue;
                string code = Stats.Normalize(kind.Substring(4));
                int q = rest.IndexOf('|');
                if (q < 0) continue;
                string label = rest.Substring(0, q);
                string val = rest.Substring(q + 1);
                Row r = new Row();
                r.Label = Unescape(label);
                r.Value = Unescape(val);
                List<Row> list;
                if (!d.Sets.TryGetValue(code, out list))
                {
                    list = new List<Row>();
                    d.Sets[code] = list;
                }
                list.Add(r);
            }
            d.Mtime = lastWrite;
            return d;
        }

        private static string Unescape(string s)
        {
            return s.Replace("\\n", "\n").Replace("\\\\", "\\");
        }

        private static Stats PreviewStats()
        {
            Stats d = new Stats();
            d.Lang = "zh";
            AddRow(d, "zh", "当前周目", "第 1 周目");
            AddRow(d, "zh", "当前难度", "逆天者");
            AddRow(d, "zh", "死亡总数", "108");
            AddRow(d, "zh", "当前 Boss", "摩天·龙柱");
            AddRow(d, "zh", "本 Boss 死亡", "18");
            AddRow(d, "en", "Cycle", "Cycle 1");
            AddRow(d, "en", "Difficulty", "Hard");
            AddRow(d, "en", "Total Deaths", "108");
            AddRow(d, "en", "Boss", "MoTian, the Dragon Pillar");
            AddRow(d, "en", "Boss Deaths", "18");
            return d;
        }

        private static void AddRow(Stats d, string code, string l, string v)
        {
            List<Row> list;
            if (!d.Sets.TryGetValue(code, out list))
            {
                list = new List<Row>();
                d.Sets[code] = list;
            }
            Row r = new Row();
            r.Label = l; r.Value = v;
            list.Add(r);
        }

        private static Font PickFont(float size)
        {
            string[] fams = { "Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI" };
            foreach (string f in fams)
            {
                try { return new Font(f, size, FontStyle.Regular, GraphicsUnit.Pixel); } catch { }
            }
            return new Font(FontFamily.GenericSansSerif, size, FontStyle.Regular, GraphicsUnit.Pixel);
        }

        private static Bitmap Layout(List<Row> rows, Config cfg, Rectangle win, out int x, out int y, out int w, out int h)
        {
            Font font = PickFont(cfg.FontSize);
            Bitmap probeBmp = new Bitmap(8, 8);
            Graphics pg = Graphics.FromImage(probeBmp);
            pg.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            StringFormat sf = (StringFormat)StringFormat.GenericTypographic.Clone();
            rows = ClampValues(rows, pg, font, sf, cfg.MaxValueWidth);
            float maxL = 0, maxV = 0;
            foreach (Row r in rows)
            {
                SizeF sl = pg.MeasureString(r.Label, font, 10000, sf);
                SizeF sv = pg.MeasureString(r.Value, font, 10000, sf);
                if (sl.Width > maxL) maxL = sl.Width;
                if (sv.Width > maxV) maxV = sv.Width;
            }
            float lineH = font.GetHeight(pg) + cfg.LineGap;
            FontHeaderMeasure();
            w = (int)Math.Ceiling(cfg.PadX * 2 + maxL + cfg.Gap + maxV) + 6;
            h = (int)Math.Ceiling(cfg.PadY * 2 + rows.Count * lineH) + 4;
            if (w < 10) w = 10; if (h < 10) h = 10;
            x = win.Left + win.Width - w - cfg.MarginRight;
            y = win.Top + (win.Height - h) / 2 + cfg.OffsetY;
            if (x < win.Left + 4) x = win.Left + 4;
            if (y < win.Top + 4) y = win.Top + 4;

            Bitmap bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                Color labelColor = ParseColor(cfg.LabelColor, Color.White);
                Color valueColor = ParseColor(cfg.ValueColor, Color.FromArgb(232, 195, 106));
                Color shadowColor = ParseColor(cfg.ShadowColor, Color.Black);
                using (SolidBrush shadow = new SolidBrush(Color.FromArgb(190, shadowColor)))
                using (SolidBrush labelBrush = new SolidBrush(labelColor))
                using (SolidBrush valueBrush = new SolidBrush(valueColor))
                {
                    float baseY = cfg.PadY;
                    foreach (Row r in rows)
                    {
                        SizeF sl = g.MeasureString(r.Label, font, 10000, sf);
                        float lx = cfg.PadX + maxL - sl.Width;
                        float vx = cfg.PadX + maxL + cfg.Gap;
                        // 1px outline in 8 directions keeps the text readable on
                        // bright and dark scenes alike.
                        for (int ox = -1; ox <= 1; ox++)
                        {
                            for (int oy = -1; oy <= 1; oy++)
                            {
                                if (ox == 0 && oy == 0) continue;
                                g.DrawString(r.Label, font, shadow, lx + ox, baseY + oy, sf);
                                g.DrawString(r.Value, font, shadow, vx + ox, baseY + oy, sf);
                            }
                        }
                        g.DrawString(r.Label, font, labelBrush, lx, baseY, sf);
                        g.DrawString(r.Value, font, valueBrush, vx, baseY, sf);
                        baseY += lineH;
                    }
                }
            }
            pg.Dispose();
            probeBmp.Dispose();
            font.Dispose();
            return bmp;
        }

        // Long boss names (Russian/German/French are the worst offenders) are cut
        // to fit MaxValueWidth and marked with an ellipsis instead of running off
        // the right edge of the screen.
        private static List<Row> ClampValues(List<Row> rows, Graphics g, Font font, StringFormat sf, int maxW)
        {
            if (maxW <= 0 || rows == null) return rows;
            List<Row> outp = new List<Row>(rows.Count);
            foreach (Row r in rows)
            {
                string v = r.Value == null ? "" : r.Value;
                if (v.Length > 0 && g.MeasureString(v, font, 10000, sf).Width > maxW)
                {
                    string cut = v;
                    while (cut.Length > 1 &&
                           g.MeasureString(cut + "\u2026", font, 10000, sf).Width > maxW)
                    {
                        cut = cut.Substring(0, cut.Length - 1);
                    }
                    v = cut + "\u2026";
                }
                Row n = new Row();
                n.Label = r.Label;
                n.Value = v;
                outp.Add(n);
            }
            return outp;
        }

        private static void FontHeaderMeasure() { }

        private static Color ParseColor(string s, Color fallback)
        {
            try
            {
                if (string.IsNullOrEmpty(s)) return fallback;
                s = s.Trim();
                if (s.StartsWith("#")) s = s.Substring(1);
                if (s.Length == 6)
                {
                    int v = int.Parse(s, NumberStyles.HexNumber);
                    return Color.FromArgb(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
                }
                if (s.Length == 8)
                {
                    long v = long.Parse(s, NumberStyles.HexNumber);
                    return Color.FromArgb((int)((v >> 24) & 0xFF), (int)((v >> 16) & 0xFF), (int)((v >> 8) & 0xFF), (int)(v & 0xFF));
                }
            }
            catch { }
            return fallback;
        }

        private static void EnableDpiAwareness()
        {
            try { Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
            try { Native.SetProcessDPIAware(); } catch { }
        }
    }


    internal static class Native
    {
        public const int WS_EX_LAYERED = 0x00080000;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW = 0x00000080;
        public const int WS_EX_NOACTIVATE = 0x08000000;
        public const int WS_EX_TOPMOST = 0x00000008;
        public const int WS_POPUP = unchecked((int)0x80000000);
        public const int SW_HIDE = 0;
        public const int SW_SHOWNOACTIVATE = 4;
        public const int SM_CXSCREEN = 0;
        public const int SM_CYSCREEN = 1;
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; }

        [StructLayout(LayoutKind.Sequential)]
        public struct SIZE { public int cx, cy; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct BITMAPINFOHEADER
        {
            public int biSize;
            public int biWidth;
            public int biHeight;
            public short biPlanes;
            public short biBitCount;
            public int biCompression;
            public int biSizeImage;
            public int biXPelsPerMeter;
            public int biYPelsPerMeter;
            public int biClrUsed;
            public int biClrImportant;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr CreateWindowEx(int exStyle, string cls, string title, int style, int x, int y, int w, int h,
            IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);

        [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] public static extern int GetSystemMetrics(int idx);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
            IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int flags);

        [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFOHEADER pbmi, uint usage, out IntPtr bits, IntPtr section, uint offset);

        public static void Present(IntPtr hwnd, Bitmap bmp, int x, int y, int w, int h)
        {
            IntPtr screenDc = GetDC(IntPtr.Zero);
            IntPtr memDc = CreateCompatibleDC(screenDc);
            IntPtr bits = IntPtr.Zero;
            BITMAPINFOHEADER bi = new BITMAPINFOHEADER();
            bi.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER));
            bi.biWidth = w;
            bi.biHeight = -h; // top-down
            bi.biPlanes = 1;
            bi.biBitCount = 32;
            bi.biCompression = 0;
            IntPtr dib = CreateDIBSection(memDc, ref bi, 0, out bits, IntPtr.Zero, 0);
            IntPtr old = IntPtr.Zero;
            try
            {
                if (dib == IntPtr.Zero || bits == IntPtr.Zero) return;
                old = SelectObject(memDc, dib);
                CopyPremultiplied(bmp, bits, w, h);
                POINT dst = new POINT(); dst.X = x; dst.Y = y;
                SIZE size = new SIZE(); size.cx = w; size.cy = h;
                POINT src = new POINT(); src.X = 0; src.Y = 0;
                BLENDFUNCTION blend = new BLENDFUNCTION();
                blend.BlendOp = 0; blend.BlendFlags = 0; blend.SourceConstantAlpha = 255; blend.AlphaFormat = 1;
                UpdateLayeredWindow(hwnd, screenDc, ref dst, ref size, memDc, ref src, 0, ref blend, 2);
            }
            finally
            {
                if (old != IntPtr.Zero) SelectObject(memDc, old);
                if (dib != IntPtr.Zero) DeleteObject(dib);
                DeleteDC(memDc);
                ReleaseDC(IntPtr.Zero, screenDc);
            }
        }

        private static void CopyPremultiplied(Bitmap bmp, IntPtr dstBits, int w, int h)
        {
            System.Drawing.Imaging.BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h),
                System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            try
            {
                unsafe
                {
                    byte* src = (byte*)bd.Scan0.ToPointer();
                    byte* dst = (byte*)dstBits.ToPointer();
                    int count = w * h;
                    for (int i = 0; i < count; i++)
                    {
                        int o = i * 4;
                        byte b = src[o + 0];
                        byte g = src[o + 1];
                        byte r = src[o + 2];
                        byte a = src[o + 3];
                        if (a == 255)
                        {
                            dst[o + 0] = b; dst[o + 1] = g; dst[o + 2] = r; dst[o + 3] = 255;
                        }
                        else if (a == 0)
                        {
                            dst[o + 0] = 0; dst[o + 1] = 0; dst[o + 2] = 0; dst[o + 3] = 0;
                        }
                        else
                        {
                            dst[o + 0] = (byte)(b * a / 255);
                            dst[o + 1] = (byte)(g * a / 255);
                            dst[o + 2] = (byte)(r * a / 255);
                            dst[o + 3] = a;
                        }
                    }
                }
            }
            finally
            {
                bmp.UnlockBits(bd);
            }
        }
    }
}

