# ArzAgent Desktop — آرزایجنت

نرم‌افزار گرافیکی فارسی بازار کریپتو برای Windows و macOS، با قیمت‌های نزدیک به زنده، تحلیل استراتژی‌های بلندمدت/کوتاه‌مدت/نوسان‌گیری، اتصال امن API صرافی، معاملات شبیه‌سازی و **مسیر اجرای اختیاری معاملات واقعی Spot**.

**مهم:** نسخه اولیه پژوهشی است؛ موتور معاملاتی، اتصال واقعی API و فایل‌های ساخته‌شده روی ویندوز/مک هنوز آزمایش کامل End-to-End نشده‌اند. پیش از هر استفاده مالی از حالت Paper استفاده کنید و حتماً کد و محدودیت‌های بخش Live را بررسی کنید. توقف نرم‌افزار، حدود ضرر و سود نرم‌افزاری را نیز از کار می‌اندازد. هیچ بازدهی تضمین نشده است.

راهنمای مرحله‌به‌مرحله فارسی، ساخت خروجی GitHub Actions و جزئیات امنیت و محدودیت‌های واقعی در **[README_FA.md](README_FA.md)** قرار دارد.

- GUI: **PySide6 / Qt**، کاملاً Desktop
- Public/live exchange data and spot APIs: **CCXT**
- Technical signals: **EMA, MACD, RSI, ADX, ATR, volume**
- Modes: **Paper (default)** / **Live (explicit opt-in)**
- GitHub Actions artifacts: **Windows .exe**, **macOS Apple Silicon .dmg**, **macOS Intel .dmg**
- Tests: `python -m pytest -q`

Copyright 2026. MIT License.
