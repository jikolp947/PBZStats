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
        public int Gap = 14;
        public string LabelColor = "#F2F2F2";
        public string ValueColor = "#E8C36A";
        public string ShadowColor = "#000000";
        public string Lang = "auto";          // auto | zh | en
        public string DataDir = "";           // empty -> auto
        public int StaleMs = 15000;
        // --- settings page -------------------------------------------------
        // Global hotkey that opens the settings window while the game runs.
        public string SettingsHotkey = "Ctrl+F8";
        // Row indexes that the user hid on the settings page (0 = first line).
        // Hiding a row removes it from the layout entirely, so the remaining
        // lines move up instead of leaving a gap.
        public readonly List<int> HiddenRows = new List<int>();
        public bool IsHidden(int index) { return HiddenRows.Contains(index); }
        // Which screen edge the five lines stick to: "right" (default) or "left".
        // The same margin value is used as the distance from that edge.
        public string Align = "right";
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
                            case "settings_hotkey": c.SettingsHotkey = v; break;
                            case "align": c.Align = (v.ToLowerInvariant() == "left") ? "left" : "right"; break;
                            case "hidden_rows":
                                c.HiddenRows.Clear();
                                foreach (string part in v.Split(','))
                                {
                                    int n;
                                    if (int.TryParse(part.Trim(), out n) && n >= 0 && n < 64) c.HiddenRows.Add(n);
                                }
                                break;
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
                SaveTo(path, new Config());
            }
            catch { }
        }

        // Rewrites the whole ini from the live values. The settings window calls
        // this after every change so a crash never loses a setting.
        public void Save(string path)
        {
            try { SaveTo(path, this); } catch { }
        }

        private static void SaveTo(string path, Config c)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("# PBZStatsHUD configuration");
            sb.AppendLine("# lang: auto (follow the game) or zh / zht / en / ja / ko / fr / de / es / pt / ru / it / th / vi");
            sb.AppendLine("lang=" + c.Lang);
            sb.AppendLine("# settings_hotkey: global hotkey that opens the settings page (at least one modifier)");
            sb.AppendLine("settings_hotkey=" + c.SettingsHotkey);
            sb.AppendLine("# hidden_rows: comma separated row indexes hidden on the settings page (0 = first line)");
            StringBuilder hid = new StringBuilder();
            for (int i = 0; i < c.HiddenRows.Count; i++)
            {
                if (i > 0) hid.Append(',');
                hid.Append(c.HiddenRows[i]);
            }
            sb.AppendLine("hidden_rows=" + hid.ToString());
            sb.AppendLine("# data_dir: empty = the data folder next to this exe (data\\)");
            sb.AppendLine("data_dir=" + c.DataDir);
            sb.AppendLine("# layout, measured from the right edge of the game window");
            sb.AppendLine("# align: text alignment inside the HUD - right (hug the right edge) or left");
            sb.AppendLine("align=" + c.Align);
            sb.AppendLine("margin_right=" + c.MarginRight);
            sb.AppendLine("offset_y=" + c.OffsetY);
            sb.AppendLine("font_size=" + c.FontSize);
            sb.AppendLine("line_gap=" + c.LineGap);
            sb.AppendLine("gap=" + c.Gap);
            sb.AppendLine("max_value_width=" + c.MaxValueWidth);
            sb.AppendLine("label_color=" + c.LabelColor);
            sb.AppendLine("value_color=" + c.ValueColor);
            sb.AppendLine("shadow_color=" + c.ShadowColor);
            sb.AppendLine("poll_ms=" + c.PollMs);
            sb.AppendLine("stale_ms=" + c.StaleMs);
            File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
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

    // Short UI strings for the settings window and the drag panel. They follow
    // the same language the game reports through stats.txt, so a player who
    // switches the game to, say, Japanese gets a Japanese settings page too.
    internal static class UiText
    {
        private static readonly Dictionary<string, string> En = Make(
            "Settings", "Hotkey", "press keys", "active", "failed (in use)",
            "Visible rows", "Font size", "Free position", "Done", "Font",
            "changes are saved immediately", "Text align", "Right", "Left", "Row {0}");

        private static readonly Dictionary<string, Dictionary<string, string>> All =
            new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase)
        {
            { "en", En },
            { "zh", Make("设置", "快捷键", "按下组合键", "已生效", "注册失败（被占用）",
                         "显示行", "字号", "自由调整 HUD 位置", "完成", "字体",
                         "所有改动立即保存", "文字对齐", "靠右", "靠左", "第 {0} 行") },
            { "zht", Make("設定", "快速鍵", "按下組合鍵", "已生效", "註冊失敗（被佔用）",
                          "顯示行", "字號", "自由調整 HUD 位置", "完成", "字體",
                          "所有變更立即儲存", "文字對齊", "靠右", "靠左", "第 {0} 行") },
            { "ja", Make("設定", "ホットキー", "キーを押す", "有効", "登録できません（使用中）",
                         "表示する行", "文字サイズ", "HUD の位置を自由に調整", "完了", "フォント",
                         "変更はすぐ保存されます", "文字揃え", "右", "左", "{0} 行目") },
            { "ko", Make("설정", "단축키", "키를 누르세요", "활성", "등록 실패(사용 중)",
                         "표시할 행", "글자 크기", "HUD 위치 자유 조정", "완료", "글꼴",
                         "변경 사항은 즉시 저장됩니다", "정렬", "오른쪽", "왼쪽", "{0}번째 행") },
            { "ru", Make("Настройки", "Горячая клавиша", "нажмите клавиши", "активно", "не удалось (занято)",
                         "Видимые строки", "Размер шрифта", "Свободное размещение HUD", "Готово", "Шрифт",
                         "изменения сохраняются сразу", "Выравнивание", "По правому краю", "По левому краю", "Строка {0}") },
            { "de", Make("Einstellungen", "Tastenkürzel", "Tasten drücken", "aktiv", "fehlgeschlagen (belegt)",
                         "Sichtbare Zeilen", "Schriftgröße", "HUD frei positionieren", "Fertig", "Schrift",
                         "Änderungen werden sofort gespeichert", "Ausrichtung", "Rechts", "Links", "Zeile {0}") },
            { "fr", Make("Réglages", "Raccourci", "appuyez sur les touches", "actif", "échec (déjà utilisé)",
                         "Lignes visibles", "Taille de police", "Position libre du HUD", "Terminé", "Police",
                         "les changements sont enregistrés aussitôt", "Alignement", "Droite", "Gauche", "Ligne {0}") },
            { "es", Make("Ajustes", "Atajo", "pulse las teclas", "activo", "falló (en uso)",
                         "Filas visibles", "Tamaño de letra", "Posición libre del HUD", "Listo", "Fuente",
                         "los cambios se guardan al instante", "Alineación", "Derecha", "Izquierda", "Fila {0}") },
            { "pt", Make("Ajustes", "Atalho", "pressione as teclas", "ativo", "falhou (em uso)",
                         "Linhas visíveis", "Tamanho da fonte", "Posição livre do HUD", "Concluir", "Fonte",
                         "as alterações são salvas na hora", "Alinhamento", "Direita", "Esquerda", "Linha {0}") },
            { "it", Make("Impostazioni", "Scorciatoia", "premi i tasti", "attivo", "non riuscito (in uso)",
                         "Righe visibili", "Dimensione testo", "Posizione libera HUD", "Fatto", "Carattere",
                         "le modifiche vengono salvate subito", "Allineamento", "Destra", "Sinistra", "Riga {0}") },
            { "th", Make("ตั้งค่า", "คีย์ลัด", "กดปุ่ม", "ใช้งานอยู่", "ลงทะเบียนไม่สำเร็จ (ถูกใช้อยู่)",
                         "แถวที่แสดง", "ขนาดตัวอักษร", "ปรับตำแหน่ง HUD อิสระ", "เสร็จ", "ฟอนต์",
                         "การเปลี่ยนแปลงจะถูกบันทึกทันที", "จัดแนว", "ขวา", "ซ้าย", "แถว {0}") },
            { "vi", Make("Cài đặt", "Phím tắt", "nhấn phím", "đang hoạt động", "không đăng ký được (đang dùng)",
                         "Dòng hiển thị", "Cỡ chữ", "Đặt vị trí HUD tự do", "Xong", "Phông chữ",
                         "thay đổi được lưu ngay", "Căn lề", "Phải", "Trái", "Dòng {0}") },
        };

        private static Dictionary<string, string> Make(string title, string hotkey, string press,
            string active, string failed, string rows, string font, string free, string done,
            string fontBar, string tip, string anchor, string right, string left, string row)
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "title", title }, { "hotkey", hotkey }, { "press", press },
                { "active", active }, { "failed", failed }, { "rows", rows },
                { "font", font }, { "free", free }, { "done", done },
                { "fontbar", fontBar }, { "tip", tip }, { "anchor", anchor },
                { "right", right }, { "left", left }, { "row", row },
            };
        }
        public static string L(string key)
        {
            if (key == "fonthint")
            {
                string hint;
                if (FontHint.TryGetValue(Program.UiLang(), out hint)) return hint;
                return FontHint["en"];
            }
            Dictionary<string, string> d;
            if (!All.TryGetValue(Program.UiLang(), out d)) d = En;
            string v;
            if (d != null && d.TryGetValue(key, out v)) return v;
            return En.TryGetValue(key, out v) ? v : key;
        }

        private static readonly Dictionary<string, string> FontHint =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "en", "tweak live in free mode" },
            { "zh", "可在自由调整模式里微调" },
            { "zht", "可在自由調整模式裡微調" },
            { "ja", "自由配置モードで微調整" },
            { "ko", "자유 배치 모드에서 조정" },
            { "ru", "правится в свободном режиме" },
            { "de", "im freien Modus anpassbar" },
            { "fr", "réglable en position libre" },
            { "es", "ajustable en posición libre" },
            { "pt", "ajustável em posição livre" },
            { "it", "regolabile in posizione libera" },
            { "th", "ปรับได้ในโหมดอิสระ" },
            { "vi", "chỉnh ở chế độ tự do" },        };

        public static string Row(string n) { return string.Format(L("row"), n); }
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
        internal const string FallbackVersion = "3.7.1";

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

        // --- settings page / free-position mode ---------------------------
        // The worker thread only reads these; the WinForms UI thread owns the
        // windows. While _editMode is on the layered HUD is hidden and a real
        // WinForms panel takes its place so the user can drag it around.
        private const int HotkeyId = 0x5B21;
        private static volatile bool _editMode;
        private static volatile List<Row> _lastRows = new List<Row>();
        private static Rectangle _lastGameRect = Rectangle.Empty;
        private static SettingsForm _settingsForm;
        private static bool _openSettingsOnStart;
        private static EditForm _editForm;
        private static HudHost _host;
        private static volatile string _hotkeyText = "Ctrl+F8";
        private static bool _hotkeyRegistered;
        private static DateTime _lastHotkeyUtc = DateTime.MinValue;
        private static volatile bool _forceRedraw;
        // Language that stats.txt currently reports; the settings page and the
        // drag panel follow it the same way the HUD itself does.
        private static volatile string _uiLang = "en";

        [STAThread]
        private static void Main(string[] args)
        {
            string home = Environment.GetEnvironmentVariable("PBZSTATS_HOME");
            if (!string.IsNullOrEmpty(home) && Directory.Exists(home)) _exeDir = home;
            else {
                string loc = "";
                try { loc = System.Reflection.Assembly.GetExecutingAssembly().Location; } catch { }
                _exeDir = string.IsNullOrEmpty(loc) ? AppDomain.CurrentDomain.BaseDirectory
                                                    : Path.GetDirectoryName(loc);
            }
            _iniPath = Path.Combine(_exeDir, "PBZStatsHUD.ini");
            string flag = args.Length > 0 ? args[0].ToLowerInvariant() : "";
            bool wantPreview = false, wantSettings = false;
            foreach (string a in args)
            {
                string al = a.ToLowerInvariant();
                if (al == "--preview" || al == "-preview") wantPreview = true;
                if (al == "--settings" || al == "-settings") wantSettings = true;
            }

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
                bool preview = wantPreview;
                // --settings: open the settings page right away (a shortcut can use
                // this, which is handy when the global hotkey is taken by the game)
                if (wantSettings) _openSettingsOnStart = true;
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
                    foreach (string raw in ReadStatsLines(p))
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
            ToolStripMenuItem settingsItem = new ToolStripMenuItem("设置 / Settings");
            settingsItem.Click += delegate { OpenSettings(); };
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
            menu.Items.Add(settingsItem);
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

        // A normal Form is the UI thread's message sink: WinForms dispatches the
        // WM_HOTKEY posted by RegisterHotKey here, so Ctrl+F8 works while the game
        // has the focus.
        private sealed class HudHost : Form
        {
            internal Action<int> OnHotkey;
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == Native.WM_HOTKEY)
                {
                    Action<int> h = OnHotkey;
                    if (h != null) { try { h(m.WParam.ToInt32()); } catch { } }
                    return;
                }
                base.WndProc(ref m);
            }
        }

        // Owns the UI thread: a hidden host form (so the worker thread can marshal
        // updates back here), the tray icon, and a timer that applies version changes.
        private sealed class HudContext : ApplicationContext
        {
            private readonly HudHost _host;
            private readonly System.Windows.Forms.Timer _timer;
            private bool _exited;

            internal HudContext(Config cfg, EventWaitHandle quit)
            {
                _host = new HudHost();
                _host.ShowInTaskbar = false;
                _host.FormBorderStyle = FormBorderStyle.None;
                _host.StartPosition = FormStartPosition.Manual;
                _host.Location = new Point(-32000, -32000);
                _host.Size = new Size(1, 1);
                _host.Opacity = 0;
                IntPtr forced = _host.Handle; // create the handle on this thread
                _host.OnHotkey = delegate(int id)
                {
                    if (id != HotkeyId) return;
                    // Windows can post WM_HOTKEY more than once for a single chord
                    // (key repeat / two mouse+key events); opening six panels in two
                    // seconds fought the game over the foreground window.
                    DateTime now = DateTime.UtcNow;
                    if ((now - _lastHotkeyUtc).TotalMilliseconds < 450) return;
                    _lastHotkeyUtc = now;
                    OpenSettings();
                };

                Program._host = _host;
                if (RegisterSettingsHotkey(_host.Handle, cfg.SettingsHotkey))
                    Log("settings hotkey registered: " + HotkeyText());
                else
                    Log("settings hotkey unavailable: " + cfg.SettingsHotkey);

                try { _tray = CreateTray(cfg, quit); }
                catch (Exception ex) { Log("tray icon failed: " + ex.Message); }

                _timer = new System.Windows.Forms.Timer();
                _timer.Interval = 500;
                _timer.Tick += delegate { ApplyPendingTrayVersion(); };
                _timer.Start();

                if (_openSettingsOnStart)
                {
                    try
                    {
                        _host.BeginInvoke((MethodInvoker)delegate
                        {
                            try { OpenSettings(); } catch { }
                        });
                    }
                    catch { }
                }
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
                    try { if (_host != null) UnregisterSettingsHotkey(_host.Handle); } catch { }
                    try { if (_timer != null) { _timer.Stop(); _timer.Dispose(); } } catch { }
                    try { if (_tray != null) { _tray.Visible = false; _tray.Dispose(); } } catch { }
                    try { if (_host != null) _host.Dispose(); } catch { }
                }
                base.Dispose(disposing);
            }
        }

        // --- settings hotkey ------------------------------------------------
        private static bool RegisterSettingsHotkey(IntPtr hwnd, string text)
        {
            try { UnregisterSettingsHotkey(hwnd); } catch { }
            uint mods, vk;
            string normalized;
            if (!ParseHotkey(text, out mods, out vk, out normalized))
            {
                if (!ParseHotkey("Ctrl+F8", out mods, out vk, out normalized)) return false;
            }
            try
            {
                if (Native.RegisterHotKey(hwnd, HotkeyId, mods, vk))
                {
                    _hotkeyRegistered = true;
                    _hotkeyText = normalized;
                    return true;
                }
            }
            catch { }
            _hotkeyRegistered = false;
            return false;
        }

        private static void UnregisterSettingsHotkey(IntPtr hwnd)
        {
            try
            {
                if (_hotkeyRegistered) Native.UnregisterHotKey(hwnd, HotkeyId);
            }
            catch { }
            _hotkeyRegistered = false;
        }

        internal static bool IsHotkeyRegistered() { return _hotkeyRegistered; }
        internal static string HotkeyText() { return _hotkeyText; }

        // Accepts "Ctrl+F8", "Ctrl+Shift+F9", "Alt+1", ... A modifier is mandatory
        // so a stray key can never swallow normal typing.
        internal static bool ParseHotkey(string text, out uint mods, out uint vk, out string normalized)
        {
            mods = 0; vk = 0; normalized = "";
            if (string.IsNullOrEmpty(text)) return false;
            string[] parts = text.Split('+');
            string keyName = "";
            bool anyMod = false;
            foreach (string raw in parts)
            {
                string p = raw.Trim();
                if (p.Length == 0) continue;
                string low = p.ToLowerInvariant();
                if (low == "ctrl" || low == "control") { mods |= Native.MOD_CONTROL; anyMod = true; }
                else if (low == "alt") { mods |= Native.MOD_ALT; anyMod = true; }
                else if (low == "shift") { mods |= Native.MOD_SHIFT; anyMod = true; }
                else if (low == "win" || low == "windows") { mods |= Native.MOD_WIN; anyMod = true; }
                else keyName = p;
            }
            if (!anyMod || keyName.Length == 0) return false;
            uint code;
            if (!KeyNameToVk(keyName, out code)) return false;
            vk = code;
            StringBuilder sb = new StringBuilder();
            if ((mods & Native.MOD_CONTROL) != 0) sb.Append("Ctrl+");
            if ((mods & Native.MOD_ALT) != 0) sb.Append("Alt+");
            if ((mods & Native.MOD_SHIFT) != 0) sb.Append("Shift+");
            if ((mods & Native.MOD_WIN) != 0) sb.Append("Win+");
            sb.Append(keyName.ToUpperInvariant());
            normalized = sb.ToString();
            return true;
        }

        private static bool KeyNameToVk(string name, out uint vk)
        {
            vk = 0;
            if (name.Length == 1)
            {
                char c = char.ToUpperInvariant(name[0]);
                if (c >= 'A' && c <= 'Z') { vk = (uint)c; return true; }
                if (c >= '0' && c <= '9') { vk = (uint)(0x30 + (c - '0')); return true; }
            }
            string n = name.ToUpperInvariant();
            if (n.Length >= 2 && n[0] == 'F')
            {
                int num;
                if (int.TryParse(n.Substring(1), out num) && num >= 1 && num <= 24)
                {
                    vk = (uint)(0x70 + (num - 1));
                    return true;
                }
            }
            switch (n)
            {
                case "SPACE": vk = 0x20; return true;
                case "TAB": vk = 0x09; return true;
                case "INSERT": vk = 0x2D; return true;
                case "DELETE": vk = 0x2E; return true;
                case "HOME": vk = 0x24; return true;
                case "END": vk = 0x23; return true;
                case "PAGEUP": case "PGUP": vk = 0x21; return true;
                case "PAGEDOWN": case "PGDN": vk = 0x22; return true;
                case "UP": vk = 0x26; return true;
                case "DOWN": vk = 0x28; return true;
                case "LEFT": vk = 0x25; return true;
                case "RIGHT": vk = 0x27; return true;
                case "ENTER": vk = 0x0D; return true;
            }
            return false;
        }

        // Builds the "Ctrl+F8" style text from a KeyDown event, or "" for a
        // modifier-only press (the textbox keeps waiting for the real key).
        internal static string HotkeyFromKey(Keys key, Keys modifiers)
        {
            if (key == Keys.None) return "";
            if (key == Keys.ControlKey || key == Keys.ShiftKey || key == Keys.Menu ||
                key == Keys.LControlKey || key == Keys.RControlKey ||
                key == Keys.LShiftKey || key == Keys.RShiftKey ||
                key == Keys.LMenu || key == Keys.RMenu) return "";
            StringBuilder sb = new StringBuilder();
            if ((modifiers & Keys.Control) != 0) sb.Append("Ctrl+");
            if ((modifiers & Keys.Alt) != 0) sb.Append("Alt+");
            if ((modifiers & Keys.Shift) != 0) sb.Append("Shift+");
            string name = key.ToString();
            if (name.Length == 2 && name[0] == 'D' && char.IsDigit(name[1])) name = name.Substring(1);
            if (name == "Return") name = "Enter";
            if (name == "Escape") return "";
            sb.Append(name.ToUpperInvariant());
            return sb.ToString();
        }

        // stats.txt is rewritten by the mod while this process polls it every few
        // hundred ms. File.ReadAllLines opens with FileShare.Read only, so the mod's
        // write could fail with a sharing violation ("cannot write stats.txt").
        // Share everything and retry briefly instead.
        private static string[] ReadStatsLines(string path)
        {
            for (int attempt = 0; ; attempt++)
            {
                try
                {
                    using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                               FileShare.ReadWrite | FileShare.Delete))
                    using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                    {
                        string all = sr.ReadToEnd();
                        return all.Split(new string[] { "\r\n", "\n" }, StringSplitOptions.None);
                    }
                }
                catch (IOException)
                {
                    if (attempt >= 3) throw;
                    System.Threading.Thread.Sleep(12);
                }
            }
        }

        internal static void OpenSettings()
        {
            try
            {
                Log("open settings");
                RefreshUiLang();
                if (_settingsForm != null && !_settingsForm.IsDisposed)
                {
                    // rebuild the panel so every caption follows the language the
                    // game is in right now (the form is long-lived between opens)
                    try { _settingsForm.Hide(); _settingsForm.Dispose(); } catch { }
                    _settingsForm = null;
                }
                if (_editMode) return; // finish the position edit first
                _settingsForm = new SettingsForm();
                _settingsForm.Show();
                _settingsForm.Activate();
            }
            catch (Exception ex) { Log("open settings failed: " + ex.Message); }
        }

        // Reads stats.txt right away and adopts its language. The render loop also
        // does this every poll, but the settings panel can open before the first
        // poll ever has data (for example when started with --settings).
        internal static void RefreshUiLang()
        {
            try
            {
                if (_dataDir == null) return;
                string p = Path.Combine(_dataDir, "stats.txt");
                if (!File.Exists(p)) return;
                Stats d = ParseStats(ReadStatsLines(p), DateTime.MinValue);
                if (d == null) return;
                string nl = Stats.Normalize(d.Lang);
                if (nl != "auto" && nl != _uiLang) _uiLang = nl;
            }
            catch { }
        }

        internal static void SaveConfig()
        {
            try { if (_cfg != null) _cfg.Save(_iniPath); } catch { }
        }

        internal static void RetryHotkey()
        {
            try
            {
                if (_host != null && !_host.IsDisposed)
                {
                    if (!RegisterSettingsHotkey(_host.Handle, _cfg.SettingsHotkey))
                        Log("settings hotkey unavailable: " + _cfg.SettingsHotkey);
                }
            }
            catch { }
        }

        internal static List<Row> LastRows() { return _lastRows; }
        internal static Rectangle LastGameRect() { return _lastGameRect; }
        internal static string UiLang() { return _uiLang; }
        internal static bool EditMode { get { return _editMode; } }
        internal static Config Cfg { get { return _cfg; } }

        internal static void BeginEditPosition()
        {
            try
            {
                int hiddenForms = 0;
                try
                {
                    foreach (System.Windows.Forms.Form f in System.Windows.Forms.Application.OpenForms)
                    {
                        if (f is SettingsForm && f.Visible) { f.Hide(); hiddenForms++; }
                    }
                }
                catch (Exception ex) { Log("hide settings forms failed: " + ex.Message); }
                if (_settingsForm != null && !_settingsForm.IsDisposed) { _settingsForm.Hide(); hiddenForms++; }
                Log("hiding settings forms = " + hiddenForms);
                if (_editForm != null && !_editForm.IsDisposed) { _editForm.Close(); _editForm = null; }
                _editForm = new EditForm();
                _editMode = true;
                _forceRedraw = true;
                _editForm.ShowInTaskbar = false;
                _editForm.Show();
                _editForm.Activate();
                Log("enter free-position mode");
            }
            catch (Exception ex) { Log("enter edit mode failed: " + ex.Message); }
        }

        internal static void EndEditPosition(bool apply)
        {
            try
            {
                EditForm f = _editForm;
                _editForm = null;
                if (f != null && !f.IsDisposed)
                {
                    if (apply) f.ApplyPosition();
                    f.Close();
                }
            }
            catch { }
            _editMode = false;
            _forceRedraw = true;
            SaveConfig();
            if (apply) Log("HUD position saved");
            Log("settings visible after edit = " + (_settingsForm != null && !_settingsForm.IsDisposed && _settingsForm.Visible));
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

        internal static void Log(string msg)
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
                            data = ParseStats(ReadStatsLines(statsPath), lastStatsWrite);
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

                if (data != null)
                {
                    string nl = Stats.Normalize(data.Lang);
                    if (nl != "auto" && nl != _uiLang) _uiLang = nl;
                }

                bool show = game && (data != null || preview);
                if (preview && data == null) data = PreviewStats();

                // Free-position mode: the WinForms edit panel takes over, so the
                // click-through layered window steps aside but the loop keeps polling.
                if (_editMode)
                {
                    if (visible)
                    {
                        Native.ShowWindow(hwnd, Native.SW_HIDE);
                        visible = false;
                        lastKey = "";
                    }
                    if (!quit.WaitOne(cfg.PollMs)) { /* timeout */ }
                    continue;
                }

                if (show)
                {
                    List<Row> rows = data.Pick(cfg.Lang);
                    _lastRows = rows;
                    List<Row> rowsShown = FilterRows(rows, cfg);
                    if (rowsShown.Count == 0)
                    {
                        if (visible) { Native.ShowWindow(hwnd, Native.SW_HIDE); visible = false; lastKey = ""; }
                        if (!quit.WaitOne(cfg.PollMs)) { /* timeout */ }
                        continue;
                    }
                    string key = KeyOf(rowsShown);
                    Rectangle win = preview ? PrimaryScreen() : WindowRect(target);
                    if (win.Width < 200) { win = PrimaryScreen(); }
                    _lastGameRect = win;
                    int x, y, w, h;
                    Bitmap bmp = Layout(rowsShown, cfg, win, out x, out y, out w, out h);
                    bool moved = (x != curX || y != curY || w != curW || h != curH);
                    bool forced = _forceRedraw;
                    _forceRedraw = false;
                    if (key != lastKey || moved || !visible || forced)
                    {
                        Native.Present(hwnd, bmp, x, y, w, h);
                        bmp.Dispose();
                        curX = x; curY = y; curW = w; curH = h;
                        lastKey = key;
                        current = rowsShown;
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

        // Rows the user hid on the settings page are dropped completely, so the
        // remaining lines shift up instead of leaving a blank slot.
        private static List<Row> FilterRows(List<Row> rows, Config cfg)
        {
            if (rows == null) return new List<Row>();
            if (cfg == null || cfg.HiddenRows.Count == 0) return rows;
            List<Row> outp = new List<Row>(rows.Count);
            for (int i = 0; i < rows.Count; i++)
            {
                if (!cfg.IsHidden(i)) outp.Add(rows[i]);
            }
            return outp;
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
            // Compact layout: every row keeps only one cfg.Gap between its label
            // and its value, so short rows do not get a huge empty middle.
            float maxRow = 0;
            foreach (Row r in rows)
            {
                SizeF sl = pg.MeasureString(r.Label, font, 10000, sf);
                SizeF sv = pg.MeasureString(r.Value, font, 10000, sf);
                float rowW = sl.Width + cfg.Gap + sv.Width;
                if (rowW > maxRow) maxRow = rowW;
            }
            float lineH = font.GetHeight(pg) + cfg.LineGap;
            FontHeaderMeasure();
            w = (int)Math.Ceiling(cfg.PadX * 2 + maxRow) + 6;
            h = (int)Math.Ceiling(cfg.PadY * 2 + rows.Count * lineH) + 4;
            if (w < 10) w = 10; if (h < 10) h = 10;
            x = win.Left + win.Width - w - cfg.MarginRight;
            y = win.Top + (win.Height - h) / 2 + cfg.OffsetY;
            if (x < win.Left + 4) x = win.Left + 4;
            if (x + w > win.Right - 4) x = Math.Max(win.Left + 4, win.Right - 4 - w);
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
                        SizeF sv = g.MeasureString(r.Value, font, 10000, sf);
                        float lx, vx;
                        if (string.Equals(cfg.Align, "left", StringComparison.OrdinalIgnoreCase))
                        {
                            // text flows from the left: label first, value right after it
                            lx = cfg.PadX;
                            vx = lx + sl.Width + cfg.Gap;
                        }
                        else
                        {
                            // text hugs the right edge: value ends at the right border,
                            // label sits right next to it (single gap, nothing in between)
                            float rowRight = cfg.PadX + maxRow;
                            vx = rowRight - sv.Width;
                            lx = vx - cfg.Gap - sl.Width;
                        }
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

        // ------------------------------------------------------------------
        // Settings overlay: a dark borderless panel shown on top of the game.
        // Everything it changes is written to PBZStatsHUD.ini immediately and
        // picked up by the render thread on its next tick.
        // ------------------------------------------------------------------
        private sealed class SettingsForm : Form
        {
            private static readonly Color BgColor = Color.FromArgb(22, 24, 30);
            private static readonly Color TextColor = Color.FromArgb(238, 238, 242);
            private static readonly Color DimColor = Color.FromArgb(150, 152, 160);
            private static readonly Color AccentColor = Color.FromArgb(232, 195, 106);

            private readonly Config _cfg;
            private readonly TextBox _hotkeyBox;
            private readonly Label _hotkeyState;
            private readonly TextBox _fontBox;
            private readonly List<CheckBox> _rowChecks = new List<CheckBox>();
            private readonly List<int> _rowIndexes = new List<int>();
            private Point _dragStart;
            private Point _formStart;
            private bool _dragging;
            private bool _headerDown;

            internal SettingsForm()
            {
                _cfg = Program.Cfg;
                FormBorderStyle = FormBorderStyle.None;
                StartPosition = FormStartPosition.CenterScreen;
                TopMost = true;
                ShowInTaskbar = false;
                BackColor = BgColor;
                KeyPreview = true;
                DoubleBuffered = true;

                Rectangle game = Program.LastGameRect();
                int width = 560;
                int rowsCount = Program.LastRows() != null ? Program.LastRows().Count : 0;
                if (rowsCount <= 0) rowsCount = 5;
                int height = 150 + rowsCount * 30 + 230;
                if (height > 820) height = 820;
                ClientSize = new Size(width, height);
                if (game.Width > 200)
                    Location = new Point(game.Left + (game.Width - width) / 2, game.Top + Math.Max(40, (game.Height - height) / 3));

                Label title = new Label();
                title.Text = UiText.L("title");
                title.ForeColor = TextColor;
                title.BackColor = BgColor;
                title.Font = new Font("Microsoft YaHei UI", 12f, FontStyle.Bold);
                title.AutoSize = true;
                title.Location = new Point(22, 16);
                Controls.Add(title);

                Label ver = new Label();
                ver.Text = "v" + Program.ReadModVersion() + "   " + Program.HotkeyText();
                ver.ForeColor = DimColor;
                ver.BackColor = BgColor;
                ver.AutoSize = true;
                ver.Location = new Point(22, 42);
                Controls.Add(ver);

                Label close = new Label();
                close.Text = "×";
                close.ForeColor = DimColor;
                close.Font = new Font("Segoe UI", 14f, FontStyle.Bold);
                close.AutoSize = false;
                close.TextAlign = ContentAlignment.MiddleCenter;
                close.Size = new Size(34, 30);
                close.Location = new Point(width - 46, 14);
                close.Cursor = Cursors.Hand;
                close.Click += delegate { Close(); };
                Controls.Add(close);

                // --- hotkey -------------------------------------------------
                AddCaption(UiText.L("hotkey"), 22, 78);
                _hotkeyBox = new TextBox();
                _hotkeyBox.ReadOnly = true;
                _hotkeyBox.ShortcutsEnabled = false;
                _hotkeyBox.Font = new Font("Microsoft YaHei UI", 10f);
                _hotkeyBox.BackColor = Color.FromArgb(34, 37, 44);
                _hotkeyBox.ForeColor = AccentColor;
                _hotkeyBox.BorderStyle = BorderStyle.FixedSingle;
                _hotkeyBox.Location = new Point(180, 76);
                _hotkeyBox.Size = new Size(190, 28);
                _hotkeyBox.Text = Program.HotkeyText();
                _hotkeyBox.KeyDown += OnHotkeyKeyDown;
                Controls.Add(_hotkeyBox);

                _hotkeyState = new Label();
                _hotkeyState.ForeColor = DimColor;
                _hotkeyState.AutoSize = true;
                _hotkeyState.Location = new Point(380, 82);
                _hotkeyState.Text = UiText.L("press");
                Controls.Add(_hotkeyState);

                // --- visible rows -------------------------------------------
                int y = 124;
                AddCaption(UiText.L("rows"), 22, y);
                y += 30;
                List<Row> rows = Program.LastRows();
                int count = rows != null && rows.Count > 0 ? rows.Count : 5;
                for (int i = 0; i < count; i++)
                {
                    string label = rows != null && i < rows.Count ? rows[i].Label : UiText.Row((i + 1).ToString());
                    CheckBox cb = new CheckBox();
                    cb.Text = label;
                    cb.ForeColor = TextColor;
                    cb.Font = new Font("Microsoft YaHei UI", 9.5f);
                    cb.AutoSize = true;
                    cb.Location = new Point(30, y + i * 30);
                    cb.Checked = !_cfg.IsHidden(i);
                    int index = i;
                    cb.CheckedChanged += delegate
                    {
                        try
                        {
                            if (cb.Checked) _cfg.HiddenRows.Remove(index);
                            else if (!_cfg.HiddenRows.Contains(index)) _cfg.HiddenRows.Add(index);
                            Program.SaveConfig();
                            _forceRedraw = true;
                        }
                        catch { }
                    };
                    Controls.Add(cb);
                    _rowChecks.Add(cb);
                    _rowIndexes.Add(i);
                }
                y += count * 30 + 14;

                // --- font size ----------------------------------------------
                AddCaption(UiText.L("font"), 22, y);
                Button minus = MakeButton("−", 180, y - 4, 40, 30);
                minus.Click += delegate { ChangeFont(-2); };
                Controls.Add(minus);
                _fontBox = new TextBox();
                _fontBox.ReadOnly = true;
                _fontBox.TextAlign = HorizontalAlignment.Center;
                _fontBox.Font = new Font("Microsoft YaHei UI", 10f);
                _fontBox.BackColor = Color.FromArgb(34, 37, 44);
                _fontBox.ForeColor = AccentColor;
                _fontBox.BorderStyle = BorderStyle.FixedSingle;
                _fontBox.Location = new Point(226, y - 2);
                _fontBox.Size = new Size(64, 28);
                _fontBox.Text = _cfg.FontSize.ToString();
                Controls.Add(_fontBox);
                Button plus = MakeButton("+", 296, y - 4, 40, 30);
                plus.Click += delegate { ChangeFont(2); };
                Controls.Add(plus);
                Label fontHint = new Label();
                fontHint.Text = UiText.L("fonthint");
                fontHint.ForeColor = DimColor;
                fontHint.AutoSize = false;
                fontHint.AutoEllipsis = true;
                fontHint.Font = new Font("Segoe UI", 8.2f);
                fontHint.Size = new Size(Math.Max(120, 560 - 348 - 18), 20);
                fontHint.Location = new Point(348, y + 4);
                Controls.Add(fontHint);
                y += 44;

                // --- anchor (left / right) ----------------------------------
                AddCaption(UiText.L("anchor"), 22, y + 6);
                Button alignRight = MakeButton(UiText.L("right"), 180, y, 96, 32);
                Button alignLeft = MakeButton(UiText.L("left"), 286, y, 96, 32);
                alignRight.Click += delegate { SetAlign("right", alignRight, alignLeft); };
                alignLeft.Click += delegate { SetAlign("left", alignRight, alignLeft); };
                Controls.Add(alignRight);
                Controls.Add(alignLeft);
                MarkAlignButtons(_cfg.Align, alignRight, alignLeft);
                y += 50;

                // --- free position ------------------------------------------
                Button free = MakeButton(UiText.L("free"), 22, y, 300, 38);
                free.BackColor = Color.FromArgb(46, 51, 60);
                free.Font = new Font("Microsoft YaHei UI", 10f, FontStyle.Bold);
                free.Click += delegate
                {
                    try { Hide(); } catch (Exception ex) { Program.Log("hide settings failed: " + ex.Message); }
                    Program.Log("free position clicked, settings visible = " + Visible);
                    Program.BeginEditPosition();
                };
                Controls.Add(free);
                y += 52;

                Label tip = new Label();
                tip.Text = UiText.L("tip");
                tip.ForeColor = DimColor;
                tip.AutoSize = true;
                tip.Location = new Point(22, y);
                Controls.Add(tip);

                MouseDown += delegate(object s, MouseEventArgs e)
                {
                    if (e.Button == MouseButtons.Left && e.Y < 70)
                    {
                        try
                        {
                            Native.ReleaseCapture();
                            Native.SendMessage(Handle, Native.WM_NCLBUTTONDOWN, (IntPtr)Native.HTCAPTION, IntPtr.Zero);
                        }
                        catch { }
                    }
                };
                MouseUp += delegate { _headerDown = false; _dragging = false; };
                KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Close(); };
            }

            private void AddCaption(string text, int x, int y)
            {
                Label l = new Label();
                l.Text = text;
                l.ForeColor = DimColor;
                l.AutoSize = true;
                l.Location = new Point(x, y);
                Controls.Add(l);
            }

            private Button MakeButton(string text, int x, int y, int w, int h)
            {
                Button b = new Button();
                b.Text = text;
                b.Font = new Font("Microsoft YaHei UI", 9.5f);
                b.FlatStyle = FlatStyle.Flat;
                b.FlatAppearance.BorderColor = Color.FromArgb(70, 74, 84);
                b.BackColor = Color.FromArgb(38, 41, 49);
                b.ForeColor = TextColor;
                b.Location = new Point(x, y);
                b.Size = new Size(w, h);
                b.TabStop = false;
                return b;
            }

            private void SetAlign(string align, Button right, Button left)
            {
                try
                {
                    _cfg.Align = align;
                    Program.SaveConfig();
                    _forceRedraw = true;
                    MarkAlignButtons(align, right, left);
                }
                catch { }
            }

            private static void MarkAlignButtons(string align, Button right, Button left)
            {
                bool isLeft = string.Equals(align, "left", StringComparison.OrdinalIgnoreCase);
                if (left != null)
                {
                    left.BackColor = isLeft ? Color.FromArgb(70, 96, 60) : Color.FromArgb(38, 41, 49);
                    left.ForeColor = isLeft ? AccentColor : TextColor;
                }
                if (right != null)
                {
                    right.BackColor = isLeft ? Color.FromArgb(38, 41, 49) : Color.FromArgb(70, 96, 60);
                    right.ForeColor = isLeft ? TextColor : AccentColor;
                }
            }

            private void OnHotkeyKeyDown(object sender, KeyEventArgs e)
            {
                string text = Program.HotkeyFromKey(e.KeyCode, e.Modifiers);
                e.SuppressKeyPress = true;
                e.Handled = true;
                if (text.Length == 0) return;
                _hotkeyBox.Text = text;
                _cfg.SettingsHotkey = text;
                Program.SaveConfig();
                Program.RetryHotkey();
                _hotkeyState.Text = Program.IsHotkeyRegistered()
                    ? UiText.L("active")
                    : UiText.L("failed");
                _hotkeyState.ForeColor = Program.IsHotkeyRegistered() ? AccentColor : Color.FromArgb(230, 120, 110);
            }

            private void ChangeFont(int delta)
            {
                int size = _cfg.FontSize + delta;
                if (size < 8) size = 8;
                if (size > 72) size = 72;
                _cfg.FontSize = size;
                _fontBox.Text = size.ToString();
                Program.SaveConfig();
                _forceRedraw = true;
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                using (Pen p = new Pen(Color.FromArgb(70, 74, 84)))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
                }
                using (SolidBrush b = new SolidBrush(Color.FromArgb(30, 33, 40)))
                {
                    e.Graphics.FillRectangle(b, 0, 0, ClientSize.Width, 68);
                }
                using (Pen p = new Pen(Color.FromArgb(52, 56, 64)))
                {
                    e.Graphics.DrawLine(p, 0, 68, ClientSize.Width, 68);
                }
            }
        }

        // ------------------------------------------------------------------
        // Free-position mode: a real WinForms panel that shows the HUD rows,
        // a font-size strip and a "Done" button. The panel itself is dragged.
        // ------------------------------------------------------------------
        private sealed class EditForm : Form
        {
            private const int StripH = 44;
            private const int DoneH = 46;

            private static readonly Color BgColor = Color.FromArgb(16, 17, 20);
            private static readonly Color PanelColor = Color.FromArgb(30, 33, 40);
            private static readonly Color TextColor = Color.FromArgb(238, 238, 242);
            private static readonly Color DimColor = Color.FromArgb(150, 152, 160);
            private static readonly Color AccentColor = Color.FromArgb(232, 195, 106);

            private readonly Config _cfg;
            private readonly int _origMargin;
            private readonly int _origOffset;
            private readonly int _origFont;
            private readonly Rectangle _game;
            private Bitmap _rowsBmp;
            private int _rowsW;
            private int _rowsH;
            private Rectangle _minusRect;
            private Rectangle _plusRect;
            private Rectangle _doneRect;
            private Rectangle _rowsRect;
            private Point _dragStart;
            private Point _formStart;
            private bool _dragging;

            internal EditForm()
            {
                _cfg = Program.Cfg;
                _origMargin = _cfg.MarginRight;
                _origOffset = _cfg.OffsetY;
                _origFont = _cfg.FontSize;
                _game = Program.LastGameRect();
                if (_game.Width < 200) _game = new Rectangle(0, 0, Screen.PrimaryScreen.Bounds.Width, Screen.PrimaryScreen.Bounds.Height);

                FormBorderStyle = FormBorderStyle.None;
                StartPosition = FormStartPosition.Manual;
                TopMost = true;
                ShowInTaskbar = false;
                BackColor = BgColor;
                DoubleBuffered = true;
                KeyPreview = true;

                Rebuild(false);
                KeyDown += delegate(object s, KeyEventArgs e)
                {
                    if (e.KeyCode != Keys.Escape) return;
                    RestoreOriginal();
                    Program.EndEditPosition(false);
                };
            }

            // Esc cancels the drag session: put back the values we started with.
            private void RestoreOriginal()
            {
                _cfg.MarginRight = _origMargin;
                _cfg.OffsetY = _origOffset;
                _cfg.FontSize = _origFont;
            }

            // Rebuilds the row bitmap and sizes/positions the panel. When the
            // font changes only the size changes; the panel keeps its top-left.
            private void Rebuild(bool reposition)
            {
                if (_rowsBmp != null) { _rowsBmp.Dispose(); _rowsBmp = null; }
                List<Row> rows = Program.FilterRowsPublic(Program.LastRows(), _cfg);
                int x, y, w, h;
                Bitmap bmp = Program.Layout(rows, _cfg, _game, out x, out y, out w, out h);
                _rowsBmp = bmp;
                _rowsW = w;
                _rowsH = h;

                int width = Math.Max(w, 330);
                ClientSize = new Size(width, h + StripH + DoneH + 10);
                _rowsRect = new Rectangle(0, 0, w, h);
                int stripY = h + 6;
                _minusRect = new Rectangle(96, stripY + 8, 34, 28);
                _plusRect = new Rectangle(212, stripY + 8, 34, 28);
                _doneRect = new Rectangle(0, ClientSize.Height - DoneH, ClientSize.Width, DoneH);

                if (reposition || Location.X == 0 && Location.Y == 0)
                {
                    int left = _game.Right - w - _cfg.MarginRight;
                    int top = _game.Top + (_game.Height - h) / 2 + _cfg.OffsetY;
                    if (left < _game.Left) left = _game.Left + 8;
                    if (top < _game.Top) top = _game.Top + 8;
                    Location = new Point(left, top);
                }
                Invalidate();
            }

            internal void ApplyPosition()
            {
                int left = Left;
                int top = Top;
                int margin = _game.Right - (left + _rowsW);
                if (margin < 0) margin = 0;
                _cfg.MarginRight = margin;
                _cfg.OffsetY = top - (_game.Top + (_game.Height - _rowsH) / 2);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                Graphics g = e.Graphics;
                if (_rowsBmp != null) g.DrawImageUnscaled(_rowsBmp, 0, 0);

                int stripY = _rowsH + 6;
                using (SolidBrush b = new SolidBrush(PanelColor)) g.FillRectangle(b, 0, stripY, ClientSize.Width, StripH);
                using (SolidBrush b = new SolidBrush(BgColor)) g.FillRectangle(b, _doneRect);
                using (Pen p = new Pen(Color.FromArgb(70, 74, 84))) g.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);

                Font ui = new Font("Microsoft YaHei UI", 9.5f);
                Font uiBold = new Font("Microsoft YaHei UI", 10f, FontStyle.Bold);
                try
                {
                    using (SolidBrush t = new SolidBrush(TextColor))
                    using (SolidBrush d = new SolidBrush(DimColor))
                    using (SolidBrush a = new SolidBrush(AccentColor))
                    {
                        g.DrawString(UiText.L("fontbar"), ui, t, 14, stripY + 13);
                        g.DrawString("−", uiBold, t, _minusRect.X + 10, stripY + 10);
                        g.DrawString("+", uiBold, t, _plusRect.X + 10, stripY + 10);
                        g.DrawString(_cfg.FontSize.ToString(), ui, a, 142, stripY + 13);
                        g.DrawString("拖动调整位置，点下方“完成”保存 / drag to move, click Done", ui, d, 258, stripY + 13);
                    }
                    using (Pen p = new Pen(Color.FromArgb(80, 84, 94))) g.DrawRectangle(p, _minusRect);
                    using (Pen p = new Pen(Color.FromArgb(80, 84, 94))) g.DrawRectangle(p, _plusRect);
                    StringFormat sf = new StringFormat();
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    using (SolidBrush a = new SolidBrush(AccentColor))
                        g.DrawString(UiText.L("done"), uiBold, a, _doneRect, sf);
                    using (Pen p = new Pen(Color.FromArgb(90, 95, 105)))
                        g.DrawLine(p, _doneRect.Left + 12, _doneRect.Top, _doneRect.Right - 12, _doneRect.Top);
                    sf.Dispose();
                }
                finally
                {
                    ui.Dispose();
                    uiBold.Dispose();
                }
            }

            protected override void OnMouseDown(MouseEventArgs e)
            {
                base.OnMouseDown(e);
                if (e.Button != MouseButtons.Left) return;
                if (_doneRect.Contains(e.Location)) { Program.EndEditPosition(true); return; }
                if (_minusRect.Contains(e.Location)) { ChangeFont(-2); return; }
                if (_plusRect.Contains(e.Location)) { ChangeFont(2); return; }
                // Let Windows drag the window natively: this uses its own modal move loop,
                // so it behaves exactly like dragging a normal title bar (and it survives
                // synthetic input, unlike a manual Location-based drag).
                Program.Log("edit drag start, caption=" + Handle);
                _dragging = true;
                Cursor = Cursors.SizeAll;
                try
                {
                    Native.ReleaseCapture();
                    Native.SendMessage(Handle, Native.WM_NCLBUTTONDOWN, (IntPtr)Native.HTCAPTION, IntPtr.Zero);
                }
                catch (Exception ex) { Program.Log("edit drag failed: " + ex.Message); }
                _dragging = false;
                Cursor = _rowsRect.Contains(e.Location) ? Cursors.SizeAll : Cursors.Default;
            }

            protected override void OnMouseMove(MouseEventArgs e)
            {
                base.OnMouseMove(e);
                if (_dragging)
                {
                    Point now = Cursor.Position;
                    Location = new Point(_formStart.X + (now.X - _dragStart.X), _formStart.Y + (now.Y - _dragStart.Y));
                }
                else
                {
                    Cursor = _rowsRect.Contains(e.Location) ? Cursors.SizeAll : Cursors.Default;
                }
            }

            protected override void OnMouseUp(MouseEventArgs e)
            {
                base.OnMouseUp(e);
                _dragging = false;
                Cursor = Cursors.Default;
            }

            private void ChangeFont(int delta)
            {
                int size = _cfg.FontSize + delta;
                if (size < 8) size = 8;
                if (size > 72) size = 72;
                _cfg.FontSize = size;
                Rebuild(false);
                Program.SaveConfig();
            }

            protected override void OnFormClosed(FormClosedEventArgs e)
            {
                try { if (_rowsBmp != null) { _rowsBmp.Dispose(); _rowsBmp = null; } } catch { }
                base.OnFormClosed(e);
            }
        }

        // The edit panel draws the same rows as the HUD, so it uses the same
        // filter helper from the worker side.
        internal static List<Row> FilterRowsPublic(List<Row> rows, Config cfg)
        {
            return FilterRows(rows, cfg);
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
        public const int WM_HOTKEY = 0x0312;
        public const int WM_NCLBUTTONDOWN = 0x00A1;
        public const int HTCAPTION = 2;
        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_SHIFT = 0x0004;
        public const uint MOD_WIN = 0x0008;

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

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
            int total = w * h * 4;
            byte[] buf = new byte[total];
            System.Drawing.Imaging.BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h),
                System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            try
            {
                Marshal.Copy(bd.Scan0, buf, 0, total);
            }
            finally
            {
                bmp.UnlockBits(bd);
            }
            for (int o = 0; o < total; o += 4)
            {
                int a = buf[o + 3];
                if (a == 255) continue;
                if (a == 0)
                {
                    buf[o] = 0; buf[o + 1] = 0; buf[o + 2] = 0; buf[o + 3] = 0;
                    continue;
                }
                buf[o] = (byte)(buf[o] * a / 255);
                buf[o + 1] = (byte)(buf[o + 1] * a / 255);
                buf[o + 2] = (byte)(buf[o + 2] * a / 255);
            }
            Marshal.Copy(buf, 0, dstBits, total);
        }
    }
}

// ---------------------------------------------------------------------------
// PowerShell host entry: the same HUD can run without any exe on disk.
// run.ps1 compiles this file with Add-Type and calls PsHost.Start(); the UI
// gets a proper STA thread, exactly like the compiled entry point does.
// ---------------------------------------------------------------------------
namespace PBZStatsHud
{
    public static class PsHost
    {
        public static void Start(string[] args)
        {
            string[] a = args ?? new string[0];
            System.Threading.Thread t = new System.Threading.Thread(delegate()
            {
                try
                {
                    System.Reflection.MethodInfo mi = typeof(Program).GetMethod("Main",
                        System.Reflection.BindingFlags.Static |
                        System.Reflection.BindingFlags.NonPublic |
                        System.Reflection.BindingFlags.Public);
                    if (mi != null) mi.Invoke(null, new object[] { a });
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine("[PBZStats] host error: " + ex);
                }
            });
            t.IsBackground = false;
            t.SetApartmentState(System.Threading.ApartmentState.STA);
            t.Start();
            t.Join();
        }
    }
}
