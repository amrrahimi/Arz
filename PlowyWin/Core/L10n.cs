using System.Globalization;

namespace Plowy;

public static partial class L10n
{
    /// Language code chosen by the user, or "" to follow the system.
    public static string Chosen = "";

    /// The user's choice, else the system UI language if supported, else English.
    public static string Current
    {
        get
        {
            if (Chosen.Length > 0 && Table["quit"].ContainsKey(Chosen)) return Chosen;
            string system = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
            return Table["quit"].ContainsKey(system) ? system : "en";
        }
    }

    public static bool IsRightToLeft => Rtl.Contains(Current);

    public static string T(string key) =>
        Table.TryGetValue(key, out var row) ? (row.TryGetValue(Current, out var s) ? s : row["en"]) : key;
}
