namespace UsageBar.Core;

public sealed class ProviderState
{
    public QuotaSnapshot? Snapshot { get; internal set; }
    public string? Error { get; internal set; }
    public bool Refreshing { get; internal set; }
}

// The caller's UI synchronization context is preserved. No credentials or usage
// snapshots are persisted; a failed refresh keeps the last successful snapshot.
public sealed class UsageTracker(Func<Provider, CancellationToken, Task<QuotaSnapshot>> fetch) : IDisposable
{
    public UsageSettings Settings { get; private set; } = new();
    public IReadOnlyDictionary<Provider, ProviderState> States => states;
    private readonly Dictionary<Provider, ProviderState> states = Enum.GetValues<Provider>().ToDictionary(provider => provider, _ => new ProviderState());
    private readonly Dictionary<Provider, CancellationTokenSource> requests = [];
    public event Action? Changed;
    private bool disposed;

    public void Configure(UsageSettings settings)
    {
        Settings = settings.Normalize();
        foreach (var provider in Enum.GetValues<Provider>().Where(provider => !Settings.Enabled(provider)))
        {
            if (requests.TryGetValue(provider, out var request)) request.Cancel();
            states[provider].Snapshot = null;
            states[provider].Error = null;
        }
        Changed?.Invoke();
    }

    public Task RefreshAllAsync() => Task.WhenAll(Enum.GetValues<Provider>().Select(RefreshAsync));

    public async Task RefreshAsync(Provider provider)
    {
        if (disposed || !Settings.Enabled(provider) || requests.ContainsKey(provider)) return;
        using var request = new CancellationTokenSource();
        requests.Add(provider, request);
        var state = states[provider];
        state.Refreshing = true;
        Changed?.Invoke();
        try
        {
            var snapshot = await fetch(provider, request.Token);
            if (!disposed && !request.IsCancellationRequested && Settings.Enabled(provider))
            {
                state.Snapshot = snapshot;
                state.Error = null;
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (!disposed && !request.IsCancellationRequested && Settings.Enabled(provider))
                state.Error = error is UsageException ? error.Message : "사용량 조회에 실패했습니다. 다음 갱신 때 다시 시도합니다.";
        }
        finally
        {
            requests.Remove(provider);
            state.Refreshing = false;
            if (!disposed) Changed?.Invoke();
        }
    }

    public void Dispose()
    {
        disposed = true;
        foreach (var request in requests.Values) request.Cancel();
    }
}
