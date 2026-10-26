"""Screen brightness, Do Not Disturb, Bluetooth, and restarting, shutting down or logging out."""

import logging
from enum import StrEnum
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import Bluetooth, Brightness, DoNotDisturb, Power, PowerAction, SettingsPanes
from bilge.desktop.process import DesktopError, NotPossibleHere
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import choice, failure, int_argument, integer, obj, refine_level, string_argument

log = logging.getLogger(__name__)
BRIGHTNESS_STEP = 10


class LevelAction(StrEnum):
    SET = "set"
    INCREASE = "increase"
    DECREASE = "decrease"


class Switch(StrEnum):
    ON = "on"
    OFF = "off"
    STATUS = "status"


_TEXTS = {
    AssistantLanguage.TURKISH: {
        "brightness": "Ekran parlaklığını ayarlar, artırır ya da azaltır.",
        "level": "Sadece 'set' için hedef parlaklık (0-100)",
        "by": "Sadece 'increase'/'decrease' için kaç puan; söylenmediyse boş bırak",
        "no_level": "Hedef parlaklık belirtilmedi.",
        "brightness_now": "Parlaklık yüzde {level}.",
        "no_brightness_windows": "Bu ekranın parlaklığını Windows'tan değiştiremiyorum; harici monitörlerde monitörün kendi düğmelerini kullanabilirsin.",
        "no_brightness": "Bu ekranın parlaklığını değiştiremiyorum. Dizüstü ekranı için brightnessctl, harici monitör için ddcutil kurulabilir; ya da monitörün düğmelerini kullanabilirsin.",
        "dnd": "Rahatsız Etmeyin modunu (bildirimleri susturma) açar, kapatır ya da açık olup olmadığını söyler.",
        "dnd_on": "Rahatsız Etmeyin açık; bildirimler sessiz.",
        "dnd_off": "Rahatsız Etmeyin kapalı; bildirimler yeniden görünecek.",
        "dnd_unknown": "Rahatsız Etmeyin'in durumunu okuyamadım.",
        "dnd_windows": "Windows, Rahatsız Etmeyin'i uygulamaların değiştirmesine izin vermiyor. Win+N ile bildirim merkezini açıp zil simgesine basabilirsin; bildirim ayarlarını da açtım.",
        "dnd_windows_status": "Windows, Rahatsız Etmeyin'in durumunu uygulamalara söylemiyor; Win+N ile bildirim merkezinde görebilirsin.",
        "dnd_kde": "Rahatsız Etmeyin başka bir yerden açılmış; bildirim alanındaki simgeden kapatabilirsin.",
        "dnd_unsupported": "Bu masaüstünde Rahatsız Etmeyin'i değiştiremiyorum; bildirim alanındaki simgeden açıp kapatabilirsin.",
        "bluetooth": "Bluetooth'u açar, kapatır ya da açık olup olmadığını söyler.",
        "bluetooth_question": "Bluetooth'u kapatırsam kablosuz kulaklık, klavye ve fare gibi cihazların bağlantısı kesilir. Kapatayım mı?",
        "bluetooth_on": "Bluetooth açık.",
        "bluetooth_off": "Bluetooth kapalı.",
        "no_bluetooth": "Bu bilgisayarda Bluetooth bulunamadı.",
        "power": "Bilgisayarı yeniden başlatır, kapatır ya da oturumu kapatır. Her seferinde önce sorar.",
        PowerAction.RESTART: "Bilgisayar yeniden başlatılıyor.",
        PowerAction.SHUT_DOWN: "Bilgisayar kapatılıyor.",
        PowerAction.LOG_OUT: "Oturum kapatılıyor.",
        "question_" + PowerAction.RESTART: "Kaydedilmemiş işler kaybolabilir. Bilgisayarı yeniden başlatayım mı?",
        "question_" + PowerAction.SHUT_DOWN: "Kaydedilmemiş işler kaybolabilir. Bilgisayarı kapatayım mı?",
        "question_" + PowerAction.LOG_OUT: "Açık uygulamalar kapanır, kaydedilmemiş işler kaybolabilir. Oturumu kapatayım mı?",
        "power_failed": "Bunu yapamadım; sistem izin vermedi.",
    },
    AssistantLanguage.ENGLISH: {
        "brightness": "Sets, raises or lowers the screen brightness.",
        "level": "Only for 'set': the target brightness (0-100)",
        "by": "Only for 'increase'/'decrease': by how many points; leave empty if not said",
        "no_level": "No target brightness was given.",
        "brightness_now": "Brightness is at {level} percent.",
        "no_brightness_windows": "Windows can't change this screen's brightness; on an external monitor, use its own buttons.",
        "no_brightness": "I can't change this screen's brightness. Installing brightnessctl (for a laptop screen) or ddcutil (for an external monitor) may help, or use the monitor's buttons.",
        "dnd": "Turns Do Not Disturb (silenced notifications) on or off, or says whether it's on.",
        "dnd_on": "Do Not Disturb is on; notifications are silenced.",
        "dnd_off": "Do Not Disturb is off; notifications will show again.",
        "dnd_unknown": "I couldn't read whether Do Not Disturb is on.",
        "dnd_windows": "Windows doesn't let apps change Do Not Disturb. Press Win+N to open the notification center and click the bell; I've opened the notification settings too.",
        "dnd_windows_status": "Windows doesn't tell apps whether Do Not Disturb is on; press Win+N to see it in the notification center.",
        "dnd_kde": "Do Not Disturb was turned on elsewhere; you can turn it off from the notification icon.",
        "dnd_unsupported": "I can't change Do Not Disturb on this desktop; use the notification icon in the panel.",
        "bluetooth": "Turns Bluetooth on or off, or says whether it's on.",
        "bluetooth_question": "Turning Bluetooth off disconnects wireless headphones, keyboards and mice. Shall I turn it off?",
        "bluetooth_on": "Bluetooth is on.",
        "bluetooth_off": "Bluetooth is off.",
        "no_bluetooth": "This computer has no Bluetooth.",
        "power": "Restarts or shuts down the computer, or logs out. Always asks first.",
        PowerAction.RESTART: "Restarting the computer.",
        PowerAction.SHUT_DOWN: "Shutting down the computer.",
        PowerAction.LOG_OUT: "Logging out.",
        "question_" + PowerAction.RESTART: "Unsaved work may be lost. Shall I restart the computer?",
        "question_" + PowerAction.SHUT_DOWN: "Unsaved work may be lost. Shall I shut down the computer?",
        "question_" + PowerAction.LOG_OUT: "Open apps will close and unsaved work may be lost. Shall I log out?",
        "power_failed": "That didn't work; the system didn't allow it.",
    },
}  # fmt: skip


def brightness_tool(brightness: Brightness, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        action = string_argument(arguments, "action")
        level, by = int_argument(arguments, "level"), int_argument(arguments, "by")
        try:
            if action == LevelAction.SET:
                if level is None:
                    raise ToolError(texts["no_level"])
                target = level
            else:
                amount = by if by is not None and by > 0 else BRIGHTNESS_STEP
                target = brightness.level() + (-amount if action == LevelAction.DECREASE else amount)
            target = max(0, min(100, target))
            brightness.set_level(target)
        except NotPossibleHere as error:
            raise ToolError(
                texts["no_brightness_windows" if error.desktop == "windows" else "no_brightness"]
            ) from error
        except DesktopError as error:
            raise failure(error, language) from error
        return texts["brightness_now"].format(level=target)

    parameters = obj(
        ["action"], action=choice(LevelAction, "set/increase/decrease"),
        level=integer(texts["level"], 0, 100), by=integer(texts["by"], 1, 100),
    )  # fmt: skip
    return Tool("setBrightness", texts["brightness"], run=run, parameters=parameters, refine=refine_level)


def do_not_disturb_tool(dnd: DoNotDisturb, settings: SettingsPanes, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def status() -> str:
        try:
            on = dnd.enabled()
        except NotPossibleHere:
            return texts["dnd_windows_status"]
        return texts["dnd_unknown"] if on is None else texts["dnd_on" if on else "dnd_off"]

    def windows_hint() -> str:
        # Not a failure: the user is told where the switch is, and the page with it opens.
        try:
            settings.open("notifications")
        except DesktopError:
            log.info("Could not open the notification settings", exc_info=True)
        return texts["dnd_windows"]

    def run(arguments: dict[str, Any]) -> str:
        action = string_argument(arguments, "action")
        if action == Switch.STATUS:
            return status()
        on = action != Switch.OFF
        try:
            dnd.set_enabled(on)
        except NotPossibleHere as error:
            if error.desktop == "windows":
                return windows_hint()
            raise ToolError(texts["dnd_kde" if error.desktop == "kde" else "dnd_unsupported"]) from error
        except DesktopError as error:
            raise failure(error, language) from error
        return texts["dnd_on" if on else "dnd_off"]

    return Tool("doNotDisturb", texts["dnd"], run=run, parameters=obj(["action"], action=choice(Switch, "")))


def bluetooth_tool(bluetooth: Bluetooth, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        action = string_argument(arguments, "action")
        try:
            if action == Switch.STATUS:
                return texts["bluetooth_on" if bluetooth.enabled() else "bluetooth_off"]
            on = action != Switch.OFF
            bluetooth.set_enabled(on)
        except NotPossibleHere as error:
            raise ToolError(texts["no_bluetooth"]) from error
        except DesktopError as error:
            raise failure(error, language) from error
        return texts["bluetooth_on" if on else "bluetooth_off"]

    def question(arguments: dict[str, Any]) -> str | None:
        # Turning it off drops headphones, keyboards and mice, so only that asks first.
        return texts["bluetooth_question"] if string_argument(arguments, "action") == Switch.OFF else None

    return Tool("bluetooth", texts["bluetooth"], run=run, parameters=obj(["action"], action=choice(Switch, "")),
                risk=Risk.CONFIRM, confirmation=question)  # fmt: skip


def power_tool(power: Power, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def action_of(arguments: dict[str, Any]) -> PowerAction | None:
        try:
            return PowerAction(string_argument(arguments, "action"))
        except ValueError:
            return None

    def run(arguments: dict[str, Any]) -> str:
        action = action_of(arguments)
        if action is None:
            raise ToolError(texts["power_failed"])
        try:
            power.act(action)
        except DesktopError as error:
            raise failure(error, language, texts["power_failed"]) from error
        return texts[action]

    def question(arguments: dict[str, Any]) -> str:
        # Asked every time: a misheard word must never end the session.
        action = action_of(arguments) or PowerAction.SHUT_DOWN
        return texts["question_" + action]

    return Tool("power", texts["power"], run=run, parameters=obj(["action"], action=choice(PowerAction, "")),
                risk=Risk.CONFIRM, confirmation=question, explicit_yes=True)  # fmt: skip


def hardware_tools(
    brightness: Brightness, dnd: DoNotDisturb, bluetooth: Bluetooth, power: Power, settings: SettingsPanes,
    language: AssistantLanguage,
) -> list[Tool]:  # fmt: skip
    return [
        brightness_tool(brightness, language),
        do_not_disturb_tool(dnd, settings, language),
        bluetooth_tool(bluetooth, language),
        power_tool(power, language),
    ]
