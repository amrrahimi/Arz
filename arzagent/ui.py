"""Fully native PySide6 desktop interface (not an embedded website)."""
from __future__ import annotations
import time
from datetime import datetime
from PySide6.QtCore import Qt, QThread, Signal as QtSignal, QStringListModel
from PySide6.QtGui import QColor, QFont, QPainter, QPen, QBrush
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QPushButton, QVBoxLayout,
    QHBoxLayout, QGridLayout, QFrame, QComboBox, QTabWidget, QLineEdit,
    QDoubleSpinBox, QTableWidget, QTableWidgetItem, QHeaderView, QMessageBox,
    QCheckBox, QCompleter, QSizePolicy, QAbstractItemView, QTextBrowser,
    QSplitter, QScrollArea
)
from .agent import MarketAgent
from .strategy import PROFILES
from .exchanges import EXCHANGES, FAVORITES, favorites_for, make_exchange, validate_live
from . import storage


STYLES = """
QWidget { background-color:#0c1120; color:#e4ecff; font-family:'Vazirmatn','Segoe UI','Arial'; font-size:13px; }
QMainWindow { background:#0c1120; }
QFrame#Card { background:#151e30; border:1px solid #25334a; border-radius:16px; }
QFrame#SubCard { background:#0f1929; border:1px solid #25344a; border-radius:12px; }
QLabel#AppTitle { font-size:25px; font-weight:800; color:#ffffff; }
QLabel#CardTitle { font-size:15px; font-weight:700; color:#fafbff; }
QLabel#Mute { color:#91a5c1; font-size:12px; }
QLabel#BigPrice { color:#ffffff; font-size:30px; font-weight:800; }
QLabel#Signal { font-size:27px; font-weight:800; }
QPushButton { background:#283850; border:1px solid #3b506d; border-radius:9px; padding:10px 16px; color:#f5f9ff; font-weight:700; }
QPushButton:hover { background:#364966; }
QPushButton:disabled { color:#688098; background:#172235; }
QPushButton#Primary { background:#22b39e; color:#061821; border:0px; }
QPushButton#Primary:hover { background:#36d7b7; }
QPushButton#Danger { background:#bd425b; border:0; color:white; }
QPushButton#Danger:hover { background:#d9516c; }
QLineEdit,QComboBox,QDoubleSpinBox { background:#0b1525; border:1px solid #344563; border-radius:8px; padding:10px; selection-background-color:#22b39e; min-height:18px; }
QLineEdit:focus,QComboBox:focus,QDoubleSpinBox:focus { border-color:#22b39e; }
QComboBox QAbstractItemView { background:#111c30; border:1px solid #314460; color:#edf3ff; selection-background-color:#224e62; }
QTabWidget::pane { border:0; margin-top:10px; }
QTabBar::tab { background:#172238; color:#a5b7d2; padding:12px 26px; margin-left:4px; border-radius:9px; }
QTabBar::tab:selected { background:#245669; color:#fff; }
QTableWidget { background:#111a2a; alternate-background-color:#172238; border:0; border-radius:8px; gridline-color:#24344b; selection-background-color:#21516a; }
QHeaderView::section { background:#19263b; color:#9faec5; border:0; padding:10px; font-weight:bold; }
QTableWidget::item { padding:6px; }
QCheckBox { spacing:11px; }
QTextBrowser { background:#101a2b; border:1px solid #25344a; border-radius:12px; padding:10px; }
QScrollArea { border:0; }
QScrollBar:vertical { background:#172238; width:10px; }
QScrollBar::handle:vertical { background:#37516b; border-radius:5px; min-height:25px; }
"""


def label(text="", name=None, alignment=None):
    w=QLabel(text)
    w.setTextInteractionFlags(Qt.TextSelectableByMouse)
    if name: w.setObjectName(name)
    if alignment is not None: w.setAlignment(alignment)
    w.setWordWrap(True)
    return w


def card(title: str | None = None):
    f=QFrame(); f.setObjectName("Card")
    lay=QVBoxLayout(f); lay.setContentsMargins(20,18,20,18); lay.setSpacing(12)
    if title: lay.addWidget(label(title,"CardTitle"))
    return f,lay


def subcard():
    f=QFrame(); f.setObjectName("SubCard")
    lay=QVBoxLayout(f); lay.setContentsMargins(16,12,16,12)
    return f,lay


def btn(text, obj=None):
    b=QPushButton(text)
    if obj:b.setObjectName(obj)
    b.setCursor(Qt.PointingHandCursor)
    return b


class Sparkline(QWidget):
    def __init__(self):
        super().__init__()
        self.points=[]
        self.setMinimumHeight(170)
    def set_data(self, candles):
        self.points=[float(x[4]) for x in candles[-100:]]
        self.update()
    def paintEvent(self, event):
        p=QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.fillRect(self.rect(), QColor("#101a2a"))
        p.setPen(QPen(QColor("#253449"),1))
        for k in range(1,4):
            y=self.height()*k/4
            p.drawLine(0,int(y),self.width(),int(y))
        a=self.points
        if len(a)<2: return
        low,high=min(a),max(a)
        if high == low: high=low+1
        margin=13
        coords=[]
        for i,value in enumerate(a):
            x=margin+(self.width()-margin*2)*i/(len(a)-1)
            y=margin+(self.height()-margin*2)*(1-(value-low)/(high-low))
            coords.append((x,y))
        pen=QPen(QColor("#27c9ae" if a[-1]>=a[0] else "#f17d8f"),2.6)
        p.setPen(pen)
        from PySide6.QtCore import QPointF
        for i in range(1,len(coords)):
            p.drawLine(QPointF(*coords[i-1]),QPointF(*coords[i]))
        p.setPen(Qt.NoPen)
        p.setBrush(QBrush(pen.color()))
        p.drawEllipse(QPointF(*coords[-1]),4,4)


class CredentialsTest(QThread):
    result=QtSignal(bool,str)
    def __init__(self, exchange_id, auth):
        super().__init__(); self.exchange_id=exchange_id; self.auth=auth
    def run(self):
        try:
            ex=make_exchange(self.exchange_id,self.auth)
            ex.load_markets()
            if not ex.has.get("fetchBalance"):
                raise RuntimeError("صرافی امکان خواندن موجودی را ندارد")
            bal=ex.fetch_balance()
            self.result.emit(True,"ارتباط خصوصی برقرار شد؛ خواندن موجودی موفق بود. اجازه ثبت سفارش هنوز تأیید نشده است.")
        except Exception as error:
            message = str(error)
            for secret in self.auth.values():
                if secret and isinstance(secret, str):
                    message = message.replace(secret, "[REDACTED]")
            self.result.emit(False,f"اتصال برقرار نشد: {type(error).__name__}: {message[:180]}")


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        storage.init_db()
        self.settings=storage.read_settings()
        self.agent=MarketAgent(self)
        self.running=False
        self.latest_prices={}
        self.markets=[]
        self.setWindowTitle("ArzAgent — دستیار تحلیل و معامله ارز دیجیتال")
        self.resize(1300,840)
        self.setMinimumSize(990,650)
        self.setLayoutDirection(Qt.RightToLeft)
        self.setStyleSheet(STYLES)
        root=QWidget(); self.setCentralWidget(root)
        main=QVBoxLayout(root); main.setContentsMargins(24,19,24,16); main.setSpacing(12)
        header=QHBoxLayout()
        headings=QVBoxLayout(); headings.setSpacing(2)
        headings.addWidget(label("ArzAgent   ◈   آرزایجنت", "AppTitle"))
        headings.addWidget(label("ایجنت تحلیل تکنیکال | معاملات اسپات | داده‌های عمومی زنده", "Mute"))
        header.addLayout(headings)
        header.addStretch()
        self.top_status=label("● در حال اتصال به بازار...", "Mute")
        header.addWidget(self.top_status)
        self.mode_pill=label("شبیه‌سازی — پیش‌فرض", "Mute")
        self.mode_pill.setStyleSheet("padding:9px 12px; background:#173644;border-radius:8px;color:#7ce8d2;")
        header.addWidget(self.mode_pill)
        main.addLayout(header)
        self.tabs=QTabWidget(); main.addWidget(self.tabs,1)
        self.make_dashboard()
        self.make_strategy_tab()
        self.make_connection_tab()
        self.make_history_tab()
        self.footer=label("نمایش قیمت‌ها از API صرافی انتخاب‌شده؛ هر ~۱۵ ثانیه تازه‌سازی. هیچ سودی تضمین نمی‌شود.","Mute")
        main.addWidget(self.footer)
        self.agent.prices.connect(self.on_prices)
        self.agent.markets_ready.connect(self.on_markets)
        self.agent.analysis_ready.connect(self.on_analysis)
        self.agent.history_ready.connect(self.sparkline.set_data)
        self.agent.status.connect(lambda msg:self.top_status.setText("● "+msg))
        self.agent.notice.connect(self.on_notice)
        self.agent.trade.connect(self.on_trade)
        self.agent.backtest_ready.connect(self.on_backtest)
        self.agent.configure(exchange=self.settings["exchange"],symbol=self.settings["symbol"],
                             profile=self.settings["profile"], budget=self.settings["quote_per_trade"],
                             max_daily_loss=self.settings["max_daily_loss"],
                             max_spread_pct=self.settings["max_spread_pct"])
        self.load_logs()
        self.agent.start()

    def make_dashboard(self):
        tab=QWidget(); self.tabs.addTab(tab,"داشبورد زنده")
        outer=QHBoxLayout(tab); outer.setSpacing(16)
        right,rl=card("نمای کلی بازار")
        right.setMinimumWidth(390)
        choose=QHBoxLayout()
        self.exchange_info=label("صرافی: —","Mute")
        choose.addWidget(self.exchange_info)
        choose.addStretch()
        self.search=QComboBox(); self.search.setEditable(True); self.search.setMinimumWidth(175)
        self.search.setInsertPolicy(QComboBox.NoInsert)
        self.search.lineEdit().setPlaceholderText("جستجوی رمز ارز...")
        self.search.lineEdit().setLayoutDirection(Qt.LeftToRight)
        self.search.setLayoutDirection(Qt.LeftToRight)
        choose.addWidget(self.search)
        rl.addLayout(choose)
        self.price=label("—", "BigPrice")
        self.price.setLayoutDirection(Qt.LeftToRight)
        rl.addWidget(self.price)
        self.change=label("در انتظار قیمت زنده...", "Mute")
        rl.addWidget(self.change)
        self.sparkline=Sparkline()
        rl.addWidget(self.sparkline)
        metrics=QGridLayout(); metrics.setSpacing(12)
        self.m_signal=label("—", "Signal")
        self.m_signal.setStyleSheet("color:#e5bb7a")
        self.m_score=label("—", "CardTitle")
        self.m_rsi=label("—", "CardTitle")
        self.m_adx=label("—", "CardTitle")
        self.m_atr=label("—", "CardTitle")
        self.m_regime=label("—", "CardTitle")
        items=[("سیگنال",self.m_signal),("امتیاز هم‌جهتی",self.m_score),("RSI",self.m_rsi),
               ("ADX",self.m_adx),("ATR ٪",self.m_atr),("وضعیت بازار",self.m_regime)]
        for i,(name,value) in enumerate(items):
            box,bl=subcard(); bl.addWidget(label(name,"Mute")); bl.addWidget(value)
            metrics.addWidget(box,i//2,i%2)
        rl.addLayout(metrics)
        self.reason=label("تحلیل پس از دریافت کندل‌های تکمیل‌شده ظاهر می‌شود.","Mute")
        rl.addWidget(self.reason)
        rl.addStretch()
        outer.addWidget(right,3)
        left,ll=card("ارزهای محبوب و قابل جستجو")
        self.watch=QTableWidget(0,3)
        self.watch.setHorizontalHeaderLabels(["بازار","قیمت","تغییر ۲۴ساعته"])
        self.watch.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.watch.verticalHeader().setVisible(False)
        self.watch.setAlternatingRowColors(True)
        self.watch.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.watch.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.watch.cellClicked.connect(self.on_watch_click)
        ll.addWidget(self.watch)
        hint=label("برای انتخاب، روی یک ردیف کلیک کنید؛ یا نام ارز را بالای صفحه جستجو کنید.","Mute")
        ll.addWidget(hint)
        self.watch_assets=[]
        outer.addWidget(left,2)
        self.search.currentTextChanged.connect(self.set_symbol)

    def make_strategy_tab(self):
        tab=QWidget(); self.tabs.addTab(tab,"استراتژی و ربات")
        layout=QHBoxLayout(tab); layout.setSpacing(17)
        config,cl=card("تنظیم استراتژی")
        cl.addWidget(label("افق سرمایه‌گذاری", "Mute"))
        self.profile_combo=QComboBox()
        for key,txt in (("long","بلندمدت — کندل روزانه"),("swing","کوتاه‌مدت — کندل یک‌ساعته"),
                        ("scalp","نوسان‌گیری — کندل پنج‌دقیقه‌ای")):
            self.profile_combo.addItem(txt,key)
        self.profile_combo.setCurrentIndex(max(0,self.profile_combo.findData(self.settings["profile"])))
        self.profile_combo.currentIndexChanged.connect(self.profile_changed)
        cl.addWidget(self.profile_combo)
        self.profile_detail=label("", "Mute")
        cl.addWidget(self.profile_detail)
        cl.addWidget(label("بودجه هر خرید (بر مبنای ارز دوم جفت‌ارز)", "Mute"))
        self.budget=QDoubleSpinBox(); self.budget.setRange(10,100000); self.budget.setDecimals(2)
        self.budget.setValue(float(self.settings["quote_per_trade"])); cl.addWidget(self.budget)
        cl.addWidget(label("حداکثر زیان تحقق‌یافته طی ۲۴ ساعت (به ارز دوم؛ فقط خرید جدید را محدود می‌کند)","Mute"))
        self.max_loss=QDoubleSpinBox(); self.max_loss.setRange(1,100000); self.max_loss.setValue(float(self.settings["max_daily_loss"]))
        cl.addWidget(self.max_loss)
        cl.addWidget(label("حداکثر اسپرد مجاز برای خرید واقعی (%)", "Mute"))
        self.max_spread=QDoubleSpinBox(); self.max_spread.setRange(.01,5); self.max_spread.setDecimals(2); self.max_spread.setSingleStep(.05)
        self.max_spread.setValue(float(self.settings["max_spread_pct"])); cl.addWidget(self.max_spread)
        self.bt_button=btn("↻ بک‌تست تاریخی (آزمایشی)")
        self.bt_button.clicked.connect(self.backtest_click)
        cl.addWidget(self.bt_button)
        self.bt_result=label("بک‌تست اجرا نشده است.","Mute")
        cl.addWidget(self.bt_result)
        cl.addStretch()
        layout.addWidget(config,3)
        run,rl=card("کنترل اجرای ایجنت")
        rl.addWidget(label("انتخاب شیوه اجرا", "Mute"))
        self.exec_mode=QComboBox()
        self.exec_mode.addItem("● شبیه‌سازی — بدون نیاز به کلید API", "paper")
        self.exec_mode.addItem("● معاملات واقعی — با دسترسی صرافی", "live")
        self.exec_mode.currentIndexChanged.connect(self.mode_changed)
        rl.addWidget(self.exec_mode)
        message,ml=subcard()
        ml.addWidget(label("نحوه کار", "CardTitle"))
        ml.addWidget(label("قیمت و کندل‌ها از صرافی دریافت می‌شوند. الگوریتم فقط بعد از بسته‌شدن کندل تصمیم می‌گیرد. سفارش‌ها فقط از نوع بازار اسپات هستند و معاملات اهرمی یا فروش استقراضی انجام نمی‌شود.","Mute"))
        ml.addWidget(label("حد ضرر و حد سود نرم‌افزاری‌اند: فقط تا زمانی کار می‌کنند که برنامه باز و متصل باشد.","Mute"))
        rl.addWidget(message)
        self.risk_ok=QCheckBox("ریسک معامله واقعی، احتمال لغزش قیمت و امکان زیان را می‌پذیرم.")
        self.risk_ok.setToolTip("تأیید آگاهانه برای معاملات واقعی")
        self.risk_ok.setVisible(False)
        rl.addWidget(self.risk_ok)
        self.start_button=btn("▶ شروع ایجنت", "Primary")
        self.start_button.clicked.connect(self.start_bot)
        rl.addWidget(self.start_button)
        self.stop_button=btn("■ توقف فوری ارسال سفارش", "Danger")
        self.stop_button.clicked.connect(self.stop_bot)
        self.stop_button.setEnabled(False)
        rl.addWidget(self.stop_button)
        self.bot_status=label("ربات خاموش است؛ صرفاً تحلیل و قیمت زنده نمایش داده می‌شود.","Mute")
        rl.addWidget(self.bot_status)
        rl.addStretch()
        layout.addWidget(run,2)
        self.profile_changed()

    def make_connection_tab(self):
        tab=QWidget(); self.tabs.addTab(tab,"اتصال به صرافی")
        layout=QVBoxLayout(tab)
        connect,cl=card("اتصال امن به API صرافی")
        self.exchange_combo=QComboBox()
        for eid,name in EXCHANGES.items(): self.exchange_combo.addItem(name, eid)
        self.exchange_combo.setCurrentIndex(max(0,self.exchange_combo.findData(self.settings["exchange"])))
        self.exchange_combo.currentIndexChanged.connect(self.exchange_changed)
        cl.addWidget(label("صرافی (پشتیبانی از معاملات Spot)","Mute"))
        cl.addWidget(self.exchange_combo)
        grid=QGridLayout()
        self.api_key=QLineEdit(); self.api_key.setPlaceholderText("API Key")
        self.api_secret=QLineEdit(); self.api_secret.setEchoMode(QLineEdit.Password); self.api_secret.setPlaceholderText("API Secret")
        self.api_pass=QLineEdit(); self.api_pass.setEchoMode(QLineEdit.Password); self.api_pass.setPlaceholderText("API Passphrase — در صورت نیاز")
        for w in (self.api_key,self.api_secret,self.api_pass):w.setLayoutDirection(Qt.LeftToRight)
        grid.addWidget(label("API Key", "Mute"),0,0); grid.addWidget(self.api_key,1,0)
        grid.addWidget(label("API Secret", "Mute"),0,1);grid.addWidget(self.api_secret,1,1)
        grid.addWidget(label("Passphrase (اختیاری)","Mute"),2,0);grid.addWidget(self.api_pass,3,0,1,2)
        cl.addLayout(grid)
        controls=QHBoxLayout()
        self.save_api=btn("ذخیره امن و آزمایش اتصال", "Primary")
        self.save_api.clicked.connect(self.save_credentials)
        controls.addWidget(self.save_api)
        self.delete_api=btn("حذف کلید ذخیره‌شده", "Danger")
        self.delete_api.clicked.connect(self.delete_credentials)
        controls.addWidget(self.delete_api)
        controls.addStretch()
        cl.addLayout(controls)
        self.credential_state=label("", "Mute")
        cl.addWidget(self.credential_state)
        layout.addWidget(connect)
        info,il=card("راهنمای امنیت و سازگاری")
        il.addWidget(label("۱) کلید API را در پنل رسمی صرافی بسازید؛ فقط مجوز مشاهده موجودی و معامله Spot را فعال کنید. مجوز برداشت (Withdrawal) را هرگز فعال نکنید.","Mute"))
        il.addWidget(label("۲) کلیدها در Keychain مک یا Credential Manager ویندوز ذخیره می‌شوند، نه در فایل تنظیمات و نه در GitHub. هر صرافی می‌تواند به احراز هویت یا Passphrase جداگانه نیاز داشته باشد.","Mute"))
        il.addWidget(label("۳) دسترسی جغرافیایی، حداقل سفارش، نوع Market Buy و محدودیت‌های هر صرافی یکسان نیست. اتصال آزمایشی فقط اعتبار کلید و خواندن موجودی را بررسی می‌کند.","Mute"))
        il.addWidget(label("۴) این برنامه API دلخواه/ناشناخته را به دلیل خطر سرقت کلید نمی‌پذیرد؛ تنها API رسمی صرافی‌های لیست‌شده از طریق CCXT استفاده می‌شود.","Mute"))
        layout.addWidget(info)
        layout.addStretch()
        self.refresh_creds_state()

    def make_history_tab(self):
        tab=QWidget(); self.tabs.addTab(tab,"سوابق و راهنما")
        layout=QVBoxLayout(tab)
        history,hl=card("سفارش‌های ثبت‌شده توسط ربات")
        self.trade_history=QTableWidget(0,7)
        self.trade_history.setHorizontalHeaderLabels(["زمان","حالت","بازار","سمت","مقدار","قیمت","سود/زیان"])
        self.trade_history.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.trade_history.verticalHeader().setVisible(False)
        self.trade_history.setEditTriggers(QAbstractItemView.NoEditTriggers)
        hl.addWidget(self.trade_history)
        layout.addWidget(history,3)
        events,el=card("گزارش رویدادها / خطاها")
        self.event_history=QTableWidget(0,3)
        self.event_history.setHorizontalHeaderLabels(["زمان","سطح","رویداد"])
        self.event_history.horizontalHeader().setSectionResizeMode(2,QHeaderView.Stretch)
        self.event_history.horizontalHeader().setSectionResizeMode(0,QHeaderView.ResizeToContents)
        self.event_history.horizontalHeader().setSectionResizeMode(1,QHeaderView.ResizeToContents)
        self.event_history.verticalHeader().setVisible(False)
        self.event_history.setEditTriggers(QAbstractItemView.NoEditTriggers)
        el.addWidget(self.event_history)
        reload=btn("↻ بازخوانی سوابق")
        reload.clicked.connect(self.load_logs)
        el.addWidget(reload)
        layout.addWidget(events,2)

    def profile_changed(self):
        name=self.profile_combo.currentData()
        self.profile_detail.setText({
            "long":"EMA 50/200 + MACD + RSI + ADX • کندل روزانه • حد ضرر ATR × ۳٫۲",
            "swing":"EMA 20/50 + MACD + RSI + ADX • کندل یک‌ساعته • حد ضرر ATR × ۲٫۴",
            "scalp":"EMA 9/21 + حجم + MACD + RSI + ADX • کندل ۵ دقیقه • حد ضرر ATR × ۱٫۷",
        }[name])
        if hasattr(self,"agent"):
            if self.running:self.stop_bot()
            self.agent.configure(profile=name)
            self.settings["profile"]=name;storage.save_settings(self.settings)

    def mode_changed(self):
        if self.running:self.stop_bot()
        is_live=self.exec_mode.currentData()=="live"
        self.risk_ok.setVisible(is_live)
        if is_live:self.tabs.setTabText(2,"اتصال به صرافی ⚑")
        else:self.tabs.setTabText(2,"اتصال به صرافی")
        self.mode_pill.setText("معامله واقعی — خاموش" if is_live else "شبیه‌سازی — پیش‌فرض")

    def exchange_changed(self):
        if self.running:self.stop_bot()
        eid=self.exchange_combo.currentData()
        self.settings["exchange"]=eid; storage.save_settings(self.settings)
        self.agent.configure(exchange=eid)
        self.exchange_info.setText("صرافی: "+EXCHANGES[eid])
        self.api_key.clear();self.api_secret.clear();self.api_pass.clear()
        self.refresh_creds_state()

    def refresh_creds_state(self):
        eid=self.exchange_combo.currentData()
        try:
            exists=storage.credentials_get(eid) is not None
            self.credential_state.setText("🔐 کلید این صرافی در محل امن سیستم موجود است." if exists else "🔐 کلیدی برای این صرافی ذخیره نشده؛ مشاهده داده عمومی بدون کلید فعال است.")
        except Exception as e:
            self.credential_state.setText("محل ذخیره امن کلید سیستم در دسترس نیست: "+str(e)[:120])

    def save_credentials(self):
        if self.running:self.stop_bot()
        eid=self.exchange_combo.currentData()
        key,secret,password=self.api_key.text(),self.api_secret.text(),self.api_pass.text()
        if not key or not secret:
            QMessageBox.warning(self,"کلید ناقص","API Key و Secret را وارد کنید.")
            return
        try:
            storage.credentials_set(eid,key,secret,password)
        except Exception as error:
            QMessageBox.critical(self,"ذخیره‌سازی امن ناموفق",f"کلید ذخیره نشد؛ از ذخیره متن ساده استفاده نمی‌کنیم.\n{error}")
            return
        self.api_key.clear();self.api_secret.clear();self.api_pass.clear()
        self.refresh_creds_state()
        self.credential_state.setText("کلید در Keychain/Credential Manager ذخیره شد؛ در حال آزمون خواندن موجودی...")
        self.save_api.setEnabled(False)
        self.tester=CredentialsTest(eid,{"key":key,"secret":secret,"password":password})
        self.tester.result.connect(self.on_credential_test)
        self.tester.finished.connect(lambda:self.save_api.setEnabled(True))
        self.tester.start()

    def on_credential_test(self, ok, message):
        self.credential_state.setText(("✓ " if ok else "⚠ ")+message)
        storage.log(message,"INFO" if ok else "WARN")

    def delete_credentials(self):
        if self.running:self.stop_bot()
        if QMessageBox.question(self,"حذف کلید API","کلید ذخیره‌شده همین صرافی از سیستم حذف شود؟") != QMessageBox.Yes:
            return
        try:
            storage.credentials_delete(self.exchange_combo.currentData())
            self.refresh_creds_state()
        except Exception as error:
            QMessageBox.warning(self,"خطا",str(error))

    def on_markets(self,symbols):
        self.markets=symbols
        self.search.blockSignals(True)
        selected=self.settings.get("symbol","BTC/USDT")
        self.search.clear()
        self.search.addItems(symbols)
        if selected not in symbols:
            picks=favorites_for(symbols)
            selected=picks[0] if picks else (symbols[0] if symbols else "")
        self.search.setCurrentText(selected)
        self.search.blockSignals(False)
        self.set_symbol(selected)
        complete=QCompleter(symbols,self)
        complete.setCaseSensitivity(Qt.CaseInsensitive)
        complete.setFilterMode(Qt.MatchContains)
        complete.setCompletionMode(QCompleter.PopupCompletion)
        self.search.setCompleter(complete)
        self.watch_assets=favorites_for(symbols)
        self.watch.setRowCount(len(self.watch_assets))
        for i,s in enumerate(self.watch_assets):
            self.watch.setItem(i,0,QTableWidgetItem(s))
            self.watch.setItem(i,1,QTableWidgetItem("—"))
            self.watch.setItem(i,2,QTableWidgetItem("—"))
        self.exchange_info.setText("صرافی: "+EXCHANGES[self.settings["exchange"]])

    def set_symbol(self,symbol):
        if symbol not in self.markets:return
        if self.running:self.stop_bot()
        self.settings["symbol"]=symbol;storage.save_settings(self.settings)
        self.agent.configure(symbol=symbol)
        self.price.setText("—")
        self.sparkline.set_data([])
        self.reason.setText(f"در حال دریافت تحلیل {symbol} ...")

    def on_watch_click(self,row,col):
        if 0<=row<len(self.watch_assets):
            self.search.setCurrentText(self.watch_assets[row])

    def on_prices(self,priced):
        self.latest_prices.update(priced)
        selected=self.settings["symbol"]
        if selected in priced:
            tick=priced[selected]
            px=tick["price"]
            self.price.setText(f"{px:,.8g}  {selected.split('/')[-1]}")
            change=tick["change"]
            self.change.setText(f"تغییر ۲۴ ساعت: {change:+.2f}%  •  بروزرسانی {datetime.now():%H:%M:%S}")
            self.change.setStyleSheet("color:"+("#65ddb2" if change>=0 else "#ef8c9b"))
        for i,s in enumerate(self.watch_assets):
            tick=self.latest_prices.get(s)
            if not tick: continue
            self.watch.item(i,1).setText(f"{tick['price']:,.8g}")
            val=f"{tick['change']:+.2f}%"
            item=self.watch.item(i,2)
            item.setText(val)
            item.setForeground(QColor("#65ddb2" if tick["change"]>=0 else "#ef8c9b"))

    def on_analysis(self,info):
        status={"BUY":"خرید پیشنهادی", "SELL":"فروش پیشنهادی", "HOLD":"انتظار"}[info["action"]]
        self.m_signal.setText(status)
        self.m_signal.setStyleSheet("color:"+{"BUY":"#51d9b6","SELL":"#f08091","HOLD":"#dfc287"}[info["action"]])
        self.m_score.setText(f"{info['score']}/100")
        self.m_rsi.setText(f"{info['rsi']:.1f}")
        self.m_adx.setText(f"{info['adx']:.1f}")
        self.m_atr.setText(f"{info['atr_percent']:.2f}%")
        self.m_regime.setText(info["regime"])
        self.reason.setText(f"{info['reason']}\nسیگنال کندل بسته‌شده {info['tf']}؛ امتیاز، احتمال موفقیت نیست.")
        self.bot_status.setText("ایجنت فعال: بررسی کندل‌ها و کنترل ریسک" if self.running else "ایجنت خاموش؛ تحلیل عمومی فعال است.")

    def start_bot(self):
        if self.running:return
        if self.search.currentText() not in self.markets:
            QMessageBox.warning(self,"بازار نامعتبر","یک بازار معتبر از فهرست انتخاب کنید.")
            return
        mode=self.exec_mode.currentData()
        if mode=="live":
            if not self.risk_ok.isChecked():
                QMessageBox.warning(self,"تأیید ریسک","ابتدا پذیرش ریسک معاملات واقعی را فعال کنید.")
                return
            eid=self.exchange_combo.currentData()
            try:auth=storage.credentials_get(eid)
            except Exception as e:
                QMessageBox.warning(self,"Keychain",str(e));return
            if not auth:
                QMessageBox.warning(self,"کلید API","در زبانه اتصال به صرافی، API را ذخیره و آزمایش کنید.")
                self.tabs.setCurrentIndex(2);return
            account=__import__("arzagent.exchanges",fromlist=["account_name"]).account_name(eid,auth,"live")
            if storage.has_pending(account,"live"):
                QMessageBox.critical(self,"سفارش نامشخص","سفارش زنده بلاتکلیف ثبت شده است. برای جلوگیری از سفارش تکراری، اجرای واقعی قفل است. ابتدا سفارش/موجودی را در صرافی تطبیق دهید و از نسخه دارای فرایند بازیابی استفاده کنید.")
                return
            result=QMessageBox.warning(self,"تأیید نهایی معامله واقعی",
                "با شروع، نرم‌افزار می‌تواند بدون سؤال مجدد سفارش Market واقعی Spot بفرستد.\n\n"
                "حد ضرر/سود نرم‌افزاری است؛ هنگام قطع اینترنت یا بستن برنامه اجرا نمی‌شود. "
                "در بازار پرنوسان، اسلیپیج و زیان بیشتر از محدودیت تخمینی ممکن است.\n\nآیا آغاز معاملات واقعی را تأیید می‌کنید؟",
                QMessageBox.Yes|QMessageBox.No,QMessageBox.No)
            if result!=QMessageBox.Yes:return
        self.settings["quote_per_trade"]=self.budget.value()
        self.settings["max_daily_loss"]=self.max_loss.value()
        self.settings["max_spread_pct"]=self.max_spread.value()
        storage.save_settings(self.settings)
        self.agent.configure(active=True,mode=mode,exchange=self.settings["exchange"],
                             symbol=self.settings["symbol"],profile=self.settings["profile"],
                             budget=self.budget.value(),max_daily_loss=self.max_loss.value(),
                             max_spread_pct=self.max_spread.value())
        self.running=True
        self.start_button.setEnabled(False)
        self.stop_button.setEnabled(True)
        for control in (self.budget,self.max_loss,self.max_spread):control.setEnabled(False)
        self.search.setEnabled(False)
        self.exchange_combo.setEnabled(False)
        self.profile_combo.setEnabled(False)
        self.exec_mode.setEnabled(False)
        self.mode_pill.setText("● معاملات واقعی فعال" if mode=="live" else "● حالت آزمایشی فعال")
        self.mode_pill.setStyleSheet("padding:9px 12px; background:"+("#593340;color:#fff0f2;" if mode=="live" else "#173644;color:#7ce8d2;")+"border-radius:8px;")
        self.bot_status.setText("در حال انتظار برای تحلیل و بررسی سفارش...")

    def stop_bot(self):
        if not self.running:return
        self.agent.configure(active=False)
        self.running=False
        self.start_button.setEnabled(True)
        self.stop_button.setEnabled(False)
        for control in (self.budget,self.max_loss,self.max_spread):control.setEnabled(True)
        self.search.setEnabled(True)
        self.exchange_combo.setEnabled(True)
        self.profile_combo.setEnabled(True)
        self.exec_mode.setEnabled(True)
        self.mode_pill.setText("● ربات متوقف است")
        self.bot_status.setText("ربات متوقف است؛ قیمت‌ و تحلیل عمومی همچنان دریافت می‌شود.")

    def on_notice(self,severity,msg):
        self.footer.setText(("⚠ " if severity in ("error","halt","warn") else "● ")+msg)
        if severity in ("error","halt"):
            if self.running and self.exec_mode.currentData()=="live":self.stop_bot()
        self.load_logs()

    def on_trade(self,msg):
        self.footer.setText("✓ "+msg)
        self.load_logs()

    def backtest_click(self):
        self.bt_result.setText("در حال محاسبه روی داده‌های تاریخی صرافی...")
        self.agent.backtest_request()

    def on_backtest(self,report):
        self.bt_result.setText(
            f"بازده نمونه: {report['return_pct']:+.2f}% | افت سرمایه: {report['max_dd_pct']:.2f}%\n"
            f"معاملات بسته‌شده: {report['round_trips']} | درصد برد: {report['win_pct']:.1f}%\n"
            f"{report['candles']} کندل، هزینه فرضی {report['cost_assumption']*100:.2f}% در هر سمت؛ "
            "نتایج گذشته پیش‌بینی آینده نیست و بک‌تست معادل اجرای واقعی نیست.")

    def load_logs(self):
        if not hasattr(self,"trade_history"):return
        fills=storage.latest_fills()
        self.trade_history.setRowCount(len(fills))
        for i,r in enumerate(fills):
            ts,mode,symbol,side,qty,px,pnl=r
            values=[datetime.fromtimestamp(ts).strftime("%m/%d %H:%M"),mode,symbol,side,
                    f"{qty:.7g}",f"{px:,.8g}",f"{pnl:+.2f}"]
            for j,val in enumerate(values):
                item=QTableWidgetItem(val);item.setTextAlignment(Qt.AlignCenter)
                if j==6:item.setForeground(QColor("#65ddb2" if pnl>=0 else "#ef8c9b"))
                self.trade_history.setItem(i,j,item)
        events=storage.events()
        self.event_history.setRowCount(len(events))
        for i,(ts,sev,msg) in enumerate(events):
            for j,val in enumerate([datetime.fromtimestamp(ts).strftime("%m/%d %H:%M"),sev,msg]):
                self.event_history.setItem(i,j,QTableWidgetItem(val))

    def closeEvent(self,event):
        if self.running and self.exec_mode.currentData()=="live":
            answer=QMessageBox.warning(self,"بستن برنامه هنگام معامله واقعی",
                "پس از بستن برنامه، حد ضرر نرم‌افزاری و پایش خودکار دیگر اجرا نمی‌شود. ربات را متوقف و برنامه را ببندم؟",
                QMessageBox.Yes|QMessageBox.No,QMessageBox.No)
            if answer!=QMessageBox.Yes:
                event.ignore();return
        self.agent.configure(active=False)
        self.agent.stop()
        if not self.agent.wait(16000):
            QMessageBox.warning(self,"درخواست شبکه در جریان است",
                "اتصال فعلی هنوز پایان نیافته است. ممکن است سفارش در جریان باشد؛ پیش از بستن، وضعیت صرافی را بررسی کنید.")
            event.ignore();return
        if hasattr(self,"tester") and self.tester.isRunning():
            if not self.tester.wait(28000):
                QMessageBox.warning(self,"تست اتصال در جریان است","پس از پایان بررسی اتصال، برنامه را ببندید.")
                event.ignore(); return
        event.accept()


def launch():
    app=QApplication([])
    app.setApplicationName("ArzAgent")
    app.setOrganizationName("ArzAgent")
    window=MainWindow()
    window.show()
    return app.exec()
