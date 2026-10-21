using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using UsageBar.Core;

namespace UsageBar.Windows;

internal static class SmokeTest
{
    // Windows CI only: fixture quotas, no login/CLI execution, preference files,
    // registry changes, browser launches, clipboard writes, or live accounts.
    public static int Run(Application app, string[] args)
    {
        try
        {
            var index = Array.IndexOf(args, "--smoke-test");
            var output = args.Length > index + 1 ? Path.GetFullPath(args[index + 1]) : Path.Combine(Path.GetTempPath(), "UsageBar-smoke");
            Directory.CreateDirectory(output);
            using var tracker = new UsageTracker((provider, _) => Task.FromResult(Fixture(provider)));
            tracker.RefreshAllAsync().GetAwaiter().GetResult();
            using var bars = TrayController.DrawIcon([(Provider.Codex, 56), (Provider.Claude, 34)], TrayStyle.Bars);
            using var percentage = TrayController.DrawIcon([(Provider.Codex, 56), (Provider.Claude, 34)], TrayStyle.Percentage);
            using var appIcon = TrayController.DrawIcon([], TrayStyle.Bars);
            using (var image = bars.ToBitmap()) image.Save(Path.Combine(output, "tray-bars.png"));
            using (var image = percentage.ToBitmap()) image.Save(Path.Combine(output, "tray-percent.png"));
            var window = new MainWindow(tracker, settings => { tracker.Configure(settings); return true; }, () => null);
            app.MainWindow = window;
            window.Show();
            foreach (var page in new[] { "usage", "settings", "setup" })
            {
                window.ShowPage(page);
                app.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                window.UpdateLayout();
                foreach (var button in Descendants(window).OfType<Button>().Where(button => button.IsEnabled))
                    foreach (var text in Descendants(button).OfType<TextBlock>())
                        if (text.Foreground is SolidColorBrush color && color.Color.R > 200 && color.Color.G > 200 && color.Color.B > 200)
                            throw new InvalidOperationException("Light button text has insufficient contrast");
                if (window.ActualWidth < 400 || window.ActualHeight < 400) throw new InvalidOperationException("Window layout collapsed");
                var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(window);
                var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
                using var file = File.Create(Path.Combine(output, page + ".png")); png.Save(file);
            }
            window.Close();
            if (window.IsVisible) throw new InvalidOperationException("Close should hide to tray");
            app.Shutdown(0);
            return 0;
        }
        catch (Exception error)
        {
            // This fixture-only path never contacts accounts or reads credentials.
            Console.Error.WriteLine($"UI smoke failed: {error.GetType().Name}: {error.Message}");
            File.WriteAllText(Path.Combine(Path.GetTempPath(), "UsageBar-smoke-failed.txt"), "Windows UI smoke test failed.");
            app.Shutdown(1);
            return 1;
        }
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            yield return child;
            foreach (var descendant in Descendants(child)) yield return descendant;
        }
    }

    private static QuotaSnapshot Fixture(Provider provider)
    {
        const string codex = """{"rateLimits":{"planType":"plus","primary":{"usedPercent":56,"windowDurationMins":300},"secondary":{"usedPercent":71,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":1}}""";
        const string claude = """{"rate_limits_available":true,"subscription_type":"max","rate_limits":{"five_hour":{"utilization":34},"seven_day":{"utilization":57},"model_scoped":[{"display_name":"Fable","utilization":14}]}}""";
        using var json = JsonDocument.Parse(provider == Provider.Codex ? codex : claude);
        return provider == Provider.Codex ? QuotaParsers.Codex(json.RootElement) : QuotaParsers.Claude(json.RootElement);
    }
}
