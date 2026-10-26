import pytest

from bilge.core.browser import browser_keys
from bilge.core.browser.browser_command import Back, Bottom, Find, LastTab, NextTab, ReopenTab, Tab, TabNamed
from bilge.core.browser.browser_keys import Family


@pytest.mark.parametrize(
    ("program", "app_class", "expected"),
    [
        ("chrome", "", Family.CHROMIUM),
        ("msedge", "chrome_widgetwin_1", Family.CHROMIUM),
        ("bwrap", "com.brave.Browser", Family.CHROMIUM),
        ("microsoft-edge", "", Family.CHROMIUM),
        ("firefox-esr", "", Family.FIREFOX),
        ("bwrap", "org.mozilla.firefox", Family.FIREFOX),
        ("python3", "navigator", Family.FIREFOX),
        ("gedit", "org.gnome.gedit", None),
        ("explorer", "cabinetwclass", None),
        ("", "", None),
    ],
)
def test_the_browser_in_front_is_recognized_by_program_or_window_class(program, app_class, expected):
    assert browser_keys.family(program, app_class) is expected


def test_commands_map_to_the_browsers_own_shortcuts():
    assert browser_keys.keys(NextTab(), Family.CHROMIUM, linux=False) == ("ctrl", "tab")
    assert browser_keys.keys(ReopenTab(), Family.FIREFOX, linux=True) == ("ctrl", "shift", "t")
    assert browser_keys.keys(Back(), Family.CHROMIUM, linux=True) == ("alt", "left")
    assert browser_keys.keys(Bottom(), Family.FIREFOX, linux=False) == ("end",)
    assert browser_keys.keys(Find("fiyat"), Family.CHROMIUM, linux=False) == ("ctrl", "f")


def test_tab_numbers_use_alt_only_in_firefox_on_linux():
    assert browser_keys.keys(Tab(3), Family.CHROMIUM, linux=True) == ("ctrl", "3")
    assert browser_keys.keys(Tab(3), Family.FIREFOX, linux=False) == ("ctrl", "3")
    assert browser_keys.keys(Tab(3), Family.FIREFOX, linux=True) == ("alt", "3")
    assert browser_keys.keys(LastTab(), Family.CHROMIUM, linux=False) == ("ctrl", "9")


def test_what_no_shortcut_does_has_no_keys():
    # Ctrl+9 is the last tab, not the ninth, and tab titles aren't visible to other programs.
    assert browser_keys.keys(Tab(9), Family.CHROMIUM, linux=False) is None
    assert browser_keys.keys(TabNamed("YouTube"), Family.CHROMIUM, linux=False) is None
