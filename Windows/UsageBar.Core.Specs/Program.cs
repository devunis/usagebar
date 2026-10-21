using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using UsageBar.Core;

internal static class Program
{
    private const string ClaudeFixture = """{"rate_limits_available":true,"subscription_type":"max","rate_limits":{"five_hour":{"utilization":84,"resets_at":"2026-10-21T12:00:00Z"},"seven_day":{"utilization":11},"model_scoped":[{"display_name":"Fable","utilization":10,"resets_at":"2026-10-26T03:00:00Z"}]}}""";
    private const string CodexFixture = """{"rateLimits":{"primary":{"usedPercent":66,"windowDurationMins":10080},"secondary":{"usedPercent":12,"windowDurationMins":300}},"rateLimitResetCredits":{"availableCount":1}}""";

    public static async Task<int> Main(string[] args)
    {
        if (args.Length > 1 && args[0] == "--fixture") return await FixtureProcess(args[1]);
        if (args.Length == 1 && args[0] == "--live-claude")
        {
            // Explicit read-only developer opt-in; never used in CI.
            var client = new CliUsageClient(provider => provider == Provider.Claude
                ? new CliLaunch("/opt/homebrew/bin/claude", []) : null);
            var snapshot = await client.FetchAsync(Provider.Claude);
            Console.WriteLine(JsonSerializer.Serialize(snapshot.Windows.Select(window => new { window.Title, window.UsedPercent })));
            return 0;
        }
        var tests = new (string Name, Func<Task> Run)[]
        {
            ("Codex canonical 5h then weekly; primary is not assumed to mean 5h", Sync(() =>
            {
                var snapshot = ParseCodex(CodexFixture);
                Equal("5시간,주간", string.Join(',', snapshot.Windows.Select(window => window.Title)));
                Equal(12d, snapshot.Primary(LimitSelection.ShortTerm)!.UsedPercent);
                Equal(66d, snapshot.Primary(LimitSelection.Highest)!.UsedPercent);
                Equal(1, snapshot.ResetCredits);
            })),
            ("Codex multi-bucket and reserve display name", Sync(() =>
            {
                var snapshot = ParseCodex("""{"rateLimitsByLimitId":{"reserve":{"limitId":"reserve","limitName":"gpt-reserve","primary":{"usedPercent":3,"windowDurationMins":10080}},"codex":{"limitId":"codex","primary":{"usedPercent":50,"windowDurationMins":10080},"secondary":{"usedPercent":4,"windowDurationMins":300}}}}""");
                Equal("5시간,주간,예비 한도 · 주간", string.Join(',', snapshot.Windows.Select(window => window.Title)));
                Equal(4d, snapshot.Primary(LimitSelection.ShortTerm)!.UsedPercent);
            })),
            ("Invalid percentages are not invented as zero", Sync(() =>
            {
                Throws(() => ParseCodex("""{"rateLimits":{"primary":{"usedPercent":true}}}"""));
                Throws(() => ParseCodex("""{"rateLimits":{"primary":{"usedPercent":101}}}"""));
                Throws(() => ParseClaude("""{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":null}}}"""));
                Throws(() => ParseClaude("""{"rate_limits_available":false}"""));
            })),
            ("Claude Fable and explicit zero preserved", Sync(() =>
            {
                var snapshot = ParseClaude(ClaudeFixture);
                Equal("5시간,주간,Fable 주간", string.Join(',', snapshot.Windows.Select(window => window.Title)));
                Equal("max", snapshot.Plan);
                True(snapshot.Windows.Last().ResetsAt != null);
                var zero = ParseClaude("""{"rate_limits_available":true,"rate_limits":{"model_scoped":[{"display_name":"Fable","utilization":0},{"display_name":"Unknown","utilization":null}]}}""");
                Equal(1, zero.Windows.Count); Equal(0d, zero.Windows[0].UsedPercent);
            })),
            ("Claude modern flat limits and legacy model windows deduplicate", Sync(() =>
            {
                var snapshot = ParseClaude("""{"rate_limits_available":true,"rate_limits":{"limits":[{"kind":"session","percent":5},{"kind":"weekly_all","percent":30},{"kind":"weekly_scoped","is_active":false,"scope":{"model":{"display_name":"Fable"}},"percent":14}],"seven_day_fable":{"utilization":20}}}""");
                Equal("5시간,주간,Fable 주간", string.Join(',', snapshot.Windows.Select(window => window.Title)));
                Equal(14d, snapshot.Windows.Last().UsedPercent);
            })),
            ("No 5h window falls back to weekly", Sync(() =>
            {
                var snapshot = ParseCodex("""{"rateLimits":{"primary":{"usedPercent":61,"windowDurationMins":10080}}}""");
                Equal(WindowKind.Weekly, snapshot.Primary(LimitSelection.ShortTerm)!.Kind);
            })),
            ("PowerShell login quotes paths without shell interpolation", Sync(() =>
            {
                Equal("& 'C:\\Users\\Test''s $PC\\claude.exe' auth login",
                    CliLocator.LoginCommand(Provider.Claude, new CliLaunch(@"C:\Users\Test's $PC\claude.exe", [])));
                True(CliLocator.InstallationCommand(Provider.Claude).Contains("https://claude.ai/"));
                True(CliLocator.InstallationCommand(Provider.Codex).Contains("https://chatgpt.com/"));
                True(!CliUsageClient.ClaudeArguments.Contains("--dangerously-skip-permissions"));
                True(CliUsageClient.ClaudeArguments.Contains("--safe-mode"));
            })),
            ("Settings manual mode persists and corrupt config recovers", Sync(() =>
            {
                InDirectory(directory =>
                {
                    var path = Path.Combine(directory, "settings.json"); var file = new SettingsFile(path);
                    file.Save(new UsageSettings { RefreshMinutes = 0, ClaudeEnabled = false });
                    Equal(0, file.Load().RefreshMinutes); True(!file.Load().ClaudeEnabled);
                    True(!File.ReadAllText(path).Contains("accessToken", StringComparison.OrdinalIgnoreCase));
                    File.WriteAllText(path, "invalid"); Equal(15, file.Load().RefreshMinutes);
                    File.WriteAllText(path, "{\"RefreshMinutes\":-10,\"CodexLimit\":99}");
                    Equal(15, file.Load().RefreshMinutes); Equal(LimitSelection.ShortTerm, file.Load().CodexLimit);
                });
            })),
            ("CLI missing fails with setup guidance", async () =>
            {
                await ExpectFailure(() => new CliUsageClient(_ => null).FetchAsync(Provider.Codex));
            }),
            ("Codex JSONL handshake, initialized notification, quota only", async () =>
            {
                var snapshot = await Client("codex").FetchAsync(Provider.Codex);
                Equal(12d, snapshot.Windows[0].UsedPercent);
            }),
            ("Claude JSONL handshake; no user/model turn", async () =>
            {
                var snapshot = await Client("claude").FetchAsync(Provider.Claude);
                Equal("Fable 주간", snapshot.Windows.Last().Title);
            }),
            ("Unrelated response IDs cannot satisfy a request", async () =>
            {
                var snapshot = await Client("unrelated").FetchAsync(Provider.Claude);
                Equal(10d, snapshot.Windows.Last().UsedPercent);
            }),
            ("Raw CLI errors do not expose private details", async () =>
            {
                await ExpectFailure(() => Client("error").FetchAsync(Provider.Claude), "PRIVATE_DETAIL");
            }),
            ("Unexpected tool control request is rejected", async () =>
            {
                await ExpectFailure(() => Client("tool").FetchAsync(Provider.Claude));
            }),
            ("Large output rejected, not buffered forever", async () =>
            {
                await ExpectFailure(() => Client("large").FetchAsync(Provider.Claude));
            }),
            ("stderr draining cannot deadlock the probe", async () =>
            {
                var snapshot = await Client("stderr").FetchAsync(Provider.Claude);
                Equal(3, snapshot.Windows.Count);
            }),
            ("Early CLI exit cannot crash host", async () =>
            {
                await ExpectFailure(() => Client("exit").FetchAsync(Provider.Claude));
            }),
            ("Timeout kills only own disposable fixture", async () =>
            {
                var watch = Stopwatch.StartNew();
                await ExpectFailure(() => Client("hang", TimeSpan.FromMilliseconds(300)).FetchAsync(Provider.Claude));
                True(watch.Elapsed < TimeSpan.FromSeconds(8));
            }),
            ("Cancellation propagates without credential fallback", async () =>
            {
                using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(300));
                try { await Client("hang").FetchAsync(Provider.Claude, cancellation.Token); throw new Exception("Expected cancel"); }
                catch (OperationCanceledException) { }
            }),
            ("Refreshing and failure retain last successful snapshot", async () =>
            {
                var snapshot = ParseCodex(CodexFixture); var failed = false;
                using var tracker = new UsageTracker((_, _) => failed ? Task.FromException<QuotaSnapshot>(new UsageException("offline")) : Task.FromResult(snapshot));
                tracker.Configure(new UsageSettings { ClaudeEnabled = false });
                await tracker.RefreshAllAsync(); failed = true;
                await tracker.RefreshAllAsync();
                Equal(snapshot, tracker.States[Provider.Codex].Snapshot); Equal("offline", tracker.States[Provider.Codex].Error);
                True(!tracker.States[Provider.Codex].Refreshing);
            }),
            ("Duplicate refresh does not spawn another process", async () =>
            {
                var completion = new TaskCompletionSource<QuotaSnapshot>(); var calls = 0;
                using var tracker = new UsageTracker((_, _) => { calls++; return completion.Task; });
                tracker.Configure(new UsageSettings { ClaudeEnabled = false });
                var first = tracker.RefreshAsync(Provider.Codex); var second = tracker.RefreshAsync(Provider.Codex);
                Equal(1, calls); True(tracker.States[Provider.Codex].Refreshing);
                completion.SetResult(ParseCodex(CodexFixture)); await Task.WhenAll(first, second);
                Equal(1, calls);
            }),
            ("Disabling provider cancels pending fetch and discards result", async () =>
            {
                var completion = new TaskCompletionSource<QuotaSnapshot>(); CancellationToken seen = default;
                using var tracker = new UsageTracker((_, cancellation) => { seen = cancellation; return completion.Task; });
                tracker.Configure(new UsageSettings { ClaudeEnabled = false });
                var request = tracker.RefreshAsync(Provider.Codex);
                tracker.Configure(new UsageSettings { CodexEnabled = false, ClaudeEnabled = false });
                True(seen.IsCancellationRequested); completion.SetResult(ParseCodex(CodexFixture)); await request;
                True(tracker.States[Provider.Codex].Snapshot is null);
            })
        };
        var failures = 0;
        foreach (var (name, run) in tests)
        {
            try { await run(); Console.WriteLine("PASS " + name); }
            catch (Exception error) { failures++; Console.Error.WriteLine($"FAIL {name}: {error.Message}"); }
        }
        Console.WriteLine($"{tests.Length - failures}/{tests.Length} passed");
        return failures == 0 ? 0 : 1;
    }

    private static CliUsageClient Client(string scenario, TimeSpan? timeout = null)
    {
        var executable = Environment.ProcessPath!;
        var prefix = new List<string>();
        if (Path.GetFileNameWithoutExtension(executable).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
            prefix.Add(Assembly.GetExecutingAssembly().Location);
        prefix.AddRange(["--fixture", scenario]);
        return new(_ => new CliLaunch(executable, prefix), Path.Combine(Path.GetTempPath(), "UsageBar-fixture-workspaces"), timeout ?? TimeSpan.FromSeconds(8));
    }

    private static async Task<int> FixtureProcess(string scenario)
    {
        if (scenario == "hang") { await Task.Delay(Timeout.Infinite); return 0; }
        if (scenario == "large") { Console.WriteLine(new string('x', 1_000_001)); return 0; }
        if (scenario == "stderr") Console.Error.WriteLine(new string('s', 200_000));
        var initialize = Console.ReadLine() ?? "";
        using var request = JsonDocument.Parse(initialize);
        if (scenario == "codex")
        {
            if (request.RootElement.GetProperty("method").GetString() != "initialize") return 3;
            Console.WriteLine("{\"id\":1,\"result\":{}}");
            using var notification = JsonDocument.Parse(Console.ReadLine()!);
            if (notification.RootElement.GetProperty("method").GetString() != "initialized") return 4;
            using var usage = JsonDocument.Parse(Console.ReadLine()!);
            if (usage.RootElement.GetProperty("method").GetString() != "account/rateLimits/read") return 5;
            Console.WriteLine("{\"id\":2,\"result\":" + CodexFixture + "}"); return 0;
        }
        if (scenario == "tool") { Console.WriteLine("{\"type\":\"control_request\",\"request\":{\"subtype\":\"can_use_tool\"}}"); return 0; }
        if (scenario == "error") { Console.WriteLine("{\"type\":\"control_response\",\"response\":{\"request_id\":\"usagebar-initialize\",\"subtype\":\"error\",\"error\":\"PRIVATE_DETAIL\"}}"); return 0; }
        if (scenario == "unrelated") Console.WriteLine("{\"type\":\"control_response\",\"response\":{\"request_id\":\"other\",\"subtype\":\"success\"}}");
        Console.WriteLine("{\"type\":\"control_response\",\"response\":{\"request_id\":\"usagebar-initialize\",\"subtype\":\"success\",\"response\":{}}}");
        if (scenario == "exit") return 0;
        var usageLine = Console.ReadLine() ?? "";
        if (!usageLine.Contains("get_usage", StringComparison.Ordinal) || !usageLine.Contains("skip_behaviors", StringComparison.Ordinal)) return 6;
        Console.WriteLine("{\"type\":\"control_response\",\"response\":{\"request_id\":\"usagebar-usage\",\"subtype\":\"success\",\"response\":" + ClaudeFixture + "}}");
        return 0;
    }

    private static QuotaSnapshot ParseCodex(string text) { using var json = JsonDocument.Parse(text); return QuotaParsers.Codex(json.RootElement); }
    private static QuotaSnapshot ParseClaude(string text) { using var json = JsonDocument.Parse(text); return QuotaParsers.Claude(json.RootElement); }
    private static Func<Task> Sync(Action action) => () => { action(); return Task.CompletedTask; };
    private static void True(bool value) { if (!value) throw new Exception("Assertion failed"); }
    private static void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}, got {actual}"); }
    private static void Throws(Action action) { try { action(); } catch (UsageException) { return; } throw new Exception("Expected UsageException"); }
    private static async Task ExpectFailure(Func<Task<QuotaSnapshot>> action, string? forbidden = null)
    {
        try { await action(); } catch (UsageException error) { if (forbidden != null) True(!error.Message.Contains(forbidden, StringComparison.Ordinal)); return; }
        throw new Exception("Expected UsageException");
    }
    private static void InDirectory(Action<string> action)
    {
        var directory = Path.Combine(Path.GetTempPath(), "UsageBar-spec-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try { action(directory); } finally { Directory.Delete(directory, recursive: true); }
    }
}
