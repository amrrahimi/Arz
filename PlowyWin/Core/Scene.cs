using SkiaSharp;

namespace Plowy;

/// The snow simulation for one screen. It works in logical units (y down,
/// origin at the screen's top-left); inputs and outputs in physical pixels are
/// converted with `Scale`.
public sealed class Scene
{
    private readonly PlowySettings settings;
    private readonly Art art = Art.Shared;
    private readonly Random rng = new();

    /// Screen and work area in global physical pixels.
    public readonly SKRect Bounds;
    private readonly SKRect work;
    public readonly float Scale;
    private readonly bool primary;
    private readonly float width, height;
    /// The top of the taskbar (or the bottom of the screen).
    private readonly float groundY;

    // Snow
    private readonly List<Flake> flakes = new();
    private List<Flake> debris = new();
    private readonly Dictionary<string, Pile> piles = new();
    private Pile? ground;

    // Decorations
    private readonly Dictionary<string, Garland> garlands = new();
    private Snapshot snapshot = new();
    private int syncedVersion = -1, settingsVersion = -1;

    // Loader
    private bool plowing;
    private float plowX, plowDirection = 1;
    private double plowCooldown;
    private float groundFill;
    private float plowLoad;

    // Snowballs, cable cars, snowman
    private readonly List<Snowball> balls = new();
    private readonly List<Cable> cables = new();
    private SKPoint? ropePreview;
    private double wobbleStart = -10;

    // Mouse
    private enum DragKind { None, Rolling, Ball, Cable, Snowman }
    private DragKind drag;
    private Snowball? dragBall;
    private SKPoint dragOffset, dragStart;
    private float lastRollX;
    private bool dragMoved;
    private SKPoint mouse = new(-1000, -1000), lastMouse = new(-1000, -1000);

    private double lastTime = -1, startTime = -1, lastPathRebuild;
    private float time;
    private bool demoDone;

    public Scene(SKRect bounds, SKRect workArea, float scale, bool isPrimary, PlowySettings settings)
    {
        this.settings = settings;
        Bounds = bounds;
        work = workArea;
        Scale = scale;
        primary = isPrimary;
        width = bounds.Width / scale;
        height = bounds.Height / scale;
        groundY = Math.Min(height, (workArea.Bottom - bounds.Top) / scale);
    }

    private SKPoint Local(SKPoint globalPx) => new((globalPx.X - Bounds.Left) / Scale, (globalPx.Y - Bounds.Top) / Scale);
    private SKRect Local(SKRect r) => new((r.Left - Bounds.Left) / Scale, (r.Top - Bounds.Top) / Scale,
                                          (r.Right - Bounds.Left) / Scale, (r.Bottom - Bounds.Top) / Scale);
    private float R(float a, float b) => a + (float)rng.NextDouble() * (b - a);

    private SKPoint StationPoint => new(width / 2, (work.Top - Bounds.Top) / Scale + 24);

    public event Action? CablesCleared;

    public void PlowNow() => StartPlow();

    public void ClearCables()
    {
        cables.Clear();
        CablesCleared?.Invoke();
    }

    // MARK: Flakes

    private int TargetFlakeCount
    {
        get
        {
            int[] bases = { 110, 260, 520 };
            float area = width * height / (1440f * 900f);
            return (int)(bases[Math.Clamp(settings.Intensity, 0, 2)] * Math.Clamp(area, 0.6f, 2.2f));
        }
    }

    private void Configure(Flake f, bool anywhere)
    {
        f.Size = R(2, 7.5f);
        f.Lands = f.Size > 3.6f;
        f.Vy = 26 + f.Size * 13 + R(0, 18);
        f.Phase = R(0, MathF.Tau);
        f.Sway = R(6, 22);
        f.X = R(-60, width + 60);
        f.Y = anywhere ? R(0, height) : -R(5, 60);
        f.Alpha = 0.4f + 0.55f * (f.Size / 7.5f);
    }

    private void AdjustFlakeCount()
    {
        int target = TargetFlakeCount, changed = 0;
        while (flakes.Count < target && changed < 12)
        {
            var f = new Flake();
            Configure(f, flakes.Count < target / 3);
            flakes.Add(f);
            changed++;
        }
        while (flakes.Count > target && changed < 12)
        {
            flakes.RemoveAt(flakes.Count - 1);
            changed++;
        }
    }

    private void SpawnDebris(float x, float y, float vx = 0, float? vy = null)
    {
        if (debris.Count >= 600) return;
        debris.Add(new Flake
        {
            Size = R(3, 6), Vx = vx, Vy = vy ?? R(10, 60), Phase = R(0, MathF.Tau), Sway = R(10, 40),
            X = x, Y = y, Alpha = 0.9f,
        });
    }

    // MARK: Piles and garlands

    private void Dump(Pile pile)
    {
        for (int i = 0; i < pile.Heights.Length; i += 2)
        {
            float h = pile.Heights[i], x = pile.ColumnX(i);
            if (h > 2 && pile.Covers(x)) SpawnDebris(x, pile.Y - R(0, h));
        }
    }

    private void Remove(Pile? pile)
    {
        if (pile == null) return;
        Dump(pile);
        pile.Path?.Dispose();
    }

    private void SyncSurfaces()
    {
        if (settings.Accumulate)
        {
            if (ground == null)
            {
                ground = new Pile("ground", SKRect.Empty, 0, groundY, Pile.NoisyCaps(width, 5, 30, rng));
                ground.Segments = new() { (0, width) };
            }
        }
        else
        {
            Remove(ground);
            ground = null;
        }

        var seenPiles = new HashSet<string>();
        var seenGarlands = new HashSet<string>();
        foreach (var sf in snapshot.Surfaces)
        {
            if (sf.Kind == SurfaceKind.Icon && !settings.IconSnow) continue;
            var lf = Local(sf.Frame);
            float ly = lf.Top;
            if (ly < 4 || ly > groundY - 16) continue;
            var segs = new List<(float A, float B)>();
            foreach (var g in sf.Segments)
            {
                float a = Math.Max(0, (g.A - Bounds.Left) / Scale), b = Math.Min(width, (g.B - Bounds.Left) / Scale);
                if (b - a >= 12) segs.Add((a, b));
            }
            if (segs.Count == 0) continue;

            if (settings.Lights && sf.Kind == SurfaceKind.Window)
            {
                seenGarlands.Add(sf.Key);
                if (!garlands.TryGetValue(sf.Key, out var garland))
                    garlands[sf.Key] = garland = new Garland();
                garland.Update(segs, ly, Math.Clamp(settings.LightStyle, 0, 3), rng);
            }

            if (!settings.Accumulate) continue;
            seenPiles.Add(sf.Key);
            if (piles.TryGetValue(sf.Key, out var pile))
            {
                var old = pile.GlobalFrame;
                if (MathF.Abs(old.Width - sf.Frame.Width) > 0.5f)
                {
                    Remove(pile);
                    piles.Remove(sf.Key);
                }
                else
                {
                    if (MathF.Abs(old.Left - sf.Frame.Left) > 0.5f || MathF.Abs(old.Top - sf.Frame.Top) > 0.5f)
                    {
                        // The window was dragged: the snow falls off.
                        Dump(pile);
                        Array.Clear(pile.Heights);
                        pile.GlobalFrame = sf.Frame;
                        pile.X0 = lf.Left;
                        pile.Y = ly;
                        pile.Dirty = true;
                    }
                    if (!pile.Segments.SequenceEqual(segs))
                    {
                        pile.Segments = segs;
                        pile.Dirty = true;
                    }
                    continue;
                }
            }
            float high = sf.Kind == SurfaceKind.Window ? 15 : 8;
            piles[sf.Key] = new Pile(sf.Key, sf.Frame, lf.Left, ly, Pile.NoisyCaps(lf.Width, high * 0.45f, high, rng))
            {
                Segments = segs,
            };
        }
        foreach (var key in piles.Keys.Where(k => !seenPiles.Contains(k)).ToList())
        {
            Remove(piles[key]);
            piles.Remove(key);
        }
        foreach (var key in garlands.Keys.Where(k => !seenGarlands.Contains(k)).ToList())
            garlands.Remove(key);
    }

    // MARK: Loader

    private void StartPlow()
    {
        if (plowing || ground == null) return;
        plowing = true;
        plowDirection = -plowDirection;
        plowX = plowDirection > 0 ? -110 : width + 110;
        plowLoad = 0;
    }

    /// Balls that are part of a stacked snowman survive the plow.
    private bool InSnowman(Snowball b) =>
        b.Role != Snowball.BallRole.Plain || balls.Any(o => o.Support == b && o.Role == Snowball.BallRole.Torso);

    /// The snow the loader scoops up, heaped in its bucket (loader-local, y down).
    private SKPath? HeapPath()
    {
        if (plowLoad <= 0.02f) return null;
        float l = Math.Min(1, plowLoad);
        float w = 18 + 18 * l, h = 6 + 22 * l, x0 = 63, b = -18;
        var p = new SKPath();
        p.MoveTo(x0 - w * 0.5f, b);
        p.CubicTo(x0 - w * 0.55f, b - h * 0.7f, x0 - w * 0.3f, b - h * 1.05f, x0 + 2, b - h);
        p.CubicTo(x0 + w * 0.35f, b - h * 0.95f, x0 + w * 0.66f, b - h * 0.55f, x0 + w * 0.62f, b - 2);
        p.Close();
        return p;
    }

    private void UpdatePlow(float dt, double now)
    {
        if (!plowing)
        {
            if (settings.Plow && groundFill > 0.88f && now > plowCooldown) StartPlow();
            return;
        }
        float before = plowX + plowDirection * 80;
        plowX += plowDirection * 105 * dt;
        float after = plowX + plowDirection * 80;
        float lo = Math.Min(before, after), hi = Math.Max(before, after);
        if (ground is { } g && hi >= 0 && lo <= width)
        {
            int a = g.Index(lo), b = g.Index(hi);
            for (int i = a; i <= b; i++)
            {
                if (g.Heights[i] <= 0.3f) continue;
                plowLoad += g.Heights[i] * 0.0035f;
                if (rng.Next(5) == 0)   // a little spray; most of it ends up in the bucket
                    SpawnDebris(g.ColumnX(i) + plowDirection * 6, groundY - g.Heights[i] - R(10, 30),
                                plowDirection * R(20, 80), -R(30, 110));
                g.Heights[i] = 0;
                g.Dirty = true;
            }
        }

        // Loose snowballs on the ground are scooped up too.
        foreach (var ball in balls.Where(b => !b.Held && b.Support == null && !InSnowman(b)
                                              && b.X + b.R >= lo && b.X - b.R <= hi).ToList())
        {
            plowLoad += ball.R / 60;
            for (int k = 0; k < 5; k++) SpawnDebris(ball.X + R(-ball.R, ball.R), ball.Y - ball.R * 0.5f);
            balls.Remove(ball);
        }
        if (plowX < -130 || plowX > width + 130)
        {
            plowing = false;
            plowCooldown = now + 20;
        }
    }

    // MARK: Snowballs

    private Snowball AddBall(float x, float y, float r)
    {
        var ball = new Snowball(x, y, r);
        balls.Add(ball);
        if (balls.Count > 14) balls.RemoveAt(0);
        return ball;
    }

    private Snowball? BallAt(SKPoint p)
    {
        for (int i = balls.Count - 1; i >= 0; i--)
            if (SKPoint.Distance(p, new SKPoint(balls[i].X, balls[i].Y)) <= balls[i].R + 3) return balls[i];
        return null;
    }

    private void UpdateBalls(float dt)
    {
        var rolling = drag == DragKind.Rolling ? dragBall : null;
        foreach (var b in balls)
        {
            if (b.Held || b == rolling) continue;
            b.Vy += 1400 * dt;
            b.Y += b.Vy * dt;
            float rest = groundY - b.R * 0.92f;
            Snowball? support = null;
            foreach (var o in balls)
            {
                if (o == b || o.Held || o == rolling || o.Support == b) continue;
                if (MathF.Abs(b.X - o.X) >= o.R * 0.85f || o.Y <= b.Y - 1) continue;
                float top = o.Y - (o.R + b.R) * 0.86f;
                if (top < rest) { rest = top; support = o; }
            }
            if (b.Y >= rest)
            {
                b.Y = rest;
                b.Vy = 0;
                b.Support = support;
                if (support != null) b.X += (support.X - b.X) * Math.Min(1, dt * 6);
            }
            else b.Support = null;
            b.X = Math.Clamp(b.X, b.R, width - b.R);
        }

        // Three stacked balls become a snowman.
        bool HasRider(Snowball s) => balls.Any(o => o.Support == s);
        foreach (var b in balls)
        {
            var rider = balls.FirstOrDefault(o => o.Support == b);
            if (rider == null && b.Support is { Support: not null }) b.Role = Snowball.BallRole.Head;
            else if (rider != null && !HasRider(rider) && b.Support != null) b.Role = Snowball.BallRole.Torso;
            else b.Role = Snowball.BallRole.Plain;
        }
    }

    // MARK: Snowman

    private SKRect SnowmanRect
    {
        get
        {
            var size = Art.SnowmanSize;
            float x = settings.SnowmanX, y = settings.SnowmanY;
            if (x < 0 || y < 0 || x > width - 20 || y > height - 20)
            {
                x = width - size.Width - 60;
                y = groundY - size.Height;
            }
            return SKRect.Create(x, y, size.Width, size.Height);
        }
    }

    private bool ShowSnowman => primary && settings.Snowman;

    // MARK: Mouse (physical pixels, global)

    private bool OnGroundSnow(SKPoint p) =>
        ground is { } g && p.Y <= groundY && g.Covers(p.X) && g.Height(p.X) > 3 && p.Y >= g.Top(p.X) - 3;

    /// True where the overlay should take clicks instead of passing them on.
    public bool WantsMouse(SKPoint globalPx)
    {
        if (drag != DragKind.None) return true;
        var p = Local(globalPx);
        if (settings.CableCar && SKPoint.Distance(p, StationPoint) < 20) return true;
        if (ShowSnowman && SnowmanRect.Contains(p) && p.Y > SnowmanRect.Top + 20) return true;
        if (BallAt(p) != null) return true;
        return OnGroundSnow(p);
    }

    public void MouseDown(SKPoint globalPx)
    {
        var p = Local(globalPx);
        dragStart = p;
        dragMoved = false;
        if (settings.CableCar && SKPoint.Distance(p, StationPoint) < 22)
        {
            drag = DragKind.Cable;
        }
        else if (BallAt(p) is { } b)
        {
            b.Held = true;
            b.Support = null;
            drag = DragKind.Ball;
            dragBall = b;
            dragOffset = new SKPoint(b.X - p.X, b.Y - p.Y);
        }
        else if (ShowSnowman && SnowmanRect.Contains(p))
        {
            drag = DragKind.Snowman;
            dragOffset = new SKPoint(SnowmanRect.Left - p.X, SnowmanRect.Top - p.Y);
        }
        else if (OnGroundSnow(p))
        {
            dragBall = AddBall(p.X, groundY - 5, 5);
            drag = DragKind.Rolling;
            lastRollX = p.X;
        }
    }

    public void MouseDrag(SKPoint globalPx)
    {
        var p = Local(globalPx);
        if (SKPoint.Distance(p, dragStart) > 3) dragMoved = true;
        switch (drag)
        {
            case DragKind.Cable:
                ropePreview = p;
                break;
            case DragKind.Ball when dragBall != null:
                dragBall.X = p.X + dragOffset.X;
                dragBall.Y = Math.Min(groundY - dragBall.R * 0.92f, p.Y + dragOffset.Y);
                dragBall.Vy = 0;
                break;
            case DragKind.Snowman:
                settings.SnowmanX = p.X + dragOffset.X;
                settings.SnowmanY = p.Y + dragOffset.Y;
                break;
            case DragKind.Rolling when dragBall != null && ground != null:
            {
                var b = dragBall;
                var g = ground;
                float dx = p.X - lastRollX;
                if (MathF.Abs(dx) >= 1)
                {
                    // Pick up the snow the ball rolls over.
                    float gathered = 0;
                    int a = g.Index(Math.Min(lastRollX, p.X) - b.R * 0.5f);
                    int c = g.Index(Math.Max(lastRollX, p.X) + b.R * 0.5f);
                    for (int i = a; i <= c; i++)
                    {
                        if (g.Heights[i] <= 0.4f || !g.Covers(g.ColumnX(i))) continue;
                        gathered += g.Heights[i] * 0.85f * Pile.ColumnWidth;
                        g.Heights[i] *= 0.15f;
                        g.Dirty = true;
                    }
                    float area = MathF.PI * b.R * b.R + gathered * 1.3f;
                    b.R = Math.Min(38, MathF.Sqrt(area / MathF.PI));
                    b.Rotation += dx / Math.Max(6, b.R);
                    lastRollX = p.X;
                }
                b.X = Math.Clamp(p.X, b.R, width - b.R);
                b.Y = groundY - b.R * 0.92f;
                break;
            }
        }
    }

    public void MouseUp(SKPoint globalPx)
    {
        var p = Local(globalPx);
        switch (drag)
        {
            case DragKind.Cable:
                ropePreview = null;
                if (SKPoint.Distance(p, dragStart) > 30) AttachCable(globalPx);
                else if (cables.Count > 0) cables.RemoveAt(cables.Count - 1);   // a plain click removes the newest rope
                break;
            case DragKind.Ball when dragBall != null:
                dragBall.Held = false;
                break;
            case DragKind.Snowman:
                if (dragMoved) settings.Changed();
                else wobbleStart = lastTime;
                break;
            case DragKind.Rolling when dragBall != null:
                if (dragBall.R < 7)
                {
                    // Too small to keep: it crumbles.
                    for (int i = 0; i < 6; i++) SpawnDebris(dragBall.X + R(-6, 6), dragBall.Y);
                    balls.Remove(dragBall);
                }
                break;
        }
        drag = DragKind.None;
        dragBall = null;
    }

    // MARK: Cable cars

    private void AttachCable(SKPoint globalPx)
    {
        Cable cable = new(0, globalPx.X, globalPx.Y);
        foreach (var w in snapshot.Windows)
        {
            if (!w.Frame.Contains(globalPx)) continue;
            cable = new Cable(w.Id, globalPx.X - w.Frame.Left, globalPx.Y - w.Frame.Top);
            break;
        }
        cables.Add(cable);
        if (cables.Count > 6) cables.RemoveAt(0);
    }

    private void UpdateCables(float dt)
    {
        if (!settings.CableCar)
        {
            cables.Clear();
            return;
        }
        for (int i = cables.Count - 1; i >= 0; i--)
        {
            var cable = cables[i];
            SKPoint? end = null;
            if (cable.WindowId == 0) end = new SKPoint(cable.Dx, cable.Dy);
            else
            {
                foreach (var w in snapshot.Windows)
                    if (w.Id == cable.WindowId) { end = new SKPoint(w.Frame.Left + cable.Dx, w.Frame.Top + cable.Dy); break; }
            }
            if (end is { } e) cable.Update(StationPoint, Local(e), dt);
            else cables.RemoveAt(i);   // its window was closed
        }
    }

    // MARK: Demo (automated screenshots)

    private void RunDemo()
    {
        demoDone = true;
        var all = piles.Values.ToList();
        if (ground != null) all.Add(ground);
        foreach (var p in all)
        {
            for (int i = 0; i < p.Heights.Length; i++) p.Heights[i] = p.Cap[i] * R(0.9f, 1);
            p.Dirty = true;
        }
        if (!primary) return;
        AttachCable(new SKPoint(Bounds.Left + Bounds.Width * 0.22f, Bounds.Top + Bounds.Height * 0.5f));
        if (snapshot.Windows.Count > 0)
        {
            var w = snapshot.Windows[0].Frame;
            AttachCable(new SKPoint(w.Right - 30 * Scale, w.Top + 4 * Scale));
        }
        float bx = width * 0.62f;
        AddBall(bx, groundY - 40, 30);
        AddBall(bx, groundY - 160, 22);
        AddBall(bx, groundY - 280, 15);
        AddBall(width * 0.5f, groundY - 40, 18);
    }

    // MARK: Frame loop

    public void Update(double now, Snapshot snap, SKPoint mouseGlobalPx)
    {
        if (startTime < 0) startTime = now;
        float dt = lastTime < 0 ? 0 : (float)Math.Clamp(now - lastTime, 0, 1.0 / 30.0);
        lastTime = now;
        time = (float)(now % 10_000);
        if (dt <= 0) return;

        AdjustFlakeCount();

        snapshot = snap;
        if (snap.Version != syncedVersion || settings.Version != settingsVersion)
        {
            syncedVersion = snap.Version;
            settingsVersion = settings.Version;
            SyncSurfaces();
        }

        if (PlowySettings.Demo && !demoDone && now - startTime > 3) RunDemo();

        float wind = settings.Wind ? 28 * MathF.Sin(time * 0.13f) + 16 * MathF.Sin(time * 0.37f + 1.3f) : 0;

        mouse = Local(mouseGlobalPx);
        bool mouseMoved = MathF.Abs(mouse.X - lastMouse.X) + MathF.Abs(mouse.Y - lastMouse.Y) > 0.5f;
        lastMouse = mouse;

        var surfaces = piles.Values.ToList();
        if (mouseMoved && drag == DragKind.None)
            foreach (var p in surfaces) Shovel(p);   // the cursor works as a little shovel
        if (ground != null) surfaces.Add(ground);

        const float radius = 90;
        foreach (var f in flakes)
        {
            f.Phase += dt * 1.6f;
            float yOld = f.Y;
            f.X += (wind * (0.4f + f.Size / 7.5f) + MathF.Sin(f.Phase) * f.Sway) * dt;
            f.Y += f.Vy * dt;

            // Flakes swirl away from the cursor.
            float dx = f.X - mouse.X, dy = f.Y - mouse.Y, d2 = dx * dx + dy * dy;
            if (d2 < radius * radius && d2 > 0.01f)
            {
                float d = MathF.Sqrt(d2), push = (1 - d / radius) * 260 * dt;
                f.X += dx / d * push;
                f.Y += dy / d * push;
            }

            bool landed = false;
            if (f.Lands)
            {
                foreach (var p in surfaces)
                {
                    if (!p.Covers(f.X)) continue;
                    float top = p.Top(f.X);
                    if (yOld <= top && f.Y >= top)
                    {
                        p.Add(f.X, f.Size * R(0.18f, 0.42f), rng);
                        landed = true;
                        break;
                    }
                }
            }
            if (landed || f.Y > groundY + 10) Configure(f, false);
            else if (f.X < -80) f.X = width + 60;
            else if (f.X > width + 80) f.X = -60;
        }

        if (debris.Count > 0)
        {
            var alive = new List<Flake>(debris.Count);
            foreach (var f in debris)
            {
                f.Phase += dt * 3;
                f.Vy = Math.Min(340, f.Vy + 260 * dt);
                f.Vx *= Math.Max(0, 1 - 1.5f * dt);
                f.X += (f.Vx + wind * 0.6f + MathF.Sin(f.Phase) * f.Sway) * dt;
                f.Y += f.Vy * dt;
                if (f.Y < groundY + 10) alive.Add(f);
            }
            debris = alive;
        }

        UpdatePlow(dt, now);
        UpdateBalls(dt);
        UpdateCables(dt);
        foreach (var g in garlands.Values) g.Animate(time);

        if (now - lastPathRebuild > 0.12 || now < lastPathRebuild)
        {
            lastPathRebuild = now;
            foreach (var p in surfaces) if (p.Dirty) p.RebuildPath();
            groundFill = ground?.FillRatio() ?? 0;
        }
    }

    private void Shovel(Pile pile)
    {
        if (!pile.Covers(mouse.X)) return;
        int i = pile.Index(mouse.X);
        if (mouse.Y > pile.Y + 4 || mouse.Y < pile.Y - pile.Cap[i] - 8) return;
        int a = pile.Index(mouse.X - 12), b = pile.Index(mouse.X + 12);
        for (int k = a; k <= b; k++)
        {
            if (pile.Heights[k] <= 0.5f) continue;
            if (rng.Next(3) == 0) SpawnDebris(pile.ColumnX(k), pile.Y - pile.Heights[k]);
            pile.Heights[k] *= 0.4f;
            pile.Dirty = true;
        }
    }

    // MARK: Drawing

    private readonly SKPaint imagePaint = new() { IsAntialias = true, FilterQuality = SKFilterQuality.Medium };
    private readonly SKPaint scratch = new() { IsAntialias = true, FilterQuality = SKFilterQuality.Medium };
    private readonly SKPaint snowFill = new() { Color = new SKColor(252, 254, 255, 247), IsAntialias = true };
    private readonly SKPaint snowEdge = new()
    {
        Color = new SKColor(189, 207, 230, 230), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 0.8f,
    };

    /// Draws onto a canvas whose origin is the screen's top-left in physical pixels.
    public void Draw(SKCanvas c)
    {
        c.Save();
        c.Scale(Scale);

        void DrawFlake(Flake f)
        {
            imagePaint.Color = SKColors.White.WithAlpha((byte)(f.Alpha * 255));
            float s = f.Size;
            c.DrawImage(art.Flake, SKRect.Create(f.X - s / 2, f.Y - s / 2, s, s), imagePaint);
        }
        foreach (var f in flakes) DrawFlake(f);
        foreach (var f in debris) DrawFlake(f);
        imagePaint.Color = SKColors.White;

        foreach (var p in piles.Values) DrawPile(c, p);
        if (ground != null) DrawPile(c, ground);

        foreach (var g in garlands.Values) g.Draw(c, art, scratch);
        foreach (var cable in cables) cable.Draw(c, art, imagePaint);
        foreach (var b in balls) b.Draw(c, art, imagePaint);

        if (plowing)
        {
            var size = Art.LoaderSize;
            float bob = MathF.Abs(MathF.Sin(time * 17)) * 0.9f;
            c.Save();
            c.Translate(plowX, groundY - bob);
            c.Scale(plowDirection, 1);
            c.DrawImage(art.Loader, SKRect.Create(-size.Width / 2, -size.Height, size.Width, size.Height), imagePaint);
            using (var heap = HeapPath())
            {
                if (heap != null)
                {
                    using var fill = new SKPaint { Color = new SKColor(252, 254, 255), IsAntialias = true };
                    c.DrawPath(heap, fill);
                    c.DrawPath(heap, snowEdge);
                }
            }
            c.Restore();
        }

        if (ropePreview is { } rp)
        {
            using var paint = new SKPaint
            {
                Color = new SKColor(41, 43, 51, 230), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 1.6f,
            };
            c.DrawLine(StationPoint, rp, paint);
        }

        if (settings.CableCar)
        {
            var size = Art.StationSize;
            var sp = StationPoint;
            float s = SKPoint.Distance(mouse, sp) < 20 ? 1.18f : 1;
            c.DrawImage(art.Station, SKRect.Create(sp.X - size.Width * s / 2, sp.Y - 5 - size.Height * s / 2,
                                                   size.Width * s, size.Height * s), imagePaint);
        }

        if (ShowSnowman) DrawSnowman(c);
        c.Restore();
    }

    private void DrawPile(SKCanvas c, Pile p)
    {
        if (p.Path == null) return;
        c.DrawPath(p.Path, snowFill);
        c.DrawPath(p.Path, snowEdge);
    }

    private void DrawSnowman(SKCanvas c)
    {
        var r = SnowmanRect;
        c.Save();
        // Damped wobble around the base after a click.
        double age = lastTime - wobbleStart;
        if (age >= 0 && age < 1.2)
        {
            float angle = (float)(0.22 * Math.Exp(-3.2 * age) * Math.Sin(age * 16));
            c.RotateRadians(-angle, r.MidX, r.Bottom - 8);
        }
        c.DrawImage(art.Snowman, r, imagePaint);

        // Eyes that follow the cursor.
        var head = new SKPoint(r.Left + 65, r.Bottom - 120);
        float dx = mouse.X - head.X, dy = mouse.Y - head.Y;
        float d = Math.Max(1, MathF.Sqrt(dx * dx + dy * dy));
        float k = Math.Min(1, d / 60) * 2.2f;
        using var pupil = new SKPaint { Color = new SKColor(26, 26, 26), IsAntialias = true };
        foreach (var side in new[] { -1f, 1f })
            c.DrawCircle(head.X + side * 7 + dx / d * k, head.Y - 4 + dy / d * k, 2.5f, pupil);
        c.Restore();
    }
}
