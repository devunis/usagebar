using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace UsageBar.Core;

public sealed class CliUsageClient(Func<Provider, CliLaunch?>? find = null, string? workspace = null,
    TimeSpan? timeout = null)
{
    private readonly Func<Provider, CliLaunch?> find = find ?? CliLocator.Find;
    public static readonly string[] ClaudeArguments = ["--safe-mode", "--strict-mcp-config",
        "--settings", "{\"remoteControlAtStartup\":false,\"disableAllHooks\":true}",
        "--no-session-persistence", "--tools", "", "--permission-mode", "dontAsk",
        "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"];

    public async Task<QuotaSnapshot> FetchAsync(Provider provider, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        var launch = find(provider) ?? throw new UsageException($"{provider.Name()} CLI를 설치하고 구독 계정으로 로그인해 주세요.");
        var directory = Path.Combine(workspace ?? Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData), "UsageBar", "CLIWorkspaces"), provider.Command());
        Directory.CreateDirectory(directory);
        var start = new ProcessStartInfo(launch.Executable)
        {
            WorkingDirectory = directory, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var argument in launch.PrefixArguments.Concat(provider == Provider.Codex ? ["app-server"] : ClaudeArguments))
            start.ArgumentList.Add(argument);
        start.Environment["PWD"] = directory;
        using var process = new Process { StartInfo = start };
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(40));
        Task? drain = null;
        var started = false;
        try
        {
            if (!process.Start()) throw new UsageException("CLI를 실행하지 못했습니다.");
            started = true;
            // Drain, but never retain or log raw stderr (may include account data).
            drain = process.StandardError.BaseStream.CopyToAsync(Stream.Null, deadline.Token);
            await SendAsync(process, provider == Provider.Codex
                ? new { method = "initialize", id = 1, @params = new { clientInfo = new { name = "usagebar_windows", version = "0.1.0" }, capabilities = new { } } }
                : ClaudeRequest("usagebar-initialize", new { subtype = "initialize", hooks = new { }, sdkMcpServers = Array.Empty<object>() }), deadline.Token);
            var initialized = false;
            await foreach (var message in ReadMessagesAsync(process.StandardOutput, deadline.Token))
            {
                if (provider == Provider.Codex)
                {
                    var id = QuotaParsers.Get(message, "id");
                    if (id.ValueKind != JsonValueKind.Number || !id.TryGetInt32(out var number) || number is not (1 or 2)) continue;
                    if (QuotaParsers.Get(message, "error").ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null))
                        throw new UsageException("Codex가 조회 요청을 처리하지 못했습니다. CLI 로그인·업데이트를 확인해 주세요.");
                    if (number == 1 && !initialized && QuotaParsers.Get(message, "result").ValueKind == JsonValueKind.Object)
                    {
                        initialized = true;
                        await SendAsync(process, new { method = "initialized" }, deadline.Token);
                        await SendAsync(process, new { method = "account/rateLimits/read", id = 2 }, deadline.Token);
                    }
                    else if (number == 2 && initialized) return QuotaParsers.Codex(QuotaParsers.Get(message, "result"));
                }
                else
                {
                    if (QuotaParsers.Text(QuotaParsers.Get(message, "type")) == "control_request")
                        throw new UsageException("Claude Code가 사용량 조회 외의 요청을 보냈습니다. 조회를 중단했습니다.");
                    if (QuotaParsers.Text(QuotaParsers.Get(message, "type")) != "control_response") continue;
                    var response = QuotaParsers.Get(message, "response");
                    var id = QuotaParsers.Text(QuotaParsers.Get(response, "request_id"));
                    if (id is not ("usagebar-initialize" or "usagebar-usage")) continue;
                    if (QuotaParsers.Text(QuotaParsers.Get(response, "subtype")) != "success")
                        throw new UsageException("Claude Code가 사용량 조회를 지원하지 않거나 로그인 갱신이 필요합니다.");
                    if (id == "usagebar-initialize" && !initialized)
                    {
                        initialized = true;
                        await SendAsync(process, ClaudeRequest("usagebar-usage", new { subtype = "get_usage", skip_behaviors = true }), deadline.Token);
                    }
                    else if (initialized && id == "usagebar-usage") return QuotaParsers.Claude(QuotaParsers.Get(response, "response"));
                }
            }
            throw new UsageException("CLI가 한도 응답 없이 종료되었습니다. 공식 CLI의 설치·로그인·업데이트를 확인해 주세요.");
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
        { throw new UsageException("조회 시간이 초과되었습니다. 이전 값은 유지하며 다음 갱신 때 다시 시도합니다."); }
        catch (Exception error) when (error is IOException or System.ComponentModel.Win32Exception or InvalidOperationException)
        { throw new UsageException("CLI 조회 연결을 완료하지 못했습니다. 설치·로그인 상태를 확인해 주세요."); }
        finally
        {
            deadline.Cancel();
            if (started)
            {
                try { process.StandardInput.Close(); } catch (IOException) { }
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { }
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3)); }
                catch (TimeoutException) { }
            }
            if (drain is not null)
                try { await drain.WaitAsync(TimeSpan.FromSeconds(1)); }
                catch (Exception error) when (error is OperationCanceledException or IOException or TimeoutException or ObjectDisposedException) { }
        }
    }

    private static object ClaudeRequest(string id, object request) => new { type = "control_request", request_id = id, request };
    private static async Task SendAsync(Process process, object value, CancellationToken cancellation)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(value).AsMemory(), cancellation);
        await process.StandardInput.FlushAsync(cancellation);
    }

    private static async IAsyncEnumerable<JsonElement> ReadMessagesAsync(StreamReader reader,
        [EnumeratorCancellation] CancellationToken cancellation)
    {
        var buffer = new char[8192];
        var pending = new StringBuilder();
        var total = 0;
        while (true)
        {
            var count = await reader.ReadAsync(buffer.AsMemory(), cancellation);
            if (count == 0) yield break;
            total += count;
            if (total > 8_000_000) throw new UsageException("CLI 응답이 허용 크기를 초과했습니다.");
            for (var index = 0; index < count; index++)
            {
                if (buffer[index] != '\n')
                {
                    pending.Append(buffer[index]);
                    if (pending.Length > 1_000_000) throw new UsageException("CLI 응답 한 줄이 허용 크기를 초과했습니다.");
                    continue;
                }
                var line = pending.ToString();
                pending.Clear();
                JsonElement? parsed = null;
                try { using var json = JsonDocument.Parse(line); parsed = json.RootElement.Clone(); }
                catch (JsonException) { /* Some CLI versions print non-JSON startup notices. */ }
                if (parsed is { } message) yield return message;
            }
        }
    }
}
