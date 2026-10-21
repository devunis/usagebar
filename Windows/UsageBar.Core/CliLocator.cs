namespace UsageBar.Core;

public sealed record CliLaunch(string Executable, IReadOnlyList<string> PrefixArguments)
{
    public string DisplayPath => PrefixArguments.Count == 0 ? Executable : PrefixArguments[0];
}

public static class CliLocator
{
    public static CliLaunch? Find(Provider provider)
    {
        var name = provider.Command();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Select(path => path.Trim('"')).Where(Path.IsPathFullyQualified).ToArray();
        // Native installers and WinGet links first; never execute a .cmd via cmd.exe.
        var directories = new[] { Path.Combine(home, ".local", "bin"),
            Path.Combine(local, "Microsoft", "WinGet", "Links") }.Concat(paths);
        foreach (var directory in directories)
        {
            var candidate = Path.Combine(directory, name + ".exe");
            if (File.Exists(candidate)) return new(candidate, []);
        }
        // npm shims are scripts, not Win32 executables. Invoke the known JS entry
        // with node.exe and ArgumentList, not a shell or an interpolated command.
        var package = provider == Provider.Codex ? "@openai/codex/bin/codex.js" : "@anthropic-ai/claude-code/cli.js";
        var js = Path.Combine(roaming, "npm", "node_modules", package.Replace('/', Path.DirectorySeparatorChar));
        var node = paths.Select(path => Path.Combine(path, "node.exe")).FirstOrDefault(File.Exists);
        if (node is not null && File.Exists(js)) return new(node, [js]);
        return null;
    }

    public static string InstallationCommand(Provider provider) => provider == Provider.Codex
        ? "irm https://chatgpt.com/codex/install.ps1 | iex"
        : "irm https://claude.ai/install.ps1 | iex";
    public static string DocumentationUrl(Provider provider) => provider == Provider.Codex
        ? "https://learn.chatgpt.com/docs/codex/cli#getting-started" : "https://code.claude.com/docs/en/setup#install-claude-code";
    public static string LoginCommand(Provider provider, CliLaunch? launch)
    {
        static string Quote(string value) => "'" + value.Replace("'", "''") + "'";
        var command = launch is null ? provider.Command() : "& " + Quote(launch.Executable) +
            string.Concat(launch.PrefixArguments.Select(argument => " " + Quote(argument)));
        return command + (provider == Provider.Codex ? " login" : " auth login");
    }
}
