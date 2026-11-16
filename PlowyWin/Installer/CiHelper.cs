// CI helper used by the workflow: screenshots (including layered windows)
// and simulated mouse drags.
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

public static class CiHelper
{
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, int rop);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(int flags, int dx, int dy, int data, IntPtr extra);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    public static void Shot(string path)
    {
        SetProcessDPIAware();
        int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppRgb))
        {
            using (var g = Graphics.FromImage(bmp))
            {
                IntPtr dst = g.GetHdc(), src = GetDC(IntPtr.Zero);
                BitBlt(dst, 0, 0, w, h, src, 0, 0, 0x00CC0020 | 0x40000000);   // SRCCOPY | CAPTUREBLT
                ReleaseDC(IntPtr.Zero, src);
                g.ReleaseHdc(dst);
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    public static void Drag(int x1, int y1, int x2, int y2)
    {
        SetProcessDPIAware();
        SetCursorPos(x1, y1);
        Thread.Sleep(400);
        mouse_event(0x02, 0, 0, 0, IntPtr.Zero);   // left down
        Thread.Sleep(60);
        for (int i = 1; i <= 40; i++)
        {
            SetCursorPos(x1 + (x2 - x1) * i / 40, y1 + (y2 - y1) * i / 40);
            Thread.Sleep(25);
        }
        mouse_event(0x04, 0, 0, 0, IntPtr.Zero);   // left up
        Thread.Sleep(200);
    }
}
