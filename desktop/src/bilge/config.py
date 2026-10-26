"""Where Bilge keeps settings and data on each system, and the API keys in the system's own key store."""

import contextlib
import json
import os
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import keyring
from keyring.errors import KeyringError, PasswordDeleteError

from bilge.core.language import AssistantLanguage
from bilge.core.media.music_request import AUTO, DEFAULT_CHOICES

APP_NAME = "Bilge"
KEYRING_SERVICE = "bilge"
# Read when no key is stored, so a key already exported for other tools works without setup.
KEY_ENVIRONMENT = {
    "openai": "OPENAI_API_KEY",
    "anthropic": "ANTHROPIC_API_KEY",
    "gemini": "GEMINI_API_KEY",
    "openrouter": "OPENROUTER_API_KEY",
    "groq": "GROQ_API_KEY",
    "deepseek": "DEEPSEEK_API_KEY",
}


def config_dir() -> Path:
    if sys.platform == "win32":
        return Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / APP_NAME
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / f"{APP_NAME} Desktop"
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / APP_NAME.lower()


def data_dir() -> Path:
    if sys.platform in ("win32", "darwin"):
        return config_dir()
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / APP_NAME.lower()


@dataclass
class ModelSettings:
    provider: str = "lmstudio"
    model: str = ""
    # Overrides the provider's usual address, for a server on another port or machine.
    base_url: str | None = None


@dataclass
class VoiceSettings:
    # "local" (Whisper on this computer), or a transcription API: "openai", "groq".
    recognizer: str = "local"
    recognizer_model: str = ""
    voice: str = "F1"
    wake_phrase: str = "bilge"
    follow_up: bool = True
    barge_in: bool = True
    speaker_check: bool = False
    input_device: str | None = None
    output_device: str | None = None
    # Whether saying the wake phrase starts a request; off, only the shortcut does.
    wake_word: bool = True
    # A key combination that makes Bilge listen, as Qt writes it ("Ctrl+Shift+B"); empty for none.
    hotkey: str = ""
    # Where local Whisper runs: "auto", "cpu", or "gpu" (any graphics card, through whisper.cpp).
    accelerator: str = "auto"
    # Minutes without a request after which the large Whisper model is let go; 0 keeps it loaded.
    unload_minutes: int = 0


ACCELERATORS = ("auto", "cpu", "gpu")
UNLOAD_MINUTES = (0, 10, 30, 60)


@dataclass
class CalendarSettings:
    # "caldav" (read and write: Nextcloud, iCloud, Fastmail, Radicale…), "ics" (a read-only address, such as
    # Google Calendar's secret iCal address), "outlook" (Windows, while Outlook is open), or "" for none. Passwords
    # and the secret address are in the key store.
    kind: str = ""
    url: str = ""
    username: str = ""
    # The calendar new events go to; the first one that takes events when empty.
    name: str = ""


@dataclass
class MailSettings:
    # An IMAP account read over TLS where Outlook isn't there to ask: "imap.example.org" or "imap.example.org:993".
    # The (app) password is in the key store.
    server: str = ""
    username: str = ""


@dataclass
class CustomCommand:
    """A program the user can start by voice ("yedekleme komutunu çalıştır"); run without a shell, and never with
    anything spoken added to it."""

    name: str
    argv: list[str] = field(default_factory=list)


@dataclass
class HomeSettings:
    # Home Assistant's address on the local network, e.g. "http://homeassistant.local:8123"; empty for none. The
    # long-lived access token is in the key store.
    address: str = ""


@dataclass
class Settings:
    language: str = AssistantLanguage.TURKISH.value
    model: ModelSettings = field(default_factory=ModelSettings)
    # Used when a weather question names no city.
    weather_city: str = "İstanbul"
    voice: VoiceSettings = field(default_factory=VoiceSettings)
    calendar: CalendarSettings = field(default_factory=CalendarSettings)
    mail: MailSettings = field(default_factory=MailSettings)
    home: HomeSettings = field(default_factory=HomeSettings)
    # The small window in the screen corner showing what was heard and the reply.
    show_hud: bool = True
    # Set once the first-run setup has been finished.
    setup_done: bool = False
    # Once a day, whether a newer Bilge has been published on GitHub.
    check_updates: bool = True
    # While Bilge runs, say so when a strong earthquake happens near the weather city.
    earthquake_alerts: bool = True
    # Where a named song plays when the command names no service: "auto" (the Spotify app when installed, otherwise
    # YouTube Music), "spotify", "youtube", "youtube_music", "deezer" or "apple_music".
    music_service: str = AUTO
    commands: list[CustomCommand] = field(default_factory=list)

    @property
    def assistant_language(self) -> AssistantLanguage:
        try:
            return AssistantLanguage(self.language)
        except ValueError:
            return AssistantLanguage.TURKISH


def settings_path() -> Path:
    return config_dir() / "settings.json"


def load_settings(path: Path | None = None) -> Settings:
    path = path or settings_path()
    try:
        # utf-8-sig: Notepad and PowerShell may save the file with a byte-order mark.
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        return Settings()
    except (OSError, ValueError) as error:
        raise RuntimeError(f"Could not read {path}: {error}") from error
    model = data.get("model") or {}
    voice = data.get("voice") if isinstance(data.get("voice"), dict) else {}
    defaults = VoiceSettings()
    calendar = data.get("calendar") if isinstance(data.get("calendar"), dict) else {}
    mail = data.get("mail") if isinstance(data.get("mail"), dict) else {}
    home = data.get("home") if isinstance(data.get("home"), dict) else {}
    return Settings(
        mail=MailSettings(server=str(mail.get("server", "")), username=str(mail.get("username", ""))),
        home=HomeSettings(address=str(home.get("address", ""))),
        calendar=CalendarSettings(
            kind=str(calendar.get("kind", "")),
            url=str(calendar.get("url", "")),
            username=str(calendar.get("username", "")),
            name=str(calendar.get("name", "")),
        ),
        voice=VoiceSettings(
            recognizer=str(voice.get("recognizer", defaults.recognizer)),
            recognizer_model=str(voice.get("recognizer_model", "")),
            voice=str(voice.get("voice", defaults.voice)),
            wake_phrase=str(voice.get("wake_phrase") or defaults.wake_phrase),
            follow_up=bool(voice.get("follow_up", defaults.follow_up)),
            barge_in=bool(voice.get("barge_in", defaults.barge_in)),
            speaker_check=bool(voice.get("speaker_check", defaults.speaker_check)),
            input_device=voice.get("input_device") or None,
            output_device=voice.get("output_device") or None,
            # A file edited by hand must not leave Bilge with no way to be called.
            wake_word=bool(voice.get("wake_word", True)) or not str(voice.get("hotkey") or ""),
            hotkey=str(voice.get("hotkey") or ""),
            accelerator=accelerator if (accelerator := str(voice.get("accelerator", ""))) in ACCELERATORS else "auto",
            unload_minutes=minutes if (minutes := voice.get("unload_minutes", 0)) in UNLOAD_MINUTES else 0,
        ),
        language=str(data.get("language", AssistantLanguage.TURKISH.value)),
        weather_city=str(data.get("weather_city") or "İstanbul"),
        show_hud=bool(data.get("show_hud", True)),
        setup_done=bool(data.get("setup_done", False)),
        check_updates=bool(data.get("check_updates", True)),
        earthquake_alerts=bool(data.get("earthquake_alerts", True)),
        music_service=service if (service := data.get("music_service")) in DEFAULT_CHOICES else AUTO,
        commands=_commands(data.get("commands")),
        model=ModelSettings(
            provider=str(model.get("provider", "lmstudio")),
            model=str(model.get("model", "")),
            base_url=model.get("base_url") or None,
        ),
    )


def _commands(value: object) -> list[CustomCommand]:
    """The well-formed entries of a list that may have been edited by hand."""
    found = []
    for item in value if isinstance(value, list) else []:
        if not isinstance(item, dict):
            continue
        name, argv = str(item.get("name") or "").strip(), item.get("argv")
        if name and isinstance(argv, list) and argv and all(isinstance(part, str) for part in argv) and argv[0].strip():
            found.append(CustomCommand(name, list(argv)))
    return found


def save_settings(settings: Settings, path: Path | None = None) -> None:
    path = path or settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(asdict(settings), ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def api_key(provider: str) -> str | None:
    try:
        stored = keyring.get_password(KEYRING_SERVICE, provider)
    except KeyringError:
        stored = None
    if stored:
        return stored
    variable = KEY_ENVIRONMENT.get(provider)
    return os.environ.get(variable) if variable else None


def store_api_key(provider: str, key: str) -> None:
    """Raises KeyringError when the system has no key store (for example a Linux session without one)."""
    keyring.set_password(KEYRING_SERVICE, provider, key)


def delete_api_key(provider: str) -> None:
    with contextlib.suppress(PasswordDeleteError):
        keyring.delete_password(KEYRING_SERVICE, provider)
