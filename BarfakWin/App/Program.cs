using System.Diagnostics;
using Microsoft.Win32;
using SkiaSharp;

namespace Barfak.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, "Barfak.SingleInstance", out bool first);
        if (!first) return;
        System.Windows.Forms.Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        System.Windows.Forms.Application.EnableVisualStyles();
        System.Windows.Forms.Application.SetCompatibleTextRenderingDefault(false);
        System.Windows.Forms.Application.Run(new BarfakContext());
    }
}

/// Owns the tray icon, one overlay per screen and the frame timer.
internal sealed class BarfakContext : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private readonly BarfakSettings settings = BarfakSettings.Load();
    private readonly Tracker tracker;
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 15 };
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly List<Overlay> overlays = new();

    public BarfakContext()
    {
        Native.timeBeginPeriod(1);
        tracker = new Tracker(settings);
        tray = new NotifyIcon { Icon = MakeTrayIcon(), Text = "Barfak", Visible = true };
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
        ToolStripMenuItem Item(string text, Action action, bool? check = null)
        {
            var it = new ToolStripMenuItem(text) { RightToLeft = RightToLeft.Yes };
            it.Click += (_, _) => action();
            if (check is bool c) it.Checked = c;
            return it;
        }

        menu.Items.Add(Item(settings.Paused ? "ادامه بارش برف" : "توقف بارش برف",
            () => { settings.Paused = !settings.Paused; Changed(); }));
        menu.Items.Add(new ToolStripSeparator());

        var intensity = new ToolStripMenuItem("شدت بارش");
        string[] levels = { "کم", "متوسط", "زیاد" };
        for (int i = 0; i < levels.Length; i++)
        {
            int level = i;
            intensity.DropDownItems.Add(Item(levels[i], () => { settings.Intensity = level; Changed(); },
                settings.Intensity == level));
        }
        menu.Items.Add(intensity);
        menu.Items.Add(Item("باد", () => { settings.Wind = !settings.Wind; Changed(); }, settings.Wind));
        menu.Items.Add(Item("نشستن برف روی پنجره‌ها و نوار وظیفه",
            () => { settings.Accumulate = !settings.Accumulate; Changed(); }, settings.Accumulate));
        menu.Items.Add(Item("برف روی آیکون‌های دسکتاپ",
            () => { settings.IconSnow = !settings.IconSnow; Changed(); }, settings.IconSnow));
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(Item("ریسهٔ چراغ روی پنجره‌ها", () => { settings.Lights = !settings.Lights; Changed(); }, settings.Lights));
        var style = new ToolStripMenuItem("مدل چراغ");
        string[] styles = { "شمعی کلاسیک", "پیازی", "کشیدهٔ پاستلی", "گوی" };
        for (int i = 0; i < styles.Length; i++)
        {
            int s = i;
            style.DropDownItems.Add(Item(styles[i], () => { settings.LightStyle = s; Changed(); }, settings.LightStyle == s));
        }
        menu.Items.Add(style);
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(Item("برف‌روب خودکار", () => { settings.Plow = !settings.Plow; Changed(); }, settings.Plow));
        menu.Items.Add(Item("همین حالا برف‌روبی کن", () => overlays.ForEach(o => o.Scene.PlowNow())));
        menu.Items.Add(Item("تله‌کابین", () => { settings.CableCar = !settings.CableCar; Changed(); }, settings.CableCar));
        menu.Items.Add(Item("حذف همهٔ طناب‌های تله‌کابین", () => overlays.ForEach(o => o.Scene.ClearCables())));
        menu.Items.Add(Item("آدم‌برفی", () => { settings.Snowman = !settings.Snowman; Changed(); }, settings.Snowman));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Item("اجرا هنگام روشن شدن ویندوز", ToggleStartup, StartsWithWindows()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Item("خروج", ExitThread));
    }

    private static bool StartsWithWindows()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue("Barfak") != null;
    }

    private static void ToggleStartup()
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (key.GetValue("Barfak") != null) key.DeleteValue("Barfak");
        else key.SetValue("Barfak", $"\"{Environment.ProcessPath}\"");
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
