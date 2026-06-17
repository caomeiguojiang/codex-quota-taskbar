using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace CodexQuotaTaskbar
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                NativeDpi.Enable();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                Options options = Options.Parse(args);
                AppPaths.Ensure();
                Logger.Info("Native runtime starting. PID=" + Process.GetCurrentProcess().Id);

                if (options.SelfTest)
                {
                    NativeSelfTests.Run();
                    return 0;
                }

                Settings settings = Settings.Load();
                if (options.Configure)
                {
                    Settings edited = SettingsDialog.Show(settings);
                    if (edited == null)
                    {
                        return 0;
                    }
                    settings = edited;
                    settings.Save();
                }

                if (options.Once)
                {
                    QuotaService quota = new QuotaService(options);
                    RateLimitSummary summary = options.MockQuota ? RateLimitSummary.Mock() : quota.Refresh();
                    Console.WriteLine(summary.FormatOnce(settings.Language));
                    quota.Dispose();
                    return 0;
                }

                if (options.VisualQa)
                {
                    using (VisualQaContext context = new VisualQaContext(options, settings))
                    {
                        Application.Run(context);
                    }
                    return 0;
                }

                using (MonitorContext context = new MonitorContext(options, settings))
                {
                    Application.Run(context);
                }
                return 0;
            }
            catch (Exception ex)
            {
                Logger.Error("Fatal native runtime error: " + ex);
                try { Console.Error.WriteLine(ex.Message); } catch { }
                return 1;
            }
        }
    }

    internal sealed class Options
    {
        public int PollSeconds = 2;
        public int QuotaRefreshSeconds = 15;
        public bool AllScreens;
        public bool Configure;
        public bool NoConfig;
        public bool Once;
        public bool MockQuota;
        public bool VisualQa;
        public bool SelfTest;
        public string VisualQaOutputDir = "";
        public string CodexExe = "";

        public static Options Parse(string[] args)
        {
            Options options = new Options();
            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i];
                string key = arg.TrimStart('-', '/').ToLowerInvariant();
                if (key == "poll-seconds" || key == "pollseconds")
                {
                    options.PollSeconds = ReadInt(args, ref i, options.PollSeconds);
                }
                else if (key == "quota-refresh-seconds" || key == "quotarefreshseconds")
                {
                    options.QuotaRefreshSeconds = ReadInt(args, ref i, options.QuotaRefreshSeconds);
                }
                else if (key == "all-screens" || key == "allscreens")
                {
                    options.AllScreens = true;
                }
                else if (key == "configure" || key == "config")
                {
                    options.Configure = true;
                }
                else if (key == "no-config" || key == "noconfig")
                {
                    options.NoConfig = true;
                }
                else if (key == "once")
                {
                    options.Once = true;
                }
                else if (key == "mock-quota" || key == "mockquota")
                {
                    options.MockQuota = true;
                }
                else if (key == "visual-qa" || key == "visualqa")
                {
                    options.VisualQa = true;
                }
                else if (key == "self-test" || key == "selftest")
                {
                    options.SelfTest = true;
                }
                else if (key == "visual-qa-output-dir" || key == "visualqaoutputdir")
                {
                    options.VisualQaOutputDir = ReadString(args, ref i, "");
                }
                else if (key == "codex-exe" || key == "codexexe")
                {
                    options.CodexExe = ReadString(args, ref i, "");
                }
            }
            if (options.PollSeconds < 1) options.PollSeconds = 1;
            if (options.QuotaRefreshSeconds < 5) options.QuotaRefreshSeconds = 5;
            return options;
        }

        private static int ReadInt(string[] args, ref int index, int fallback)
        {
            string value = ReadString(args, ref index, null);
            int parsed;
            return int.TryParse(value, out parsed) ? parsed : fallback;
        }

        private static string ReadString(string[] args, ref int index, string fallback)
        {
            if (index + 1 >= args.Length) return fallback;
            index++;
            return args[index];
        }
    }

    internal static class AppPaths
    {
        public static readonly string AppData = BuildPath(Environment.SpecialFolder.ApplicationData);
        public static readonly string LocalData = BuildPath(Environment.SpecialFolder.LocalApplicationData);
        public static readonly string Runtime = Path.Combine(LocalData, "runtime");
        public static readonly string Logs = Path.Combine(LocalData, "logs");
        public static readonly string SettingsPath = Path.Combine(AppData, "settings.json");
        public static readonly string MonitorLog = Path.Combine(Logs, "monitor.log");
        public static readonly string OverlayLog = Path.Combine(Logs, "overlay.log");
        public static readonly string RuntimeStatePath = Path.Combine(Runtime, "native-" + Process.GetCurrentProcess().Id + ".json");
        public static readonly string ActivityStatePath = Path.Combine(Runtime, "activity.json");

        public static void Ensure()
        {
            Directory.CreateDirectory(AppData);
            Directory.CreateDirectory(LocalData);
            Directory.CreateDirectory(Runtime);
            Directory.CreateDirectory(Logs);
            CleanupStaleRuntimeState();
        }

        private static void CleanupStaleRuntimeState()
        {
            foreach (string path in Directory.GetFiles(Runtime, "native-*.json"))
            {
                try
                {
                    JavaScriptSerializer serializer = new JavaScriptSerializer();
                    Dictionary<string, object> data = serializer.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
                    if (data == null || !data.ContainsKey("NativePid")) continue;
                    int nativePid = Convert.ToInt32(data["NativePid"], CultureInfo.InvariantCulture);
                    Process process = Process.GetProcessById(nativePid);
                    try { process.Dispose(); } catch { }
                }
                catch
                {
                    try { File.Delete(path); } catch { }
                }
            }
        }

        private static string BuildPath(Environment.SpecialFolder folder)
        {
            string basePath = Environment.GetFolderPath(folder);
            if (String.IsNullOrEmpty(basePath))
            {
                basePath = AppDomain.CurrentDomain.BaseDirectory;
            }
            return Path.Combine(basePath, "CodexQuotaTaskbar");
        }
    }

    internal static class Logger
    {
        public static void Info(string message)
        {
            Write(AppPaths.MonitorLog, message);
        }

        public static void Overlay(string message)
        {
            Write(AppPaths.OverlayLog, message);
        }

        public static void Error(string message)
        {
            Write(AppPaths.MonitorLog, "ERROR " + message);
        }

        private static void Write(string path, string message)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " " + message + Environment.NewLine, Encoding.UTF8);
            }
            catch
            {
            }
        }
    }

    internal sealed class Settings
    {
        public string TargetMonitorDevice = "";
        public int XOffset;
        public int VerticalOffset;
        public string Language = DefaultLanguage();
        public bool ShowActivityIcon;

        public static Settings Load()
        {
            Settings settings = new Settings();
            Screen defaultScreen = Screen.AllScreens.FirstOrDefault(s => !s.Primary) ?? Screen.PrimaryScreen;
            if (defaultScreen != null) settings.TargetMonitorDevice = defaultScreen.DeviceName;

            if (!File.Exists(AppPaths.SettingsPath))
            {
                return settings;
            }

            try
            {
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                Dictionary<string, object> data = serializer.DeserializeObject(File.ReadAllText(AppPaths.SettingsPath, Encoding.UTF8)) as Dictionary<string, object>;
                if (data == null) return settings;
                if (data.ContainsKey("TargetMonitorDevice") && data["TargetMonitorDevice"] != null) settings.TargetMonitorDevice = Convert.ToString(data["TargetMonitorDevice"], CultureInfo.InvariantCulture);
                if (data.ContainsKey("XOffset") && data["XOffset"] != null) settings.XOffset = Convert.ToInt32(data["XOffset"], CultureInfo.InvariantCulture);
                if (data.ContainsKey("VerticalOffset") && data["VerticalOffset"] != null) settings.VerticalOffset = Convert.ToInt32(data["VerticalOffset"], CultureInfo.InvariantCulture);
                if (data.ContainsKey("Language") && data["Language"] != null) settings.Language = NormalizeLanguage(Convert.ToString(data["Language"], CultureInfo.InvariantCulture));
                if (data.ContainsKey("ShowActivityIcon") && data["ShowActivityIcon"] != null) settings.ShowActivityIcon = Convert.ToBoolean(data["ShowActivityIcon"], CultureInfo.InvariantCulture);
            }
            catch (Exception ex)
            {
                Logger.Error("Settings load failed: " + ex.Message);
            }
            return settings;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(AppPaths.SettingsPath));
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                Dictionary<string, object> data = new Dictionary<string, object>();
                data["TargetMonitorDevice"] = TargetMonitorDevice ?? "";
                data["XOffset"] = XOffset;
                data["VerticalOffset"] = VerticalOffset;
                data["Language"] = NormalizeLanguage(Language);
                data["ShowActivityIcon"] = ShowActivityIcon;
                File.WriteAllText(AppPaths.SettingsPath, serializer.Serialize(data), Encoding.UTF8);
                Logger.Overlay("Settings saved to " + AppPaths.SettingsPath);
            }
            catch (Exception ex)
            {
                Logger.Error("Settings save failed: " + ex.Message);
            }
        }

        public static string DefaultLanguage()
        {
            return NormalizeLanguage(CultureInfo.CurrentUICulture.Name);
        }

        public static string NormalizeLanguage(string language)
        {
            if (String.IsNullOrWhiteSpace(language)) return "en-US";
            if (language.StartsWith("zh", StringComparison.OrdinalIgnoreCase)) return "zh-CN";
            if (language.StartsWith("en", StringComparison.OrdinalIgnoreCase)) return "en-US";
            return "en-US";
        }

        public string T(string key)
        {
            return Text.For(key, Language);
        }
    }

    internal static class Text
    {
        public static string For(string key, string language)
        {
            bool en = Settings.NormalizeLanguage(language) == "en-US";
            if (en)
            {
                switch (key)
                {
                    case "SettingsTitle": return "Codex quota taskbar settings";
                    case "General": return "General";
                    case "Display": return "Display";
                    case "About": return "About";
                    case "DisplayLanguage": return "Display language:";
                    case "Monitor": return "Monitor:";
                    case "ShowActivityIcon": return "Show Codex status icon";
                    case "Primary": return " primary";
                    case "PrimaryShort": return " primary";
                    case "SelectedMonitor": return "Selected monitor";
                    case "Device": return "Device:";
                    case "Bounds": return "Bounds:";
                    case "WorkingArea": return "Working area:";
                    case "SettingsFile": return "Settings file";
                    case "Path": return "Path:";
                    case "OpenFolder": return "Open folder";
                    case "OpenLogs": return "Open log folder";
                    case "RuntimeInfo": return "Runtime information";
                    case "Version": return "Version:";
                    case "InstallPath": return "Install path:";
                    case "Save": return "Save";
                    case "Cancel": return "Cancel";
                    case "RestoreDefault": return "Restore default";
                    case "SettingsMenu": return "Settings...";
                    case "RefreshNow": return "Refresh now";
                    case "RefreshQuota": return "Refresh quota";
                    case "Exit": return "Exit";
                    case "OpenCodex": return "Open Codex";
                    case "SwitchMonitor": return "Switch monitor";
                    case "Screen": return "Screen";
                    case "Loading": return "Loading...";
                    case "Running": return "Codex is open. Overlay is running.";
                    case "Waiting": return "Waiting for Codex Desktop";
                    case "Starting": return "Starting...";
                    case "Unavailable": return "Codex quota unavailable";
                    case "Remaining": return "Remaining";
                    case "QuotaRemaining": return "Remaining";
                    case "Reset": return "reset";
                    case "FiveLeft": return "5H left";
                    case "WeekLeft": return "Week left";
                }
            }
            else
            {
                switch (key)
                {
                    case "SettingsTitle": return "Codex 额度任务栏设置";
                    case "General": return "常规";
                    case "Display": return "显示";
                    case "About": return "关于";
                    case "DisplayLanguage": return "显示语言:";
                    case "Monitor": return "显示器:";
                    case "ShowActivityIcon": return "\u663e\u793a Codex \u72b6\u6001\u56fe\u6807";
                    case "Primary": return " 主屏";
                    case "PrimaryShort": return " 主";
                    case "SelectedMonitor": return "选中的显示器";
                    case "Device": return "设备:";
                    case "Bounds": return "边界:";
                    case "WorkingArea": return "工作区:";
                    case "SettingsFile": return "配置文件位置";
                    case "Path": return "路径:";
                    case "OpenFolder": return "打开所在文件夹";
                    case "OpenLogs": return "打开日志文件夹";
                    case "RuntimeInfo": return "运行时信息";
                    case "Version": return "版本:";
                    case "InstallPath": return "安装路径:";
                    case "Save": return "保存";
                    case "Cancel": return "取消";
                    case "RestoreDefault": return "恢复默认";
                    case "SettingsMenu": return "设置...";
                    case "RefreshNow": return "立即刷新";
                    case "RefreshQuota": return "刷新额度";
                    case "Exit": return "退出";
                    case "OpenCodex": return "打开 Codex";
                    case "SwitchMonitor": return "切换显示器";
                    case "Screen": return "屏幕";
                    case "Loading": return "加载中...";
                    case "Running": return "Codex 已打开，额度浮层运行中";
                    case "Waiting": return "等待 Codex Desktop 打开";
                    case "Starting": return "正在启动...";
                    case "Unavailable": return "Codex 额度不可用";
                    case "Remaining": return "剩余";
                    case "QuotaRemaining": return "剩余可用额度";
                    case "Reset": return "重置";
                    case "FiveLeft": return "5H 剩余";
                    case "WeekLeft": return "本周剩余";
                }
            }
            return key;
        }
    }

    internal sealed class RateLimitSummary
    {
        public double FiveRemaining;
        public double WeekRemaining;
        public DateTime? FiveReset;
        public DateTime? WeekReset;
        public DateTime CheckedAt = DateTime.Now;

        public static RateLimitSummary Mock()
        {
            return new RateLimitSummary
            {
                FiveRemaining = 72.4,
                WeekRemaining = 41.8,
                FiveReset = DateTime.Now.AddHours(2.5),
                WeekReset = DateTime.Now.AddDays(2),
                CheckedAt = DateTime.Now
            };
        }

        public string FormatOnce(string language)
        {
            return Text.For("FiveLeft", language) + ": " + FiveRemaining.ToString("0.0", CultureInfo.InvariantCulture) + "% (" + Text.For("Reset", language) + " " + FormatReset(FiveReset) + "); " +
                   Text.For("WeekLeft", language) + ": " + WeekRemaining.ToString("0.0", CultureInfo.InvariantCulture) + "% (" + Text.For("Reset", language) + " " + FormatReset(WeekReset) + ")";
        }

        public static string FormatReset(DateTime? value)
        {
            if (!value.HasValue) return "--:--";
            if ((value.Value - DateTime.Now).TotalHours > 24) return value.Value.ToString("MM-dd", CultureInfo.InvariantCulture);
            return value.Value.ToString("HH:mm", CultureInfo.InvariantCulture);
        }
    }

    internal enum CodexActivityState
    {
        Idle,
        Running,
        Complete
    }

    internal sealed class CodexActivityService : IDisposable
    {
        private const double BusyCpuSecondsPerSample = 0.12;
        private readonly Dictionary<int, double> _lastCpuByPid = new Dictionary<int, double>();
        private readonly CodexIpcActivitySource _ipcSource = new CodexIpcActivitySource();
        private CodexActivityState _state = CodexActivityState.Idle;
        private DateTime _completeUntil = DateTime.MinValue;

        public CodexActivityState Sample(int excludedAppServerPid)
        {
            CodexActivityState ipcState;
            if (_ipcSource.TrySample(out ipcState))
            {
                _state = ipcState;
                _completeUntil = DateTime.MinValue;
                return _state;
            }

            DateTime now = DateTime.Now;
            List<int> seen = new List<int>();
            double cpuDelta = 0;

            foreach (Process process in GetCodexProcesses())
            {
                try
                {
                    if (process.Id == excludedAppServerPid) continue;
                    seen.Add(process.Id);
                    double cpu = process.TotalProcessorTime.TotalSeconds;
                    double previous;
                    if (_lastCpuByPid.TryGetValue(process.Id, out previous))
                    {
                        cpuDelta += Math.Max(0, cpu - previous);
                    }
                    _lastCpuByPid[process.Id] = cpu;
                }
                catch
                {
                }
                finally
                {
                    try { process.Dispose(); } catch { }
                }
            }

            foreach (int pid in _lastCpuByPid.Keys.ToArray())
            {
                if (!seen.Contains(pid)) _lastCpuByPid.Remove(pid);
            }

            if (seen.Count == 0)
            {
                _state = CodexActivityState.Idle;
                _completeUntil = DateTime.MinValue;
                return _state;
            }

            if (cpuDelta >= BusyCpuSecondsPerSample)
            {
                _state = CodexActivityState.Running;
                _completeUntil = DateTime.MinValue;
                return _state;
            }

            if (_state == CodexActivityState.Running)
            {
                _state = CodexActivityState.Complete;
                _completeUntil = now.AddSeconds(7);
                return _state;
            }

            if (_state == CodexActivityState.Complete && now < _completeUntil)
            {
                return _state;
            }

            _state = CodexActivityState.Idle;
            _completeUntil = DateTime.MinValue;
            return _state;
        }

        private static IEnumerable<Process> GetCodexProcesses()
        {
            foreach (Process process in Process.GetProcessesByName("Codex")) yield return process;
            foreach (Process process in Process.GetProcessesByName("codex")) yield return process;
        }

        public void Dispose()
        {
            _ipcSource.Dispose();
        }
    }

    internal sealed class CodexIpcActivitySource : IDisposable
    {
        private const string PipeName = "codex-ipc";
        private const int MaxFrameBytes = 256 * 1024 * 1024;
        private static readonly TimeSpan CompleteIconDuration = TimeSpan.FromSeconds(5);
        private static readonly TimeSpan ReconnectDelay = TimeSpan.FromSeconds(3);
        private static readonly TimeSpan ConversationTtl = TimeSpan.FromMinutes(30);

        private readonly object _sync = new object();
        private readonly Dictionary<string, ConversationActivity> _conversations = new Dictionary<string, ConversationActivity>();
        private Thread _thread;
        private bool _started;
        private bool _disposed;
        private bool _connected;
        private bool _hasLiveSignal;
        private DateTime _lastMessageAt = DateTime.MinValue;
        private DateTime _completeUntil = DateTime.MinValue;
        private CodexActivityState _state = CodexActivityState.Idle;
        private string _clientId = "initializing-client";
        private DateTime _nextErrorLogAt = DateTime.MinValue;
        private DateTime _nextDebugWriteAt = DateTime.MinValue;

        public bool TrySample(out CodexActivityState state)
        {
            EnsureStarted();
            lock (_sync)
            {
                DateTime now = DateTime.Now;
                ExpireCompleteIfNeededLocked(now);

                if (!_connected || !_hasLiveSignal)
                {
                    state = CodexActivityState.Idle;
                    return false;
                }

                state = _state;
                WriteDebugStatusLocked("ipc", state, now);
                return true;
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                _disposed = true;
            }
        }

        private void EnsureStarted()
        {
            lock (_sync)
            {
                if (_started) return;
                _started = true;
                _thread = new Thread(Run);
                _thread.Name = "Codex IPC activity reader";
                _thread.IsBackground = true;
                _thread.Start();
            }
        }

        private void Run()
        {
            while (!IsDisposed())
            {
                try
                {
                    ReadLoop();
                    MarkDisconnected("pipe closed");
                    SleepReconnectDelay();
                }
                catch (Exception ex)
                {
                    MarkDisconnected(ex.Message);
                    SleepReconnectDelay();
                }
            }
        }

        private void ReadLoop()
        {
            using (NamedPipeClientStream pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous))
            {
                pipe.Connect(2000);
                MarkConnected();
                string requestId = Guid.NewGuid().ToString();
                SendFrame(pipe, new Dictionary<string, object>
                {
                    {"type", "request"},
                    {"requestId", requestId},
                    {"sourceClientId", _clientId},
                    {"version", 0},
                    {"method", "initialize"},
                    {"params", new Dictionary<string, object>{{"clientType", "codex-quota-taskbar"}}}
                });

                while (!IsDisposed() && pipe.IsConnected)
                {
                    Dictionary<string, object> message = ReadFrame(pipe);
                    if (message != null) HandleMessage(pipe, message);
                }
            }
        }

        private void HandleMessage(Stream stream, Dictionary<string, object> message)
        {
            string type = GetString(message, "type");
            if (type == "response")
            {
                HandleResponse(message);
                TouchLiveSignal();
                return;
            }

            if (type == "client-discovery-request")
            {
                object requestId;
                if (message.TryGetValue("requestId", out requestId) && requestId != null)
                {
                    SendFrame(stream, new Dictionary<string, object>
                    {
                        {"type", "client-discovery-response"},
                        {"requestId", requestId.ToString()},
                        {"response", new Dictionary<string, object>{{"canHandle", false}}}
                    });
                }
                TouchLiveSignal();
                return;
            }

            if (type == "broadcast" && GetString(message, "method") == "thread-stream-state-changed")
            {
                Dictionary<string, object> parameters = AsDictionary(GetValue(message, "params"));
                if (parameters != null) HandleThreadStreamStateChanged(parameters);
                TouchLiveSignal();
            }
        }

        private void HandleResponse(Dictionary<string, object> message)
        {
            if (GetString(message, "method") != "initialize") return;
            Dictionary<string, object> result = AsDictionary(GetValue(message, "result"));
            string clientId = result == null ? "" : GetString(result, "clientId");
            if (clientId.Length == 0) return;
            lock (_sync)
            {
                _clientId = clientId;
            }
        }

        private void HandleThreadStreamStateChanged(Dictionary<string, object> parameters)
        {
            string conversationId = GetString(parameters, "conversationId");
            if (conversationId.Length == 0) return;

            Dictionary<string, object> change = AsDictionary(GetValue(parameters, "change"));
            if (change == null) return;

            string changeType = GetString(change, "type");
            if (changeType == "snapshot")
            {
                Dictionary<string, object> conversationState = AsDictionary(GetValue(change, "conversationState"));
                if (conversationState == null) return;
                ApplyConversationSnapshot(conversationId, conversationState);
                return;
            }

            if (changeType == "patches")
            {
                ApplyConversationPatches(conversationId, AsArray(GetValue(change, "patches")));
            }
        }

        private void ApplyConversationSnapshot(string conversationId, Dictionary<string, object> conversationState)
        {
            object[] turns = AsArray(GetValue(conversationState, "turns"));
            ConversationActivity next = new ConversationActivity();
            next.ThreadRuntimeActive = IsThreadRuntimeActive(AsDictionary(GetValue(conversationState, "threadRuntimeStatus")));

            for (int i = 0; i < turns.Length; i++)
            {
                Dictionary<string, object> turn = AsDictionary(turns[i]);
                if (turn == null) continue;
                next.Turns.Add(TurnActivity.FromDictionary(turn));
            }

            StoreConversation(conversationId, next, true);
        }

        private void ApplyConversationPatches(string conversationId, object[] patches)
        {
            if (patches.Length == 0) return;

            lock (_sync)
            {
                DateTime now = DateTime.Now;
                RemoveStaleConversations(now);
                bool wasAnyRunning = AnyConversationRunningLocked();

                ConversationActivity conversation;
                if (!_conversations.TryGetValue(conversationId, out conversation))
                {
                    conversation = new ConversationActivity();
                }

                bool touched = false;
                for (int i = 0; i < patches.Length; i++)
                {
                    Dictionary<string, object> patch = AsDictionary(patches[i]);
                    if (patch == null) continue;
                    touched = ApplyPatchToConversation(conversation, patch) || touched;
                }

                if (!touched) return;
                conversation.UpdatedAt = now;
                _conversations[conversationId] = conversation;
                RecalculateStateLocked(wasAnyRunning, now);
            }
        }

        private void StoreConversation(string conversationId, ConversationActivity conversation, bool authoritative)
        {
            lock (_sync)
            {
                DateTime now = DateTime.Now;
                RemoveStaleConversations(now);
                bool wasAnyRunning = AnyConversationRunningLocked();
                conversation.Authoritative = authoritative || conversation.Authoritative;
                conversation.UpdatedAt = now;
                _conversations[conversationId] = conversation;
                RecalculateStateLocked(wasAnyRunning, now);
            }
        }

        private bool ApplyPatchToConversation(ConversationActivity conversation, Dictionary<string, object> patch)
        {
            string op = GetString(patch, "op");
            object[] path = AsArray(GetValue(patch, "path"));
            if (path.Length == 0) return false;

            string root = ToPathSegment(path[0]);
            if (root == "threadRuntimeStatus")
            {
                if (op == "remove")
                {
                    conversation.ThreadRuntimeActive = false;
                    return true;
                }
                if (path.Length == 1)
                {
                    conversation.ThreadRuntimeActive = IsThreadRuntimeActive(AsDictionary(GetValue(patch, "value")));
                    return true;
                }
                if (path.Length >= 2 && ToPathSegment(path[1]) == "type")
                {
                    conversation.ThreadRuntimeActive = IsActiveRuntimeStatus(Convert.ToString(GetValue(patch, "value"), CultureInfo.InvariantCulture));
                    return true;
                }
                return false;
            }

            if (root != "turns" || path.Length < 2) return false;
            int turnIndex;
            if (!TryParsePathIndex(path[1], out turnIndex)) return false;

            if (path.Length == 2)
            {
                if (op == "remove")
                {
                    if (turnIndex < 0 || turnIndex >= conversation.Turns.Count) return false;
                    conversation.Turns.RemoveAt(turnIndex);
                    return true;
                }

                Dictionary<string, object> value = AsDictionary(GetValue(patch, "value"));
                if (value == null) return false;
                TurnActivity turn = TurnActivity.FromDictionary(value);
                SetTurnAtIndex(conversation.Turns, turnIndex, turn, op == "add");
                return true;
            }

            TurnActivity existing = EnsureTurnAtIndex(conversation.Turns, turnIndex);
            string field = ToPathSegment(path[2]);
            if (field == "status")
            {
                existing.Status = op == "remove" ? "" : Convert.ToString(GetValue(patch, "value"), CultureInfo.InvariantCulture) ?? "";
                return true;
            }
            if (field == "turnId")
            {
                existing.TurnId = op == "remove" ? "" : Convert.ToString(GetValue(patch, "value"), CultureInfo.InvariantCulture) ?? "";
                return true;
            }
            return false;
        }

        private void RecalculateStateLocked(bool wasAnyRunning, DateTime now)
        {
            bool anyRunning = AnyConversationRunningLocked();
            if (anyRunning)
            {
                SetStateLocked(CodexActivityState.Running, now);
                _completeUntil = DateTime.MinValue;
                return;
            }

            if (wasAnyRunning)
            {
                SetStateLocked(CodexActivityState.Complete, now);
                _completeUntil = now.Add(CompleteIconDuration);
                return;
            }

            if (_state == CodexActivityState.Complete && now < _completeUntil)
            {
                return;
            }

            SetStateLocked(CodexActivityState.Idle, now);
            _completeUntil = DateTime.MinValue;
        }

        private void ExpireCompleteIfNeededLocked(DateTime now)
        {
            if (_state == CodexActivityState.Complete && now >= _completeUntil)
            {
                _state = CodexActivityState.Idle;
                _completeUntil = DateTime.MinValue;
            }
        }

        private void SetStateLocked(CodexActivityState state, DateTime now)
        {
            if (_state != state)
            {
                Logger.Info("Codex IPC activity state changed: " + state.ToString() +
                    " activeConversations=" + _conversations.Values.Count(c => c.Running).ToString(CultureInfo.InvariantCulture) +
                    " knownConversations=" + _conversations.Count.ToString(CultureInfo.InvariantCulture));
            }
            _state = state;
            _lastMessageAt = now;
            _hasLiveSignal = true;
        }

        private bool AnyConversationRunningLocked()
        {
            return _conversations.Values.Any(c => c.Running);
        }

        private void TouchLiveSignal()
        {
            lock (_sync)
            {
                _hasLiveSignal = true;
                _lastMessageAt = DateTime.Now;
            }
        }

        private void MarkConnected()
        {
            lock (_sync)
            {
                _connected = true;
            }
        }

        private void MarkDisconnected(string reason)
        {
            lock (_sync)
            {
                _connected = false;
                _hasLiveSignal = false;
                _lastMessageAt = DateTime.MinValue;
                WriteDebugStatusLocked("disconnected", CodexActivityState.Idle, DateTime.Now);
            }

            DateTime now = DateTime.Now;
            if (now >= _nextErrorLogAt)
            {
                _nextErrorLogAt = now.AddMinutes(1);
                Logger.Info("Codex IPC activity source unavailable: " + reason);
            }
        }

        private void RemoveStaleConversations(DateTime now)
        {
            foreach (string key in _conversations.Keys.ToArray())
            {
                ConversationActivity conversation = _conversations[key];
                if (!conversation.Running && now - conversation.UpdatedAt > ConversationTtl) _conversations.Remove(key);
            }
        }

        private void WriteDebugStatusLocked(string source, CodexActivityState state, DateTime now)
        {
            if (now < _nextDebugWriteAt && source != "disconnected") return;
            _nextDebugWriteAt = now.AddSeconds(2);
            try
            {
                JavaScriptSerializer serializer = NewSerializer();
                Dictionary<string, object> data = new Dictionary<string, object>();
                data["Source"] = source;
                data["State"] = state.ToString();
                data["Connected"] = _connected;
                data["HasLiveSignal"] = _hasLiveSignal;
                data["KnownConversations"] = _conversations.Count;
                data["ActiveConversations"] = _conversations.Values.Count(c => c.Running);
                data["LastMessageAt"] = _lastMessageAt == DateTime.MinValue ? "" : _lastMessageAt.ToString("o", CultureInfo.InvariantCulture);
                data["CompleteUntil"] = _completeUntil == DateTime.MinValue ? "" : _completeUntil.ToString("o", CultureInfo.InvariantCulture);
                data["ClientId"] = _clientId;
                data["UpdatedAt"] = now.ToString("o", CultureInfo.InvariantCulture);
                File.WriteAllText(AppPaths.ActivityStatePath, serializer.Serialize(data), Encoding.UTF8);
            }
            catch
            {
            }
        }

        private static bool IsThreadRuntimeActive(Dictionary<string, object> data)
        {
            if (data == null) return false;
            return IsActiveRuntimeStatus(GetString(data, "type"));
        }

        private static bool IsActiveRuntimeStatus(string value)
        {
            return String.Equals(value, "active", StringComparison.OrdinalIgnoreCase);
        }

        private static bool TryParsePathIndex(object value, out int index)
        {
            if (value is int)
            {
                index = (int)value;
                return index >= 0;
            }
            return Int32.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Integer, CultureInfo.InvariantCulture, out index) && index >= 0;
        }

        private static TurnActivity EnsureTurnAtIndex(List<TurnActivity> turns, int index)
        {
            while (turns.Count <= index) turns.Add(new TurnActivity());
            return turns[index];
        }

        private static void SetTurnAtIndex(List<TurnActivity> turns, int index, TurnActivity turn, bool insert)
        {
            if (insert && index <= turns.Count)
            {
                turns.Insert(index, turn);
                return;
            }
            EnsureTurnAtIndex(turns, index);
            turns[index] = turn;
        }

        private bool IsDisposed()
        {
            lock (_sync)
            {
                return _disposed;
            }
        }

        private static void SleepReconnectDelay()
        {
            Thread.Sleep(ReconnectDelay);
        }

        private static void SendFrame(Stream stream, object data)
        {
            JavaScriptSerializer serializer = NewSerializer();
            string json = serializer.Serialize(data);
            byte[] payload = Encoding.UTF8.GetBytes(json);
            byte[] header = BitConverter.GetBytes(payload.Length);
            if (!BitConverter.IsLittleEndian) Array.Reverse(header);
            stream.Write(header, 0, header.Length);
            stream.Write(payload, 0, payload.Length);
            stream.Flush();
        }

        private static Dictionary<string, object> ReadFrame(Stream stream)
        {
            byte[] header = ReadExact(stream, 4);
            if (!BitConverter.IsLittleEndian) Array.Reverse(header);
            int length = BitConverter.ToInt32(header, 0);
            if (length <= 0 || length > MaxFrameBytes) throw new InvalidOperationException("Invalid Codex IPC frame length.");
            byte[] payload = ReadExact(stream, length);
            string json = Encoding.UTF8.GetString(payload);
            JavaScriptSerializer serializer = NewSerializer();
            return serializer.DeserializeObject(json) as Dictionary<string, object>;
        }

        private static byte[] ReadExact(Stream stream, int length)
        {
            byte[] buffer = new byte[length];
            int offset = 0;
            while (offset < length)
            {
                int read = stream.Read(buffer, offset, length - offset);
                if (read <= 0) throw new EndOfStreamException("Codex IPC pipe closed.");
                offset += read;
            }
            return buffer;
        }

        private static JavaScriptSerializer NewSerializer()
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            return serializer;
        }

        private static object GetValue(Dictionary<string, object> data, string key)
        {
            object value;
            return data != null && data.TryGetValue(key, out value) ? value : null;
        }

        private static string GetString(Dictionary<string, object> data, string key)
        {
            object value = GetValue(data, key);
            return value == null ? "" : Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
        }

        private static Dictionary<string, object> AsDictionary(object value)
        {
            return value as Dictionary<string, object>;
        }

        private static object[] AsArray(object value)
        {
            object[] array = value as object[];
            if (array != null) return array;
            ArrayList list = value as ArrayList;
            return list == null ? new object[0] : list.Cast<object>().ToArray();
        }

        private static string ToPathSegment(object value)
        {
            return value == null ? "" : Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
        }

        private sealed class ConversationActivity
        {
            public readonly List<TurnActivity> Turns = new List<TurnActivity>();
            public bool ThreadRuntimeActive;
            public bool Running
            {
                get { return ThreadRuntimeActive || Turns.Any(t => t.Status == "inProgress"); }
            }
            public bool Authoritative;
            public DateTime UpdatedAt = DateTime.MinValue;
        }

        private sealed class TurnActivity
        {
            public string TurnId = "";
            public string Status = "";

            public static TurnActivity FromDictionary(Dictionary<string, object> data)
            {
                TurnActivity turn = new TurnActivity();
                if (data != null)
                {
                    turn.TurnId = GetString(data, "turnId");
                    turn.Status = GetString(data, "status");
                }
                return turn;
            }
        }

        public static void RunSelfTest()
        {
            DateTime start = DateTime.Now;
            CodexIpcActivitySource source = new CodexIpcActivitySource();
            source.MarkConnected();
            source.TouchLiveSignal();

            source.ApplyConversationSnapshot("conversation-a", ConversationState(false, new[] { Turn("turn-a", "inProgress") }));
            source.AssertState(CodexActivityState.Running, start, "running snapshot");

            source.ApplyConversationPatches("conversation-a", new object[] { Patch("replace", new object[] { "turns", 0, "status" }, "completed") });
            source.AssertState(CodexActivityState.Complete, start.AddSeconds(1), "complete transition");
            source.AssertState(CodexActivityState.Complete, start.AddSeconds(4.9), "complete grace");
            source.AssertState(CodexActivityState.Idle, start.AddSeconds(5.1), "complete expiry");

            source.ApplyConversationSnapshot("conversation-b", ConversationState(true, new object[0]));
            source.AssertState(CodexActivityState.Running, DateTime.Now, "thread runtime active");

            source.ApplyConversationPatches("conversation-b", new object[] { Patch("replace", new object[] { "threadRuntimeStatus", "type" }, "idle") });
            source.AssertState(CodexActivityState.Complete, DateTime.Now, "thread runtime inactive complete");
            source.ApplyConversationPatches("conversation-b", new object[] { Patch("add", new object[] { "turns", 0 }, Turn("turn-b", "inProgress")) });
            source.AssertState(CodexActivityState.Running, DateTime.Now, "turn add running");
            source.ApplyConversationPatches("conversation-b", new object[] { Patch("remove", new object[] { "turns", 0 }, null) });
            source.AssertState(CodexActivityState.Complete, DateTime.Now, "turn remove complete");

            source.Dispose();
        }

        private void AssertState(CodexActivityState expected, DateTime now, string label)
        {
            lock (_sync)
            {
                ExpireCompleteIfNeededLocked(now);
                if (_state != expected)
                {
                    throw new InvalidOperationException("Activity self-test failed: " + label + ". Expected " + expected + " but got " + _state + ".");
                }
            }
        }

        private static Dictionary<string, object> ConversationState(bool threadRuntimeActive, object[] turns)
        {
            Dictionary<string, object> state = new Dictionary<string, object>();
            state["turns"] = turns;
            state["threadRuntimeStatus"] = new Dictionary<string, object> { { "type", threadRuntimeActive ? "active" : "idle" } };
            return state;
        }

        private static Dictionary<string, object> Turn(string turnId, string status)
        {
            Dictionary<string, object> turn = new Dictionary<string, object>();
            turn["turnId"] = turnId;
            turn["status"] = status;
            return turn;
        }

        private static Dictionary<string, object> Patch(string op, object[] path, object value)
        {
            Dictionary<string, object> patch = new Dictionary<string, object>();
            patch["op"] = op;
            patch["path"] = path;
            if (op != "remove") patch["value"] = value;
            return patch;
        }
    }

    internal static class NativeSelfTests
    {
        public static void Run()
        {
            CodexIpcActivitySource.RunSelfTest();
            Console.WriteLine("Native self-tests passed.");
        }
    }

    internal sealed class QuotaService : IDisposable
    {
        private readonly Options _options;
        private Process _serverProcess;
        private int _serverPort;
        private string _codexExe;

        public QuotaService(Options options)
        {
            _options = options;
        }

        public RateLimitSummary Refresh()
        {
            EnsureServer();
            return ReadRateLimits(_serverPort);
        }

        public int AppServerProcessId
        {
            get
            {
                try
                {
                    return _serverProcess != null && !_serverProcess.HasExited ? _serverProcess.Id : 0;
                }
                catch
                {
                    return 0;
                }
            }
        }

        public void Dispose()
        {
            StopServer();
        }

        private void EnsureServer()
        {
            if (_serverProcess != null)
            {
                try
                {
                    if (!_serverProcess.HasExited) return;
                }
                catch
                {
                }
            }

            _codexExe = ResolveCodexExe(_options.CodexExe);
            _serverPort = GetFreePort();
            ProcessStartInfo start = new ProcessStartInfo(_codexExe);
            start.Arguments = "app-server --listen ws://127.0.0.1:" + _serverPort.ToString(CultureInfo.InvariantCulture);
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WindowStyle = ProcessWindowStyle.Hidden;
            Logger.Overlay("Starting Codex app-server. Exe=" + _codexExe + " Port=" + _serverPort);
            _serverProcess = Process.Start(start);
            Thread.Sleep(900);
            if (_serverProcess == null || _serverProcess.HasExited)
            {
                throw new InvalidOperationException("codex app-server exited during startup.");
            }
            WriteRuntimeState();
        }

        private void StopServer()
        {
            try
            {
                if (_serverProcess != null && !_serverProcess.HasExited)
                {
                    _serverProcess.Kill();
                }
            }
            catch
            {
            }
            try
            {
                if (File.Exists(AppPaths.RuntimeStatePath)) File.Delete(AppPaths.RuntimeStatePath);
            }
            catch
            {
            }
        }

        private void WriteRuntimeState()
        {
            try
            {
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                Dictionary<string, object> data = new Dictionary<string, object>();
                data["NativePid"] = Process.GetCurrentProcess().Id;
                data["AppServerPid"] = _serverProcess == null ? 0 : _serverProcess.Id;
                data["Port"] = _serverPort;
                data["CodexExe"] = _codexExe ?? "";
                data["ExePath"] = Application.ExecutablePath;
                data["StartedAt"] = DateTime.Now.ToString("o", CultureInfo.InvariantCulture);
                File.WriteAllText(AppPaths.RuntimeStatePath, serializer.Serialize(data), Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Logger.Error("Runtime state write failed: " + ex.Message);
            }
        }

        private static string ResolveCodexExe(string overridePath)
        {
            if (!String.IsNullOrEmpty(overridePath) && File.Exists(overridePath)) return Path.GetFullPath(overridePath);

            string localBin = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenAI", "Codex", "bin");
            if (Directory.Exists(localBin))
            {
                FileInfo latest = Directory.GetFiles(localBin, "codex.exe", SearchOption.AllDirectories)
                    .Select(p => new FileInfo(p))
                    .OrderByDescending(f => f.LastWriteTimeUtc)
                    .FirstOrDefault();
                if (latest != null) return latest.FullName;
            }

            string path = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (string part in path.Split(Path.PathSeparator))
            {
                try
                {
                    string candidate = Path.Combine(part.Trim(), "codex.exe");
                    if (File.Exists(candidate)) return candidate;
                }
                catch
                {
                }
            }
            throw new FileNotFoundException("codex.exe was not found.");
        }

        private static int GetFreePort()
        {
            TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            try
            {
                return ((IPEndPoint)listener.LocalEndpoint).Port;
            }
            finally
            {
                listener.Stop();
            }
        }

        private static RateLimitSummary ReadRateLimits(int port)
        {
            using (ClientWebSocket socket = new ClientWebSocket())
            {
                socket.ConnectAsync(new Uri("ws://127.0.0.1:" + port.ToString(CultureInfo.InvariantCulture)), CancellationToken.None).Wait(5000);
                Send(socket, new Dictionary<string, object>
                {
                    {"id", 1},
                    {"method", "initialize"},
                    {"params", new Dictionary<string, object>
                        {
                            {"clientInfo", new Dictionary<string, object>{{"name", "codex-quota-taskbar"}, {"version", "0.5.0"}}},
                            {"capabilities", new Dictionary<string, object>{{"experimentalApi", true}}}
                        }
                    }
                });

                while (true)
                {
                    Dictionary<string, object> message = Receive(socket);
                    if (HasId(message, 1))
                    {
                        Send(socket, new Dictionary<string, object> { { "method", "initialized" } });
                        break;
                    }
                }

                Send(socket, new Dictionary<string, object> { { "id", 2 }, { "method", "account/rateLimits/read" } });
                while (true)
                {
                    Dictionary<string, object> message = Receive(socket);
                    if (HasId(message, 2))
                    {
                        if (message.ContainsKey("error") && message["error"] != null)
                        {
                            throw new InvalidOperationException("Codex returned quota error.");
                        }
                        return ParseSummary(message);
                    }
                }
            }
        }

        private static bool HasId(Dictionary<string, object> message, int id)
        {
            return message.ContainsKey("id") && Convert.ToInt32(message["id"], CultureInfo.InvariantCulture) == id;
        }

        private static void Send(ClientWebSocket socket, object data)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            byte[] bytes = Encoding.UTF8.GetBytes(serializer.Serialize(data));
            socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None).Wait(5000);
        }

        private static Dictionary<string, object> Receive(ClientWebSocket socket)
        {
            byte[] buffer = new byte[65536];
            using (MemoryStream stream = new MemoryStream())
            {
                while (true)
                {
                    WebSocketReceiveResult result = socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None).Result;
                    if (result.MessageType == WebSocketMessageType.Close) throw new InvalidOperationException("WebSocket closed.");
                    stream.Write(buffer, 0, result.Count);
                    if (result.EndOfMessage) break;
                }
                string text = Encoding.UTF8.GetString(stream.ToArray());
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                return serializer.DeserializeObject(text) as Dictionary<string, object>;
            }
        }

        private static RateLimitSummary ParseSummary(Dictionary<string, object> message)
        {
            Dictionary<string, object> result = (Dictionary<string, object>)message["result"];
            Dictionary<string, object> limits = (Dictionary<string, object>)result["rateLimits"];
            Dictionary<string, object> primary = (Dictionary<string, object>)limits["primary"];
            Dictionary<string, object> secondary = (Dictionary<string, object>)limits["secondary"];
            RateLimitSummary summary = new RateLimitSummary();
            summary.FiveRemaining = 100.0 - Convert.ToDouble(primary["usedPercent"], CultureInfo.InvariantCulture);
            summary.WeekRemaining = 100.0 - Convert.ToDouble(secondary["usedPercent"], CultureInfo.InvariantCulture);
            summary.FiveReset = ParseReset(primary);
            summary.WeekReset = ParseReset(secondary);
            summary.CheckedAt = DateTime.Now;
            return summary;
        }

        private static DateTime? ParseReset(Dictionary<string, object> data)
        {
            if (!data.ContainsKey("resetsAt") || data["resetsAt"] == null) return null;
            long seconds = Convert.ToInt64(data["resetsAt"], CultureInfo.InvariantCulture);
            DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            return epoch.AddSeconds(seconds).ToLocalTime();
        }
    }

    internal sealed class MonitorContext : ApplicationContext
    {
        private readonly Options _options;
        private Settings _settings;
        private readonly NotifyIcon _notifyIcon;
        private readonly System.Windows.Forms.Timer _timer;
        private readonly System.Windows.Forms.Timer _activityTimer;
        private readonly System.Windows.Forms.Timer _quotaTimer;
        private readonly QuotaService _quotaService;
        private readonly CodexActivityService _activityService;
        private readonly OverlayManager _overlayManager;
        private readonly ToolStripMenuItem _statusMenuItem;
        private readonly ToolStripMenuItem _settingsMenuItem;
        private readonly ToolStripMenuItem _refreshMenuItem;
        private readonly ToolStripMenuItem _openLogsMenuItem;
        private readonly ToolStripMenuItem _exitMenuItem;
        private CodexActivityState _lastActivityState = CodexActivityState.Idle;
        private string _lastError = "";
        private string _statusKey = "Starting";

        public MonitorContext(Options options, Settings settings)
        {
            _options = options;
            _settings = settings;
            StopOtherNativeInstances();
            _quotaService = new QuotaService(options);
            _activityService = new CodexActivityService();
            _overlayManager = new OverlayManager(options, settings, _quotaService, ExitThread);

            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem status = new ToolStripMenuItem(settings.T("Starting"));
            status.Enabled = false;
            _statusMenuItem = status;
            menu.Items.Add(status);
            menu.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem settingsItem = new ToolStripMenuItem(settings.T("SettingsMenu"));
            _settingsMenuItem = settingsItem;
            settingsItem.Click += delegate { ShowSettings(); };
            menu.Items.Add(settingsItem);
            ToolStripMenuItem refresh = new ToolStripMenuItem(settings.T("RefreshNow"));
            _refreshMenuItem = refresh;
            refresh.Click += delegate { RefreshNow(); };
            menu.Items.Add(refresh);
            ToolStripMenuItem openLogs = new ToolStripMenuItem(settings.T("OpenLogs"));
            _openLogsMenuItem = openLogs;
            openLogs.Click += delegate { OpenFolder(AppPaths.Logs); };
            menu.Items.Add(openLogs);
            menu.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem exit = new ToolStripMenuItem(settings.T("Exit"));
            _exitMenuItem = exit;
            exit.Click += delegate { ExitThread(); };
            menu.Items.Add(exit);

            _notifyIcon = new NotifyIcon();
            _notifyIcon.Icon = SystemIcons.Application;
            _notifyIcon.ContextMenuStrip = menu;
            _notifyIcon.Text = "Codex Quota Taskbar";
            _notifyIcon.Visible = true;

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = Math.Max(1, options.PollSeconds) * 1000;
            _timer.Tick += delegate
            {
                Tick(status);
            };

            _activityTimer = new System.Windows.Forms.Timer();
            _activityTimer.Interval = 250;
            _activityTimer.Tick += delegate
            {
                UpdateActivityStateOnly();
            };

            _quotaTimer = new System.Windows.Forms.Timer();
            _quotaTimer.Interval = Math.Max(5, options.QuotaRefreshSeconds) * 1000;
            _quotaTimer.Tick += delegate
            {
                if (IsCodexOpen())
                {
                    _overlayManager.RefreshQuotaAsync("timer");
                }
            };

            Tick(status);
            _timer.Start();
            _activityTimer.Start();
            _quotaTimer.Start();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _timer.Stop();
                _timer.Dispose();
                _activityTimer.Stop();
                _activityTimer.Dispose();
                _quotaTimer.Stop();
                _quotaTimer.Dispose();
                _overlayManager.Dispose();
                _activityService.Dispose();
                _quotaService.Dispose();
                _notifyIcon.Visible = false;
                _notifyIcon.Dispose();
            }
            base.Dispose(disposing);
        }

        private void Tick(ToolStripMenuItem status)
        {
            try
            {
                if (IsCodexOpen())
                {
                    UpdateActivityStateOnly();
                    _overlayManager.EnsureVisible();
                    _statusKey = "Running";
                    status.Text = _settings.T("Running");
                    _notifyIcon.Text = TrimNotify(status.Text);
                    _lastError = "";
                }
                else
                {
                    _lastActivityState = CodexActivityState.Idle;
                    _overlayManager.UpdateActivityState(CodexActivityState.Idle);
                    _overlayManager.Hide();
                    _statusKey = "Waiting";
                    status.Text = _settings.T("Waiting");
                    _notifyIcon.Text = TrimNotify(status.Text);
                }
            }
            catch (Exception ex)
            {
                Logger.Error("Monitor tick failed: " + ex.Message);
                if (_lastError != ex.Message)
                {
                    _lastError = ex.Message;
                    _notifyIcon.ShowBalloonTip(5000, "Codex quota monitor failed", ex.Message, ToolTipIcon.Error);
                }
            }
        }

        private void UpdateActivityStateOnly()
        {
            try
            {
                if (!IsCodexOpen())
                {
                    _lastActivityState = CodexActivityState.Idle;
                    _overlayManager.UpdateActivityState(CodexActivityState.Idle);
                    return;
                }

                CodexActivityState state = _activityService.Sample(_quotaService.AppServerProcessId);
                _overlayManager.UpdateActivityState(state);
                if (_lastActivityState == CodexActivityState.Running && state == CodexActivityState.Complete)
                {
                    _overlayManager.RefreshQuotaAsync("activity-complete");
                }
                _lastActivityState = state;
            }
            catch (Exception ex)
            {
                Logger.Error("Activity state update failed: " + ex.Message);
            }
        }

        private void RefreshNow()
        {
            try
            {
                _overlayManager.RefreshQuotaAsync("tray");
            }
            catch (Exception ex)
            {
                Logger.Error("Refresh failed: " + ex.Message);
            }
        }

        private void ShowSettings()
        {
            bool timerWasEnabled = _timer.Enabled;
            if (timerWasEnabled) _timer.Stop();
            string originalLanguage = _settings.Language;
            Settings edited = null;
            try
            {
                _overlayManager.PulseTopmost();
                using (_overlayManager.SuspendTopmost())
                {
                    edited = SettingsDialog.Show(_settings, delegate(string selectedLanguage)
                    {
                        ApplyLanguage(selectedLanguage);
                    });
                }
            }
            finally
            {
                if (timerWasEnabled) _timer.Start();
            }
            if (edited == null)
            {
                ApplyLanguage(originalLanguage);
                return;
            }
            _settings = edited;
            _settings.Save();
            _overlayManager.UpdateSettings(edited);
            UpdateTrayMenuLanguage();
        }

        private void ApplyLanguage(string language)
        {
            _settings.Language = Settings.NormalizeLanguage(language);
            _overlayManager.UpdateLanguage(_settings.Language);
            UpdateTrayMenuLanguage();
        }

        private void UpdateTrayMenuLanguage()
        {
            _settingsMenuItem.Text = _settings.T("SettingsMenu");
            _refreshMenuItem.Text = _settings.T("RefreshNow");
            _openLogsMenuItem.Text = _settings.T("OpenLogs");
            _exitMenuItem.Text = _settings.T("Exit");
            _statusMenuItem.Text = _settings.T(_statusKey);
            _notifyIcon.Text = TrimNotify(_statusMenuItem.Text);
        }

        private static bool IsCodexOpen()
        {
            Process[] processes = Process.GetProcessesByName("Codex");
            if (processes.Length > 0) return true;
            processes = Process.GetProcessesByName("codex");
            return processes.Length > 0;
        }

        private static void OpenFolder(string path)
        {
            try
            {
                Directory.CreateDirectory(path);
                Process.Start(path);
            }
            catch
            {
            }
        }

        private static string TrimNotify(string text)
        {
            if (String.IsNullOrEmpty(text)) return "Codex Quota Taskbar";
            return text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private static void StopOtherNativeInstances()
        {
            int current = Process.GetCurrentProcess().Id;
            string currentExe = Application.ExecutablePath;
            foreach (Process process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(currentExe)))
            {
                try
                {
                    if (process.Id != current && String.Equals(process.MainModule.FileName, currentExe, StringComparison.OrdinalIgnoreCase))
                    {
                        process.Kill();
                    }
                }
                catch
                {
                }
            }
        }
    }

    internal sealed class OverlayManager : IDisposable
    {
        private const int BaseOverlayWidth = 245;
        private const int BaseOverlayHeight = 42;
        private const int ClockReservePx = 96;
        private readonly Options _options;
        private Settings _settings;
        private readonly QuotaService _quotaService;
        private readonly Action _exit;
        private readonly List<WpfOverlayForm> _forms = new List<WpfOverlayForm>();
        private readonly List<System.Windows.Controls.ContextMenu> _menus = new List<System.Windows.Controls.ContextMenu>();
        private readonly object _quotaReadLock = new object();
        private readonly object _asyncRefreshLock = new object();
        private RateLimitSummary _summary;
        private CodexActivityState _activityState = CodexActivityState.Idle;
        private int _topmostSuspendDepth;
        private bool _asyncRefreshInProgress;
        private bool _asyncRefreshPending;
        private string _asyncRefreshPendingReason = "";
        private volatile bool _disposed;

        public OverlayManager(Options options, Settings settings, QuotaService quotaService, Action exit)
        {
            _options = options;
            _settings = settings;
            _quotaService = quotaService;
            _exit = exit;
            EnsureWpfApplication();
        }

        public IEnumerable<WpfOverlayForm> Forms { get { return _forms; } }
        private bool TopmostSuspended { get { return _topmostSuspendDepth > 0; } }

        public IDisposable SuspendTopmost()
        {
            _topmostSuspendDepth++;
            return new TopmostSuspendScope(this);
        }

        public void PulseTopmost()
        {
            foreach (WpfOverlayForm form in _forms)
            {
                if (form.Visible) form.EnsureTopmost();
            }
        }

        public void EnsureVisible()
        {
            if (_summary == null) RefreshQuota();
            Screen[] screens = GetTargetScreens();
            while (_forms.Count < screens.Length)
            {
                _forms.Add(new WpfOverlayForm(this));
            }
            for (int i = 0; i < _forms.Count; i++)
            {
                WpfOverlayForm form = _forms[i];
                if (i < screens.Length)
                {
                    OverlayLayout layout = GetOverlayLayout(screens[i]);
                    form.SetSettings(_settings);
                    form.SetActivityState(_activityState);
                    form.SetSummary(_summary);
                    form.SetLayout(layout);
                    form.SetBounds(ComputeBounds(screens[i], layout.Width, layout.Height, _settings.XOffset));
                    if (!form.Visible) form.Show();
                    if (!TopmostSuspended)
                    {
                        form.EnsureTopmost();
                    }
                }
                else
                {
                    form.Hide();
                }
            }
        }

        public void Hide()
        {
            foreach (WpfOverlayForm form in _forms) form.Hide();
        }

        public void RefreshQuota()
        {
            try
            {
                ApplyRefreshResult(ReadQuotaSummary(), "", "sync");
            }
            catch (Exception ex)
            {
                ApplyRefreshResult(null, ex.Message, "sync");
            }
        }

        public void RefreshQuotaAsync(string reason)
        {
            if (_disposed) return;
            lock (_asyncRefreshLock)
            {
                if (_asyncRefreshInProgress)
                {
                    _asyncRefreshPending = true;
                    _asyncRefreshPendingReason = reason;
                    return;
                }
                _asyncRefreshInProgress = true;
            }

            StartAsyncRefresh(reason);
        }

        private void StartAsyncRefresh(string reason)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                RateLimitSummary summary = null;
                string error = "";
                try
                {
                    summary = ReadQuotaSummary();
                }
                catch (Exception ex)
                {
                    error = ex.Message;
                }

                try
                {
                    BeginOnUi(delegate
                    {
                        try
                        {
                            if (!_disposed)
                            {
                                ApplyRefreshResult(summary, error, reason);
                            }
                        }
                        finally
                        {
                            FinishAsyncRefresh();
                        }
                    });
                }
                catch (Exception ex)
                {
                    Logger.Overlay("Async refresh dispatch failed: " + ex.Message);
                    FinishAsyncRefresh();
                }
            });
        }

        private RateLimitSummary ReadQuotaSummary()
        {
            lock (_quotaReadLock)
            {
                return _options.MockQuota ? RateLimitSummary.Mock() : _quotaService.Refresh();
            }
        }

        private void ApplyRefreshResult(RateLimitSummary summary, string error, string reason)
        {
            if (String.IsNullOrEmpty(error))
            {
                _summary = summary;
                foreach (WpfOverlayForm form in _forms)
                {
                    form.SetSummary(_summary);
                }
                UpdateMenus("");
                return;
            }

            string suffix = String.IsNullOrEmpty(reason) ? "" : " (" + reason + ")";
            Logger.Overlay("Refresh failed" + suffix + ": " + error);
            _summary = null;
            foreach (WpfOverlayForm form in _forms)
            {
                form.SetError(error);
            }
            UpdateMenus(error);
        }

        private void BeginOnUi(Action action)
        {
            System.Windows.Application app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher != null && !app.Dispatcher.HasShutdownStarted && !app.Dispatcher.HasShutdownFinished)
            {
                app.Dispatcher.BeginInvoke(action);
                return;
            }
            action();
        }

        private void FinishAsyncRefresh()
        {
            string pendingReason = "";
            lock (_asyncRefreshLock)
            {
                if (_asyncRefreshPending && !_disposed)
                {
                    pendingReason = _asyncRefreshPendingReason;
                    _asyncRefreshPending = false;
                    _asyncRefreshPendingReason = "";
                }
                else
                {
                    _asyncRefreshInProgress = false;
                }
            }

            if (!String.IsNullOrEmpty(pendingReason))
            {
                StartAsyncRefresh(pendingReason);
            }
        }

        public void UpdateSettings(Settings settings)
        {
            _settings = settings;
            foreach (WpfOverlayForm form in _forms)
            {
                form.SetSettings(settings);
                form.SetActivityState(_activityState);
            }
            EnsureVisible();
            UpdateMenus("");
        }

        public void UpdateLanguage(string language)
        {
            _settings.Language = Settings.NormalizeLanguage(language);
            foreach (WpfOverlayForm form in _forms)
            {
                form.SetSettings(_settings);
            }
            UpdateMenus("");
        }

        public void UpdateActivityState(CodexActivityState state)
        {
            _activityState = state;
            foreach (WpfOverlayForm form in _forms)
            {
                form.SetActivityState(state);
            }
        }

        public System.Windows.Controls.ContextMenu BuildMenu()
        {
            System.Windows.Controls.ContextMenu menu = new System.Windows.Controls.ContextMenu();
            ApplyModernContextMenuStyle(menu);
            WpfMenuState state = new WpfMenuState();
            menu.Tag = state;

            state.StatusFive = NewWpfMenuItem(_settings.T("Loading"), "5H", false);
            state.StatusWeek = NewWpfMenuItem(_settings.T("Loading"), "W", false);
            menu.Items.Add(state.StatusFive);
            menu.Items.Add(state.StatusWeek);
            menu.Items.Add(new System.Windows.Controls.Separator());

            state.Refresh = NewWpfMenuItem(_settings.T("RefreshQuota"), "R", true);
            state.Refresh.Click += delegate { RefreshQuotaAsync("menu"); EnsureVisible(); };
            menu.Items.Add(state.Refresh);

            state.Settings = NewWpfMenuItem(_settings.T("SettingsMenu"), "S", true);
            state.Settings.Click += delegate
            {
                string originalLanguage = _settings.Language;
                Settings edited;
                PulseTopmost();
                using (SuspendTopmost())
                {
                    edited = SettingsDialog.Show(_settings, delegate(string selectedLanguage)
                    {
                        UpdateLanguage(selectedLanguage);
                    });
                }
                if (edited != null)
                {
                    edited.Save();
                    UpdateSettings(edited);
                }
                else
                {
                    UpdateLanguage(originalLanguage);
                }
            };
            menu.Items.Add(state.Settings);

            state.Open = NewWpfMenuItem(_settings.T("OpenCodex"), "O", true);
            state.Open.Click += delegate { NativeWindowActivation.ShowCodexWindow(); };
            menu.Items.Add(state.Open);
            menu.Items.Add(new System.Windows.Controls.Separator());

            state.SwitchMonitor = NewWpfMenuItem(_settings.T("SwitchMonitor"), "M", false);
            menu.Items.Add(state.SwitchMonitor);

            Screen[] screens = Screen.AllScreens;
            for (int i = 0; i < screens.Length; i++)
            {
                Screen screen = screens[i];
                System.Windows.Controls.MenuItem item = NewWpfMenuItem(ScreenLabel(screen, i), "-", true);
                item.Tag = new ScreenMenuTag(screen.DeviceName, i);
                item.Click += delegate(object sender, System.Windows.RoutedEventArgs e)
                {
                    System.Windows.Controls.MenuItem clicked = (System.Windows.Controls.MenuItem)sender;
                    ScreenMenuTag tag = (ScreenMenuTag)clicked.Tag;
                    _settings.TargetMonitorDevice = tag.DeviceName;
                    _settings.XOffset = 0;
                    _settings.Save();
                    UpdateSettings(_settings);
                };
                state.ScreenItems.Add(item);
                menu.Items.Add(item);
            }

            menu.Items.Add(new System.Windows.Controls.Separator());
            state.Exit = NewWpfMenuItem(_settings.T("Exit"), "X", true);
            state.Exit.Click += delegate { _exit(); };
            menu.Items.Add(state.Exit);

            menu.Opened += delegate { UpdateMenu(menu, ""); };
            _menus.Add(menu);
            UpdateMenu(menu, "");
            return menu;
        }

        public double ClampDraggedLeft(WpfOverlayForm form, double left, Screen screen)
        {
            if (screen == null)
            {
                screen = Screen.FromPoint(form.CenterPoint);
            }
            Rectangle bounds = screen.Bounds;
            const int margin = 8;
            double minLeft = bounds.Left + margin;
            double maxLeft = bounds.Right - form.Width - margin;
            return Math.Max(minLeft, Math.Min(left, maxLeft));
        }

        public void SaveDragOffset(WpfOverlayForm form)
        {
            Screen screen = Screen.FromPoint(form.CenterPoint);
            OverlayLayout layout = GetOverlayLayout(screen);
            Rectangle baseRect = ComputeBounds(screen, layout.Width, layout.Height, 0);
            _settings.TargetMonitorDevice = screen.DeviceName;
            _settings.XOffset = (int)Math.Round(form.Left - baseRect.Left);
            _settings.Save();
            UpdateMenus("");
        }

        public Rectangle ComputeBounds(Screen screen, int width, int height, int xOffset)
        {
            Rectangle bounds = screen.Bounds;
            Rectangle work = screen.WorkingArea;
            string edge = TaskbarEdge(screen);
            const int margin = 8;
            int x;
            int y;
            if (edge == "Top")
            {
                int taskbarHeight = Math.Max(height + 4, GetTaskbarThickness(screen));
                x = bounds.Right - ClockReservePx - width;
                y = bounds.Top + (int)Math.Round((taskbarHeight - height) / 2.0) - _settings.VerticalOffset;
            }
            else if (edge == "Right")
            {
                int taskbarWidth = Math.Max(56, GetTaskbarThickness(screen));
                x = work.Right + (int)((taskbarWidth - width) / 2.0);
                y = bounds.Bottom - ClockReservePx - height + _settings.VerticalOffset;
            }
            else if (edge == "Left")
            {
                int taskbarWidth = Math.Max(56, GetTaskbarThickness(screen));
                x = bounds.Left + (int)((taskbarWidth - width) / 2.0);
                y = bounds.Bottom - ClockReservePx - height + _settings.VerticalOffset;
            }
            else
            {
                int taskbarHeight = Math.Max(height + 4, GetTaskbarThickness(screen));
                x = bounds.Right - ClockReservePx - width;
                y = work.Bottom + (int)Math.Round((taskbarHeight - height) / 2.0) + _settings.VerticalOffset;
            }

            x += xOffset;
            x = Math.Max(bounds.Left + margin, Math.Min(x, bounds.Right - width - margin));
            if (edge == "Top") y = Math.Max(bounds.Top, Math.Min(y, work.Top - height));
            else if (edge == "Bottom") y = Math.Max(work.Bottom, Math.Min(y, bounds.Bottom - height));
            else y = Math.Max(bounds.Top + margin, Math.Min(y, bounds.Bottom - height - margin));
            return new Rectangle(x, y, width, height);
        }

        private OverlayLayout GetOverlayLayout(Screen screen)
        {
            int taskbarThickness = GetTaskbarThickness(screen);
            if (taskbarThickness <= 0) taskbarThickness = 48;

            double scale = taskbarThickness / 48.0;
            scale = Math.Max(0.72, Math.Min(1.22, scale));
            int height = (int)Math.Round(BaseOverlayHeight * scale);
            int maxHeight = Math.Max(22, taskbarThickness - 4);
            height = Math.Max(22, Math.Min(height, maxHeight));
            scale = height / (double)BaseOverlayHeight;
            double activityColumn = _settings.ShowActivityIcon ? Math.Max(16, Math.Round(20 * scale, 1)) : 0;

            return new OverlayLayout
            {
                Scale = scale,
                Width = (int)Math.Round((BaseOverlayWidth * scale) + activityColumn),
                Height = height,
                ActivityIconColumn = activityColumn,
                ActivityIconSize = Math.Max(10, Math.Round(13.4 * scale, 1)),
                Margin = Math.Max(1, Math.Round(1 * scale, 1)),
                PaddingX = Math.Max(4, Math.Round(7 * scale, 1)),
                PaddingY = Math.Max(1, Math.Round(3 * scale, 1)),
                CornerRadius = Math.Max(4, Math.Round(7 * scale, 1)),
                RowHeight = Math.Max(11, Math.Round(16 * scale, 1)),
                TagColumn = Math.Max(16, Math.Round(23 * scale, 1)),
                LabelColumn = Math.Max(52, Math.Round(70 * scale, 1)),
                BarColumn = Math.Max(40, Math.Round(55 * scale, 1)),
                PercentColumn = Math.Max(27, Math.Round(32 * scale, 1)),
                TimeColumn = Math.Max(37, Math.Round(47 * scale, 1)),
                BarWidth = Math.Max(38, Math.Round(55 * scale, 1)),
                BarHeight = Math.Max(5, Math.Round(8 * scale, 1)),
                TagFontSize = Math.Max(8.4, Math.Round(11.2 * scale, 1)),
                LabelFontSize = Math.Max(8.0, Math.Round(10.4 * scale, 1)),
                PercentFontSize = Math.Max(8.2, Math.Round(10.6 * scale, 1)),
                TimeFontSize = Math.Max(7.5, Math.Round(9.6 * scale, 1))
            };
        }

        private Screen[] GetTargetScreens()
        {
            Screen[] screens = Screen.AllScreens;
            if (!String.IsNullOrEmpty(_settings.TargetMonitorDevice))
            {
                Screen selected = screens.FirstOrDefault(s => s.DeviceName == _settings.TargetMonitorDevice);
                if (selected != null) return new[] { selected };
            }
            if (_options.AllScreens) return screens;
            Screen[] secondary = screens.Where(s => !s.Primary).ToArray();
            return secondary.Length > 0 ? secondary : screens;
        }

        private static int GetTaskbarThickness(Screen screen)
        {
            Rectangle bounds = screen.Bounds;
            Rectangle work = screen.WorkingArea;
            string edge = TaskbarEdge(screen);
            if (edge == "Bottom") return Math.Max(0, bounds.Bottom - work.Bottom);
            if (edge == "Top") return Math.Max(0, work.Top - bounds.Top);
            if (edge == "Right") return Math.Max(0, bounds.Right - work.Right);
            if (edge == "Left") return Math.Max(0, work.Left - bounds.Left);
            return 0;
        }

        private static string TaskbarEdge(Screen screen)
        {
            Rectangle bounds = screen.Bounds;
            Rectangle work = screen.WorkingArea;
            if (work.Bottom < bounds.Bottom) return "Bottom";
            if (work.Top > bounds.Top) return "Top";
            if (work.Right < bounds.Right) return "Right";
            if (work.Left > bounds.Left) return "Left";
            return "Bottom";
        }

        private string ScreenLabel(Screen screen, int index)
        {
            return MonitorDisplayNames.FormatLabel(_settings.T("Monitor"), _settings.T("PrimaryShort"), screen, index);
        }

        private string CurrentTargetDevice()
        {
            if (!String.IsNullOrEmpty(_settings.TargetMonitorDevice)) return _settings.TargetMonitorDevice;
            Screen[] screens = GetTargetScreens();
            return screens.Length > 0 ? screens[0].DeviceName : "";
        }

        private void UpdateMenus(string error)
        {
            foreach (System.Windows.Controls.ContextMenu menu in _menus.ToArray())
            {
                UpdateMenu(menu, error);
            }
        }

        private void UpdateMenu(System.Windows.Controls.ContextMenu menu, string error)
        {
            WpfMenuState state = menu.Tag as WpfMenuState;
            if (state == null) return;

            state.StatusFive.Header = String.IsNullOrEmpty(error) && _summary != null
                ? Math.Round(_summary.FiveRemaining).ToString("0", CultureInfo.InvariantCulture) + "% " + _settings.T("Reset") + " " + RateLimitSummary.FormatReset(_summary.FiveReset)
                : _settings.T("Unavailable");
            state.StatusWeek.Header = String.IsNullOrEmpty(error) && _summary != null
                ? Math.Round(_summary.WeekRemaining).ToString("0", CultureInfo.InvariantCulture) + "% " + _settings.T("Reset") + " " + RateLimitSummary.FormatReset(_summary.WeekReset)
                : (String.IsNullOrEmpty(error) ? _settings.T("Loading") : error);
            state.Refresh.Header = _settings.T("RefreshQuota");
            state.Settings.Header = _settings.T("SettingsMenu");
            state.Open.Header = _settings.T("OpenCodex");
            state.SwitchMonitor.Header = _settings.T("SwitchMonitor");
            state.Exit.Header = _settings.T("Exit");

            string currentDevice = CurrentTargetDevice();
            Screen[] screens = Screen.AllScreens;
            for (int i = 0; i < state.ScreenItems.Count; i++)
            {
                System.Windows.Controls.MenuItem item = state.ScreenItems[i];
                ScreenMenuTag tag = item.Tag as ScreenMenuTag;
                if (i < screens.Length) item.Header = ScreenLabel(screens[i], i);
                item.Icon = tag != null && String.Equals(tag.DeviceName, currentDevice, StringComparison.OrdinalIgnoreCase) ? ">" : "-";
            }
        }

        private static System.Windows.Controls.MenuItem NewWpfMenuItem(string header, string icon, bool enabled)
        {
            System.Windows.Controls.MenuItem item = new System.Windows.Controls.MenuItem();
            item.Header = header;
            item.Icon = icon;
            item.IsEnabled = enabled;
            return item;
        }

        private static void ApplyModernContextMenuStyle(System.Windows.Controls.ContextMenu menu)
        {
            const string xaml =
@"<ResourceDictionary xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                    xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml"">
    <Style x:Key=""ModernContextMenu"" TargetType=""{x:Type ContextMenu}"">
        <Setter Property=""OverridesDefaultStyle"" Value=""True""/>
        <Setter Property=""HasDropShadow"" Value=""True""/>
        <Setter Property=""Background"" Value=""Transparent""/>
        <Setter Property=""BorderThickness"" Value=""0""/>
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""{x:Type ContextMenu}"">
                    <Border Background=""#F0181C24""
                            BorderBrush=""#48FFFFFF""
                            BorderThickness=""1""
                            CornerRadius=""8""
                            Padding=""4"">
                        <StackPanel IsItemsHost=""True""/>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType=""{x:Type MenuItem}"">
        <Setter Property=""Foreground"" Value=""#EAF1F8""/>
        <Setter Property=""FontFamily"" Value=""Microsoft YaHei UI""/>
        <Setter Property=""FontSize"" Value=""11.5""/>
        <Setter Property=""Padding"" Value=""5,5""/>
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""{x:Type MenuItem}"">
                    <Border x:Name=""Bd"" Background=""Transparent"" CornerRadius=""6"" Padding=""{TemplateBinding Padding}"">
                        <Grid MinWidth=""108"">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width=""20""/>
                                <ColumnDefinition Width=""*""/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text=""{TemplateBinding Icon}"" Foreground=""#9BE7B8"" HorizontalAlignment=""Center"" TextAlignment=""Center"" VerticalAlignment=""Center""/>
                            <ContentPresenter Grid.Column=""1"" ContentSource=""Header"" RecognizesAccessKey=""True"" Margin=""3,0,0,0"" VerticalAlignment=""Center""/>
                        </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property=""IsHighlighted"" Value=""True"">
                            <Setter TargetName=""Bd"" Property=""Background"" Value=""#273446""/>
                        </Trigger>
                        <Trigger Property=""IsEnabled"" Value=""False"">
                            <Setter Property=""Foreground"" Value=""#9AA6B2""/>
                            <Setter TargetName=""Bd"" Property=""Opacity"" Value=""0.72""/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType=""{x:Type Separator}"">
        <Setter Property=""Template"">
            <Setter.Value>
                <ControlTemplate TargetType=""{x:Type Separator}"">
                    <Border Height=""1"" Margin=""7,4"" Background=""#344050""/>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>";

            using (System.Xml.XmlReader reader = System.Xml.XmlReader.Create(new StringReader(xaml)))
            {
                System.Windows.ResourceDictionary resources = (System.Windows.ResourceDictionary)System.Windows.Markup.XamlReader.Load(reader);
                menu.Resources.MergedDictionaries.Add(resources);
                menu.Style = (System.Windows.Style)resources["ModernContextMenu"];
            }
        }

        private static void EnsureWpfApplication()
        {
            if (System.Windows.Application.Current == null)
            {
                System.Windows.Application app = new System.Windows.Application();
                app.ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown;
            }
        }

        public void Dispose()
        {
            _disposed = true;
            foreach (WpfOverlayForm form in _forms)
            {
                form.Close();
            }
            _forms.Clear();
            _menus.Clear();
        }

        private void ResumeTopmost()
        {
            if (_topmostSuspendDepth > 0) _topmostSuspendDepth--;
            if (_topmostSuspendDepth == 0)
            {
                foreach (WpfOverlayForm form in _forms)
                {
                    if (form.Visible) form.EnsureTopmost();
                }
            }
        }

        private sealed class TopmostSuspendScope : IDisposable
        {
            private OverlayManager _owner;

            public TopmostSuspendScope(OverlayManager owner)
            {
                _owner = owner;
            }

            public void Dispose()
            {
                OverlayManager owner = _owner;
                _owner = null;
                if (owner != null) owner.ResumeTopmost();
            }
        }
    }

    internal sealed class OverlayLayout
    {
        public double Scale;
        public int Width;
        public int Height;
        public double ActivityIconColumn;
        public double ActivityIconSize;
        public double Margin;
        public double PaddingX;
        public double PaddingY;
        public double CornerRadius;
        public double RowHeight;
        public double TagColumn;
        public double LabelColumn;
        public double BarColumn;
        public double PercentColumn;
        public double TimeColumn;
        public double BarWidth;
        public double BarHeight;
        public double TagFontSize;
        public double LabelFontSize;
        public double PercentFontSize;
        public double TimeFontSize;
    }

    internal static class MonitorDisplayNames
    {
        private const uint EddGetDeviceInterfaceName = 0x00000001;
        private const int MaxDisplayDevices = 32;
        private const int MaxMonitorDevices = 16;

        public static string FormatLabel(string monitorText, string primarySuffix, Screen screen, int index)
        {
            string prefix = TrimMonitorPrefix(monitorText);
            string name = FriendlyName(screen);
            string label = prefix + " " + (index + 1).ToString(CultureInfo.InvariantCulture) + ": " + name;
            if (screen != null && screen.Primary) label += primarySuffix;
            return label;
        }

        public static string FriendlyName(Screen screen)
        {
            if (screen == null || String.IsNullOrEmpty(screen.DeviceName)) return "";
            string name = FindMonitorName(screen.DeviceName);
            return String.IsNullOrEmpty(name) ? screen.DeviceName : name;
        }

        private static string FindMonitorName(string screenDeviceName)
        {
            for (uint i = 0; i < MaxDisplayDevices; i++)
            {
                DisplayDevice adapter = DisplayDevice.Create();
                if (!EnumDisplayDevices(null, i, ref adapter, 0)) break;
                if (!String.Equals(adapter.DeviceName, screenDeviceName, StringComparison.OrdinalIgnoreCase)) continue;
                return FindAttachedMonitorName(adapter.DeviceName);
            }
            return null;
        }

        private static string FindAttachedMonitorName(string adapterDeviceName)
        {
            string fallback = null;
            for (uint i = 0; i < MaxMonitorDevices; i++)
            {
                DisplayDevice monitor = DisplayDevice.Create();
                if (!EnumDisplayDevices(adapterDeviceName, i, ref monitor, EddGetDeviceInterfaceName)) break;
                string name = CleanName(monitor.DeviceString);
                if (String.IsNullOrEmpty(name)) continue;
                if (!IsGenericMonitorName(name)) return name;
                if (String.IsNullOrEmpty(fallback)) fallback = name;
            }
            return fallback;
        }

        private static string CleanName(string name)
        {
            if (String.IsNullOrWhiteSpace(name)) return null;
            return name.Trim();
        }

        private static bool IsGenericMonitorName(string name)
        {
            return name.IndexOf("Generic", StringComparison.OrdinalIgnoreCase) >= 0
                || name.IndexOf("PnP", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static string TrimMonitorPrefix(string value)
        {
            if (String.IsNullOrWhiteSpace(value)) return "Monitor";
            value = value.Trim();
            while (value.EndsWith(":", StringComparison.Ordinal) || value.EndsWith("：", StringComparison.Ordinal))
            {
                value = value.Substring(0, value.Length - 1).TrimEnd();
            }
            return String.IsNullOrEmpty(value) ? "Monitor" : value;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct DisplayDevice
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceKey;

            public static DisplayDevice Create()
            {
                DisplayDevice device = new DisplayDevice();
                device.cb = Marshal.SizeOf(typeof(DisplayDevice));
                return device;
            }
        }

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DisplayDevice lpDisplayDevice, uint dwFlags);
    }

    internal sealed class ScreenMenuTag
    {
        public readonly string DeviceName;
        public readonly int Index;

        public ScreenMenuTag(string deviceName, int index)
        {
            DeviceName = deviceName;
            Index = index;
        }
    }

    internal sealed class WpfMenuState
    {
        public System.Windows.Controls.MenuItem StatusFive;
        public System.Windows.Controls.MenuItem StatusWeek;
        public System.Windows.Controls.MenuItem Refresh;
        public System.Windows.Controls.MenuItem Settings;
        public System.Windows.Controls.MenuItem Open;
        public System.Windows.Controls.MenuItem SwitchMonitor;
        public System.Windows.Controls.MenuItem Exit;
        public readonly List<System.Windows.Controls.MenuItem> ScreenItems = new List<System.Windows.Controls.MenuItem>();
    }

    internal sealed class WpfQuotaRow
    {
        public System.Windows.Controls.Grid Row;
        public System.Windows.Controls.TextBlock Tag;
        public System.Windows.Controls.TextBlock Label;
        public System.Windows.Controls.Border Track;
        public System.Windows.Controls.Border Fill;
        public System.Windows.Controls.TextBlock Percent;
        public System.Windows.Controls.TextBlock Time;
        public System.Windows.Controls.ColumnDefinition[] Columns;
    }

    internal sealed class WpfActivityIcon
    {
        public readonly System.Windows.Controls.Canvas Element;
        private readonly System.Windows.Shapes.Ellipse _ring;
        private readonly System.Windows.Shapes.Ellipse _dot;
        private readonly System.Windows.Shapes.Path _check;
        private readonly System.Windows.Media.RotateTransform _rotate;
        private CodexActivityState _state = CodexActivityState.Idle;

        public WpfActivityIcon()
        {
            Element = new System.Windows.Controls.Canvas();
            Element.Width = 14;
            Element.Height = 14;
            Element.HorizontalAlignment = System.Windows.HorizontalAlignment.Center;
            Element.VerticalAlignment = System.Windows.VerticalAlignment.Center;

            _rotate = new System.Windows.Media.RotateTransform(0);
            _ring = new System.Windows.Shapes.Ellipse();
            _ring.Stroke = MediaBrush(97, 198, 255, 255);
            _ring.StrokeThickness = 1.6;
            _ring.StrokeDashArray = new System.Windows.Media.DoubleCollection(new[] { 2.8, 2.0 });
            _ring.RenderTransform = _rotate;
            _ring.RenderTransformOrigin = new System.Windows.Point(0.5, 0.5);
            Element.Children.Add(_ring);

            _dot = new System.Windows.Shapes.Ellipse();
            _dot.Fill = MediaBrush(154, 166, 178, 255);
            Element.Children.Add(_dot);

            _check = new System.Windows.Shapes.Path();
            _check.Stroke = MediaBrush(98, 230, 154, 255);
            _check.StrokeThickness = 1.8;
            _check.StrokeStartLineCap = System.Windows.Media.PenLineCap.Round;
            _check.StrokeEndLineCap = System.Windows.Media.PenLineCap.Round;
            _check.StrokeLineJoin = System.Windows.Media.PenLineJoin.Round;
            _check.Fill = null;
            Element.Children.Add(_check);

            SetLayout(14);
            SetState(false, CodexActivityState.Idle);
        }

        public void SetLayout(double size)
        {
            size = Math.Max(10, size);
            Element.Width = size;
            Element.Height = size;
            _ring.Width = size;
            _ring.Height = size;
            _ring.StrokeThickness = Math.Max(1.2, Math.Round(size * 0.12, 1));
            System.Windows.Controls.Canvas.SetLeft(_ring, 0);
            System.Windows.Controls.Canvas.SetTop(_ring, 0);

            double dotSize = Math.Max(4, Math.Round(size * 0.42, 1));
            _dot.Width = dotSize;
            _dot.Height = dotSize;
            System.Windows.Controls.Canvas.SetLeft(_dot, Math.Round((size - dotSize) / 2.0, 1));
            System.Windows.Controls.Canvas.SetTop(_dot, Math.Round((size - dotSize) / 2.0, 1));

            _check.StrokeThickness = Math.Max(1.4, Math.Round(size * 0.13, 1));
            _check.Data = BuildCheckGeometry(size);
            SetState(Element.Visibility == System.Windows.Visibility.Visible, _state);
        }

        public void SetState(bool enabled, CodexActivityState state)
        {
            _state = state;
            if (!enabled)
            {
                StopSpin();
                Element.Visibility = System.Windows.Visibility.Collapsed;
                return;
            }

            Element.Visibility = System.Windows.Visibility.Visible;
            if (state == CodexActivityState.Running)
            {
                _ring.Visibility = System.Windows.Visibility.Visible;
                _dot.Visibility = System.Windows.Visibility.Collapsed;
                _check.Visibility = System.Windows.Visibility.Collapsed;
                _ring.Opacity = 1.0;
                StartSpin();
            }
            else if (state == CodexActivityState.Complete)
            {
                StopSpin();
                _ring.Visibility = System.Windows.Visibility.Collapsed;
                _dot.Visibility = System.Windows.Visibility.Collapsed;
                _check.Visibility = System.Windows.Visibility.Visible;
                _check.Opacity = 1.0;
            }
            else
            {
                StopSpin();
                _ring.Visibility = System.Windows.Visibility.Collapsed;
                _dot.Visibility = System.Windows.Visibility.Visible;
                _check.Visibility = System.Windows.Visibility.Collapsed;
                _dot.Opacity = 0.72;
            }
        }

        private void StartSpin()
        {
            System.Windows.Media.Animation.DoubleAnimation animation = new System.Windows.Media.Animation.DoubleAnimation(0, 360, new System.Windows.Duration(TimeSpan.FromMilliseconds(920)));
            animation.RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever;
            _rotate.BeginAnimation(System.Windows.Media.RotateTransform.AngleProperty, animation);
        }

        private void StopSpin()
        {
            _rotate.BeginAnimation(System.Windows.Media.RotateTransform.AngleProperty, null);
            _rotate.Angle = 0;
        }

        private static System.Windows.Media.Geometry BuildCheckGeometry(double size)
        {
            System.Windows.Media.PathFigure figure = new System.Windows.Media.PathFigure();
            figure.StartPoint = new System.Windows.Point(size * 0.22, size * 0.54);
            figure.Segments.Add(new System.Windows.Media.LineSegment(new System.Windows.Point(size * 0.42, size * 0.74), true));
            figure.Segments.Add(new System.Windows.Media.LineSegment(new System.Windows.Point(size * 0.80, size * 0.28), true));
            System.Windows.Media.PathGeometry geometry = new System.Windows.Media.PathGeometry();
            geometry.Figures.Add(figure);
            return geometry;
        }

        private static System.Windows.Media.SolidColorBrush MediaBrush(byte r, byte g, byte b, byte a)
        {
            System.Windows.Media.SolidColorBrush brush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(a, r, g, b));
            brush.Freeze();
            return brush;
        }
    }

    internal sealed class WpfOverlayForm
    {
        private readonly OverlayManager _manager;
        private readonly System.Windows.Window _window;
        private readonly System.Windows.Controls.Border _root;
        private readonly System.Windows.Controls.Grid _contentGrid;
        private readonly System.Windows.Controls.Grid _rowsGrid;
        private readonly System.Windows.Controls.ColumnDefinition _activityColumn;
        private readonly System.Windows.Controls.ColumnDefinition _rowsColumn;
        private readonly WpfActivityIcon _activityIcon;
        private readonly System.Windows.Controls.RowDefinition _row1;
        private readonly System.Windows.Controls.RowDefinition _row2;
        private readonly WpfQuotaRow _five;
        private readonly WpfQuotaRow _week;
        private readonly System.Windows.Controls.ContextMenu _menu;
        private Settings _settings;
        private RateLimitSummary _summary;
        private string _error;
        private CodexActivityState _activityState = CodexActivityState.Idle;
        private double _barWidth = 55;
        private bool _dragging;
        private bool _dragStarted;
        private int _dragStartX;
        private double _dragStartLeft;
        private DateTime _dragStartedAt;
        private Screen _dragScreen;

        public WpfOverlayForm(OverlayManager manager)
        {
            _manager = manager;
            _window = new System.Windows.Window();
            _window.WindowStyle = System.Windows.WindowStyle.None;
            _window.ResizeMode = System.Windows.ResizeMode.NoResize;
            _window.AllowsTransparency = true;
            _window.Background = System.Windows.Media.Brushes.Transparent;
            _window.ShowInTaskbar = false;
            _window.Topmost = true;
            _window.ShowActivated = false;
            _window.Width = 245;
            _window.Height = 42;
            _window.WindowStartupLocation = System.Windows.WindowStartupLocation.Manual;
            _window.UseLayoutRounding = false;
            _window.SnapsToDevicePixels = false;
            _window.SourceInitialized += delegate { NativeOverlayWindow.Configure(_window); };

            _menu = manager.BuildMenu();
            _root = new System.Windows.Controls.Border();
            _root.CornerRadius = new System.Windows.CornerRadius(7);
            _root.Background = MediaBrush(17, 20, 25, 245);
            _root.BorderBrush = MediaBrush(255, 255, 255, 54);
            _root.BorderThickness = new System.Windows.Thickness(1);
            _root.Margin = new System.Windows.Thickness(1);
            _root.Padding = new System.Windows.Thickness(7, 3, 7, 3);
            _root.ContextMenu = _menu;
            _root.SnapsToDevicePixels = false;
            System.Windows.Media.TextOptions.SetTextFormattingMode(_root, System.Windows.Media.TextFormattingMode.Display);
            System.Windows.Media.TextOptions.SetTextRenderingMode(_root, System.Windows.Media.TextRenderingMode.ClearType);

            _contentGrid = new System.Windows.Controls.Grid();
            _contentGrid.VerticalAlignment = System.Windows.VerticalAlignment.Center;
            _activityColumn = AddColumn(_contentGrid, 0);
            _rowsColumn = AddColumn(_contentGrid, 227);
            _activityIcon = new WpfActivityIcon();
            System.Windows.Controls.Grid.SetColumn(_activityIcon.Element, 0);
            _contentGrid.Children.Add(_activityIcon.Element);

            _rowsGrid = new System.Windows.Controls.Grid();
            _rowsGrid.VerticalAlignment = System.Windows.VerticalAlignment.Center;
            System.Windows.Controls.Grid.SetColumn(_rowsGrid, 1);
            _contentGrid.Children.Add(_rowsGrid);
            _row1 = new System.Windows.Controls.RowDefinition();
            _row1.Height = new System.Windows.GridLength(16);
            _row2 = new System.Windows.Controls.RowDefinition();
            _row2.Height = new System.Windows.GridLength(16);
            _rowsGrid.RowDefinitions.Add(_row1);
            _rowsGrid.RowDefinitions.Add(_row2);
            _root.Child = _contentGrid;
            _window.Content = _root;

            _five = NewQuotaRow("5H", MediaBrush(98, 230, 154, 255), 55);
            _week = NewQuotaRow("W", MediaBrush(97, 198, 255, 255), 55);
            System.Windows.Controls.Grid.SetRow(_five.Row, 0);
            System.Windows.Controls.Grid.SetRow(_week.Row, 1);
            _rowsGrid.Children.Add(_five.Row);
            _rowsGrid.Children.Add(_week.Row);

            _root.MouseEnter += delegate
            {
                _root.Background = MediaBrush(24, 29, 37, 250);
                _root.BorderBrush = MediaBrush(255, 255, 255, 86);
            };
            _root.MouseLeave += delegate
            {
                _root.Background = MediaBrush(17, 20, 25, 245);
                _root.BorderBrush = MediaBrush(255, 255, 255, 54);
            };
            _root.MouseLeftButtonDown += OnMouseLeftButtonDown;
            _root.MouseMove += OnMouseMove;
            _root.MouseLeftButtonUp += OnMouseLeftButtonUp;
            _root.MouseRightButtonUp += OnMouseRightButtonUp;
        }

        public bool Visible { get { return _window.IsVisible; } }
        public double Left { get { return _window.Left; } }
        public double Width { get { return _window.Width; } }
        public System.Drawing.Point CenterPoint
        {
            get { return new System.Drawing.Point((int)(_window.Left + (_window.Width / 2.0)), (int)(_window.Top + (_window.Height / 2.0))); }
        }

        public void SetSettings(Settings settings)
        {
            _settings = settings;
            ApplyActivityState();
            ApplySummary();
        }

        public void SetActivityState(CodexActivityState state)
        {
            _activityState = state;
            ApplyActivityState();
        }

        public void SetSummary(RateLimitSummary summary)
        {
            _summary = summary;
            _error = null;
            ApplySummary();
        }

        public void SetError(string error)
        {
            _summary = null;
            _error = error;
            ApplySummary();
        }

        public void SetLayout(OverlayLayout layout)
        {
            _window.Width = layout.Width;
            _window.Height = layout.Height;
            _root.CornerRadius = new System.Windows.CornerRadius(layout.CornerRadius);
            _root.Margin = new System.Windows.Thickness(layout.Margin);
            _root.Padding = new System.Windows.Thickness(layout.PaddingX, layout.PaddingY, layout.PaddingX, layout.PaddingY);
            SetColumnWidth(_activityColumn, _settings != null && _settings.ShowActivityIcon ? layout.ActivityIconColumn : 0);
            SetColumnWidth(_rowsColumn, layout.TagColumn + layout.LabelColumn + layout.BarColumn + layout.PercentColumn + layout.TimeColumn);
            _activityIcon.SetLayout(layout.ActivityIconSize);
            _row1.Height = new System.Windows.GridLength(layout.RowHeight);
            _row2.Height = new System.Windows.GridLength(layout.RowHeight);
            SetQuotaRowLayout(_five, layout);
            SetQuotaRowLayout(_week, layout);
            _barWidth = layout.BarWidth;
            ApplyActivityState();
            ApplySummary();
        }

        public void SetBounds(Rectangle rect)
        {
            _window.Width = rect.Width;
            _window.Height = rect.Height;
            _window.Left = rect.X;
            _window.Top = rect.Y;
        }

        public void Show()
        {
            _window.Show();
            NativeOverlayWindow.Configure(_window);
        }

        public void Hide()
        {
            _window.Hide();
        }

        public void EnsureTopmost()
        {
            if (!_window.Topmost) _window.Topmost = true;
            NativeOverlayWindow.EnsureTopmost(_window);
        }

        public void SetTopmost(bool topmost)
        {
            _window.Topmost = topmost;
            if (topmost)
            {
                NativeOverlayWindow.EnsureTopmost(_window);
            }
            else
            {
                NativeOverlayWindow.ClearTopmost(_window);
            }
        }

        public void Close()
        {
            _window.Close();
        }

        public void SaveOverlayPng(string path)
        {
            SaveFrameworkElementPng(_window.Content as System.Windows.FrameworkElement, path);
        }

        public bool SaveMenuPng(string path)
        {
            if (_menu == null) return false;
            _menu.PlacementTarget = _root;
            _menu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom;
            _menu.IsOpen = true;
            System.Windows.Forms.Application.DoEvents();
            _menu.Dispatcher.Invoke(System.Windows.Threading.DispatcherPriority.Render, new Action(delegate { }));
            bool saved = SaveFrameworkElementPng(_menu, path);
            _menu.IsOpen = false;
            return saved;
        }

        private void ApplySummary()
        {
            if (_settings == null) return;
            if (!String.IsNullOrEmpty(_error))
            {
                _root.Background = MediaBrush(25, 18, 20, 245);
                _five.Label.Text = _settings.T("Unavailable");
                _five.Percent.Text = "!";
                _five.Time.Text = "";
                _week.Label.Text = _error;
                _week.Percent.Text = "";
                _week.Time.Text = "";
                _five.Fill.Width = 0;
                _week.Fill.Width = 0;
                return;
            }

            RateLimitSummary summary = _summary ?? RateLimitSummary.Mock();
            _root.Background = MediaBrush(17, 20, 25, 245);
            ApplyQuotaRow(_five, summary.FiveRemaining, RateLimitSummary.FormatReset(summary.FiveReset));
            ApplyQuotaRow(_week, summary.WeekRemaining, RateLimitSummary.FormatReset(summary.WeekReset));
        }

        private void ApplyActivityState()
        {
            if (_settings == null) return;
            _activityIcon.SetState(_settings.ShowActivityIcon, _activityState);
        }

        private void ApplyQuotaRow(WpfQuotaRow row, double remaining, string reset)
        {
            row.Label.Text = _settings.T("QuotaRemaining");
            row.Percent.Text = Math.Round(remaining).ToString("0", CultureInfo.InvariantCulture) + "%";
            row.Time.Text = reset;
            row.Fill.Width = Math.Max(0, Math.Round(_barWidth * Math.Max(0, Math.Min(100, remaining)) / 100.0));
        }

        private void OnMouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            if (e.ClickCount >= 2)
            {
                _dragging = false;
                _dragStarted = false;
                NativeWindowActivation.ShowCodexWindow();
                EnsureTopmost();
                e.Handled = true;
                return;
            }

            _dragging = true;
            _dragStarted = false;
            _dragStartX = System.Windows.Forms.Cursor.Position.X;
            _dragStartLeft = _window.Left;
            _dragStartedAt = DateTime.Now;
            _dragScreen = Screen.FromPoint(CenterPoint);
            _root.CaptureMouse();
            e.Handled = true;
        }

        private void OnMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
        {
            if (!_dragging || e.LeftButton != System.Windows.Input.MouseButtonState.Pressed) return;
            int dxPixels = System.Windows.Forms.Cursor.Position.X - _dragStartX;
            double elapsed = (DateTime.Now - _dragStartedAt).TotalMilliseconds;
            if (!_dragStarted && (Math.Abs(dxPixels) >= 6 || elapsed >= 220))
            {
                _dragStarted = true;
            }
            if (_dragStarted)
            {
                double dx = GetDipDeltaX(dxPixels);
                _window.Left = _manager.ClampDraggedLeft(this, _dragStartLeft + dx, _dragScreen);
                EnsureTopmost();
                e.Handled = true;
            }
        }

        private void OnMouseLeftButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            if (!_dragging) return;
            _root.ReleaseMouseCapture();
            if (_dragStarted)
            {
                _manager.SaveDragOffset(this);
            }
            else
            {
                _manager.RefreshQuotaAsync("overlay-click");
            }
            _dragging = false;
            _dragStarted = false;
            _dragScreen = null;
            e.Handled = true;
        }

        private void OnMouseRightButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            _menu.PlacementTarget = _root;
            _menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
            _menu.IsOpen = true;
            e.Handled = true;
        }

        private double GetDipDeltaX(double pixels)
        {
            System.Windows.PresentationSource source = System.Windows.PresentationSource.FromVisual(_window);
            if (source != null && source.CompositionTarget != null)
            {
                return pixels * source.CompositionTarget.TransformFromDevice.M11;
            }
            return pixels;
        }

        private static WpfQuotaRow NewQuotaRow(string tag, System.Windows.Media.Brush accent, double barWidth)
        {
            WpfQuotaRow result = new WpfQuotaRow();
            result.Row = new System.Windows.Controls.Grid();
            result.Row.Height = 16;
            result.Row.SnapsToDevicePixels = true;
            System.Windows.Controls.ColumnDefinition c0 = AddColumn(result.Row, 23);
            System.Windows.Controls.ColumnDefinition c1 = AddColumn(result.Row, 70);
            System.Windows.Controls.ColumnDefinition c2 = AddColumn(result.Row, 55);
            System.Windows.Controls.ColumnDefinition c3 = AddColumn(result.Row, 32);
            System.Windows.Controls.ColumnDefinition c4 = AddColumn(result.Row, 47);
            result.Columns = new[] { c0, c1, c2, c3, c4 };

            result.Tag = NewTextBlock(tag, 11.2, accent, "Segoe UI", System.Windows.FontWeights.Bold, System.Windows.TextAlignment.Center);
            System.Windows.Controls.Grid.SetColumn(result.Tag, 0);
            result.Row.Children.Add(result.Tag);

            result.Label = NewTextBlock("", 10.4, MediaBrush(235, 241, 248, 255), "Microsoft YaHei UI", System.Windows.FontWeights.Normal, System.Windows.TextAlignment.Left);
            System.Windows.Controls.Grid.SetColumn(result.Label, 1);
            result.Row.Children.Add(result.Label);

            result.Track = new System.Windows.Controls.Border();
            result.Track.Width = barWidth;
            result.Track.Height = 8;
            result.Track.CornerRadius = new System.Windows.CornerRadius(4);
            result.Track.Background = MediaBrush(78, 86, 98, 255);
            result.Track.HorizontalAlignment = System.Windows.HorizontalAlignment.Left;
            result.Track.VerticalAlignment = System.Windows.VerticalAlignment.Center;

            System.Windows.Controls.Grid trackGrid = new System.Windows.Controls.Grid();
            result.Fill = new System.Windows.Controls.Border();
            result.Fill.Width = 0;
            result.Fill.Height = 8;
            result.Fill.CornerRadius = new System.Windows.CornerRadius(4);
            result.Fill.Background = accent;
            result.Fill.HorizontalAlignment = System.Windows.HorizontalAlignment.Left;
            trackGrid.Children.Add(result.Fill);
            result.Track.Child = trackGrid;
            System.Windows.Controls.Grid.SetColumn(result.Track, 2);
            result.Row.Children.Add(result.Track);

            result.Percent = NewTextBlock("0%", 10.6, MediaBrush(235, 241, 248, 255), "Segoe UI", System.Windows.FontWeights.Bold, System.Windows.TextAlignment.Right);
            System.Windows.Controls.Grid.SetColumn(result.Percent, 3);
            result.Row.Children.Add(result.Percent);

            result.Time = NewTextBlock("--:--", 9.6, MediaBrush(202, 211, 222, 255), "Segoe UI", System.Windows.FontWeights.Normal, System.Windows.TextAlignment.Right);
            System.Windows.Controls.Grid.SetColumn(result.Time, 4);
            result.Row.Children.Add(result.Time);
            return result;
        }

        private static void SetQuotaRowLayout(WpfQuotaRow row, OverlayLayout layout)
        {
            row.Row.Height = layout.RowHeight;
            SetColumnWidth(row.Columns[0], layout.TagColumn);
            SetColumnWidth(row.Columns[1], layout.LabelColumn);
            SetColumnWidth(row.Columns[2], layout.BarColumn);
            SetColumnWidth(row.Columns[3], layout.PercentColumn);
            SetColumnWidth(row.Columns[4], layout.TimeColumn);
            row.Tag.FontSize = layout.TagFontSize;
            row.Label.FontSize = layout.LabelFontSize;
            row.Percent.FontSize = layout.PercentFontSize;
            row.Time.FontSize = layout.TimeFontSize;
            row.Track.Width = layout.BarWidth;
            row.Track.Height = layout.BarHeight;
            row.Track.CornerRadius = new System.Windows.CornerRadius(layout.BarHeight / 2.0);
            row.Fill.Height = layout.BarHeight;
            row.Fill.CornerRadius = new System.Windows.CornerRadius(layout.BarHeight / 2.0);
        }

        private static System.Windows.Controls.TextBlock NewTextBlock(string text, double fontSize, System.Windows.Media.Brush foreground, string fontFamily, System.Windows.FontWeight fontWeight, System.Windows.TextAlignment alignment)
        {
            System.Windows.Controls.TextBlock block = new System.Windows.Controls.TextBlock();
            block.Text = text;
            block.FontSize = fontSize;
            block.FontFamily = new System.Windows.Media.FontFamily(fontFamily);
            block.FontWeight = fontWeight;
            block.Foreground = foreground;
            block.TextAlignment = alignment;
            block.HorizontalAlignment = System.Windows.HorizontalAlignment.Stretch;
            block.VerticalAlignment = System.Windows.VerticalAlignment.Center;
            block.TextTrimming = System.Windows.TextTrimming.CharacterEllipsis;
            return block;
        }

        private static System.Windows.Controls.ColumnDefinition AddColumn(System.Windows.Controls.Grid grid, double width)
        {
            System.Windows.Controls.ColumnDefinition column = new System.Windows.Controls.ColumnDefinition();
            column.Width = new System.Windows.GridLength(width);
            grid.ColumnDefinitions.Add(column);
            return column;
        }

        private static void SetColumnWidth(System.Windows.Controls.ColumnDefinition column, double width)
        {
            column.Width = new System.Windows.GridLength(width);
        }

        private static System.Windows.Media.SolidColorBrush MediaBrush(byte r, byte g, byte b, byte a)
        {
            System.Windows.Media.SolidColorBrush brush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(a, r, g, b));
            brush.Freeze();
            return brush;
        }

        private static bool SaveFrameworkElementPng(System.Windows.FrameworkElement element, string path)
        {
            if (element == null) return false;
            element.UpdateLayout();
            int width = (int)Math.Ceiling(element.ActualWidth);
            int height = (int)Math.Ceiling(element.ActualHeight);
            if (width <= 0 || height <= 0) return false;
            System.Windows.Media.Imaging.RenderTargetBitmap bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(width, height, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
            bitmap.Render(element);
            System.Windows.Media.Imaging.PngBitmapEncoder encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
            encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
            using (FileStream stream = File.Open(path, FileMode.Create))
            {
                encoder.Save(stream);
            }
            return true;
        }
    }

    internal static class NativeOverlayWindow
    {
        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
        private const int GWL_EXSTYLE = -20;
        private const long WS_EX_TOOLWINDOW = 0x00000080L;
        private const long WS_EX_NOACTIVATE = 0x08000000L;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_FRAMECHANGED = 0x0020;
        private const uint SWP_SHOWWINDOW = 0x0040;

        public static void Configure(System.Windows.Window window)
        {
            IntPtr handle = new System.Windows.Interop.WindowInteropHelper(window).Handle;
            if (handle == IntPtr.Zero) return;
            long style = GetWindowLongPtr(handle, GWL_EXSTYLE).ToInt64();
            style = style | WS_EX_TOOLWINDOW;
            style = style & ~WS_EX_NOACTIVATE;
            SetWindowLongPtr(handle, GWL_EXSTYLE, new IntPtr(style));
            SetWindowPos(handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        }

        public static void EnsureTopmost(System.Windows.Window window)
        {
            IntPtr handle = new System.Windows.Interop.WindowInteropHelper(window).Handle;
            if (handle == IntPtr.Zero) return;
            SetWindowPos(handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        public static void ClearTopmost(System.Windows.Window window)
        {
            IntPtr handle = new System.Windows.Interop.WindowInteropHelper(window).Handle;
            if (handle == IntPtr.Zero) return;
            SetWindowPos(handle, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        private static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex)
        {
            if (IntPtr.Size == 8) return GetWindowLongPtr64(hWnd, nIndex);
            return new IntPtr(GetWindowLong32(hWnd, nIndex));
        }

        private static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong)
        {
            if (IntPtr.Size == 8) return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
            return new IntPtr(SetWindowLong32(hWnd, nIndex, dwNewLong.ToInt32()));
        }

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
        private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
        private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
        private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    }

    internal sealed class ModernContextMenuStrip : ContextMenuStrip
    {
        public ModernContextMenuStrip()
        {
            ShowImageMargin = true;
            ShowCheckMargin = false;
            BackColor = Color.FromArgb(240, 24, 28, 36);
            ForeColor = Color.FromArgb(234, 241, 248);
            Font = new Font("Microsoft YaHei UI", 8.6f, FontStyle.Regular);
            Padding = new Padding(4);
            Margin = Padding.Empty;
            ImageScalingSize = new Size(20, 16);
            Renderer = new ModernMenuRenderer();
        }

        protected override void OnOpened(EventArgs e)
        {
            base.OnOpened(e);
            try
            {
                using (GraphicsPath path = Rounded(new Rectangle(0, 0, Width, Height), 8))
                {
                    Region = new Region(path);
                }
            }
            catch
            {
            }
        }

        protected override void OnClosed(ToolStripDropDownClosedEventArgs e)
        {
            if (Region != null)
            {
                Region.Dispose();
                Region = null;
            }
            base.OnClosed(e);
        }

        private static GraphicsPath Rounded(Rectangle rect, int radius)
        {
            rect.Width -= 1;
            rect.Height -= 1;
            GraphicsPath path = new GraphicsPath();
            int diameter = radius * 2;
            path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class ModernMenuItem : ToolStripMenuItem
    {
        private string _iconText;
        public bool Passive { get; private set; }

        public ModernMenuItem(string text, string iconText, bool enabled)
            : base(text)
        {
            _iconText = iconText ?? "";
            Passive = !enabled;
            Enabled = true;
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText;
            ImageScaling = ToolStripItemImageScaling.None;
            Padding = new Padding(5, 5, 8, 5);
            Margin = Padding.Empty;
            AutoSize = true;
            ForeColor = Passive ? Color.FromArgb(154, 166, 178) : Color.FromArgb(234, 241, 248);
            Image = CreateIconImage(_iconText, !Passive);
        }

        public void SetIconText(string iconText)
        {
            _iconText = iconText ?? "";
            Image old = Image;
            Image = CreateIconImage(_iconText, !Passive);
            if (old != null) old.Dispose();
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            base.OnEnabledChanged(e);
            ForeColor = Passive ? Color.FromArgb(154, 166, 178) : Color.FromArgb(234, 241, 248);
            SetIconText(_iconText);
        }

        protected override void OnClick(EventArgs e)
        {
            if (Passive) return;
            base.OnClick(e);
        }

        private static Bitmap CreateIconImage(string text, bool enabled)
        {
            Bitmap bitmap = new Bitmap(20, 16);
            Color color = Color.FromArgb(155, 231, 184);
            if (String.Equals(text, "W", StringComparison.OrdinalIgnoreCase))
            {
                color = Color.FromArgb(97, 198, 255);
            }
            else if (!enabled && !String.Equals(text, "5H", StringComparison.OrdinalIgnoreCase))
            {
                color = Color.FromArgb(122, 135, 149);
            }
            using (Graphics g = Graphics.FromImage(bitmap))
            using (Font font = new Font("Segoe UI", text != null && text.Length > 1 ? 7.4f : 8.4f, FontStyle.Bold, GraphicsUnit.Point))
            using (Brush brush = new SolidBrush(color))
            using (StringFormat format = new StringFormat())
            {
                g.Clear(Color.Transparent);
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                g.DrawString(text ?? "", font, brush, new RectangleF(0, 0, 20, 16), format);
            }
            return bitmap;
        }
    }

    internal sealed class ModernMenuRenderer : ToolStripProfessionalRenderer
    {
        public ModernMenuRenderer()
            : base(new ModernMenuColorTable())
        {
            RoundedEdges = true;
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rect = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
            using (GraphicsPath path = Rounded(rect, 8))
            using (Brush brush = new SolidBrush(Color.FromArgb(240, 24, 28, 36)))
            {
                e.Graphics.FillPath(brush, path);
            }
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rect = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
            using (GraphicsPath path = Rounded(rect, 8))
            using (Pen pen = new Pen(Color.FromArgb(72, 255, 255, 255)))
            {
                e.Graphics.DrawPath(pen, path);
            }
        }

        protected override void OnRenderImageMargin(ToolStripRenderEventArgs e)
        {
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            ModernMenuItem modern = e.Item as ModernMenuItem;
            if (!e.Item.Selected || !e.Item.Enabled || (modern != null && modern.Passive)) return;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rect = new Rectangle(4, 2, e.Item.Width - 8, e.Item.Height - 4);
            using (GraphicsPath path = Rounded(rect, 6))
            using (Brush brush = new SolidBrush(Color.FromArgb(39, 52, 70)))
            {
                e.Graphics.FillPath(brush, path);
            }
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            ModernMenuItem modern = e.Item as ModernMenuItem;
            e.TextColor = e.Item.Enabled && (modern == null || !modern.Passive) ? Color.FromArgb(234, 241, 248) : Color.FromArgb(154, 166, 178);
            e.TextFont = new Font("Microsoft YaHei UI", 8.6f, FontStyle.Regular, GraphicsUnit.Point);
            base.OnRenderItemText(e);
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            Rectangle rect = new Rectangle(7, e.Item.Height / 2, e.Item.Width - 14, 1);
            using (Pen pen = new Pen(Color.FromArgb(52, 64, 80)))
            {
                e.Graphics.DrawLine(pen, rect.Left, rect.Top, rect.Right, rect.Top);
            }
        }

        private static GraphicsPath Rounded(Rectangle rect, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int diameter = radius * 2;
            path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class ModernMenuColorTable : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Color.FromArgb(240, 24, 28, 36); } }
        public override Color ImageMarginGradientBegin { get { return Color.FromArgb(240, 24, 28, 36); } }
        public override Color ImageMarginGradientMiddle { get { return Color.FromArgb(240, 24, 28, 36); } }
        public override Color ImageMarginGradientEnd { get { return Color.FromArgb(240, 24, 28, 36); } }
        public override Color MenuBorder { get { return Color.Transparent; } }
        public override Color MenuItemBorder { get { return Color.Transparent; } }
        public override Color MenuItemSelected { get { return Color.FromArgb(39, 52, 70); } }
    }

    internal sealed class VisualQaContext : ApplicationContext
    {
        private readonly Options _options;
        private readonly OverlayManager _manager;
        private readonly System.Windows.Forms.Timer _timer;

        public VisualQaContext(Options options, Settings settings)
        {
            _options = options;
            options.MockQuota = true;
            settings.ShowActivityIcon = true;
            QuotaService quota = new QuotaService(options);
            _manager = new OverlayManager(options, settings, quota, ExitThread);
            _manager.UpdateActivityState(CodexActivityState.Running);
            _manager.RefreshQuota();
            _manager.EnsureVisible();
            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 700;
            _timer.Tick += delegate
            {
                _timer.Stop();
                SaveArtifacts();
                ExitThread();
            };
            _timer.Start();
        }

        private void SaveArtifacts()
        {
            string outputDir = _options.VisualQaOutputDir;
            if (String.IsNullOrEmpty(outputDir)) outputDir = Path.Combine(AppPaths.LocalData, "visual-qa-native");
            Directory.CreateDirectory(outputDir);

            List<string> files = new List<string>();
            int index = 1;
            foreach (WpfOverlayForm form in _manager.Forms)
            {
                if (form.Visible)
                {
                    string file = "native-overlay-" + index.ToString(CultureInfo.InvariantCulture) + ".png";
                    string path = Path.Combine(outputDir, file);
                    form.SaveOverlayPng(path);
                    if (File.Exists(path))
                    {
                        files.Add(file);
                    }

                    if (form.Visible)
                    {
                        string menuFile = "native-menu-" + index.ToString(CultureInfo.InvariantCulture) + ".png";
                        string menuPath = Path.Combine(outputDir, menuFile);
                        if (form.SaveMenuPng(menuPath) && File.Exists(menuPath))
                        {
                            files.Add(menuFile);
                        }
                    }
                    index++;
                }
            }
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            Dictionary<string, object> metadata = new Dictionary<string, object>();
            metadata["CapturedAt"] = DateTime.Now.ToString("o", CultureInfo.InvariantCulture);
            metadata["MockQuota"] = true;
            metadata["Files"] = files.ToArray();
            File.WriteAllText(Path.Combine(outputDir, "native-visual-qa.json"), serializer.Serialize(metadata), Encoding.UTF8);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _timer.Dispose();
                _manager.Dispose();
            }
            base.Dispose(disposing);
        }
    }

    internal static class SettingsDialog
    {
        public static Settings Show(Settings current)
        {
            return Show(current, null);
        }

        public static Settings Show(Settings current, Action<string> onLanguageChanged)
        {
            string language = Settings.NormalizeLanguage(current.Language);
            Form form = new Form();
            form.ClientSize = new Size(470, 340);
            form.StartPosition = FormStartPosition.CenterScreen;
            form.FormBorderStyle = FormBorderStyle.FixedDialog;
            form.MaximizeBox = false;
            form.MinimizeBox = false;
            form.TopMost = true;
            form.ShowInTaskbar = false;
            form.Font = SystemFonts.MessageBoxFont;
            form.AutoScaleMode = AutoScaleMode.Dpi;

            TabControl tabs = new TabControl();
            tabs.SetBounds(12, 12, 446, 276);
            TabPage general = new TabPage();
            TabPage display = new TabPage();
            TabPage about = new TabPage();
            tabs.TabPages.Add(general);
            tabs.TabPages.Add(display);
            tabs.TabPages.Add(about);
            form.Controls.Add(tabs);

            Label languageLabel = Label("", 12, 16, 112);
            general.Controls.Add(languageLabel);
            ComboBox languageBox = new ComboBox();
            languageBox.SetBounds(124, 14, 150, 24);
            languageBox.DropDownStyle = ComboBoxStyle.DropDownList;
            languageBox.Items.Add("简体中文");
            languageBox.Items.Add("English");
            languageBox.SelectedIndex = language == "en-US" ? 1 : 0;
            general.Controls.Add(languageBox);

            GroupBox settingsGroup = new GroupBox();
            settingsGroup.SetBounds(10, 54, 414, 104);
            general.Controls.Add(settingsGroup);
            Label pathLabel = Label("", 10, 24, 58);
            settingsGroup.Controls.Add(pathLabel);
            settingsGroup.Controls.Add(ReadOnlyText(74, 22, 326, AppPaths.SettingsPath));
            Button openSettings = new Button();
            openSettings.SetBounds(74, 62, 140, 27);
            openSettings.Click += delegate { OpenFolder(Path.GetDirectoryName(AppPaths.SettingsPath)); };
            settingsGroup.Controls.Add(openSettings);
            Button openLogs = new Button();
            openLogs.SetBounds(224, 62, 150, 27);
            openLogs.Click += delegate { OpenFolder(AppPaths.Logs); };
            settingsGroup.Controls.Add(openLogs);

            Label monitorLabel = Label("", 12, 18, 100);
            display.Controls.Add(monitorLabel);
            ComboBox monitorBox = new ComboBox();
            monitorBox.SetBounds(116, 15, 308, 24);
            monitorBox.DropDownStyle = ComboBoxStyle.DropDownList;
            ArrayList devices = new ArrayList();
            Screen[] screens = Screen.AllScreens;
            display.Controls.Add(monitorBox);

            GroupBox monitorGroup = new GroupBox();
            monitorGroup.SetBounds(10, 54, 414, 142);
            display.Controls.Add(monitorGroup);
            Label deviceLabel = Label("", 10, 25, 100);
            monitorGroup.Controls.Add(deviceLabel);
            TextBox device = ReadOnlyText(116, 23, 284, "");
            monitorGroup.Controls.Add(device);
            Label boundsLabel = Label("", 10, 58, 100);
            monitorGroup.Controls.Add(boundsLabel);
            TextBox bounds = ReadOnlyText(116, 56, 284, "");
            monitorGroup.Controls.Add(bounds);
            Label workLabel = Label("", 10, 91, 100);
            monitorGroup.Controls.Add(workLabel);
            TextBox work = ReadOnlyText(116, 89, 284, "");
            monitorGroup.Controls.Add(work);
            CheckBox statusIconBox = new CheckBox();
            statusIconBox.SetBounds(12, 212, 360, 24);
            statusIconBox.Checked = current.ShowActivityIcon;
            display.Controls.Add(statusIconBox);
            Action update = delegate
            {
                int index = monitorBox.SelectedIndex;
                if (index < 0 || index >= screens.Length) return;
                Screen screen = screens[index];
                device.Text = MonitorDisplayNames.FriendlyName(screen);
                bounds.Text = screen.Bounds.Width + "x" + screen.Bounds.Height + ", " + screen.Bounds.X + "," + screen.Bounds.Y;
                work.Text = screen.WorkingArea.Width + "x" + screen.WorkingArea.Height + ", " + screen.WorkingArea.X + "," + screen.WorkingArea.Y;
            };
            monitorBox.SelectedIndexChanged += delegate { update(); };
            Action refreshMonitorItems = delegate
            {
                string selectedDevice = monitorBox.SelectedIndex >= 0 && monitorBox.SelectedIndex < devices.Count
                    ? Convert.ToString(devices[monitorBox.SelectedIndex], CultureInfo.InvariantCulture)
                    : current.TargetMonitorDevice;
                monitorBox.BeginUpdate();
                monitorBox.Items.Clear();
                devices.Clear();
                for (int i = 0; i < screens.Length; i++)
                {
                    Screen screen = screens[i];
                    monitorBox.Items.Add(MonitorDisplayNames.FormatLabel(Text.For("Monitor", language), Text.For("Primary", language), screen, i) + " (" + screen.Bounds.Width + "x" + screen.Bounds.Height + ", " + screen.Bounds.X + "," + screen.Bounds.Y + ")");
                    devices.Add(screen.DeviceName);
                    if (screen.DeviceName == selectedDevice) monitorBox.SelectedIndex = i;
                }
                if (monitorBox.SelectedIndex < 0 && monitorBox.Items.Count > 0) monitorBox.SelectedIndex = 0;
                monitorBox.EndUpdate();
                update();
            };

            GroupBox aboutGroup = new GroupBox();
            aboutGroup.SetBounds(10, 18, 414, 130);
            about.Controls.Add(aboutGroup);
            aboutGroup.Controls.Add(Label("Codex Quota Taskbar", 10, 24, 320));
            Label versionLabel = Label("", 10, 52, 96);
            aboutGroup.Controls.Add(versionLabel);
            aboutGroup.Controls.Add(Label(ReadVersion(), 116, 52, 284));
            Label installPathLabel = Label("", 10, 82, 96);
            aboutGroup.Controls.Add(installPathLabel);
            aboutGroup.Controls.Add(ReadOnlyText(116, 80, 284, GetInstallRoot()));

            Button restore = new Button();
            restore.Click += delegate
            {
                languageBox.SelectedIndex = Settings.DefaultLanguage() == "en-US" ? 1 : 0;
                statusIconBox.Checked = false;
                for (int i = 0; i < screens.Length; i++)
                {
                    if (screens[i].Primary)
                    {
                        monitorBox.SelectedIndex = i;
                        return;
                    }
                }
                if (monitorBox.Items.Count > 0) monitorBox.SelectedIndex = 0;
            };
            form.Controls.Add(restore);

            Button save = new Button();
            save.DialogResult = DialogResult.OK;
            form.Controls.Add(save);
            Button cancel = new Button();
            cancel.DialogResult = DialogResult.Cancel;
            form.Controls.Add(cancel);
            form.AcceptButton = save;
            form.CancelButton = cancel;

            bool suppressLanguageCallback = true;
            Action applyLanguage = delegate
            {
                language = languageBox.SelectedIndex == 1 ? "en-US" : "zh-CN";
                form.Text = Text.For("SettingsTitle", language);
                general.Text = Text.For("General", language);
                display.Text = Text.For("Display", language);
                about.Text = Text.For("About", language);
                languageLabel.Text = Text.For("DisplayLanguage", language);
                settingsGroup.Text = Text.For("SettingsFile", language);
                pathLabel.Text = Text.For("Path", language);
                openSettings.Text = Text.For("OpenFolder", language);
                openLogs.Text = Text.For("OpenLogs", language);
                monitorLabel.Text = Text.For("Monitor", language);
                statusIconBox.Text = Text.For("ShowActivityIcon", language);
                monitorGroup.Text = Text.For("SelectedMonitor", language);
                deviceLabel.Text = Text.For("Device", language);
                boundsLabel.Text = Text.For("Bounds", language);
                workLabel.Text = Text.For("WorkingArea", language);
                aboutGroup.Text = Text.For("RuntimeInfo", language);
                versionLabel.Text = Text.For("Version", language);
                installPathLabel.Text = Text.For("InstallPath", language);
                restore.Text = Text.For("RestoreDefault", language);
                save.Text = Text.For("Save", language);
                cancel.Text = Text.For("Cancel", language);
                refreshMonitorItems();
                LayoutFooterButtons(form, restore, save, cancel);
                LayoutGroupButtons(openSettings, openLogs);
                if (!suppressLanguageCallback && onLanguageChanged != null)
                {
                    onLanguageChanged(language);
                }
            };
            languageBox.SelectedIndexChanged += delegate { applyLanguage(); };
            applyLanguage();
            suppressLanguageCallback = false;

            if (form.ShowDialog() != DialogResult.OK) return null;
            Settings edited = new Settings();
            edited.TargetMonitorDevice = monitorBox.SelectedIndex >= 0 ? Convert.ToString(devices[monitorBox.SelectedIndex], CultureInfo.InvariantCulture) : current.TargetMonitorDevice;
            edited.XOffset = current.XOffset;
            edited.VerticalOffset = current.VerticalOffset;
            edited.Language = languageBox.SelectedIndex == 1 ? "en-US" : "zh-CN";
            edited.ShowActivityIcon = statusIconBox.Checked;
            return edited;
        }

        private static void LayoutFooterButtons(Form form, Button restore, Button save, Button cancel)
        {
            const int margin = 12;
            const int gap = 8;
            int top = form.ClientSize.Height - 39;
            restore.Width = ButtonWidth(restore, 104);
            save.Width = ButtonWidth(save, 78);
            cancel.Width = ButtonWidth(cancel, 78);
            cancel.SetBounds(form.ClientSize.Width - margin - cancel.Width, top, cancel.Width, 27);
            save.SetBounds(cancel.Left - gap - save.Width, top, save.Width, 27);
            restore.SetBounds(save.Left - gap - restore.Width, top, restore.Width, 27);
        }

        private static void LayoutGroupButtons(Button first, Button second)
        {
            first.Width = ButtonWidth(first, 130);
            second.Width = ButtonWidth(second, 140);
            second.Left = first.Right + 10;
        }

        private static int ButtonWidth(Button button, int minimum)
        {
            int measured = TextRenderer.MeasureText(button.Text, button.Font).Width + 24;
            return Math.Max(minimum, measured);
        }

        private static Label Label(string text, int x, int y, int width)
        {
            Label label = new Label();
            label.Text = text;
            label.SetBounds(x, y, width, 22);
            label.TextAlign = ContentAlignment.MiddleLeft;
            return label;
        }

        private static TextBox ReadOnlyText(int x, int y, int width, string text)
        {
            TextBox box = new TextBox();
            box.SetBounds(x, y, width, 23);
            box.Text = text;
            box.ReadOnly = true;
            box.BorderStyle = BorderStyle.FixedSingle;
            return box;
        }

        private static void OpenFolder(string path)
        {
            try
            {
                Directory.CreateDirectory(path);
                Process.Start(path);
            }
            catch
            {
            }
        }

        private static string ReadVersion()
        {
            try
            {
                foreach (string root in GetRuntimeRoots())
                {
                    string path = Path.Combine(root, "VERSION");
                    if (File.Exists(path)) return File.ReadAllText(path, Encoding.UTF8).Trim();
                }
            }
            catch
            {
            }
            return "native";
        }

        private static string GetInstallRoot()
        {
            return GetRuntimeRoots().Last().TrimEnd(Path.DirectorySeparatorChar);
        }

        private static IEnumerable<string> GetRuntimeRoots()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            yield return baseDir;

            DirectoryInfo parent = Directory.GetParent(baseDir);
            if (parent != null && string.Equals(Path.GetFileName(baseDir), "bin", StringComparison.OrdinalIgnoreCase))
            {
                yield return parent.FullName.TrimEnd(Path.DirectorySeparatorChar);
            }
        }
    }

    internal static class NativeWindowActivation
    {
        public static void ShowCodexWindow()
        {
            foreach (Process process in Process.GetProcessesByName("Codex"))
            {
                if (process.MainWindowHandle != IntPtr.Zero)
                {
                    ShowWindow(process.MainWindowHandle, 9);
                    SetForegroundWindow(process.MainWindowHandle);
                    return;
                }
            }
        }

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);
    }

    internal static class NativeDpi
    {
        public static void Enable()
        {
            try { SetProcessDPIAware(); } catch { }
        }

        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();
    }
}
