using Plowy;
using SkiaSharp;

// Runs the scene headless against made-up windows and writes PNG frames, so
// the artwork and the simulation can be checked without Windows.
// Usage: Plowy.Preview <output-dir> [--icon <ico-path>]
string outDir = args.Length > 0 ? args[0] : "preview";
Directory.CreateDirectory(outDir);

if (args.Length > 2 && args[1] == "--icon")
{
    WriteIco(args[2], new[] { 16, 20, 24, 32, 48, 64, 128, 256 });
    return;
}

Environment.SetEnvironmentVariable("PLOWY_DEMO", "1");
const int W = 1280, H = 800;
var bounds = new SKRect(0, 0, W, H);
var work = new SKRect(0, 0, W, H - 48);   // a 48 px taskbar
var settings = new PlowySettings();
var scene = new Scene(bounds, work, 1, true, settings);

var windows = new List<WindowInfo>
{
    new(1, new SKRect(120, 150, 720, 560)),
    new(2, new SKRect(640, 330, 1060, 640)),
};
var icons = new List<SKRect> { new(1180, 20, 1255, 100), new(1180, 120, 1255, 200), new(1180, 220, 1255, 300) };
var snap = Snapshot.Build(windows, icons, 1);
snap.Version = 1;

double t = 0;
void Run(double seconds, SKPoint mouse)
{
    for (int i = 0; i < seconds * 60; i++) { t += 1 / 60.0; scene.Update(t, snap, mouse); }
}

Run(5, new SKPoint(-500, -500));
Save("win-demo.png");

// Roll a fresh snowball along the taskbar snow and hang a rope on window 2.
var ground = new SKPoint(60, H - 50);
scene.MouseDown(ground);
for (int x = 60; x < 420; x += 6) { scene.MouseDrag(new SKPoint(x, H - 50)); Run(1 / 60.0, new SKPoint(x, H - 50)); }
scene.MouseUp(new SKPoint(420, H - 50));
scene.MouseDown(new SKPoint(W / 2f, 24));
scene.MouseDrag(new SKPoint(900, 400));
scene.MouseUp(new SKPoint(900, 400));
settings.LightStyle = 3;
settings.Changed();
scene.PlowNow();
Run(5.5, new SKPoint(-500, -500));
Save("win-interact.png");

void Save(string name)
{
    var info = new SKImageInfo(W, H, SKColorType.Bgra8888, SKAlphaType.Premul);
    using var surface = SKSurface.Create(info);
    var c = surface.Canvas;
    using (var sky = SKShader.CreateLinearGradient(new SKPoint(0, 0), new SKPoint(0, H),
               new[] { new SKColor(28, 44, 78), new SKColor(10, 16, 32) }, SKShaderTileMode.Clamp))
    using (var p = new SKPaint { Shader = sky }) c.DrawRect(bounds, p);
    using (var p = new SKPaint { Color = new SKColor(32, 32, 40, 235) }) c.DrawRect(new SKRect(0, H - 48, W, H), p);
    foreach (var w in Enumerable.Reverse(windows))
    {
        using var body = new SKPaint { Color = new SKColor(245, 246, 250), IsAntialias = true };
        using var bar = new SKPaint { Color = new SKColor(222, 226, 236), IsAntialias = true };
        c.DrawRoundRect(w.Frame, 8, 8, body);
        c.DrawRect(new SKRect(w.Frame.Left, w.Frame.Top, w.Frame.Right, w.Frame.Top + 32), bar);
    }
    foreach (var r in icons)
    {
        using var p = new SKPaint { Color = new SKColor(90, 170, 240), IsAntialias = true };
        c.DrawRoundRect(new SKRect(r.MidX - 22, r.Top + 4, r.MidX + 22, r.Top + 48), 6, 6, p);
    }
    scene.Draw(c);
    using var img = surface.Snapshot();
    using var data = img.Encode(SKEncodedImageFormat.Png, 100);
    File.WriteAllBytes(Path.Combine(outDir, name), data.ToArray());
    Console.WriteLine("wrote " + name);
}

static void WriteIco(string path, int[] sizes)
{
    var images = sizes.Select(s =>
    {
        using var bmp = Art.AppIcon(s);
        using var img = SKImage.FromBitmap(bmp);
        return img.Encode(SKEncodedImageFormat.Png, 100).ToArray();
    }).ToList();
    using var fs = File.Create(path);
    using var w = new BinaryWriter(fs);
    w.Write((short)0); w.Write((short)1); w.Write((short)sizes.Length);
    int offset = 6 + 16 * sizes.Length;
    for (int i = 0; i < sizes.Length; i++)
    {
        w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
        w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
        w.Write((byte)0); w.Write((byte)0);
        w.Write((short)1); w.Write((short)32);
        w.Write(images[i].Length); w.Write(offset);
        offset += images[i].Length;
    }
    foreach (var img in images) w.Write(img);
    Console.WriteLine("wrote " + path);
}
