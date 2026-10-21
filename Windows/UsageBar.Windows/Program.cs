using System;
using System.Linq;
using System.Threading;
using System.Windows;

namespace UsageBar.Windows;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        Theme.Install(app);
        if (args.Contains("--smoke-test")) return SmokeTest.Run(app, args);
        using var mutex = new Mutex(true, @"Local\UsageBar.Windows", out var first);
        if (!first)
        {
            MessageBox.Show("UsageBar가 이미 실행 중입니다. 작업표시줄의 숨겨진 아이콘(∧)도 확인해 주세요.", "UsageBar");
            return 0;
        }
        using var controller = new TrayController(app);
        app.DispatcherUnhandledException += (_, eventArgs) =>
        {
            eventArgs.Handled = true;
            MessageBox.Show("작업을 완료하지 못했습니다. UsageBar를 다시 실행해 주세요.", "UsageBar");
        };
        app.Run();
        return 0;
    }
}
