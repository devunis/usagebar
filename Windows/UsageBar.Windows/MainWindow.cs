using System;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using UsageBar.Core;

namespace UsageBar.Windows;

internal sealed class MainWindow : Window
{
    private readonly UsageTracker tracker;
    private readonly Func<UsageSettings, bool> save;
    private readonly Func<string?> notice;
    private readonly ContentControl content = new();
    private readonly TextBlock feedback = new() { Foreground = Theme.Muted, Margin = new Thickness(0, 8, 0, 0) };
    private string page = "usage";

    public MainWindow(UsageTracker tracker, Func<UsageSettings, bool> save, Func<string?> notice)
    {
        this.tracker = tracker;
        this.save = save;
        this.notice = notice;
        Title = "UsageBar · Windows Preview";
        Width = 580; Height = 780; MinWidth = 480; MinHeight = 560;
        Background = Theme.Background; FontFamily = new FontFamily("Segoe UI"); FontSize = 13;
        Icon = Theme.AppIcon(); WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var layout = new DockPanel { Margin = new Thickness(22) };
        var header = new StackPanel { Margin = new Thickness(0, 0, 0, 18) };
        var title = new StackPanel { Orientation = Orientation.Horizontal };
        title.Children.Add(new Image { Source = Theme.AppIcon(), Width = 42, Height = 42, Margin = new Thickness(0, 0, 12, 0) });
        var titleText = new StackPanel();
        titleText.Children.Add(Text("UsageBar", 23, bold: true));
        titleText.Children.Add(Text("Windows Preview 0.1 · AI 구독 한도", 12, Theme.Muted));
        title.Children.Add(titleText); header.Children.Add(title);
        var navigation = Row(); navigation.Margin = new Thickness(0, 16, 0, 0);
        navigation.Children.Add(Button("사용량", () => ShowPage("usage")));
        navigation.Children.Add(Button("설정", () => ShowPage("settings")));
        navigation.Children.Add(Button("설치·로그인", () => ShowPage("setup")));
        header.Children.Add(navigation);
        DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);
        var footer = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };
        footer.Children.Add(feedback);
        footer.Children.Add(Text("창을 닫아도 트레이에서 실행됩니다. 종료는 트레이 우클릭 메뉴에서 해 주세요.", 11, Theme.Muted));
        DockPanel.SetDock(footer, Dock.Bottom); layout.Children.Add(footer);
        layout.Children.Add(new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        Content = layout;
        Closing += (_, args) => { args.Cancel = true; Hide(); };
        Activated += (_, _) => { if (page == "setup") RenderSetup(); };
        ShowPage("usage");
    }

    public void ShowPage(string destination)
    {
        page = destination;
        feedback.Text = "";
        switch (page)
        {
            case "settings": RenderSettings(); break;
            case "setup": RenderSetup(); break;
            default: RenderUsage(); break;
        }
    }
    public void RefreshUsage() { if (page == "usage") RenderUsage(); }

    private void RenderUsage()
    {
        var panel = new StackPanel();
        panel.Children.Add(Button("모두 새로고침", async () => await tracker.RefreshAllAsync()));
        var visible = Enum.GetValues<Provider>().Where(tracker.Settings.Enabled).ToArray();
        if (visible.Length == 0) panel.Children.Add(Text("설정에서 표시할 서비스를 켜 주세요.", 14, Theme.Muted));
        foreach (var provider in visible)
        {
            var state = tracker.States[provider];
            var body = new StackPanel();
            var header = Row();
            header.Children.Add(new Image { Source = Theme.Brand(provider), Width = 28, Height = 28, Margin = new Thickness(0, 0, 12, 0) });
            header.Children.Add(Text(provider.Name(), 18, bold: true));
            body.Children.Add(header);
            if (state.Refreshing) body.Children.Add(Text("새로고침 중… 이전 사용량을 유지합니다.", 12, Theme.Muted));
            if (state.Snapshot is { } snapshot)
            {
                if (!string.IsNullOrWhiteSpace(snapshot.Plan)) body.Children.Add(Text(snapshot.Plan.ToUpperInvariant(), 11, Theme.Muted));
                foreach (var window in snapshot.Windows)
                {
                    var labels = new DockPanel { Margin = new Thickness(0, 8, 0, 3) };
                    var percent = Text($"{window.UsedPercent:0.#}% 사용", 13, Theme.ProviderBrush(provider));
                    DockPanel.SetDock(percent, Dock.Right); labels.Children.Add(percent);
                    labels.Children.Add(Text(window.Title, 14, bold: true)); body.Children.Add(labels);
                    body.Children.Add(new ProgressBar { Minimum = 0, Maximum = 100, Value = window.UsedPercent,
                        Height = 6, Foreground = Theme.ProviderBrush(provider), Background = Theme.Brush("#344154"), BorderThickness = new Thickness(0) });
                    if (window.ResetsAt is { } reset)
                        body.Children.Add(Text($"재설정 {reset.LocalDateTime:g}", 11, Theme.Muted));
                }
                if (snapshot.ResetCredits is { } credits) body.Children.Add(Text($"사용 한도 재설정 크레딧 · {credits}회 (실행은 이 초기 버전에서 지원하지 않음)", 11, Theme.Muted));
                body.Children.Add(Text($"마지막 성공 {snapshot.FetchedAt.LocalDateTime:g}", 11, Theme.Muted));
            }
            else if (!state.Refreshing) body.Children.Add(Text("아직 사용량이 없습니다. CLI 설치·로그인을 확인해 주세요.", 13, Theme.Muted));
            if (state.Error is { } error)
                body.Children.Add(Text((state.Snapshot is null ? "연결 확인 필요 · " : "갱신 지연 · 이전 값입니다. ") + error, 12, Theme.Brush("#FFBE7C")));
            if (provider == Provider.Claude)
                body.Children.Add(Text("크레딧·제한 초기화 추가 정보는 이 초기 버전에서 지원하지 않습니다.", 11, Theme.Muted));
            panel.Children.Add(Card(body));
        }
        content.Content = panel;
    }

    private void RenderSettings()
    {
        var settings = tracker.Settings;
        var panel = new StackPanel();
        panel.Children.Add(Text("표시·새로고침", 18, bold: true));
        var codex = new CheckBox { Content = "ChatGPT / Codex 사용", IsChecked = settings.CodexEnabled };
        var claude = new CheckBox { Content = "Claude 사용", IsChecked = settings.ClaudeEnabled };
        panel.Children.Add(codex); panel.Children.Add(claude);
        var interval = Combo(panel, "자동 갱신", new[] { "수동", "5분", "15분", "30분", "60분" }, Array.IndexOf(new[] { 0, 5, 15, 30, 60 }, settings.RefreshMinutes));
        var names = new[] { "5시간 우선 (없으면 주간)", "주간 우선", "가장 높은 사용량" };
        var codexLimit = Combo(panel, "Codex 트레이 한도", names, (int)settings.CodexLimit);
        var claudeLimit = Combo(panel, "Claude 트레이 한도", names, (int)settings.ClaudeLimit);
        var style = Combo(panel, "트레이 스타일", new[] { "색상 막대", "사용률 숫자" }, (int)settings.TrayStyle);
        panel.Children.Add(Text("트레이 아이콘은 두 서비스를 위·아래로 함께 표시합니다. 정확한 퍼센트와 한도 이름은 마우스를 올리거나 창을 열어 확인해 주세요.", 12, Theme.Muted));
        var startup = new CheckBox { Content = "Windows 로그인 시 자동 실행", IsChecked = settings.StartWithWindows };
        panel.Children.Add(startup);
        panel.Children.Add(Text("현재 사용자 시작 프로그램만 변경합니다. ZIP을 풀어 둔 앱 폴더를 옮기면 다시 설정해 주세요.", 11, Theme.Muted));
        panel.Children.Add(Button("설정 저장", async () =>
        {
            var updated = settings with
            {
                CodexEnabled = codex.IsChecked == true, ClaudeEnabled = claude.IsChecked == true,
                RefreshMinutes = new[] { 0, 5, 15, 30, 60 }[interval.SelectedIndex],
                CodexLimit = (LimitSelection)codexLimit.SelectedIndex, ClaudeLimit = (LimitSelection)claudeLimit.SelectedIndex,
                TrayStyle = (TrayStyle)style.SelectedIndex, StartWithWindows = startup.IsChecked == true
            };
            if (save(updated)) { feedback.Text = "설정을 저장했습니다."; await tracker.RefreshAllAsync(); }
            else feedback.Text = notice() ?? "설정을 저장하지 못했습니다.";
        }));
        panel.Children.Add(Text("Gemini·맥의 모든 아이콘 스타일·한도 재설정 실행은 Windows 초기 버전에 포함되지 않습니다.", 11, Theme.Muted));
        content.Content = panel;
    }

    private void RenderSetup()
    {
        var panel = new StackPanel();
        panel.Children.Add(Text("설치 → 구독 로그인 → 사용량 확인", 18, bold: true));
        panel.Children.Add(Text("Windows 네이티브 CLI를 사용합니다. WSL 안에만 설치된 CLI는 이 초기 버전에서 찾지 않습니다. 쓰지 않는 서비스는 설정에서 꺼 주세요.", 12, Theme.Muted));
        foreach (var provider in Enum.GetValues<Provider>())
        {
            var launch = CliLocator.Find(provider);
            var body = new StackPanel();
            body.Children.Add(Text(provider.Name(), 17, Theme.ProviderBrush(provider), bold: true));
            body.Children.Add(Text(!tracker.Settings.Enabled(provider) ? "서비스 꺼짐 · 설치할 필요 없음" : launch is null ? "CLI 미설치" : "CLI 설치됨 · 로그인/사용량은 별도 확인", 12, Theme.Muted));
            if (launch is not null) body.Children.Add(Text(launch.DisplayPath, 11, Theme.Muted));
            if (tracker.Settings.Enabled(provider))
            {
                if (launch is null) CommandStep(body, "1. PowerShell에서 공식 CLI 설치", CliLocator.InstallationCommand(provider));
                body.Children.Add(Button("공식 설치 안내 열기 ↗", () => OpenUrl(CliLocator.DocumentationUrl(provider))));
                CommandStep(body, "2. 구독 계정으로 로그인", CliLocator.LoginCommand(provider, launch), enabled: launch is not null);
                body.Children.Add(Text(provider == Provider.Codex ? "브라우저에서 ChatGPT 계정으로 로그인하세요." : "Claude 구독 계정으로 로그인하세요. Console/API 키 로그인이 아닙니다.", 11, Theme.Muted));
            }
            panel.Children.Add(Card(body));
        }
        var actions = Row();
        actions.Children.Add(Button("PowerShell 열기", () =>
        {
            try { Process.Start(new ProcessStartInfo("powershell.exe") { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { feedback.Text = "시작 메뉴에서 PowerShell을 직접 열어 주세요."; }
        }));
        actions.Children.Add(Button("설치·사용량 다시 확인", async () => { RenderSetup(); await tracker.RefreshAllAsync(); feedback.Text = "확인했습니다. 사용량 탭에서 결과를 확인해 주세요."; }));
        panel.Children.Add(actions);
        panel.Children.Add(Text("명령어는 복사만 합니다. 설치·로그인은 직접 실행해 주세요. UsageBar는 API 키나 브라우저 쿠키를 수집하지 않고 CLI에 사용량만 요청합니다.", 11, Theme.Muted));
        content.Content = panel;
    }

    private void CommandStep(StackPanel panel, string title, string command, bool enabled = true)
    {
        panel.Children.Add(Text(title, 12, bold: true));
        panel.Children.Add(new TextBox { Text = command, IsReadOnly = true, TextWrapping = TextWrapping.Wrap,
            FontFamily = new FontFamily("Consolas"), Background = Theme.Background, Foreground = Brushes.White,
            BorderThickness = new Thickness(0), Padding = new Thickness(7), Margin = new Thickness(0, 4, 0, 5) });
        var copy = Button("명령어 복사", () =>
        {
            try { Clipboard.SetText(command); feedback.Text = "복사했습니다. PowerShell에 붙여넣고 Enter를 눌러 주세요."; }
            catch (System.Runtime.InteropServices.COMException) { feedback.Text = "클립보드를 사용하지 못했습니다. 명령어를 직접 선택해 복사해 주세요."; }
        });
        copy.IsEnabled = enabled; panel.Children.Add(copy);
    }

    private void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (System.ComponentModel.Win32Exception) { feedback.Text = "브라우저를 열지 못했습니다. 공식 문서 주소를 직접 확인해 주세요."; }
    }
    private static TextBlock Text(string text, double size = 13, Brush? foreground = null, bool bold = false) =>
        new() { Text = text, FontSize = size, Foreground = foreground ?? Brushes.White,
            FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, Margin = new Thickness(0, 3, 0, 3) };
    private static Button Button(string title, Action action)
    { var button = new Button { Content = title, HorizontalAlignment = HorizontalAlignment.Left }; button.Click += (_, _) => action(); return button; }
    private static StackPanel Row() => new() { Orientation = Orientation.Horizontal };
    private static Border Card(UIElement body) => new() { Child = body, Background = Theme.Card, Padding = new Thickness(17),
        CornerRadius = new CornerRadius(13), Margin = new Thickness(0, 14, 6, 0) };
    private static ComboBox Combo(StackPanel panel, string label, string[] options, int index)
    {
        panel.Children.Add(Text(label, 12, Theme.Muted));
        var combo = new ComboBox { ItemsSource = options, SelectedIndex = Math.Max(0, index), MinWidth = 260,
            HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 10) };
        panel.Children.Add(combo); return combo;
    }
}
