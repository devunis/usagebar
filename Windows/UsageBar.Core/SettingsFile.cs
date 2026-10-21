using System.Text.Json;

namespace UsageBar.Core;

public sealed class SettingsFile(string path)
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    public UsageSettings Load()
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 65536) return new();
            return (JsonSerializer.Deserialize<UsageSettings>(File.ReadAllText(path)) ?? new()).Normalize();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }

    public void Save(UsageSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(settings.Normalize(), Options));
            File.Move(temporary, path, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
