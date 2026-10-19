"""Runs on CI with PySide6 installed; skips in lean offline source-review environments."""
import pytest

pytest.importorskip('PySide6')
from PySide6.QtWidgets import QApplication
from arzagent import ui, storage


def test_native_window_builds(monkeypatch, tmp_path):
    monkeypatch.setattr(storage,'DB_PATH',tmp_path/'app.sqlite')
    monkeypatch.setattr(storage,'SETTINGS',tmp_path/'prefs.json')
    monkeypatch.setattr(ui.MarketAgent,'start',lambda self:None)
    app=QApplication.instance() or QApplication([])
    window=ui.MainWindow()
    assert window.tabs.count()==4
    assert window.exec_mode.currentData() == 'paper'
    assert window.search.isEditable()
    assert not window.running
    window.close()
