using System.Diagnostics;
using Microsoft.Win32;
using SkiaSharp;

namespace Plowy.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, "Plowy.SingleInstance", out bool first);
        if (!first) return;
        System.Windows.Forms.Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        System.Windows.Forms.Application.EnableVisualStyles();
        System.Windows.Forms.Application.SetCompatibleTextRenderingDefault(false);
        System.Windows.Forms.Application.Run(new PlowyContext());
    }
}

/// Owns the tray icon, one overlay per screen and the frame timer.
internal sealed class PlowyContext : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private readonly PlowySettings settings = PlowySettings.Load();
    private readonly Tracker tracker;
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 15 };
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly List<Overlay> overlays = new();

    public PlowyContext()
    {
        Native.timeBeginPeriod(1);
        tracker = new Tracker(settings);
        L10n.Chosen = settings.Language;
        tray = new NotifyIcon { Icon = MakeTrayIcon(), Text = "Plowy", Visible = true };
        tray.ContextMenuStrip = new ContextMenuStrip { RightToLeft = RightToLeft.Yes, ShowCheckMargin = true, ShowImageMargin = false };
        tray.ContextMenuStrip.Opening += (_, _) => BuildMenu(tray.ContextMenuStrip);
        tray.MouseUp += (_, e) =>
        {
            if (e.Button != MouseButtons.Left) return;
            // Show the same menu on a left click.
            typeof(NotifyIcon).GetMethod("ShowContextMenu",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)?.Invoke(tray, null);
        };

        SystemEvents.DisplaySettingsChanged += (_, _) => RebuildOverlays();
        timer.Tick += (_, _) => Frame();
        RebuildOverlays();
        ApplyPaused();
    }

    private static Icon MakeTrayIcon()
    {
        using var bmp = Art.AppIcon(32);
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        using var ms = new MemoryStream(data.ToArray());
        using var bitmap = new Bitmap(ms);
        return Icon.FromHandle(bitmap.GetHicon());
    }

    private void RebuildOverlays()
    {
        foreach (var o in overlays) { o.Close(); o.Dispose(); }
        overlays.Clear();
        foreach (var screen in Screen.AllScreens)
        {
            var o = new Overlay(screen, Tracker.DpiScale(screen), settings);
            overlays.Add(o);
            if (!settings.Paused) o.Show();
        }
    }

    private void ApplyPaused()
    {
        foreach (var o in overlays)
        {
            if (settings.Paused) o.Hide(); else o.Show();
        }
        timer.Enabled = !settings.Paused;
    }

    private void Frame()
    {
        double now = clock.Elapsed.TotalSeconds;
        var snap = tracker.Get(now);
        Native.GetCursorPos(out var p);
        var cursor = new SKPoint(p.X, p.Y);
        foreach (var o in overlays)
        {
            o.Scene.Update(now, snap, cursor);
            o.UpdateHitTest(cursor);
            o.Render();
        }
    }

    // MARK: Menu

    private void Changed()
    {
        settings.Changed();
        ApplyPaused();
    }

    private void BuildMenu(ContextMenuStrip menu)
    {
        menu.Items.Clear();
        var t = L10n.T;
        var direction = L10n.IsRightToLeft ? RightToLeft.Yes : RightToLeft.No;
        menu.RightToLeft = direction;
        ToolStripMenuItem Item(string text, Action action, bool? check = null)
        {
            var it = new ToolStripMenuItem(text) { RightToLeft = direction };
            it.Click += (_, _) => action();
            if (check is bool c) it.Checked = c;
            return it;
        }
        ToolStripMenuItem Sub(string text) => new(text) { RightToLeft = direction };

        menu.Items.Add(Item(settings.Paused ? t("resume") : t("pause"),
            () => { settings.Paused = !settings.Paused; Changed(); }));
        menu.Items.Add(new ToolStripSeparator());

        var intensity = Sub(t("intensity"));
        string[] levels = { t("light"), t("medium"), t("heavy") };
        for (int i = 0; i < levels.Length; i++)
        {
            int level = i;
            intensity.DropDownItems.Add(Item(levels[i], () => { settings.Intensity = level; Changed(); },
                settings.Intensity == level));
        }
        menu.Items.Add(intensity);
        menu.Items.Add(Item(t("wind"), () => { settings.Wind = !settings.Wind; Changed(); }, settings.Wind));
        menu.Items.Add(Item(t("accumulateWin"),
            () => { settings.Accumulate = !settings.Accumulate; Changed(); }, settings.Accumulate));
        menu.Items.Add(Item(t("iconSnowWin"),
            () => { settings.IconSnow = !settings.IconSnow; Changed(); }, settings.IconSnow));
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(Item(t("lights"), () => { settings.Lights = !settings.Lights; Changed(); }, settings.Lights));
        var style = Sub(t("lightStyle"));
        string[] styles = { t("styleClassic"), t("styleOnion"), t("stylePastel"), t("styleGlobe") };
        for (int i = 0; i < styles.Length; i++)
        {
            int s = i;
            style.DropDownItems.Add(Item(styles[i], () => { settings.LightStyle = s; Changed(); }, settings.LightStyle == s));
        }
        menu.Items.Add(style);
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(Item(t("plow"), () => { settings.Plow = !settings.Plow; Changed(); }, settings.Plow));
        menu.Items.Add(Item(t("plowNow"), () => overlays.ForEach(o => o.Scene.PlowNow())));
        menu.Items.Add(Item(t("cableCar"), () => { settings.CableCar = !settings.CableCar; Changed(); }, settings.CableCar));
        menu.Items.Add(Item(t("clearCables"), () => overlays.ForEach(o => o.Scene.ClearCables())));
        menu.Items.Add(Item(t("snowman"), () => { settings.Snowman = !settings.Snowman; Changed(); }, settings.Snowman));
        menu.Items.Add(new ToolStripSeparator());

        var language = Sub("🌐 " + t("language"));
        void SetLanguage(string code)
        {
            settings.Language = code;
            L10n.Chosen = code;
            Changed();
        }
        language.DropDownItems.Add(Item(t("systemLanguage"), () => SetLanguage(""), settings.Language.Length == 0));
        language.DropDownItems.Add(new ToolStripSeparator());
        foreach (var (code, name) in L10n.Languages)
            language.DropDownItems.Add(Item(name, () => SetLanguage(code), settings.Language == code));
        menu.Items.Add(language);
        menu.Items.Add(Item(t("loginWin"), ToggleStartup, StartsWithWindows()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Item(t("quit"), ExitThread));
    }

    private static bool StartsWithWindows()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue("Plowy") != null;
    }

    private static void ToggleStartup()
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (key.GetValue("Plowy") != null) key.DeleteValue("Plowy");
        else key.SetValue("Plowy", $"\"{Environment.ProcessPath}\"");
    }

    protected override void ExitThreadCore()
    {
        timer.Stop();
        tray.Visible = false;
        tray.Dispose();
        foreach (var o in overlays) { o.Close(); o.Dispose(); }
        base.ExitThreadCore();
    }
}
