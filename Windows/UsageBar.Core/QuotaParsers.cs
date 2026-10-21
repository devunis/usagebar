using System.Globalization;
using System.Text.Json;

namespace UsageBar.Core;

public static class QuotaParsers
{
    public static QuotaSnapshot Codex(JsonElement root, DateTimeOffset? now = null)
    {
        var buckets = Get(root, "rateLimitsByLimitId");
        var limits = buckets.ValueKind == JsonValueKind.Object
            ? buckets.EnumerateObject().Select(property => property.Value).ToList() : [];
        if (limits.Count == 0 && Get(root, "rateLimits").ValueKind == JsonValueKind.Object)
            limits.Add(Get(root, "rateLimits"));
        var rows = new List<(QuotaWindow Window, int Rank)>();
        string? plan = null;
        foreach (var limit in limits.Take(200))
        {
            plan ??= Text(Get(limit, "planType"));
            var id = Text(Get(limit, "limitId")) ?? "codex";
            var name = Text(Get(limit, "limitName"))?.Trim();
            if (name?.Equals("gpt-reserve", StringComparison.OrdinalIgnoreCase) == true) name = "예비 한도";
            foreach (var key in new[] { "primary", "secondary" })
            {
                var source = Get(limit, key);
                if (Percent(Get(source, "usedPercent")) is not { } used) continue;
                var duration = Integer(Get(source, "windowDurationMins"));
                var named = !string.IsNullOrWhiteSpace(name);
                var kind = named ? WindowKind.Model : duration >= 10080 ? WindowKind.Weekly : WindowKind.ShortTerm;
                var title = duration switch
                {
                    >= 10080 => "주간", >= 1440 => $"{duration / 1440}일",
                    >= 60 => $"{duration / 60}시간", > 0 => $"{duration}분", _ => "한도"
                };
                rows.Add((new QuotaWindow($"{id}-{key}", named ? $"{name} · {title}" : title,
                    kind, used, duration, Timestamp(Get(source, "resetsAt"))),
                    named ? 2 : kind == WindowKind.ShortTerm ? 0 : 1));
            }
        }
        var windows = rows.OrderBy(row => row.Rank).ThenBy(row => row.Window.DurationMinutes ?? int.MaxValue)
            .ThenBy(row => row.Window.Id, StringComparer.Ordinal).Select(row => row.Window).ToArray();
        if (windows.Length == 0) throw new UsageException("Codex 사용량을 읽지 못했습니다. ChatGPT 계정 로그인 상태를 확인해 주세요.");
        var credits = Integer(Get(Get(root, "rateLimitResetCredits"), "availableCount"));
        return new(Provider.Codex, windows, now ?? DateTimeOffset.Now, plan, credits >= 0 ? credits : null);
    }

    public static QuotaSnapshot Claude(JsonElement payload, DateTimeOffset? now = null)
    {
        if (Get(payload, "rate_limits_available").ValueKind != JsonValueKind.True)
            throw new UsageException("Claude 구독 계정으로 CLI에 로그인해 주세요. API 키 계정에는 구독 한도가 없습니다.");
        var limits = Get(payload, "rate_limits");
        var windows = new List<QuotaWindow>();
        var flat = Items(Get(limits, "limits")).Take(200).ToArray();
        foreach (var (key, title, kind, minutes, flatKind) in new[] {
            ("five_hour", "5시간", WindowKind.ShortTerm, 300, "session"),
            ("seven_day", "주간", WindowKind.Weekly, 10080, "weekly_all") })
        {
            var source = Get(limits, key);
            var used = Percent(Get(source, "utilization"));
            if (used is null)
            {
                source = flat.FirstOrDefault(row => Text(Get(row, "kind")) == flatKind && Percent(Get(row, "percent")) != null);
                used = Percent(Get(source, "percent"));
            }
            if (used is { } value) windows.Add(new(key, title, kind, value, minutes, Timestamp(Get(source, "resets_at"))));
        }
        var scoped = new SortedDictionary<string, QuotaWindow>(StringComparer.OrdinalIgnoreCase);
        void AddModel(string? name, double? used, JsonElement reset)
        {
            name = name?.Trim();
            if (string.IsNullOrEmpty(name) || name.Length > 120 || used is null ||
                new[] { "all", "all models", "all_models" }.Contains(name.ToLowerInvariant())) return;
            scoped.TryAdd(name, new("model-" + name.ToLowerInvariant(), name + " 주간", WindowKind.Model,
                used.Value, 10080, Timestamp(reset)));
        }
        foreach (var row in Items(Get(limits, "model_scoped")).Take(200))
            AddModel(Text(Get(row, "display_name")), Percent(Get(row, "utilization")), Get(row, "resets_at"));
        foreach (var row in flat.Where(row => Text(Get(row, "kind")) == "weekly_scoped"))
            AddModel(Text(Get(Get(Get(row, "scope"), "model"), "display_name")), Percent(Get(row, "percent")), Get(row, "resets_at"));
        if (limits.ValueKind == JsonValueKind.Object)
            foreach (var property in limits.EnumerateObject().Where(property => property.Name.StartsWith("seven_day_", StringComparison.Ordinal)))
                AddModel(CultureInfo.InvariantCulture.TextInfo.ToTitleCase(property.Name[10..].Replace('_', ' ')),
                    Percent(Get(property.Value, "utilization")), Get(property.Value, "resets_at"));
        windows.AddRange(scoped.Values);
        if (windows.Count == 0) throw new UsageException("Claude 한도 응답을 해석하지 못했습니다. CLI 업데이트를 확인해 주세요.");
        return new(Provider.Claude, windows, now ?? DateTimeOffset.Now, Text(Get(payload, "subscription_type")));
    }

    internal static JsonElement Get(JsonElement source, string key) =>
        source.ValueKind == JsonValueKind.Object && source.TryGetProperty(key, out var value) ? value : default;
    internal static string? Text(JsonElement value) => value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static IEnumerable<JsonElement> Items(JsonElement value) =>
        value.ValueKind == JsonValueKind.Array ? value.EnumerateArray() : [];
    private static double? Number(JsonElement value) =>
        value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) && double.IsFinite(number) ? number : null;
    private static double? Percent(JsonElement value) => Number(value) is >= 0 and <= 100 ? Number(value) : null;
    private static int? Integer(JsonElement value) => Number(value) is { } number && number == Math.Truncate(number)
        && number is >= 0 and <= int.MaxValue ? (int)number : null;
    private static DateTimeOffset? Timestamp(JsonElement value)
    {
        if (Number(value) is { } seconds && seconds is >= -62135596800 and <= 253402300799)
            return DateTimeOffset.FromUnixTimeSeconds((long)seconds);
        return Text(value) is { } text && DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal, out var date) ? date : null;
    }
}
