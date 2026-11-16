using SkiaSharp;

namespace Plowy;

/// Drawing helpers. Sprites are drawn in a y-up coordinate system (origin at
/// the bottom-left), matching the macOS version so the artwork is identical.
internal static class Draw
{
    public static SKColor Rgb(int r, int g, int b, float a = 1) =>
        new((byte)r, (byte)g, (byte)b, (byte)Math.Round(a * 255));

    public static SKColor White(float a) => new(255, 255, 255, (byte)Math.Round(a * 255));
    public static SKColor Black(float a) => new(0, 0, 0, (byte)Math.Round(a * 255));
    public static SKColor Gray(float w, float a = 1)
    {
        byte v = (byte)Math.Round(w * 255);
        return new SKColor(v, v, v, (byte)Math.Round(a * 255));
    }

    public static SKColor Mix(SKColor a, SKColor b, float t) => new(
        (byte)(a.Red + (b.Red - a.Red) * t), (byte)(a.Green + (b.Green - a.Green) * t),
        (byte)(a.Blue + (b.Blue - a.Blue) * t), (byte)(a.Alpha + (b.Alpha - a.Alpha) * t));

    public static SKPath Oval(float cx, float cy, float rx, float ry)
    {
        var p = new SKPath();
        p.AddOval(new SKRect(cx - rx, cy - ry, cx + rx, cy + ry));
        return p;
    }

    public static SKPath RRect(float x, float y, float w, float h, float r)
    {
        var p = new SKPath();
        p.AddRoundRect(new SKRect(x, y, x + w, y + h), r, r);
        return p;
    }

    public static SKPath Rect(float x, float y, float w, float h)
    {
        var p = new SKPath();
        p.AddRect(new SKRect(x, y, x + w, y + h));
        return p;
    }

    public static SKPath Poly(params (float X, float Y)[] pts)
    {
        var p = new SKPath();
        p.MoveTo(pts[0].X, pts[0].Y);
        for (int i = 1; i < pts.Length; i++) p.LineTo(pts[i].X, pts[i].Y);
        p.Close();
        return p;
    }

    public static SKPath Line(params (float X, float Y)[] pts)
    {
        var p = new SKPath();
        p.MoveTo(pts[0].X, pts[0].Y);
        for (int i = 1; i < pts.Length; i++) p.LineTo(pts[i].X, pts[i].Y);
        return p;
    }

    public static void Fill(SKCanvas c, SKPath p, SKColor color)
    {
        using var paint = new SKPaint { Color = color, IsAntialias = true };
        c.DrawPath(p, paint);
    }

    /// Vertical gradient; "top" is the larger y in the y-up drawing space.
    public static void Fill(SKCanvas c, SKPath p, SKColor top, SKColor bottom)
    {
        var b = p.Bounds;
        using var shader = SKShader.CreateLinearGradient(new SKPoint(0, b.Bottom), new SKPoint(0, b.Top),
            new[] { top, bottom }, SKShaderTileMode.Clamp);
        using var paint = new SKPaint { Shader = shader, IsAntialias = true };
        c.DrawPath(p, paint);
    }

    /// Radial gradient whose centre is offset by `rel` (-1..1) of the half size.
    public static void Radial(SKCanvas c, SKPath p, SKColor[] colors, float[] stops, float relX, float relY)
    {
        var b = p.Bounds;
        var center = new SKPoint(b.MidX + relX * b.Width / 2, b.MidY + relY * b.Height / 2);
        float r = Math.Max(b.Width, b.Height) / 2 * (1 + MathF.Sqrt(relX * relX + relY * relY));
        using var shader = SKShader.CreateRadialGradient(center, r, colors, stops, SKShaderTileMode.Clamp);
        using var paint = new SKPaint { Shader = shader, IsAntialias = true };
        c.DrawPath(p, paint);
    }

    public static void Stroke(SKCanvas c, SKPath p, SKColor color, float width)
    {
        using var paint = new SKPaint
        {
            Color = color, IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = width,
            StrokeCap = SKStrokeCap.Round, StrokeJoin = SKStrokeJoin.Round,
        };
        c.DrawPath(p, paint);
    }

    /// Renders into an offscreen bitmap at `scale` so sprites stay sharp.
    public static SKImage Render(float w, float h, float scale, Action<SKCanvas> draw)
    {
        var info = new SKImageInfo((int)Math.Ceiling(w * scale), (int)Math.Ceiling(h * scale),
            SKImageInfo.PlatformColorType, SKAlphaType.Premul);
        using var surface = SKSurface.Create(info);
        var c = surface.Canvas;
        c.Clear(SKColors.Transparent);
        c.Scale(scale);
        c.Translate(0, h);
        c.Scale(1, -1);
        draw(c);
        c.Flush();
        return surface.Snapshot();
    }
}

/// All sprites are drawn in code, so the app ships without image files.
public sealed class Art
{
    private static Art? shared;
    public static Art Shared => shared ??= new Art();

    public static readonly SKSize[] BulbSizes =
    {
        new(11, 23),   // 0: classic candle bulbs
        new(15, 21),   // 1: onion bulbs
        new(11, 25),   // 2: long pastel bulbs
        new(17, 21),   // 3: globes
    };

    public static readonly SKColor[][] BulbColors =
    {
        new[] { Draw.Rgb(226, 44, 38), Draw.Rgb(44, 168, 84), Draw.Rgb(255, 150, 32), Draw.Rgb(56, 116, 236), Draw.Rgb(255, 212, 60) },
        new[] { Draw.Rgb(48, 142, 84), Draw.Rgb(244, 140, 44), Draw.Rgb(190, 32, 32), Draw.Rgb(248, 198, 72) },
        new[] { Draw.Rgb(234, 62, 52), Draw.Rgb(250, 170, 186), Draw.Rgb(62, 150, 92), Draw.Rgb(255, 238, 200) },
        new[] { Draw.Rgb(244, 140, 44), Draw.Rgb(112, 180, 132), Draw.Rgb(244, 166, 180), Draw.Rgb(220, 46, 42) },
    };

    public static readonly SKSize LoaderSize = new(180, 136);
    public static readonly SKSize GondolaSize = new(44, 58);
    public static readonly SKSize StationSize = new(46, 40);
    public static readonly SKSize SnowmanSize = new(130, 166);

    public readonly SKImage Flake, Glow, Loader, Gondola, Station, Ball, Face, Buttons, Hat, Arms, Snowman;
    /// [style][color]
    public readonly SKImage[][] Bulbs;

    private Art()
    {
        Flake = SoftDot(0.45f);
        Glow = SoftDot(0f);
        Bulbs = BulbColors.Select((colors, style) => colors.Select(c => Bulb(style, c)).ToArray()).ToArray();
        Loader = LoaderImage();
        Gondola = GondolaImage();
        Station = StationImage();
        Ball = BallImage();
        Face = FaceImage();
        Buttons = ButtonsImage();
        Hat = HatImage();
        Arms = ArmsImage();
        Snowman = SnowmanImage();
    }

    // MARK: Small sprites

    public static SKImage SoftDot(float hardness) => Draw.Render(32, 32, 2, c =>
    {
        using var p = Draw.Oval(16, 16, 16, 16);
        Draw.Radial(c, p, new[] { Draw.White(1), Draw.White(hardness > 0 ? 0.85f : 0.35f), Draw.White(0) },
            new[] { 0f, Math.Max(0.2f, hardness), 1f }, 0, 0);
    });

    public static SKImage Bulb(int style, SKColor color)
    {
        var size = BulbSizes[style];
        return Draw.Render(size.Width, size.Height, 4, c =>
        {
            float w = size.Width, h = size.Height, cx = w / 2;
            float socketH = 5.5f, socketW = style == 3 || style == 1 ? 6.5f : 5.5f;
            float gt = h - socketH + 1.2f;
            var glass = new SKPath();
            switch (style)
            {
                case 0:
                    glass.MoveTo(cx - 2.4f, gt);
                    glass.CubicTo(cx - w * 0.74f, gt - h * 0.30f, cx - w * 0.36f, 0.6f, cx, 0.4f);
                    glass.CubicTo(cx + w * 0.36f, 0.6f, cx + w * 0.74f, gt - h * 0.30f, cx + 2.4f, gt);
                    glass.Close();
                    break;
                case 1:
                    glass.MoveTo(cx - 2.8f, gt);
                    glass.CubicTo(cx - w * 0.95f, gt - h * 0.28f, cx - w * 0.30f, h * 0.16f, cx, 0.4f);
                    glass.CubicTo(cx + w * 0.30f, h * 0.16f, cx + w * 0.95f, gt - h * 0.28f, cx + 2.8f, gt);
                    glass.Close();
                    break;
                case 2:
                    glass.AddRoundRect(new SKRect(1.6f, 0.5f, w - 1.6f, gt), (w - 3.2f) / 2, (w - 3.2f) / 2);
                    break;
                default:
                    float r = w / 2 - 0.8f;
                    glass.AddOval(new SKRect(cx - r, gt - 2 * r + 0.6f, cx + r, gt + 0.6f));
                    break;
            }
            var light = Draw.Mix(color, SKColors.White, 0.65f);
            var dark = Draw.Mix(color, SKColors.Black, 0.38f);
            Draw.Radial(c, glass, new[] { light, color, dark }, new[] { 0f, 0.5f, 1f }, -0.25f, 0.15f);
            Draw.Stroke(c, glass, dark.WithAlpha(140), 0.4f);
            using (var hl = Draw.Oval(cx - w * 0.16f, gt - h * 0.26f, w * 0.09f, h * 0.11f)) Draw.Fill(c, hl, Draw.White(0.6f));

            using var socket = Draw.RRect(cx - socketW / 2, h - socketH, socketW, socketH, 1.2f);
            Draw.Fill(c, socket, Draw.Rgb(46, 92, 62), Draw.Rgb(18, 44, 28));
            using var ring = Draw.Rect(cx - socketW / 2, h - socketH + 1.6f, socketW, 0.7f);
            Draw.Fill(c, ring, Draw.Rgb(110, 160, 124, 0.7f));
        });
    }

    static SKImage BallImage() => Draw.Render(64, 64, 3, c =>
    {
        using var p = Draw.Oval(32, 32, 31, 31);
        Draw.Radial(c, p, new[] { SKColors.White, Draw.Rgb(236, 242, 250), Draw.Rgb(198, 214, 234) },
            new[] { 0f, 0.55f, 1f }, -0.3f, 0.35f);
        Draw.Stroke(c, p, Draw.Rgb(150, 172, 204, 0.75f), 0.9f);
        foreach (var (x, y, r) in new[] { (20f, 22f, 5f), (42f, 16f, 4f), (46f, 38f, 6f), (18f, 44f, 3.5f) })
        {
            using var d = Draw.Oval(x, y, r, r * 0.7f);
            Draw.Fill(c, d, Draw.Rgb(120, 150, 190, 0.10f));
        }
    });

    static SKImage FaceImage() => Draw.Render(64, 64, 3, c =>
    {
        var ink = Draw.Rgb(24, 24, 28);
        foreach (var x in new[] { 23f, 41f })
        {
            using var e = Draw.Oval(x, 39, 3.4f, 3.8f); Draw.Fill(c, e, ink);
            using var g = Draw.Oval(x - 1, 40.4f, 1, 1); Draw.Fill(c, g, Draw.White(0.7f));
        }
        using var nose = Draw.Poly((30, 33), (30, 26.5f), (51, 28.5f));
        Draw.Fill(c, nose, Draw.Rgb(255, 150, 40), Draw.Rgb(226, 104, 14));
        for (int i = 0; i < 5; i++)
        {
            float a = MathF.PI * (1.22f + 0.14f * i);
            using var d = Draw.Oval(32 + MathF.Cos(a) * 14, 31 + MathF.Sin(a) * 14, 1.5f, 1.5f);
            Draw.Fill(c, d, ink);
        }
    });

    static SKImage ButtonsImage() => Draw.Render(64, 64, 3, c =>
    {
        foreach (var y in new[] { 46f, 32f, 18f })
        {
            using var b = Draw.Oval(32, y, 3.2f, 3.2f); Draw.Fill(c, b, Draw.Rgb(24, 24, 28));
            using var g = Draw.Oval(31, y + 1, 0.9f, 0.9f); Draw.Fill(c, g, Draw.White(0.5f));
        }
    });

    static SKImage HatImage() => Draw.Render(64, 44, 3, c =>
    {
        using var crown = Draw.RRect(15, 6, 34, 34, 3); Draw.Fill(c, crown, Draw.Rgb(58, 58, 64), Draw.Rgb(22, 22, 26));
        using var band = Draw.Rect(15, 9, 34, 6); Draw.Fill(c, band, Draw.Rgb(200, 36, 42));
        using var brim = Draw.RRect(4, 2, 56, 7, 3.5f); Draw.Fill(c, brim, Draw.Rgb(52, 52, 58), Draw.Rgb(18, 18, 22));
    });

    static SKImage ArmsImage() => Draw.Render(160, 50, 3, c =>
    {
        var wood = Draw.Rgb(98, 64, 34);
        using (var p = Draw.Line((60, 8), (10, 40))) Draw.Stroke(c, p, wood, 3.2f);
        using (var p = Draw.Line((24, 31), (12, 22))) Draw.Stroke(c, p, wood, 2.4f);
        using (var p = Draw.Line((20, 34), (22, 46))) Draw.Stroke(c, p, wood, 2.4f);
        using (var p = Draw.Line((100, 8), (150, 42))) Draw.Stroke(c, p, wood, 3.2f);
        using (var p = Draw.Line((136, 32), (150, 26))) Draw.Stroke(c, p, wood, 2.4f);
        using (var p = Draw.Line((140, 35), (136, 47))) Draw.Stroke(c, p, wood, 2.4f);
    });

    /// The desktop snowman without pupils (those follow the cursor and are drawn live).
    static SKImage SnowmanImage() => Draw.Render(SnowmanSize.Width, SnowmanSize.Height, 3, c =>
    {
        float cx = 65;
        using (var shadow = Draw.Oval(cx, 8, 40, 6)) Draw.Fill(c, shadow, Draw.Black(0.18f));
        var stick = Draw.Rgb(107, 69, 36);
        using (var p = Draw.Line((cx - 22, 78), (cx - 52, 100))) Draw.Stroke(c, p, stick, 3);
        using (var p = Draw.Line((cx - 44, 94), (cx - 50, 84))) Draw.Stroke(c, p, stick, 3);
        using (var p = Draw.Line((cx + 22, 78), (cx + 52, 104))) Draw.Stroke(c, p, stick, 3);
        using (var p = Draw.Line((cx + 44, 97), (cx + 54, 92))) Draw.Stroke(c, p, stick, 3);

        void Ball(float y, float r)
        {
            using var p = Draw.Oval(cx, y, r, r);
            Draw.Radial(c, p, new[] { SKColors.White, Draw.Rgb(204, 222, 242) }, new[] { 0f, 1f }, -0.35f, 0.4f);
            Draw.Stroke(c, p, Draw.Rgb(158, 184, 214, 0.9f), 1);
        }
        Ball(40, 34);
        Ball(84, 25);
        Ball(120, 18);

        var red = Draw.Rgb(217, 41, 51);
        using (var p = Draw.RRect(cx - 19, 100, 38, 8, 4)) Draw.Fill(c, p, red);
        using (var p = Draw.RRect(cx + 6, 82, 9, 22, 3)) Draw.Fill(c, p, red);
        foreach (var y in new[] { 70f, 84f, 50f })
        {
            using var b = Draw.Oval(cx, y + 2.5f, 2.5f, 2.5f);
            Draw.Fill(c, b, Draw.Gray(0.15f));
        }
        foreach (var side in new[] { -1f, 1f })
        {
            using var e = Draw.Oval(cx + side * 7, 124, 4.5f, 4.5f);
            Draw.Fill(c, e, SKColors.White);
        }
        using (var nose = Draw.Poly((cx - 1, 121), (cx + 16, 117), (cx - 1, 115)))
            Draw.Fill(c, nose, Draw.Rgb(255, 128, 26));
        for (int i = 0; i < 5; i++)
        {
            float a = MathF.PI * (1.2f + 0.15f * i);
            using var d = Draw.Oval(cx + MathF.Cos(a) * 10, 120 + MathF.Sin(a) * 10 + 1, 1.2f, 1.2f);
            Draw.Fill(c, d, Draw.Gray(0.15f));
        }
        var hat = Draw.Gray(0.12f);
        using (var p = Draw.RRect(cx - 20, 133, 40, 5, 2.5f)) Draw.Fill(c, p, hat);
        using (var p = Draw.RRect(cx - 12, 136, 24, 20, 2)) Draw.Fill(c, p, hat);
        using (var p = Draw.Rect(cx - 12, 138, 24, 4)) Draw.Fill(c, p, red);
    });

    // MARK: Cable car

    static SKImage GondolaImage() => Draw.Render(GondolaSize.Width, GondolaSize.Height, 3, c =>
    {
        using (var p = Draw.RRect(13, 53, 18, 5, 2)) Draw.Fill(c, p, Draw.Rgb(120, 124, 132), Draw.Rgb(60, 62, 68));
        using (var p = Draw.Oval(17, 55.5f, 2.2f, 2.2f)) Draw.Fill(c, p, Draw.Rgb(30, 30, 34));
        using (var p = Draw.Oval(27, 55.5f, 2.2f, 2.2f)) Draw.Fill(c, p, Draw.Rgb(30, 30, 34));
        using (var p = Draw.Line((22, 53), (22, 36))) Draw.Stroke(c, p, Draw.Rgb(70, 72, 78), 2.4f);
        using (var cabin = Draw.RRect(3, 2, 38, 34, 8))
        {
            Draw.Fill(c, cabin, Draw.Rgb(226, 52, 50), Draw.Rgb(156, 22, 30));
            Draw.Stroke(c, cabin, Draw.Rgb(96, 12, 18, 0.8f), 0.8f);
        }
        using (var p = Draw.RRect(6, 33, 32, 4, 2)) Draw.Fill(c, p, Draw.Rgb(90, 92, 98), Draw.Rgb(50, 52, 58));
        using (var glass = Draw.RRect(6.5f, 15, 31, 15, 3.5f))
        {
            Draw.Fill(c, glass, Draw.Rgb(206, 234, 250), Draw.Rgb(120, 172, 210));
            Draw.Stroke(c, glass, Draw.Rgb(70, 20, 24, 0.7f), 0.7f);
        }
        using (var p = Draw.Rect(21.2f, 15, 1.6f, 15)) Draw.Fill(c, p, Draw.Rgb(150, 26, 32));
        using (var p = Draw.Poly((10, 30), (15, 30), (11, 15), (7, 15))) Draw.Fill(c, p, Draw.White(0.35f));
        using (var p = Draw.Rect(3.5f, 9, 37, 2.2f)) Draw.Fill(c, p, Draw.White(0.85f));
    });

    static SKImage StationImage() => Draw.Render(StationSize.Width, StationSize.Height, 3, c =>
    {
        using (var p = Draw.RRect(19, 18, 8, 22, 2)) Draw.Fill(c, p, Draw.Rgb(70, 74, 82), Draw.Rgb(110, 114, 122));
        using (var p = Draw.RRect(8, 34, 30, 6, 2)) Draw.Fill(c, p, Draw.Rgb(60, 64, 72), Draw.Rgb(92, 96, 104));
        using (var wheel = Draw.Oval(23, 15, 13, 13))
        {
            Draw.Fill(c, wheel, Draw.Rgb(250, 196, 44), Draw.Rgb(214, 148, 10));
            Draw.Stroke(c, wheel, Draw.Rgb(120, 78, 0, 0.9f), 1);
        }
        using (var p = Draw.Oval(23, 15, 9, 9)) Draw.Fill(c, p, Draw.Rgb(54, 58, 66), Draw.Rgb(34, 36, 42));
        for (int i = 0; i < 6; i++)
        {
            float a = i * MathF.PI / 3;
            using var p = Draw.Line((23, 15), (23 + MathF.Cos(a) * 9, 15 + MathF.Sin(a) * 9));
            Draw.Stroke(c, p, Draw.Rgb(150, 154, 162), 1.2f);
        }
        using (var p = Draw.Oval(23, 15, 3, 3)) Draw.Fill(c, p, Draw.Rgb(240, 70, 60), Draw.Rgb(170, 26, 26));
    });

    // MARK: Snow loader

    static SKImage LoaderImage() => Draw.Render(LoaderSize.Width, LoaderSize.Height, 3, c =>
    {
        var yellowTop = Draw.Rgb(252, 196, 30);
        var yellowBottom = Draw.Rgb(214, 148, 6);
        var edge = Draw.Rgb(110, 72, 0, 0.75f);
        var gold = (Draw.Rgb(250, 214, 96), Draw.Rgb(206, 158, 40));

        using (var p = Draw.Oval(92, 4, 82, 4)) Draw.Fill(c, p, Draw.Black(0.22f));

        // Presents on the back
        using (var p = Draw.RRect(4, 4, 30, 26, 2)) Draw.Fill(c, p, Draw.Rgb(222, 52, 48), Draw.Rgb(160, 24, 28));
        using (var p = Draw.Rect(16.5f, 4, 5, 26)) Draw.Fill(c, p, gold.Item1, gold.Item2);
        using (var p = Draw.Rect(4, 15, 30, 4.5f)) Draw.Fill(c, p, gold.Item1, gold.Item2);
        using (var p = Draw.RRect(9, 30, 22, 18, 2)) Draw.Fill(c, p, Draw.Rgb(64, 160, 84), Draw.Rgb(30, 104, 52));
        using (var p = Draw.Rect(18.2f, 30, 3.6f, 18)) Draw.Fill(c, p, Draw.Rgb(214, 44, 44));
        using (var p = Draw.Oval(16, 50.5f, 4.6f, 3)) Draw.Fill(c, p, Draw.Rgb(232, 60, 56), Draw.Rgb(176, 28, 32));
        using (var p = Draw.Oval(24, 50.5f, 4.6f, 3)) Draw.Fill(c, p, Draw.Rgb(232, 60, 56), Draw.Rgb(176, 28, 32));
        using (var p = Draw.Oval(20, 49.5f, 2, 2)) Draw.Fill(c, p, Draw.Rgb(150, 20, 26));

        // Rubber track
        using (var p = Draw.RRect(38, 2, 98, 34, 17)) Draw.Fill(c, p, Draw.Rgb(52, 52, 56), Draw.Rgb(20, 20, 22));
        for (float x = 50; x < 124; x += 8)
        {
            using var a = Draw.Rect(x, 34.6f, 4, 2.4f); Draw.Fill(c, a, Draw.Rgb(16, 16, 18));
            using var b = Draw.Rect(x, 1, 4, 2.4f); Draw.Fill(c, b, Draw.Rgb(16, 16, 18));
        }
        using (var p = Draw.RRect(44, 8, 86, 22, 11)) Draw.Fill(c, p, Draw.Rgb(44, 44, 48), Draw.Rgb(70, 70, 76));
        foreach (var cx in new[] { 56f, 87f, 118f })
        {
            using var w = Draw.Oval(cx, 19, 9.5f, 9.5f);
            Draw.Fill(c, w, Draw.Rgb(124, 126, 132), Draw.Rgb(70, 72, 78));
            Draw.Stroke(c, w, Draw.Rgb(30, 30, 34), 0.8f);
            using var hub = Draw.Oval(cx, 19, 3.6f, 3.6f);
            Draw.Fill(c, hub, Draw.Rgb(200, 202, 208), Draw.Rgb(130, 132, 138));
        }
        foreach (var cx in new[] { 71.5f, 102.5f })
        {
            using var w = Draw.Oval(cx, 12.5f, 4.2f, 4.2f);
            Draw.Fill(c, w, Draw.Rgb(110, 112, 118), Draw.Rgb(64, 66, 72));
        }

        // Chassis and engine cover
        using (var p = Draw.Poly((40, 34), (132, 34), (137, 43), (133, 51), (40, 51)))
        {
            Draw.Fill(c, p, yellowTop, yellowBottom);
            Draw.Stroke(c, p, edge, 0.8f);
        }
        using (var p = Draw.RRect(38, 49, 36, 36, 5))
        {
            Draw.Fill(c, p, yellowTop, yellowBottom);
            Draw.Stroke(c, p, edge, 0.8f);
        }
        foreach (var y in new[] { 58f, 63.5f, 69f })
        {
            using var p = Draw.RRect(43, y, 16, 2.2f, 1);
            Draw.Fill(c, p, Draw.Rgb(70, 46, 0, 0.6f));
        }
        using (var p = Draw.RRect(47, 84, 4.5f, 12, 1.5f)) Draw.Fill(c, p, Draw.Rgb(90, 92, 98), Draw.Rgb(48, 50, 56));

        // Cab
        using (var p = Draw.Poly((68, 49), (112, 49), (117, 61), (111, 99), (72, 99), (68, 91)))
            Draw.Fill(c, p, Draw.Rgb(62, 64, 70), Draw.Rgb(30, 32, 36));
        using (var p = Draw.Poly((74, 57), (108, 57), (111, 63), (106, 93), (76, 93), (74, 87)))
            Draw.Fill(c, p, Draw.Rgb(204, 232, 248), Draw.Rgb(112, 164, 202));
        using (var p = Draw.Poly((85, 92), (94, 92), (86, 58), (78, 58))) Draw.Fill(c, p, Draw.White(0.34f));
        using (var p = Draw.Poly((97, 92), (100, 92), (93, 58), (90, 58))) Draw.Fill(c, p, Draw.White(0.2f));
        using (var p = Draw.RRect(67, 97, 48, 5.5f, 2.5f))
        {
            Draw.Fill(c, p, yellowTop, yellowBottom);
            Draw.Stroke(c, p, edge, 0.7f);
        }
        using (var p = Draw.Oval(114, 53.5f, 2.6f, 2.6f)) Draw.Fill(c, p, Draw.Rgb(255, 244, 190));

        // Lift arm, cylinder and bucket
        using (var p = Draw.Line((98, 50), (122, 57))) Draw.Stroke(c, p, Draw.Rgb(176, 178, 186), 3.2f);
        using (var arm = Draw.Line((57, 87), (124, 58), (141, 36)))
        {
            Draw.Stroke(c, arm, edge, 11);
            Draw.Stroke(c, arm, Draw.Rgb(240, 176, 14), 9);
        }
        using (var p = Draw.Line((60, 87.5f), (123, 60.5f))) Draw.Stroke(c, p, Draw.Rgb(255, 214, 90, 0.8f), 1.6f);
        using (var p = Draw.Oval(57, 87, 4, 4)) Draw.Fill(c, p, Draw.Rgb(90, 92, 98), Draw.Rgb(40, 42, 46));
        using (var p = Draw.Oval(124, 58, 3.4f, 3.4f)) Draw.Fill(c, p, Draw.Rgb(90, 92, 98), Draw.Rgb(40, 42, 46));

        using (var p = Draw.Oval(152, 28, 12, 9)) Draw.Fill(c, p, SKColors.White, Draw.Rgb(206, 220, 238));
        using (var bucket = Draw.Poly((134, 45), (149, 41), (174, 7), (170, 2), (136, 2), (130, 21)))
        {
            Draw.Fill(c, bucket, Draw.Rgb(92, 94, 102), Draw.Rgb(40, 42, 48));
            Draw.Stroke(c, bucket, Draw.Rgb(18, 18, 22, 0.8f), 0.8f);
        }
        using (var p = Draw.Line((137, 2.6f), (172, 5.6f))) Draw.Stroke(c, p, Draw.Rgb(212, 214, 220), 2);

        // Elf hat on the roof
        using (var hat = new SKPath())
        {
            hat.MoveTo(74, 104);
            hat.LineTo(108, 104);
            hat.CubicTo(104, 126, 80, 136, 60, 119);
            hat.CubicTo(70, 117, 76, 112, 74, 104);
            hat.Close();
            Draw.Fill(c, hat, Draw.Rgb(58, 168, 84), Draw.Rgb(22, 104, 48));
            Draw.Stroke(c, hat, Draw.Rgb(10, 60, 26, 0.7f), 0.7f);
        }
        using (var p = Draw.RRect(70, 101, 42, 7.5f, 3.6f)) Draw.Fill(c, p, Draw.Rgb(232, 56, 54), Draw.Rgb(170, 26, 32));
        using (var p = Draw.Oval(59, 118.5f, 5.5f, 5.5f)) Draw.Fill(c, p, Draw.Rgb(240, 70, 64), Draw.Rgb(168, 24, 30));
        using (var p = Draw.Oval(57.4f, 120.4f, 1.6f, 1.6f)) Draw.Fill(c, p, Draw.White(0.5f));
    });

    /// A simple snowflake icon for the tray and the program icon.
    public static SKBitmap AppIcon(int size)
    {
        var bmp = new SKBitmap(size, size, SKColorType.Bgra8888, SKAlphaType.Premul);
        using var c = new SKCanvas(bmp);
        c.Clear(SKColors.Transparent);
        float s = size / 1024f;
        c.Scale(s);
        using (var bg = new SKPath())
        {
            bg.AddRoundRect(new SKRect(40, 40, 984, 984), 225, 225);
            using var shader = SKShader.CreateLinearGradient(new SKPoint(0, 40), new SKPoint(0, 984),
                new[] { Draw.Rgb(90, 168, 255), Draw.Rgb(23, 71, 184) }, SKShaderTileMode.Clamp);
            using var paint = new SKPaint { Shader = shader, IsAntialias = true };
            c.DrawPath(bg, paint);
        }
        using var pen = new SKPaint
        {
            Color = SKColors.White, IsAntialias = true, Style = SKPaintStyle.Stroke,
            StrokeWidth = size <= 20 ? 80 : 50, StrokeCap = SKStrokeCap.Round,
        };
        for (int i = 0; i < 6; i++)
        {
            float a = i * MathF.PI / 3 - MathF.PI / 2;
            c.DrawLine(512, 512, 512 + MathF.Cos(a) * 320, 512 + MathF.Sin(a) * 320, pen);
            if (size <= 20) continue;
            foreach (var f in new[] { 0.45f, 0.7f })
            {
                float bx = 512 + MathF.Cos(a) * 320 * f, by = 512 + MathF.Sin(a) * 320 * f;
                float l = 320 * (f == 0.45f ? 0.28f : 0.2f);
                foreach (var sgn in new[] { -1, 1 })
                {
                    float b = a + sgn * MathF.PI / 4;
                    c.DrawLine(bx, by, bx + MathF.Cos(b) * l, by + MathF.Sin(b) * l, pen);
                }
            }
        }
        return bmp;
    }
}
