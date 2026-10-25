"""What the tools need from the operating system. Each platform provides these; the tools stay the same."""

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True)
class AppEntry:
    """An installed application. `names` are everything the user might call it ("Hesap Makinesi", "calculator")."""

    id: str
    display_name: str
    names: tuple[str, ...]


@dataclass(frozen=True)
class FrontWindow:
    """The application in front. `name` is the program or window class, lowercase ("gnome-terminal-server");
    `app_class` the window class or Wayland app id ("org.gnome.console"), which names apps a script runs."""

    name: str
    title: str = ""
    app_class: str = ""


@dataclass(frozen=True)
class VolumeState:
    level: int
    muted: bool


@dataclass(frozen=True)
class NowPlaying:
    player: str
    playing: bool
    title: str = ""
    artist: str = ""


@dataclass(frozen=True)
class PlayerStart:
    """A music player Bilge started; `playing` is False when it opened but didn't take the play command."""

    name: str
    playing: bool


class MediaCommand(StrEnum):
    PLAY = "play"
    PAUSE = "pause"
    TOGGLE = "toggle"
    NEXT = "next"
    PREVIOUS = "previous"


class RepeatMode(StrEnum):
    OFF = "off"
    TRACK = "track"
    ALL = "all"


class PowerAction(StrEnum):
    RESTART = "restart"
    SHUT_DOWN = "shutDown"
    LOG_OUT = "logOut"


class ScreenshotArea(StrEnum):
    WHOLE_SCREEN = "wholeScreen"
    FRONT_WINDOW = "frontWindow"
    SELECTION = "selection"


class WindowAction(StrEnum):
    MINIMIZE = "minimize"
    MAXIMIZE = "maximize"
    RESTORE = "restore"
    FULL_SCREEN = "fullScreen"
    CLOSE = "close"


class Apps(Protocol):
    def installed(self) -> list[AppEntry]: ...

    def launch(self, app: AppEntry) -> None: ...

    def running(self) -> list[AppEntry]: ...

    def quit(self, app: AppEntry) -> bool:
        """Asks the app to close; False when it wasn't running."""
        ...


class Volume(Protocol):
    def state(self) -> VolumeState: ...

    def set_level(self, level: int) -> None: ...

    def set_muted(self, muted: bool) -> None: ...


class Media(Protocol):
    def now_playing(self) -> NowPlaying | None:
        """None when no player is open."""
        ...

    def send(self, command: MediaCommand) -> str:
        """Returns the player's name."""
        ...

    def seek(self, seconds: float) -> str:
        """Moves playback by `seconds`, back when negative; NotPossibleHere when the player can't seek."""
        ...

    def restart_track(self) -> str: ...

    def set_shuffle(self, on: bool) -> str:
        """NotPossibleHere when the player has no shuffle; likewise for repeat."""
        ...

    def set_repeat(self, mode: RepeatMode) -> str: ...


class MusicLauncher(Protocol):
    def start_player(self) -> PlayerStart | None:
        """Starts the user's music player and asks it to play; None when no player is installed."""
        ...

    def play_search(self, query: str) -> str:
        """Opens a search for `query` in Spotify when it is installed, otherwise a web music search; returns where."""
        ...


class Clipboard(Protocol):
    def read(self) -> str: ...

    def write(self, text: str) -> None: ...

    def selection(self) -> str:
        """The text selected in the app in front, or empty."""
        ...


# What `Keyboard.press` takes besides a single letter or digit.
MODIFIER_KEYS = ("ctrl", "shift", "alt")
NAMED_KEYS = ("tab", "left", "right", "page_up", "page_down", "home", "end", "return", "escape", "f5")


class Keyboard(Protocol):
    def front_window(self) -> FrontWindow | None:
        """None when the platform doesn't say which app is in front."""
        ...

    def type(self, text: str) -> None: ...

    def press(self, *keys: str) -> None:
        """A shortcut into the app in front: the keys held down in order ("ctrl", "shift", "tab"), then released.
        Each is one of MODIFIER_KEYS, NAMED_KEYS, a letter or a digit; DesktopError for anything else."""
        ...

    def new_line(self) -> None:
        """Shift+Enter: a line break even where Enter would send a message."""
        ...

    def backspace(self, count: int) -> None: ...


class WindowControl(Protocol):
    def act(self, action: WindowAction) -> None:
        """On the window in front. FULL_SCREEN toggles; CLOSE asks the window to close, as its close button does."""
        ...


class Session(Protocol):
    def lock(self) -> None: ...

    def suspend(self) -> None: ...

    def dark_mode(self) -> bool | None: ...

    def set_dark_mode(self, dark: bool) -> None: ...


class Network(Protocol):
    def wifi_enabled(self) -> bool | None: ...

    def wifi_name(self) -> str | None:
        """The name (SSID) of the Wi-Fi network connected to; None when there is none or it can't be read."""
        ...

    def set_wifi(self, enabled: bool) -> None: ...


class Brightness(Protocol):
    """The built-in screen's brightness in percent, or an external monitor's where the platform can reach it."""

    def level(self) -> int: ...

    def set_level(self, level: int) -> None:
        """NotPossibleHere when no screen here lets a program change it."""
        ...


class DoNotDisturb(Protocol):
    def enabled(self) -> bool | None:
        """None when reading it failed; NotPossibleHere where the desktop never tells programs."""
        ...

    def set_enabled(self, on: bool) -> None:
        """NotPossibleHere where the desktop gives programs no way to change it."""
        ...


class Bluetooth(Protocol):
    def enabled(self) -> bool:
        """NotPossibleHere when the computer has no Bluetooth adapter."""
        ...

    def set_enabled(self, on: bool) -> None: ...


class Power(Protocol):
    def act(self, action: PowerAction) -> None: ...


class Screenshots(Protocol):
    def capture(self, area: ScreenshotArea, destination: Path) -> bool:
        """False when the user cancelled (for example, no area was selected); DesktopError when it failed."""
        ...

    def copy_image(self, image: Path) -> None: ...


class ScreenText(Protocol):
    def read(self, area: ScreenshotArea) -> str:
        """The text shown in the front window or on the whole screen, recognized in a screenshot that is not kept.
        Empty when the user cancelled the capture; MissingProgram or NotPossibleHere when nothing here can
        recognize text."""
        ...


class FileSelection(Protocol):
    def selected(self) -> tuple[Path, ...]:
        """The files the user picked in the file manager; empty when there are none or it won't say."""
        ...


class SettingsPanes(Protocol):
    def open(self, pane: str) -> bool:
        """`pane` is one of the names in `bilge.core.conversation.quick_intent_parser.SettingsPane`; False when this
        desktop has no such page, in which case the main settings window is opened."""
        ...


class Opener(Protocol):
    def open(self, target: str) -> None:
        """A web address or a file, in the app the user chose for it."""
        ...

    def reveal(self, path: Path) -> None:
        """Shows the file selected in the file manager, without opening it."""
        ...


class Folders(Protocol):
    """The user's standard folders, which may have translated names ("Masaüstü", "İndirilenler")."""

    def home(self) -> Path: ...

    def desktop(self) -> Path: ...

    def downloads(self) -> Path: ...

    def documents(self) -> Path: ...

    def pictures(self) -> Path: ...

    def music(self) -> Path: ...

    def videos(self) -> Path: ...


class Notifier(Protocol):
    def notify(self, title: str, body: str) -> None: ...


@dataclass(frozen=True)
class PairedPhone:
    id: str
    name: str


class TextMessages(Protocol):
    """SMS through the user's own phone, paired with this computer."""

    def reachable_phone(self) -> PairedPhone:
        """MissingProgram when the bridge to the phone isn't installed; NotPossibleHere when no paired phone is
        reachable."""
        ...

    def send(self, phone: PairedPhone, number: str, text: str) -> None: ...


@dataclass(frozen=True)
class Desktop:
    apps: Apps
    volume: Volume
    media: Media
    music: MusicLauncher
    clipboard: Clipboard
    keyboard: Keyboard
    windows: WindowControl
    session: Session
    network: Network
    screenshots: Screenshots
    screen_text: ScreenText
    file_selection: FileSelection
    settings: SettingsPanes
    opener: Opener
    notifier: Notifier
    folders: Folders
    brightness: Brightness
    do_not_disturb: DoNotDisturb
    bluetooth: Bluetooth
    power: Power
