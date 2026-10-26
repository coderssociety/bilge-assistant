import pytest

from bilge.brain.routing import rule
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import FrontWindow
from bilge.desktop.process import DesktopError
from bilge.tools.base import ToolError
from bilge.tools.desktop import browser

from ..brain.test_routing import agent_with

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
CHROME = FrontWindow("chrome", "YouTube - Google Chrome", "chrome_widgetwin_1")
FIREFOX = FrontWindow("firefox", "Mozilla Firefox", "navigator")


class FakeKeyboard:
    def __init__(self, front=CHROME, fails=False):
        self.front = front
        self.fails = fails
        self.events = []

    def front_window(self):
        if isinstance(self.front, Exception):
            raise self.front
        return self.front

    def press(self, *keys):
        if self.fails:
            raise DesktopError("xdotool failed")
        self.events.append(keys)

    def type(self, text):
        self.events.append(("type", text))


def tool(keyboard, language=TR, linux=False):
    return browser.browser_tool(keyboard, language, linux=linux, pause=lambda _: None)


@pytest.mark.parametrize(
    ("command", "keys", "reply"),
    [
        ("sonraki sekmeye geç", ("ctrl", "tab"), "Sonraki sekme."),
        ("yeni sekme aç", ("ctrl", "t"), "Yeni sekme açtım."),
        ("bu sekmeyi kapat", ("ctrl", "w"), "Sekmeyi kapattım."),
        ("geri git", ("alt", "left"), "Geri gittim."),
        ("sayfayı yenile", ("ctrl", "r"), "Sayfayı yeniledim."),
        ("aşağı kaydır", ("page_down",), "Aşağı kaydırdım."),
        ("sayfanın en altına in", ("end",), "Sonuna indim."),
        ("üçüncü sekmeye geç", ("ctrl", "3"), "3. sekme."),
    ],
)
def test_commands_press_the_shortcut_in_the_browser_in_front(command, keys, reply):
    keyboard = FakeKeyboard()
    assert tool(keyboard).run({"command": command}) == reply
    assert keyboard.events == [keys]


def test_find_opens_the_find_bar_types_the_words_and_searches():
    keyboard = FakeKeyboard(FIREFOX)
    assert tool(keyboard, EN, linux=True).run({"command": "find return policy on this page"}) == (
        "Looking for 'return policy' on the page."
    )
    assert keyboard.events == [("ctrl", "f"), ("type", "return policy"), ("return",)]


def test_firefox_on_linux_picks_tabs_with_alt():
    keyboard = FakeKeyboard(FIREFOX)
    tool(keyboard, linux=True).run({"command": "ikinci sekmeye geç"})
    assert keyboard.events == [("alt", "2")]


def test_no_key_is_sent_unless_a_browser_is_known_to_be_in_front():
    for front, message in [(FrontWindow("gedit"), "tarayıcı yok"), (None, "göremiyorum"),
                           (DesktopError("no xdotool"), "göremiyorum")]:  # fmt: skip
        keyboard = FakeKeyboard(front)
        with pytest.raises(ToolError, match=message):
            tool(keyboard).run({"command": "sekmeyi kapat"})
        assert keyboard.events == []


def test_what_shortcuts_cannot_do_is_said_plainly():
    keyboard = FakeKeyboard()
    with pytest.raises(ToolError, match="adıyla geçemiyorum"):
        tool(keyboard).run({"command": "YouTube sekmesine geç"})
    with pytest.raises(ToolError, match="1'den 8'e"):
        tool(keyboard).run({"command": "dokuzuncu sekmeye geç"})
    with pytest.raises(ToolError, match="anlayamadım"):
        tool(keyboard).run({"command": "müziği aç"})
    assert keyboard.events == []


def test_a_failed_key_press_is_reported():
    with pytest.raises(ToolError, match="gönderemedim"):
        tool(FakeKeyboard(fails=True)).run({"command": "geri git"})


def test_the_rule_routes_browser_commands_without_the_model():
    keyboard = FakeKeyboard()
    control = tool(keyboard)
    route = rule("browserControl", lambda c: browser.claims(c, TR), lambda c: {"command": c})
    agent, asked = agent_with([control], rules=[route])
    assert agent.handle("önceki sekmeye dön").text == "Önceki sekme."
    assert keyboard.events == [("ctrl", "shift", "tab")] and asked == []
    assert not browser.claims("bu akşam ne yiyelim", TR)


def test_the_model_s_wording_is_replaced_by_the_words_said():
    refined = tool(FakeKeyboard()).refine({"command": "next tab"}, "sonraki sekmeye geç")
    assert refined == {"command": "sonraki sekmeye geç"}
