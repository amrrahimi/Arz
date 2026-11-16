# Plowy for Windows ❄️

Windows 10/11 version of Plowy, using the same features and artwork as the macOS version.

- `Core/`: snow simulation and artwork (SkiaSharp); has no Windows dependency
- `App/`: tray menu, transparent always-on-top overlay per screen, window tracking (Win32) and desktop icons (UI Automation)
- `Preview/`: runs the scene headless on any OS and writes PNG frames (`dotnet run --project Preview -- out`)
- `Installer/`: Inno Setup script (per-user install, no admin rights)

GitHub Actions (`.github/workflows/plowy-windows.yml`) builds `Plowy-Setup.exe` and a portable zip and publishes them to the `plowy-latest` release.

Local build on Windows:

```
dotnet publish App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o out/publish
```
