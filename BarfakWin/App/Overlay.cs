using SkiaSharp;

namespace Barfak.App;

/// A transparent, always-on-top, click-through layered window covering one
/// screen. The scene is drawn with Skia straight into a DIB section and pushed
/// with UpdateLayeredWindow, which keeps per-pixel alpha.
internal sealed class Overlay : Form
{
    public readonly Scene Scene;
    private readonly Rectangle bounds;
    private IntPtr memDC, dib, bits;
    private SKSurface? surface;
    private bool passThrough = true;
    private bool dragging;

    public Overlay(Screen screen, float scale, BarfakSettings settings)
    {
        bounds = screen.Bounds;
        var b = new SKRect(bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        var w = screen.WorkingArea;
        Scene = new Scene(b, new SKRect(w.Left, w.Top, w.Right, w.Bottom), scale, screen.Primary, settings);

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        TopMost = true;
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= Native.WS_EX_LAYERED | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOOLWINDOW
                          | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOPMOST;
            return cp;
        }
    }

    protected override bool ShowWithoutActivation => true;

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        CreateBuffer();
    }

    private void CreateBuffer()
    {
        var header = new Native.BITMAPINFOHEADER
        {
            biSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.BITMAPINFOHEADER>(),
            biWidth = bounds.Width,
            biHeight = -bounds.Height,   // top-down rows
            biPlanes = 1,
            biBitCount = 32,
        };
        IntPtr screenDC = Native.GetDC(IntPtr.Zero);
        memDC = Native.CreateCompatibleDC(screenDC);
        dib = Native.CreateDIBSection(screenDC, ref header, 0, out bits, IntPtr.Zero, 0);
        Native.SelectObject(memDC, dib);
        Native.ReleaseDC(IntPtr.Zero, screenDC);
        var info = new SKImageInfo(bounds.Width, bounds.Height, SKColorType.Bgra8888, SKAlphaType.Premul);
        surface = SKSurface.Create(info, bits, bounds.Width * 4);
    }

    public void Render()
    {
        if (surface == null || !IsHandleCreated) return;
        var c = surface.Canvas;
        c.Clear(SKColors.Transparent);
        Scene.Draw(c);
        c.Flush();

        var dst = new Native.POINT { X = bounds.Left, Y = bounds.Top };
        var size = new Native.SIZE { Cx = bounds.Width, Cy = bounds.Height };
        var src = new Native.POINT();
        var blend = new Native.BLENDFUNCTION
        {
            BlendOp = Native.AC_SRC_OVER, SourceConstantAlpha = 255, AlphaFormat = Native.AC_SRC_ALPHA,
        };
        IntPtr screenDC = Native.GetDC(IntPtr.Zero);
        Native.UpdateLayeredWindow(Handle, screenDC, ref dst, ref size, memDC, ref src, 0, ref blend, Native.ULW_ALPHA);
        Native.ReleaseDC(IntPtr.Zero, screenDC);
    }

    /// Takes clicks only over things that can be grabbed; elsewhere they pass through.
    public void UpdateHitTest(SKPoint cursor)
    {
        bool want = dragging || Scene.WantsMouse(cursor);
        if (want == !passThrough || !IsHandleCreated) return;
        passThrough = !want;
        int ex = Native.GetWindowLong(Handle, Native.GWL_EXSTYLE);
        ex = want ? ex & ~Native.WS_EX_TRANSPARENT : ex | Native.WS_EX_TRANSPARENT;
        Native.SetWindowLong(Handle, Native.GWL_EXSTYLE, ex);
    }

    private static SKPoint CursorPos()
    {
        Native.GetCursorPos(out var p);
        return new SKPoint(p.X, p.Y);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        dragging = true;
        Capture = true;
        Scene.MouseDown(CursorPos());
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (dragging) Scene.MouseDrag(CursorPos());
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (!dragging) return;
        dragging = false;
        Capture = false;
        Scene.MouseUp(CursorPos());
    }

    protected override void Dispose(bool disposing)
    {
        surface?.Dispose();
        surface = null;
        if (dib != IntPtr.Zero) Native.DeleteObject(dib);
        if (memDC != IntPtr.Zero) Native.DeleteDC(memDC);
        dib = memDC = IntPtr.Zero;
        base.Dispose(disposing);
    }
}
