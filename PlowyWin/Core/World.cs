using SkiaSharp;

namespace Plowy;

/// A top-level window. Coordinates are global physical pixels, y down.
public readonly record struct WindowInfo(long Id, SKRect Frame);

public enum SurfaceKind { Window, Icon }

/// A horizontal edge where snow can settle: snow sits on Frame.Top.
public sealed record Surface(string Key, SurfaceKind Kind, SKRect Frame, List<(float A, float B)> Segments);

public sealed class Snapshot
{
    public int Version;
    /// Front to back.
    public List<WindowInfo> Windows = new();
    public List<Surface> Surfaces = new();

    /// Builds surfaces for windows and desktop icons, removing the parts of
    /// each top edge hidden behind windows in front of it.
    public static Snapshot Build(List<WindowInfo> windows, List<SKRect> icons, float iconScale)
    {
        var snap = new Snapshot { Windows = windows };
        for (int i = 0; i < windows.Count; i++)
        {
            var segs = Visible(windows[i].Frame, windows, i);
            if (segs.Count > 0)
                snap.Surfaces.Add(new Surface("w" + windows[i].Id, SurfaceKind.Window, windows[i].Frame, segs));
        }
        foreach (var r in icons)
        {
            // An icon item holds the picture and its label; snow sits on the picture.
            float w = Math.Min(r.Width * 0.62f, 52 * iconScale);
            var f = new SKRect(r.MidX - w / 2, r.Top + 4 * iconScale, r.MidX + w / 2, r.Bottom);
            var segs = Visible(f, windows, windows.Count);
            if (segs.Count > 0)
                snap.Surfaces.Add(new Surface($"i{(int)r.Left}:{(int)r.Top}", SurfaceKind.Icon, f, segs));
        }
        return snap;
    }

    private static List<(float A, float B)> Visible(SKRect frame, List<WindowInfo> windows, int frontCount)
    {
        float top = frame.Top;
        var segs = new List<(float A, float B)> { (frame.Left, frame.Right) };
        for (int j = 0; j < frontCount && segs.Count > 0; j++)
        {
            var o = windows[j].Frame;
            if (!(o.Top <= top && o.Bottom > top)) continue;
            var next = new List<(float A, float B)>();
            foreach (var s in segs)
            {
                if (o.Right <= s.A || o.Left >= s.B) { next.Add(s); continue; }
                if (o.Left > s.A) next.Add((s.A, o.Left));
                if (o.Right < s.B) next.Add((o.Right, s.B));
            }
            segs = next;
        }
        segs.RemoveAll(s => s.B - s.A < 12);
        return segs;
    }
}
