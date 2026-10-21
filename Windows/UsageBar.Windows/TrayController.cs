using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
using UsageBar.Core;
using Forms = System.Windows.Forms;

namespace UsageBar.Windows;

internal sealed class TrayController : IDisposable
{
    private readonly Application app;
    private readonly SettingsFile settingsFile;
    private readonly Forms.NotifyIcon tray;
    private readonly Forms.ContextMenuStrip menu;
    private readonly DispatcherTimer timer = new();
    private readonly DispatcherTimer resumeTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private Icon? currentIcon;
    private string? lastIconSignature;
    private int recoveryAttempts;
    private bool disposed;
    public UsageTracker Tracker { get; }
    public MainWindow Window { get; }
    public string? Notice { get; private set; }

    public TrayController(Application app)
    {
        this.app = app;
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UsageBar");
        settingsFile = new(Path.Combine(directory, "settings.json"));
        Tracker = new(new CliUsageClient().FetchAsync);
        Tracker.Configure(settingsFile.Load() with { StartWithWindows = StartupRegistration.IsEnabled() });
        Window = new MainWindow(Tracker, settings => SavePreferences(settings), () => Notice);
        menu = new Forms.ContextMenuStrip();
        menu.Items.Add("사용량 보기", null, (_, _) => Show("usage"));
        menu.Items.Add("새로고침", null, async (_, _) => await Tracker.RefreshAllAsync());
        menu.Items.Add("설정", null, (_, _) => Show("settings"));
        menu.Items.Add("설치·로그인 안내", null, (_, _) => Show("setup"));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("종료", null, (_, _) => app.Shutdown());
        tray = new Forms.NotifyIcon { Text = "UsageBar", ContextMenuStrip = menu };
        tray.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) Show("usage"); };
        Tracker.Changed += OnChanged;
        timer.Tick += async (_, _) => await Tracker.RefreshAllAsync();
        resumeTimer.Tick += async (_, _) =>
        {
            resumeTimer.Stop();
            if (Tracker.Settings.RefreshMinutes == 0) return;
            await Tracker.RefreshAllAsync();
            if (Tracker.States.Any(pair => Tracker.Settings.Enabled(pair.Key) && pair.Value.Error != null) && recoveryAttempts++ < 2)
            { resumeTimer.Interval = TimeSpan.FromSeconds(10); resumeTimer.Start(); }
        };
        SystemEvents.PowerModeChanged += OnPowerChanged;
        NetworkChange.NetworkAvailabilityChanged += OnNetworkChanged;
        ConfigureTimer();
        OnChanged();
        tray.Visible = true;
        var missing = Enum.GetValues<Provider>().Any(provider => Tracker.Settings.Enabled(provider) && CliLocator.Find(provider) is null);
        if (!Tracker.Settings.HasSeenSetup && missing) Show("setup");
        SavePreferences(Tracker.Settings with { HasSeenSetup = true }, changeStartup: false);
        // Start after Application.Run installs the UI synchronization context.
        app.Dispatcher.InvokeAsync(async () => await Tracker.RefreshAllAsync());
    }

    public void Show(string page)
    {
        Window.ShowPage(page);
        Window.Show();
        Window.WindowState = WindowState.Normal;
        Window.Activate();
    }

    public bool SavePreferences(UsageSettings settings, bool changeStartup = true)
    {
        try
        {
            settings = settings.Normalize();
            if (changeStartup && settings.StartWithWindows != StartupRegistration.IsEnabled())
                StartupRegistration.SetEnabled(settings.StartWithWindows);
            settingsFile.Save(settings);
            Tracker.Configure(settings);
            ConfigureTimer();
            Notice = null;
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { Notice = "설정을 저장하지 못했습니다. 폴더 또는 시작 프로그램 권한을 확인해 주세요."; return false; }
    }

    private void ConfigureTimer()
    {
        timer.Stop();
        if (Tracker.Settings.RefreshMinutes > 0)
        { timer.Interval = TimeSpan.FromMinutes(Tracker.Settings.RefreshMinutes); timer.Start(); }
        else resumeTimer.Stop();
    }

    private void OnChanged()
    {
        if (disposed) return;
        if (!app.Dispatcher.CheckAccess())
        { app.Dispatcher.InvokeAsync(OnChanged); return; }
        Window.RefreshUsage();
        var summaries = Enum.GetValues<Provider>().Where(Tracker.Settings.Enabled).Select(provider =>
        {
            var state = Tracker.States[provider];
            var primary = state.Snapshot?.Primary(Tracker.Settings.Selection(provider));
            return (Provider: provider, Window: primary, Stale: state.Error != null);
        }).ToArray();
        var tooltip = "UsageBar · " + string.Join(" | ", summaries.Select(summary => summary.Window is { } window
            ? $"{summary.Provider.Command()} {window.Title} {window.UsedPercent:0}%{(summary.Stale ? " (갱신 지연)" : "")}" : $"{summary.Provider.Command()} 연결 필요"));
        tray.Text = tooltip.Length <= 127 ? tooltip : tooltip[..126];
        var signature = Tracker.Settings.TrayStyle + ":" + string.Join("|", summaries.Select(summary => $"{summary.Provider}:{summary.Window?.UsedPercent.ToString("0", CultureInfo.InvariantCulture)}"));
        if (lastIconSignature == signature) return;
        lastIconSignature = signature;
        var icon = DrawIcon(summaries.Where(summary => summary.Window != null).Select(summary => (summary.Provider, summary.Window!.UsedPercent)).ToArray(), Tracker.Settings.TrayStyle);
        var previous = currentIcon;
        currentIcon = icon;
        tray.Icon = icon;
        previous?.Dispose();
    }

    internal static Icon DrawIcon(IReadOnlyList<(Provider Provider, double Percent)> values, TrayStyle style)
    {
        using var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        if (values.Count == 0)
        {
            using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppIcon.png"))!.Stream;
            using var source = new Bitmap(stream);
            graphics.DrawImage(source, 0, 0, 32, 32);
        }
        else if (style == TrayStyle.Percentage)
        {
            using var font = new Font("Segoe UI", 15, System.Drawing.FontStyle.Bold, GraphicsUnit.Pixel);
            for (var index = 0; index < values.Count; index++)
            {
                using var brush = new SolidBrush(values[index].Provider == Provider.Codex ? Color.FromArgb(80, 212, 174) : Color.FromArgb(230, 155, 113));
                graphics.DrawString(values[index].Percent.ToString("0", CultureInfo.InvariantCulture), font, brush, 0, index * 15 - 2);
            }
        }
        else
        {
            for (var index = 0; index < values.Count; index++)
            {
                using var track = new SolidBrush(Color.FromArgb(200, 64, 76, 93));
                using var fill = new SolidBrush(values[index].Provider == Provider.Codex ? Color.FromArgb(80, 212, 174) : Color.FromArgb(230, 155, 113));
                var y = values.Count == 1 ? 11 : 5 + index * 15;
                graphics.FillRectangle(track, 2, y, 28, 9);
                if (values[index].Percent > 0) graphics.FillRectangle(fill, 2, y, Math.Max(1, (float)(28 * values[index].Percent / 100)), 9);
            }
        }
        var handle = bitmap.GetHicon();
        try { using var borrowed = Icon.FromHandle(handle); return (Icon)borrowed.Clone(); }
        finally { DestroyIcon(handle); }
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);

    private void ScheduleRecovery()
    {
        if (disposed) return;
        app.Dispatcher.BeginInvoke(() =>
        {
            if (disposed || Tracker.Settings.RefreshMinutes == 0) return;
            recoveryAttempts = 0;
            resumeTimer.Stop(); resumeTimer.Interval = TimeSpan.FromSeconds(3); resumeTimer.Start();
        });
    }
    private void OnPowerChanged(object sender, PowerModeChangedEventArgs args) { if (args.Mode == PowerModes.Resume) ScheduleRecovery(); }
    private void OnNetworkChanged(object? sender, NetworkAvailabilityEventArgs args) { if (args.IsAvailable) ScheduleRecovery(); }

    public void Dispose()
    {
        disposed = true;
        SystemEvents.PowerModeChanged -= OnPowerChanged;
        NetworkChange.NetworkAvailabilityChanged -= OnNetworkChanged;
        timer.Stop(); resumeTimer.Stop(); Tracker.Dispose();
        tray.Visible = false; tray.Dispose(); menu.Dispose(); currentIcon?.Dispose();
    }
}

internal static class StartupRegistration
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "UsageBar";
    private static string Command => "\"" + Environment.ProcessPath + "\"";
    public static bool IsEnabled()
    {
        try { using var key = Registry.CurrentUser.OpenSubKey(KeyPath); return key?.GetValue(Name) as string == Command; }
        catch (Exception error) when (error is System.Security.SecurityException or UnauthorizedAccessException or IOException) { return false; }
    }
    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath, writable: true);
        if (enabled) key.SetValue(Name, Command, RegistryValueKind.String);
        // Never delete an entry owned by another installation/path.
        else if (key.GetValue(Name) as string == Command) key.DeleteValue(Name, throwOnMissingValue: false);
    }
}
