"""Screenshots through the xdg-desktop-portal, for Wayland desktops whose own screenshot program isn't installed
(GNOME stopped shipping gnome-screenshot). The portal saves the picture itself and answers with its address.

Like every portal request, the answer comes later as a Response signal on a path built from a token Bilge chooses,
so the signal is subscribed to before the request is sent (see bilge.desktop.hotkey.portal).
"""

import contextlib
import secrets
from pathlib import Path
from urllib.parse import unquote, urlparse

from bilge.desktop.process import DesktopError

PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENSHOT = "org.freedesktop.portal.Screenshot"
CALL_SECONDS = 10
# An interactive screenshot waits on the user choosing an area or a window.
ANSWER_SECONDS = 120
_CANCELLED = 1


class PortalUnavailable(DesktopError):
    """No portal answers, or it has no screenshot interface."""


def screenshot_file(code: int, results: dict) -> Path | None:
    """The saved picture from a Response; None when the user cancelled."""
    if code == _CANCELLED:
        return None
    if code != 0:
        raise DesktopError(f"The screenshot portal answered {code}")
    uri = results.get("uri", ("s", ""))[1]
    parsed = urlparse(str(uri))
    if parsed.scheme != "file" or not parsed.path:
        raise DesktopError(f"The screenshot portal gave no file: {uri!r}")
    return Path(unquote(parsed.path))


class PortalScreenshot:
    def take(self, interactive: bool) -> Path | None:
        """`interactive` lets the user pick an area or a window in the desktop's own dialog."""
        try:
            from jeepney import DBusAddress, MatchRule, new_method_call
            from jeepney.bus_messages import message_bus
            from jeepney.io.blocking import open_dbus_connection
            from jeepney.wrappers import DBusErrorResponse, unwrap_msg
        except ImportError as error:
            raise PortalUnavailable("jeepney is missing") from error
        try:
            connection = open_dbus_connection(bus="SESSION")
        except (OSError, KeyError) as error:
            raise PortalUnavailable(f"No session D-Bus: {error}") from error
        try:
            token = f"bilge{secrets.token_hex(6)}"
            sender = connection.unique_name.lstrip(":").replace(".", "_")
            rule = MatchRule(type="signal", interface="org.freedesktop.portal.Request", member="Response",
                             path=f"{PORTAL_PATH}/request/{sender}/{token}")  # fmt: skip
            connection.send_and_get_reply(message_bus.AddMatch(rule), timeout=CALL_SECONDS)
            address = DBusAddress(PORTAL_PATH, bus_name=PORTAL_NAME, interface=SCREENSHOT)
            options = {"handle_token": ("s", token), "interactive": ("b", interactive), "modal": ("b", True)}
            with connection.filter(rule) as queue:
                try:
                    unwrap_msg(connection.send_and_get_reply(new_method_call(address, "Screenshot", "sa{sv}",
                                                                             ("", options)), timeout=CALL_SECONDS))  # fmt: skip
                except DBusErrorResponse as error:
                    raise PortalUnavailable(f"Screenshot: {error.name}") from error
                try:
                    answer = connection.recv_until_filtered(queue, timeout=ANSWER_SECONDS)
                except TimeoutError as error:
                    raise DesktopError("The screenshot portal didn't answer") from error
            code, results = answer.body
            return screenshot_file(code, results)
        except (OSError, TimeoutError) as error:
            raise DesktopError(f"Screenshot portal: {error}") from error
        finally:
            with contextlib.suppress(OSError):
                connection.close()
