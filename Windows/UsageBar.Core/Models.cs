namespace UsageBar.Core;

public enum Provider { Codex, Claude }
public enum WindowKind { ShortTerm, Weekly, Model }
public enum LimitSelection { ShortTerm, Weekly, Highest }
public enum TrayStyle { Bars, Percentage }

public static class ProviderNames
{
    public static string Name(this Provider provider) => provider == Provider.Codex ? "ChatGPT / Codex" : "Claude";
    public static string Command(this Provider provider) => provider == Provider.Codex ? "codex" : "claude";
}

public sealed record QuotaWindow(string Id, string Title, WindowKind Kind, double UsedPercent,
    int? DurationMinutes = null, DateTimeOffset? ResetsAt = null);

public sealed record QuotaSnapshot(Provider Provider, IReadOnlyList<QuotaWindow> Windows,
    DateTimeOffset FetchedAt, string? Plan = null, int? ResetCredits = null)
{
    public QuotaWindow? Primary(LimitSelection selection) => selection switch
    {
        LimitSelection.Highest => Windows.MaxBy(window => window.UsedPercent),
        LimitSelection.Weekly => Windows.FirstOrDefault(window => window.Kind == WindowKind.Weekly)
            ?? Windows.FirstOrDefault(),
        _ => Windows.FirstOrDefault(window => window.Kind == WindowKind.ShortTerm)
            ?? Windows.FirstOrDefault(window => window.Kind == WindowKind.Weekly) ?? Windows.FirstOrDefault()
    };
}

public sealed class UsageException(string message) : Exception(message);

public sealed record UsageSettings
{
    public bool CodexEnabled { get; init; } = true;
    public bool ClaudeEnabled { get; init; } = true;
    public int RefreshMinutes { get; init; } = 15;
    public LimitSelection CodexLimit { get; init; } = LimitSelection.ShortTerm;
    public LimitSelection ClaudeLimit { get; init; } = LimitSelection.ShortTerm;
    public TrayStyle TrayStyle { get; init; } = TrayStyle.Bars;
    public bool StartWithWindows { get; init; }
    public bool HasSeenSetup { get; init; }
    public bool Enabled(Provider provider) => provider == Provider.Codex ? CodexEnabled : ClaudeEnabled;
    public LimitSelection Selection(Provider provider) => provider == Provider.Codex ? CodexLimit : ClaudeLimit;
    public UsageSettings Normalize() => this with
    {
        RefreshMinutes = new[] { 0, 5, 15, 30, 60 }.Contains(RefreshMinutes) ? RefreshMinutes : 15,
        CodexLimit = Enum.IsDefined(CodexLimit) ? CodexLimit : LimitSelection.ShortTerm,
        ClaudeLimit = Enum.IsDefined(ClaudeLimit) ? ClaudeLimit : LimitSelection.ShortTerm,
        TrayStyle = Enum.IsDefined(TrayStyle) ? TrayStyle : TrayStyle.Bars
    };
}
