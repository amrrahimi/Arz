using System.Text.Json;
using System.Text.Json.Serialization;

namespace Barfak;

/// User preferences, persisted as JSON in %AppData%\Barfak.
public sealed class BarfakSettings
{
    public int Intensity { get; set; } = 1;          // 0 light, 1 medium, 2 heavy
    public bool Wind { get; set; } = true;
    public bool Accumulate { get; set; } = true;
    public bool IconSnow { get; set; } = true;
    public bool Lights { get; set; } = true;
    public int LightStyle { get; set; } = 0;         // 0..3, see Art.BulbStyles
    public bool Plow { get; set; } = true;
    public bool CableCar { get; set; } = true;
    public bool Snowman { get; set; } = true;
    public bool Paused { get; set; } = false;
    /// Snowman position in logical units on the primary screen (-1 = default).
    public float SnowmanX { get; set; } = -1;
    public float SnowmanY { get; set; } = -1;

    /// Bumped on every change so scenes can react.
    [JsonIgnore] public int Version { get; private set; }

    /// BARFAK_DEMO=1 pre-fills the scene; used for automated screenshots.
    [JsonIgnore] public static bool Demo => Environment.GetEnvironmentVariable("BARFAK_DEMO") != null;

    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Barfak", "settings.json");

    public void Changed()
    {
        Version++;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
        }
        catch { /* settings are best effort */ }
    }

    public static BarfakSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<BarfakSettings>(File.ReadAllText(FilePath)) ?? new();
        }
        catch { }
        return new BarfakSettings();
    }
}
