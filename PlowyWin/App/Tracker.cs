using System.Diagnostics;
using System.Text;
using System.Windows.Automation;
using SkiaSharp;

namespace Plowy.App;

/// Collects the frames of top-level windows (every few frames) and desktop
/// icons (every couple of seconds, on a background thread through UI Automation).
internal sealed class Tracker
{
    private readonly PlowySettings settings;
    private readonly uint ownPid = (uint)Environment.ProcessId;
    private Snapshot cached = new();
    private double lastRefresh = -1;
    private int version;
    private bool windowsLogged;

    private readonly object iconLock = new();
    private List<SKRect> icons = new();
    private double lastIconRefresh = -10;
    private bool iconBusy;

    private static readonly HashSet<string> IgnoredClasses = new()
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow",
        "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland", "XamlExplorerHostIslandWindow",
    };

    public Tracker(PlowySettings settings) { this.settings = settings; }

    public Snapshot Get(double now)
    {
        if (now - lastRefresh < 0.15 && now >= lastRefresh) return cached;
        lastRefresh = now;
        RefreshIcons(now);
        List<SKRect> iconCopy;
        lock (iconLock) iconCopy = settings.IconSnow ? new List<SKRect>(icons) : new();
        cached = Snapshot.Build(Windows(), iconCopy, Screen.PrimaryScreen is { } s ? DpiScale(s) : 1);
        cached.Version = ++version;
        return cached;
    }

    public static float DpiScale(Screen screen)
    {
        uint dpiX = 96;
        try
        {
            var hmon = MonitorFromPoint(new Native.POINT { X = screen.Bounds.Left + 1, Y = screen.Bounds.Top + 1 }, 2);
            if (GetDpiForMonitor(hmon, 0, out dpiX, out _) != 0) dpiX = 96;
        }
        catch { dpiX = 96; }
        return Math.Max(1, dpiX / 96f);
    }

    private List<WindowInfo> Windows()
    {
        var list = new List<WindowInfo>();
        var sb = new StringBuilder(256);
        Native.EnumWindows((h, _) =>
        {
            if (!Native.IsWindowVisible(h) || Native.IsIconic(h)) return true;
            Native.GetWindowThreadProcessId(h, out uint pid);
            if (pid == ownPid) return true;
            int ex = Native.GetWindowLong(h, Native.GWL_EXSTYLE);
            if ((ex & Native.WS_EX_TOOLWINDOW) != 0 && (ex & Native.WS_EX_APPWINDOW) == 0) return true;
            if ((ex & Native.WS_EX_TRANSPARENT) != 0 && (ex & Native.WS_EX_LAYERED) != 0) return true;
            if (Native.DwmGetWindowAttribute(h, Native.DWMWA_CLOAKED, out int cloaked, 4) == 0 && cloaked != 0) return true;
            sb.Clear();
            Native.GetClassName(h, sb, sb.Capacity);
            if (IgnoredClasses.Contains(sb.ToString())) return true;
            if (Native.GetWindowTextLength(h) == 0) return true;
            if (Native.DwmGetWindowAttribute(h, Native.DWMWA_EXTENDED_FRAME_BOUNDS, out Native.RECT r,
                    System.Runtime.InteropServices.Marshal.SizeOf<Native.RECT>()) != 0)
                Native.GetWindowRect(h, out r);
            if (r.Right - r.Left < 80 || r.Bottom - r.Top < 40) return true;
            list.Add(new WindowInfo(h.ToInt64(), new SKRect(r.Left, r.Top, r.Right, r.Bottom)));
            if (PlowySettings.Demo && !windowsLogged)
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "plowy-icons.txt"),
                    $"window {sb} ex={ex:X} {r.Left},{r.Top},{r.Right},{r.Bottom} pid={pid}\n");
            return true;
        }, IntPtr.Zero);
        windowsLogged = true;
        return list;
    }

    private void RefreshIcons(double now)
    {
        if (!settings.IconSnow || iconBusy || now - lastIconRefresh < 2) return;
        lastIconRefresh = now;
        iconBusy = true;
        var thread = new Thread(() =>
        {
            var found = new List<SKRect>();
            string error = "";
            try { found = DesktopIcons(out error); }
            catch (Exception e) { error = e.ToString(); }
            if (PlowySettings.Demo)
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "plowy-icons.txt"),
                    $"{DateTime.Now:T} icons={found.Count} {string.Join(" ", found.Take(4))} {error}\n");
            lock (iconLock) icons = found;
            iconBusy = false;
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }

    /// The desktop is a list view (SysListView32 "FolderView") inside
    /// SHELLDLL_DefView, hosted by Progman or by one of the WorkerW windows.
    private static List<SKRect> DesktopIcons(out string info)
    {
        info = "";
        IntPtr defView = Native.FindWindowEx(Native.FindWindow("Progman", null), IntPtr.Zero, "SHELLDLL_DefView", null);
        IntPtr worker = IntPtr.Zero;
        while (defView == IntPtr.Zero && (worker = Native.FindWindowEx(IntPtr.Zero, worker, "WorkerW", null)) != IntPtr.Zero)
            defView = Native.FindWindowEx(worker, IntPtr.Zero, "SHELLDLL_DefView", null);
        var result = new List<SKRect>();
        if (defView == IntPtr.Zero) { info = "no DefView"; return result; }
        IntPtr listView = Native.FindWindowEx(defView, IntPtr.Zero, "SysListView32", null);
        if (listView == IntPtr.Zero) { info = "no list view"; return result; }

        var list = AutomationElement.FromHandle(listView);
        var items = list.FindAll(TreeScope.Children,
            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem));
        info = $"items={items.Count}";
        foreach (AutomationElement item in items)
        {
            if (result.Count >= 300) break;
            var r = item.Current.BoundingRectangle;
            if (r.IsEmpty || r.Width < 16 || r.Height < 16 || item.Current.IsOffscreen) continue;
            result.Add(new SKRect((float)r.Left, (float)r.Top, (float)r.Right, (float)r.Bottom));
        }
        return result;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(Native.POINT pt, uint flags);
    [System.Runtime.InteropServices.DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hmon, int type, out uint dpiX, out uint dpiY);
}
