using SkiaSharp;

namespace Barfak;

// All scene coordinates are logical units local to one screen, y down.

/// One falling snowflake (or loose snow knocked off a pile).
public sealed class Flake
{
    public float X, Y, Vx, Vy, Size, Phase, Sway, Alpha;
    /// Small "distant" flakes fall past surfaces, big ones settle on them.
    public bool Lands;
}

/// Snow settled on a horizontal edge.
public sealed class Pile
{
    public const float ColumnWidth = 3;

    public readonly string Key;
    public SKRect GlobalFrame;
    public float X0;
    /// The edge; snow grows upwards (towards smaller y) from here.
    public float Y;
    public List<(float A, float B)> Segments = new();
    public readonly float[] Heights;
    public readonly float[] Cap;
    public bool Dirty = true;
    public SKPath? Path;

    public Pile(string key, SKRect globalFrame, float x0, float y, float[] cap)
    {
        Key = key;
        GlobalFrame = globalFrame;
        X0 = x0;
        Y = y;
        Cap = cap;
        Heights = new float[cap.Length];
    }

    /// Lumpy height limits built from a few sine waves plus fine jitter.
    public static float[] NoisyCaps(float width, float low, float high, Random rng)
    {
        int count = Math.Max(1, (int)Math.Ceiling(width / ColumnWidth));
        float R(float a, float b) => a + (float)rng.NextDouble() * (b - a);
        float p1 = R(0, 6.28f), p2 = R(0, 6.28f), p3 = R(0, 6.28f), p4 = R(0, 6.28f);
        float w1 = R(70, 110), w2 = R(30, 46), w3 = R(11, 17), w4 = R(210, 330);
        var caps = new float[count];
        for (int i = 0; i < count; i++)
        {
            float x = i * ColumnWidth;
            float n = 0.34f * MathF.Sin(x / w1 + p1) + 0.22f * MathF.Sin(x / w2 + p2)
                    + 0.12f * MathF.Sin(x / w3 + p3) + 0.32f * MathF.Sin(x / w4 + p4);
            float unit = Math.Clamp(0.5f + 0.5f * n + R(-0.04f, 0.04f), 0, 1);
            caps[i] = low + (high - low) * unit;
        }
        return caps;
    }

    public int Index(float x) => Math.Clamp((int)((x - X0) / ColumnWidth), 0, Heights.Length - 1);
    public float ColumnX(int i) => X0 + (i + 0.5f) * ColumnWidth;

    public bool Covers(float x)
    {
        foreach (var s in Segments) if (x >= s.A && x <= s.B) return true;
        return false;
    }

    public float Height(float x) => Heights[Index(x)];
    public float Top(float x) => Y - Heights[Index(x)];

    public void Add(float x, float amount, Random rng)
    {
        int i = Index(x), n = Heights.Length;
        Heights[i] += amount;
        if (i > 0) Heights[i - 1] += amount * (0.2f + 0.5f * (float)rng.NextDouble());
        if (i < n - 1) Heights[i + 1] += amount * (0.2f + 0.5f * (float)rng.NextDouble());
        // Let steep heaps slide sideways, but keep some roughness.
        int lo = Math.Max(0, i - 4), hi = Math.Min(n - 2, i + 4);
        for (int k = lo; k <= hi; k++)
        {
            float diff = Heights[k] - Heights[k + 1];
            if (MathF.Abs(diff) > 2.6f)
            {
                Heights[k] -= diff * 0.22f;
                Heights[k + 1] += diff * 0.22f;
            }
        }
        for (int k = Math.Max(0, i - 5); k <= Math.Min(n - 1, i + 5); k++)
            if (Heights[k] > Cap[k]) Heights[k] = Cap[k];
        Dirty = true;
    }

    /// How full the visible part of the pile is, 0...1.
    public float FillRatio()
    {
        float have = 0, room = 0;
        foreach (var s in Segments)
        {
            int i0 = Index(s.A + 0.01f), i1 = Index(s.B - 0.01f);
            for (int i = i0; i <= i1; i++) { have += Heights[i]; room += Cap[i]; }
        }
        return room > 0 ? have / room : 0;
    }

    public void RebuildPath()
    {
        Dirty = false;
        Path?.Dispose();
        Path = null;
        var path = new SKPath();
        bool any = false;
        foreach (var s in Segments)
        {
            int i0 = Index(s.A + 0.01f), i1 = Index(s.B - 0.01f);
            if (i1 <= i0) continue;
            float peak = 0;
            for (int i = i0; i <= i1; i++) peak = Math.Max(peak, Heights[i]);
            if (peak <= 0.6f) continue;
            any = true;
            path.MoveTo(s.A, Y);
            for (int i = i0; i <= i1; i++)
                path.LineTo(Math.Clamp(ColumnX(i), s.A, s.B), Y - Heights[i]);
            path.LineTo(s.B, Y);
            path.Close();
        }
        if (any) Path = path; else path.Dispose();
    }
}

/// A string of blinking lights draped along the top of a window.
public sealed class Garland
{
    private sealed record Bulb(SKPoint Anchor, float Angle, int Color, float Phase);

    private readonly List<Bulb> bulbs = new();
    private SKPath? wire;
    private string signature = "";
    private int style;
    private float time;

    public void Update(List<(float A, float B)> segments, float y, int newStyle, Random rng)
    {
        string sig = $"{newStyle}|{(int)y}|" + string.Join(",", segments.Select(s => $"{(int)s.A}-{(int)s.B}"));
        if (sig == signature) return;
        signature = sig;
        style = newStyle;
        bulbs.Clear();
        wire?.Dispose();
        wire = new SKPath();

        int colors = Art.BulbColors[style].Length;
        float spacing = new[] { 24f, 27f, 25f, 30f }[style];
        float tilt = new[] { 0.30f, 0.14f, 0.34f, 0f }[style];
        int index = 0;
        foreach (var s in segments)
        {
            float a = s.A + 8, b = s.B - 8, length = b - a;
            if (length < 50 || bulbs.Count >= 140) continue;
            int spans = Math.Max(1, (int)MathF.Round(length / 130));
            float span = length / spans;
            int perSpan = Math.Max(2, (int)(span / spacing));
            for (int k = 0; k < spans; k++)
            {
                var p0 = new SKPoint(a + k * span, y + 2);
                var p1 = new SKPoint(p0.X + span, y + 2);
                var c = new SKPoint((p0.X + p1.X) / 2, y + 2 + 22);
                wire.MoveTo(p0);
                wire.QuadTo(c, p1);
                for (int j = 0; j < perSpan; j++)
                {
                    float u = (j + 0.5f) / perSpan, v = 1 - u;
                    var pt = new SKPoint(v * v * p0.X + 2 * u * v * c.X + u * u * p1.X,
                                         v * v * p0.Y + 2 * u * v * c.Y + u * u * p1.Y);
                    float angle = (index % 2 == 0 ? tilt : -tilt) + ((float)rng.NextDouble() - 0.5f) * 0.12f;
                    bulbs.Add(new Bulb(pt, angle, index % colors, (float)rng.NextDouble() * 6.28f));
                    index++;
                }
            }
        }
    }

    /// Cycles through three blink programs: chase, alternate and twinkle.
    private float Brightness(int i, float phase)
    {
        int program = (int)(time / 9) % 3;
        float b = program switch
        {
            0 => ((int)(time * 3) + i) % 4 == 0 ? 1 : 0.18f,
            1 => ((int)(time * 1.4f) + i) % 2 == 0 ? 1 : 0.15f,
            _ => 0.55f + 0.45f * MathF.Sin(time * 2.6f + phase),
        };
        return Math.Clamp(b, 0, 1);
    }

    public void Animate(float t) => time = t;

    public void Draw(SKCanvas c, Art art, SKPaint scratch)
    {
        if (wire == null) return;
        var size = Art.BulbSizes[style];
        var colors = Art.BulbColors[style];

        // Glow first, blended additively.
        scratch.BlendMode = SKBlendMode.Plus;
        for (int i = 0; i < bulbs.Count; i++)
        {
            var bl = bulbs[i];
            float b = Brightness(i, bl.Phase);
            float d = size.Height * 0.6f;
            var center = new SKPoint(bl.Anchor.X - MathF.Sin(bl.Angle) * d, bl.Anchor.Y + MathF.Cos(bl.Angle) * d);
            float r = size.Width * 1.8f;
            var col = colors[bl.Color];
            scratch.Color = col.WithAlpha((byte)(255 * (0.12f + 0.78f * b) * 0.85f));
            scratch.ColorFilter = null;
            using var shader = SKShader.CreateRadialGradient(center, r,
                new[] { col.WithAlpha((byte)(200 * (0.12f + 0.78f * b))), col.WithAlpha(0) }, null, SKShaderTileMode.Clamp);
            scratch.Shader = shader;
            c.DrawCircle(center, r, scratch);
            scratch.Shader = null;
        }
        scratch.BlendMode = SKBlendMode.SrcOver;

        using (var wirePaint = new SKPaint
        {
            Color = new SKColor(18, 56, 33), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 1.3f,
        })
            c.DrawPath(wire, wirePaint);

        for (int i = 0; i < bulbs.Count; i++)
        {
            var bl = bulbs[i];
            float b = Brightness(i, bl.Phase);
            var img = art.Bulbs[style][bl.Color];
            c.Save();
            c.Translate(bl.Anchor);
            c.RotateRadians(bl.Angle);
            var dest = new SKRect(-size.Width / 2, 0, size.Width / 2, size.Height);
            scratch.Color = SKColors.White;
            scratch.ColorFilter = null;
            c.DrawImage(img, dest, scratch);
            // Dim unlit bulbs by laying a dark silhouette on top.
            float dim = (1 - b) * 0.42f;
            if (dim > 0.01f)
            {
                using var cf = SKColorFilter.CreateBlendMode(new SKColor(0, 0, 0, (byte)(dim * 255)), SKBlendMode.SrcIn);
                scratch.ColorFilter = cf;
                c.DrawImage(img, dest, scratch);
                scratch.ColorFilter = null;
            }
            c.Restore();
        }
    }
}

/// A snowball rolled by the user. Three stacked balls become a snowman.
public sealed class Snowball
{
    public enum BallRole { Plain, Head, Torso }

    public float X, Y, R, Vy, Rotation;
    public bool Held;
    public Snowball? Support;
    public BallRole Role = BallRole.Plain;

    public Snowball(float x, float y, float r) { X = x; Y = y; R = r; }

    public void Draw(SKCanvas c, Art art, SKPaint paint)
    {
        float d = R * 2;
        c.Save();
        c.Translate(X, Y);
        if (Role == BallRole.Torso)
            c.DrawImage(art.Arms, SKRect.Create(-d * 1.25f, -R * 0.5f - d * 0.39f, d * 2.5f, d * 0.78f), paint);
        c.Save();
        if (Role == BallRole.Plain) c.RotateRadians(Rotation);
        c.DrawImage(art.Ball, SKRect.Create(-R, -R, d, d), paint);
        c.Restore();
        if (Role == BallRole.Torso)
            c.DrawImage(art.Buttons, SKRect.Create(-R, -R, d, d), paint);
        if (Role == BallRole.Head)
        {
            c.DrawImage(art.Face, SKRect.Create(-R, -R, d, d), paint);
            float hy = -(R * 0.72f + d * 0.3f);
            c.DrawImage(art.Hat, SKRect.Create(-R, hy - d * 0.345f, d, d * 0.69f), paint);
        }
        c.Restore();
    }
}

/// A rope from the station to a window or a point, with a gondola on it.
public sealed class Cable
{
    public readonly long WindowId;   // 0 = fixed point
    public readonly float Dx, Dy;   // offset from the window's top-left (physical px) or the fixed point
    private SKPoint start, end;
    private float t, direction = 1, pause = 0.6f;

    public Cable(long windowId, float dx, float dy) { WindowId = windowId; Dx = dx; Dy = dy; }

    private SKPoint Control()
    {
        float dist = SKPoint.Distance(start, end);
        return new SKPoint((start.X + end.X) / 2, (start.Y + end.Y) / 2 + Math.Min(46, dist * 0.09f));
    }

    public void Update(SKPoint newStart, SKPoint newEnd, float dt)
    {
        start = newStart;
        end = newEnd;
        float length = Math.Max(60, SKPoint.Distance(start, end));
        if (pause > 0) { pause -= dt; return; }
        t += direction * 75 * dt / length;
        if (t >= 1) { t = 1; direction = -1; pause = 1.4f; }
        if (t <= 0) { t = 0; direction = 1; pause = 1.4f; }
    }

    public void Draw(SKCanvas c, Art art, SKPaint paint)
    {
        var ctl = Control();
        using (var rope = new SKPath())
        {
            rope.MoveTo(start);
            rope.QuadTo(ctl, end);
            using var stroke = new SKPaint
            {
                Color = new SKColor(41, 43, 51), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 1.6f,
            };
            c.DrawPath(rope, stroke);
        }
        using (var peg = new SKPaint { Color = new SKColor(217, 51, 51), IsAntialias = true })
            c.DrawCircle(end, 3.5f, peg);

        // Ease in and out near the ends.
        float u = t * t * (3 - 2 * t), v = 1 - u;
        float x = v * v * start.X + 2 * u * v * ctl.X + u * u * end.X;
        float y = v * v * start.Y + 2 * u * v * ctl.Y + u * u * end.Y - 1.5f;
        var size = Art.GondolaSize;
        c.DrawImage(art.Gondola, SKRect.Create(x - size.Width / 2, y, size.Width, size.Height), paint);
    }
}
