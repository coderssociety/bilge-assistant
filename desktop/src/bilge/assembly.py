"""Builds the assistant from the settings: the one place the CLI, the tray app and the benchmarks share."""

import logging
import sys
import threading
from collections.abc import Callable, Iterator
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING

from bilge import calendars, config, contacts, desktop, mailboxes
from bilge.brain.action_log import ActionLog
from bilge.brain.agent import Agent, Confirmer
from bilge.brain.routing import Mode, Rule, rule
from bilge.core.alerts import earthquake_alert
from bilge.core.context import context_intent
from bilge.core.context.screen_context import ContextItem
from bilge.core.dictation import dictation_command
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import Desktop
from bilge.llm.providers import ProviderError, make_provider
from bilge.models.downloader import Downloader, ModelSpec
from bilge.tools.base import Registry, Tool
from bilge.tools.builtin import (
    earthquakes,
    football,
    internet,
    podcasts,
    prayer,
    prices,
    radio,
    routines,
    stocks,
    wikipedia,
)
from bilge.tools.builtin.briefing import Briefing, briefing_tool
from bilge.tools.builtin.calculator import calculator
from bilge.tools.builtin.calendar import calendar_tools
from bilge.tools.builtin.clock import current_date_time
from bilge.tools.builtin.contacts import ContactLookup, find_contact_tool
from bilge.tools.builtin.home_assistant import HomeAssistant, smart_home_rule, smart_home_tool
from bilge.tools.builtin.mail import read_mail_tool
from bilge.tools.builtin.memory import memory_tools
from bilge.tools.builtin.units import convert_units
from bilge.tools.builtin.world_clock import world_clock_tool
from bilge.tools.builtin.youtube import summarize_video_tool
from bilge.tools.desktop import sources
from bilge.tools.memory_store import MemoryStore
from bilge.tools.player import Player
from bilge.tools.reading import TextReading, continue_reading_tool

if TYPE_CHECKING:
    from bilge.desktop.base import TextMessages
    from bilge.tools.desktop.timers import TimerService
    from bilge.voice.assistant import Service
    from bilge.voice.media_player import MediaPlayer

log = logging.getLogger(__name__)
CALDAV_SECRET = "caldav"
ICS_SECRET = "calendar-ics"
# One for the whole run: the watcher a restart builds must not announce an earthquake the previous one already did.
_ANNOUNCED_EARTHQUAKES = earthquake_alert.Announced()
IMAP_SECRET = "imap"
HOME_ASSISTANT_SECRET = "home-assistant"


def models_dir() -> Path:
    return config.data_dir() / "models"


def calendar_source(settings: config.CalendarSettings) -> calendars.CalendarSource | None:
    if settings.kind == "caldav" and settings.url:
        return calendars.CalDAVSource(
            settings.url, settings.username, config.api_key(CALDAV_SECRET) or "", settings.name
        )
    if settings.kind == "outlook" and sys.platform == "win32":
        from bilge.desktop.windows.office import Outlook, OutlookCalendar

        return OutlookCalendar(Outlook())
    if settings.kind == "ics":
        url = config.api_key(ICS_SECRET)
        return calendars.ICSSource(url) if url else None
    return None


def contact_source(settings: config.Settings) -> contacts.ContactSource | None:
    """Outlook's contacts on Windows; elsewhere the address book of the CalDAV account, when its server has one."""
    if sys.platform == "win32":
        from bilge.desktop.windows.office import Outlook, OutlookContacts

        return OutlookContacts(Outlook())
    calendar = settings.calendar
    if calendar.kind == "caldav" and calendar.url:
        return contacts.CardDAVContacts(calendar.url, calendar.username, config.api_key(CALDAV_SECRET) or "")
    return None


def mailbox(settings: config.MailSettings) -> mailboxes.Mailbox | None:
    """The IMAP account; on Windows mail comes from Outlook instead."""
    if not settings.server:
        return None
    return mailboxes.IMAPMailbox(settings.server, settings.username, config.api_key(IMAP_SECRET) or "")


def routine_store() -> routines.RoutineStore:
    return routines.RoutineStore(config.data_dir() / "routines.json")


def home_assistant(settings: config.HomeSettings) -> HomeAssistant | None:
    """None until both the address and the token are set."""
    if not settings.address:
        return None
    token = config.api_key(HOME_ASSISTANT_SECRET)
    return HomeAssistant(settings.address, token) if token else None


def build_agent(
    settings: config.Settings,
    confirm: Confirmer,
    provider: str | None = None,
    model: str | None = None,
    announce: Callable[[str], None] | None = None,
    services: list["Service"] | None = None,
    run_routine: Callable[[str], None] | None = None,
    player: "MediaPlayer | None" = None,
) -> Agent:
    """`announce` says something unprompted (a timer going off). Work that runs while Bilge listens (the earthquake
    watcher, the routines) is added to `services` for the voice assistant to start and stop. `run_routine` runs a
    routine's command unattended and says the reply; without it routines can be set up but don't run. `player` plays
    radio and podcasts; without one (the text chat) a player with its own speaker output is made."""
    language = settings.assistant_language
    preset = provider or settings.model.provider
    chosen = model or settings.model.model
    if not chosen:
        raise ProviderError("No model chosen. Run `bilge models` to list them, then `bilge use <provider> <model>`.")
    chat = make_provider(preset, chosen, config.api_key(preset), settings.model.base_url if not provider else None)
    memory = MemoryStore(config.data_dir() / "memory.json")
    weather = internet.weather(language, lambda: settings.weather_city)

    def calendar() -> calendars.CalendarSource | None:
        return calendar_source(settings.calendar)

    briefing = Briefing(language, weather, calendar, settings.voice.wake_phrase)
    news_reading = internet.NewsReading()
    text_reading = TextReading(language)
    people = ContactLookup(lambda: contact_source(settings), language)
    found = desktop.current(language)
    player = player or _media_player(language)
    tool_player: Player = sources.TurnTakingPlayer(player, found.media) if found is not None else player
    alert = _alert(found, announce)
    alarms = _timer_service(language, alert) if found is not None else None
    if services is not None and settings.earthquake_alerts:
        services.append(earthquakes.EarthquakeWatcher(language, lambda: settings.weather_city, alert,
                                                      _ANNOUNCED_EARTHQUAKES))  # fmt: skip
    saved_routines = routine_store()
    if services is not None and run_routine is not None:
        services.append(routines.RoutineService(saved_routines, lambda routine: run_routine(routine.command)))
    registry = Registry([
        current_date_time(language),
        calculator(language),
        convert_units(language),
        world_clock_tool(language),
        weather,
        internet.exchange_rate(language),
        prices.gold_price(language),
        prices.fuel_price(language, lambda: settings.weather_city),
        prayer.prayer_times_tool(language, lambda: settings.weather_city),
        wikipedia.wikipedia(language),
        internet.news(language, news_reading),
        earthquakes.earthquakes(language, lambda: settings.weather_city),
        football.football(language),
        stocks.stocks(language),
        internet.read_web_page(language, text_reading),
        continue_reading_tool(text_reading, language),
        radio.radio_tool(language, tool_player, radio.StationMemory(config.data_dir() / "radio.json")),
        podcasts.podcast_tool(language, tool_player),
        summarize_video_tool(language, text_reading, _pasted(found)),
        briefing_tool(briefing),
        find_contact_tool(people, language),
        *calendar_tools(calendar, language, alert=_reminder_alert(alarms) if alarms is not None else None),
        *routines.routine_tools(saved_routines, language),
    ])  # fmt: skip
    if sys.platform != "win32":
        registry.add(read_mail_tool(lambda: mailbox(settings.mail), language, reading=text_reading))
    rules: list[Rule] = [
        rule("radio", radio.claims, radio.rule_arguments),
        rule("podcast", podcasts.claims, podcasts.rule_arguments),
        rule("dailyBriefing", briefing.claims),
        rule("news", internet.news_source_rule_claims(language, news_reading)),
        rule("goldPrice", internet.asks_for_gold(language)),
        rule("prayerTimes", prayer.asks_for_prayer_times(language)),
        rule("fuelPrice", prices.asks_for_fuel_prices(language)),
        rule("earthquakes", earthquakes.asks_about_earthquakes),
        rule("football", football.asks_about_football),
        rule("stocks", stocks.asks_about_stocks),
    ]
    modes: list[Mode] = []
    opener = found.opener.open if found is not None else None
    registry.add(internet.news_article(language, news_reading, opener, text_reading))
    # Tools that refer to "the previous answer" are built before the agent that remembers it.
    built: list[Agent] = []
    if found is not None and alarms is not None:
        last_reply = lambda: built[0].last_reply if built else None  # noqa: E731
        tools, desktop_rules, desktop_modes = _desktop_tools(found, language, alarms, last_reply, text_reading,
                                                             people, settings.commands, tool_player,
                                                             lambda: settings.music_service)  # fmt: skip
        for tool in tools:
            registry.add(tool)
        rules = [*desktop_rules, *rules]
        modes = desktop_modes
    home = home_assistant(settings.home)
    if home is not None:
        registry.add(smart_home_tool(home, language))
        rules = [smart_home_rule(language), *rules]
    # A routine carries a command other rules would claim ("her sabah 8'de günün özetini oku").
    rules = [*routines.routine_rules(language), *rules]
    agent = Agent(chat, registry, confirm=confirm, language=language, memory=memory.prompt_lines,
                  action_log=ActionLog(config.data_dir() / "actions.jsonl"), rules=rules, modes=modes,
                  reading=text_reading)  # fmt: skip
    built.append(agent)
    for tool in memory_tools(memory, language, lambda: agent.last_reply):
        registry.add(tool)
    return agent


def _media_player(language: AssistantLanguage) -> "MediaPlayer":
    from bilge.voice.media_player import MediaPlayer

    return MediaPlayer(language)


def _pasted(found: Desktop | None) -> Callable[[], Iterator[str]] | None:
    """The clipboard's text, then the selection: where a video's address is looked for when none is said."""
    if found is None:
        return None
    from bilge.desktop.process import DesktopError

    def pasted() -> Iterator[str]:
        for read in (found.clipboard.read, found.clipboard.selection):
            try:
                yield read()
            except DesktopError:
                log.info("Could not read the clipboard or the selection", exc_info=True)

    return pasted


def _alert(found: Desktop | None, announce: Callable[[str], None] | None) -> Callable[[str], None]:
    """Says it after any reply in progress and shows it as a desktop notification."""

    def alert(message: str) -> None:
        if found is not None:
            try:
                found.notifier.notify("Bilge", message)
            except Exception:  # noqa: BLE001 - a missing notification must not silence the spoken one
                log.info("Could not show a notification", exc_info=True)
        if announce is not None:
            announce(message)

    return alert


def _timer_service(language: AssistantLanguage, alert: Callable[[str], None]) -> "TimerService":
    from bilge.tools.desktop import timers

    service = timers.TimerService(alert, language, store=config.data_dir() / "timers.json")
    service.restore()
    return service


def _reminder_alert(alarms: "TimerService") -> Callable[[datetime, str], None]:
    # The timer service runs on the local wall clock, without a zone.
    return lambda due, title: alarms.schedule(due.astimezone().replace(tzinfo=None), title)


def _desktop_tools(
    found: Desktop,
    language: AssistantLanguage,
    alarms: "TimerService",
    last_reply: Callable[[], str | None],
    text_reading: TextReading,
    people: ContactLookup,
    custom_commands: list[config.CustomCommand],
    player: Player,
    music_service: Callable[[], str],
) -> tuple[list[Tool], list[Rule], list[Mode]]:
    from bilge.desktop.calc import LibreOfficeCalc
    from bilge.desktop.process import Runner
    from bilge.tools.command_approvals import CommandApprovals
    from bilge.tools.desktop import (
        apps,
        browser,
        clipboard,
        commands,
        context,
        files,
        hardware,
        messages,
        notes,
        playback,
        screen,
        sound,
        spreadsheet,
        system,
        timers,
        typing,
        web,
        windows,
    )
    from bilge.tools.notes_folder import NotesFolder, notes_folder

    dictation = typing.DictationSession(found.keyboard, language)
    pointed = context.ContextReader(found.clipboard, found.file_selection)
    sheet = spreadsheet.SpreadsheetSession(language)
    own_commands = commands.CommandTools(custom_commands, CommandApprovals(config.data_dir() / "command-approvals.json"),
                                         Runner(), language)  # fmt: skip
    sheet_tool = spreadsheet.SpreadsheetTool(_spreadsheet_apps(LibreOfficeCalc(Runner())), sheet, language)
    tools = [
        *apps.app_tools(apps.AppCatalog(found.apps), language),
        sound.volume_tool(found.volume, language),
        sound.music_tool(found.media, language, found.music, player),
        sound.music_search_tool(found.music, language, music_service, player=player),
        playback.playback_tool(found.media, language, player),
        *hardware.hardware_tools(
            found.brightness, found.do_not_disturb, found.bluetooth, found.power, found.settings, language
        ),
        *system.system_tools(found.session, found.network, found.settings, found.screenshots, found.folders, language),
        *clipboard.clipboard_tools(found.clipboard, language, last_reply),
        typing.type_text_tool(found.keyboard, language),
        windows.window_tool(found.windows, language),
        typing.start_dictation_tool(dictation, language),
        *files.file_tools(found.folders, found.opener, language, text_reading),
        *web.web_tools(found.opener, language),
        browser.browser_tool(found.keyboard, language),
        screen.read_screen_tool(found.screen_text, language, text_reading),
        context.context_tool(pointed, found.screen_text, found.opener, language, text_reading),
        *timers.timer_tools(alarms, language),
        spreadsheet.spreadsheet_tool(sheet_tool),
        *_office_tools(
            language, text_reading, people, lambda body: pointed.item(context_intent.wanted_kind(body, language))
        ),
        *notes.note_tools(NotesFolder(notes_folder(found.folders.documents(), language)), language, text_reading),
        *commands.command_tools(own_commands),
        messages.send_message_tool(_text_messages(), people, language),
    ]
    rules = [
        rule("startDictation", lambda command: dictation_command.is_start(command, language)),
        rule("spreadsheet", sheet.claims, lambda command: {"command": command}),
        # "YouTube'da Tarkan aç": before "aç" is taken for opening an app.
        rule("playMusic", sound.music_claims, sound.music_rule_arguments),
        *notes.note_rules(language),
        *commands.command_rules(own_commands, language),
        rule("browserControl", lambda command: browser.claims(command, language), lambda command: {"command": command}),
        # "Bunu Ahmet'e gönder": the text is read only when the e-mail is prepared, never by the model.
        context.send_pointed_rule(language),
    ]
    modes = [
        Mode(lambda: dictation.active, dictation.window, lambda _: True, dictation.end, takes=dictation.handle,
             owns=typing.dictation_owns(dictation)),
        Mode(lambda: sheet.active, lambda: sheet.window, sheet.accepts, lambda: setattr(sheet, "active", False),
             tools=frozenset({"spreadsheet"})),
    ]  # fmt: skip
    return tools, rules, modes


def _text_messages() -> "TextMessages | None":
    """KDE Connect on Linux; Windows has no way to send SMS yet."""
    if sys.platform == "win32":
        return None
    from bilge.desktop.linux.kdeconnect import KdeConnectMessages
    from bilge.desktop.process import Runner

    return KdeConnectMessages(Runner())


def _spreadsheet_apps(calc):
    if sys.platform != "win32":
        return calc
    from bilge.desktop.windows.office import ExcelSheets, SpreadsheetApps

    return SpreadsheetApps({"excel": ExcelSheets(), "calc": calc})


def _office_tools(
    language: AssistantLanguage,
    text_reading: TextReading,
    people: ContactLookup,
    pointed: Callable[[str], ContextItem | None],
) -> list[Tool]:
    if sys.platform != "win32":
        return []
    from bilge.desktop.windows.office import Outlook
    from bilge.tools.desktop.mail import mail_tools

    return mail_tools(Outlook(), language, text_reading, people, pointed)


def voice_models(settings: config.Settings) -> tuple[ModelSpec, ...]:
    from bilge.voice import models, placement

    needed = [models.SUPERTONIC, models.WHISPER_BASE]
    if settings.voice.recognizer == "local":
        on_vulkan = placement.choose(settings.voice.accelerator).where is placement.Where.VULKAN
        needed.append(models.WHISPER_TURBO_GGML if on_vulkan else models.WHISPER_TURBO)
    if settings.voice.speaker_check:
        needed.append(models.CAMPLUS)
    return tuple(needed)


# Setup and the starting assistant may both ask for the same models; one downloads while the other waits and then
# finds them in place, instead of both writing the same partial files.
_DOWNLOADING = threading.Lock()


def download_missing(
    specs: tuple[ModelSpec, ...],
    progress: Callable[[ModelSpec, int, int], None] | None = None,
    cancelled: Callable[[], bool] = lambda: False,
) -> None:
    with _DOWNLOADING:
        downloader = Downloader(models_dir())
        for spec in specs:
            if not downloader.is_downloaded(spec):
                downloader.download(
                    spec,
                    progress=(lambda done, total, s=spec: progress(s, done, total)) if progress else None,
                    cancelled=cancelled,
                )


def build_voice_assistant(settings: config.Settings, on_event, provider: str | None = None, model: str | None = None):
    """Returns (assistant, front_end); call front_end.start() and assistant.start() to begin listening."""
    from bilge.voice import models
    from bilge.voice.assistant import Options, VoiceAssistant
    from bilge.voice.audio_io import FrontEnd, SoundDevice
    from bilge.voice.echo import EchoCanceller
    from bilge.voice.media_player import MediaPlayer
    from bilge.voice.recognizers import GuardedRecognizer, WhisperRecognizer
    from bilge.voice.speaker import CampPlus, SpeakerGate, VoiceStore
    from bilge.voice.speech_output import SpeechOutput
    from bilge.voice.supertonic import Supertonic

    language = settings.assistant_language
    voice = settings.voice
    root = models_dir()
    holder: dict = {}
    services: list = []
    player = MediaPlayer(language)
    agent = build_agent(
        settings,
        confirm=lambda question, strict=False: holder["assistant"].confirm(question, strict),
        provider=provider,
        model=model,
        announce=lambda text: holder["assistant"].announce(text),
        services=services,
        run_routine=lambda command: holder["assistant"].run_unattended(command),
        player=player,
    )
    # The wake word is Turkish in both languages.
    wake = GuardedRecognizer(
        WhisperRecognizer(str(root / models.WHISPER_BASE.name), AssistantLanguage.TURKISH, hint="Bilge")
    )
    if voice.recognizer == "local" and voice.unload_minutes:
        from bilge.voice.idle import IdleUnloadingRecognizer

        recognizer = GuardedRecognizer(
            IdleUnloadingRecognizer(lambda: _recognizer(voice, language, root), voice.unload_minutes * 60)
        )
    else:
        recognizer = GuardedRecognizer(_recognizer(voice, language, root))
    try:
        device = SoundDevice(voice.input_device, voice.output_device)
        player.attach(device)
        speech = SpeechOutput(Supertonic(root / models.SUPERTONIC.name), device, language, voice.voice)
        gate = None
        if voice.speaker_check:
            gate = SpeakerGate(VoiceStore(config.data_dir() / "voiceprint.json"),
                               CampPlus(root / models.CAMPLUS.name / models.CAMPLUS_FILE), enabled=True)  # fmt: skip
    except BaseException:
        recognizer.close()
        raise
    options = Options(wake_phrase=voice.wake_phrase, follow_up=voice.follow_up, barge_in=voice.barge_in,
                      wake_word=voice.wake_word or not voice.hotkey)  # fmt: skip
    interpreter, recorder, meetings = _listening_modes(agent, recognizer, language, root,
                                                       announce=lambda text: holder["assistant"].announce(text))  # fmt: skip
    assistant = VoiceAssistant(recognizer, speech, agent, language, options, gate, _making_way(player, on_event),
                               wake_recognizer=wake, services=services, interpreter=interpreter,
                               recorder=recorder, meetings=meetings)  # fmt: skip
    holder["assistant"] = assistant
    front_end = FrontEnd(device, assistant.on_chunk, EchoCanceller() if voice.barge_in else None)
    return assistant, front_end


def _listening_modes(agent: Agent, recognizer, language: AssistantLanguage, root: Path,
                     announce: Callable[[str], None]):  # fmt: skip
    """The interpreter and meeting recording, which need the microphone and the recognizer, so they exist only when
    Bilge listens; their tools and rules are added to the agent."""
    from bilge.tools.meetings import Meetings
    from bilge.voice.interpreter import Interpreter
    from bilge.voice.meeting import MeetingNotes, MeetingRecorder

    folders = desktop.folders()
    notes = MeetingNotes(lambda: agent.provider, folders.documents, language)
    recorder = MeetingRecorder(recognizer, notes)
    meetings = Meetings(recorder, notes, recognizer, folders, language, announce)
    interpreter = Interpreter(lambda: _interpreting_recognizer(recognizer, language, root), lambda: agent.provider,
                              language)  # fmt: skip
    for tool in [*meetings.tools(), interpreter.tool()]:
        agent.registry.add(tool)
    # build_agent puts the routine rules first; a routine may carry a meeting command ("her pazartesi 10'da
    # toplantıyı kaydet"), so they stay ahead of the meeting rules.
    routine_rules = len(routines.routine_rules(language))
    agent.rules = [*agent.rules[:routine_rules], *meetings.rules(), interpreter.rule(), *agent.rules[routine_rules:]]
    return interpreter, recorder, meetings


def _interpreting_recognizer(recognizer, language: AssistantLanguage, root: Path):
    """The configured recognizer when it can tell languages apart; otherwise the local faster-whisper model, if it
    has been downloaded (whisper.cpp on a graphics card and the hosted APIs are told the language)."""
    from bilge.voice import models
    from bilge.voice.recognizers import GuardedRecognizer, WhisperRecognizer, detects_language, has_cuda

    if detects_language(recognizer):
        return recognizer
    if not Downloader(root).is_downloaded(models.WHISPER_TURBO):
        return None
    device = "cuda" if has_cuda() else "cpu"
    return GuardedRecognizer(WhisperRecognizer(str(root / models.WHISPER_TURBO.name), language, device=device))


def _making_way(player: "MediaPlayer", on_event):
    """The radio is turned down (and a podcast waits) from the wake word until Bilge has answered; it stops when
    listening is turned off, since the speaker stops with it."""

    def handle(kind: str, text: str) -> None:
        if kind == "status":
            if text == "off":
                player.stop()
            player.set_busy(text not in ("listening", "off"))
        if on_event is not None:
            on_event(kind, text)

    return handle


def _recognizer(voice: config.VoiceSettings, language: AssistantLanguage, root: Path):
    from bilge.voice import models, placement
    from bilge.voice.recognizers import TRANSCRIPTION_PRESETS, APIRecognizer, WhisperRecognizer
    from bilge.voice.whisper_cpp import WhisperServer, WhisperServerError, server_program

    if voice.recognizer in TRANSCRIPTION_PRESETS:
        base_url, default_model = TRANSCRIPTION_PRESETS[voice.recognizer]
        key = config.api_key(voice.recognizer)
        if not key:
            raise ProviderError(f"Speech recognition through {voice.recognizer} needs an API key.")
        return APIRecognizer(base_url, key, voice.recognizer_model or default_model, language)
    if voice.recognizer != "local":
        raise ProviderError(f"Unknown speech recognizer: {voice.recognizer}")
    chosen = placement.choose(voice.accelerator)
    program = server_program()
    if chosen.where is placement.Where.VULKAN and program is not None:
        model = root / models.WHISPER_TURBO_GGML.name / models.WHISPER_TURBO_GGML_FILE
        server = WhisperServer(program, model, language, chosen.gpu, hint="Bilge",
                               pid_file=config.data_dir() / "whisper-server.pid")  # fmt: skip
        try:
            server.start()
        except WhisperServerError as error:
            raise ProviderError(
                f"Whisper could not start on {chosen.description}: {error}. "
                "Choose the processor under Settings → Recognition."
            ) from error
        return server
    device = "cuda" if chosen.where is placement.Where.CUDA else "cpu"
    return WhisperRecognizer(str(root / models.WHISPER_TURBO.name), language, device=device, hint="Bilge")
