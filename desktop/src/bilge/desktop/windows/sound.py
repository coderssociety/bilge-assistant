"""The default speaker's volume (Core Audio through pycaw) and the playing media (the media controls Windows shows
over the volume flyout, which Spotify, browsers and most players report to)."""

import asyncio
from datetime import UTC, datetime, timedelta

from bilge.desktop.base import AppEntry, Apps, MediaCommand, NowPlaying, RepeatMode, VolumeState
from bilge.desktop.music import is_spotify
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere
from bilge.desktop.windows import com


def _endpoint():
    try:
        from pycaw.pycaw import AudioUtilities
    except ImportError as error:
        raise MissingProgram("pycaw") from error
    speakers = AudioUtilities.GetSpeakers()
    if speakers is None:
        raise DesktopError("No speaker")
    volume = getattr(speakers, "EndpointVolume", None)
    if volume is not None:
        return volume
    # pycaw before 2024 hands back the raw device.
    from ctypes import POINTER, cast

    from comtypes import CLSCTX_ALL
    from pycaw.pycaw import IAudioEndpointVolume

    return cast(speakers.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None), POINTER(IAudioEndpointVolume))


class WindowsVolume:
    def _call(self, action):
        try:
            return com.call(_endpoint, action, keep=(DesktopError,))
        except com.ComFailure as error:
            # No sound output device, or the audio service stopped.
            raise DesktopError(f"Core Audio: {error}") from None

    def state(self) -> VolumeState:
        return self._call(lambda volume: VolumeState(round(volume.GetMasterVolumeLevelScalar() * 100),
                                                     bool(volume.GetMute())))  # fmt: skip

    def set_level(self, level: int) -> None:
        def change(volume) -> None:
            volume.SetMute(0, None)
            volume.SetMasterVolumeLevelScalar(max(0, min(100, level)) / 100, None)

        self._call(change)

    def set_muted(self, muted: bool) -> None:
        self._call(lambda volume: volume.SetMute(1 if muted else 0, None))


_PLAYING = 4
_METHODS = {
    MediaCommand.PLAY: "try_play_async",
    MediaCommand.PAUSE: "try_pause_async",
    MediaCommand.TOGGLE: "try_toggle_play_pause_async",
    MediaCommand.NEXT: "try_skip_next_async",
    MediaCommand.PREVIOUS: "try_skip_previous_async",
}
# MediaPlaybackAutoRepeatMode: None, Track, List.
_REPEAT = {RepeatMode.OFF: 0, RepeatMode.TRACK: 1, RepeatMode.ALL: 2}
_TICKS_PER_SECOND = 10_000_000


def player_name(app_id: str) -> str:
    """ "Spotify.exe" → "Spotify"; "Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic" → "ZuneMusic";
    "MSEdge" → "MSEdge"."""
    name = app_id.split("!", 1)[-1].rsplit("\\", 1)[-1]
    name = name.removesuffix(".exe").removesuffix(".EXE")
    return name.rsplit(".", 1)[-1] if "." in name else name


class WindowsMedia:
    def __init__(self, sessions=None):
        # For tests: a function returning the media sessions.
        self._sessions = sessions

    async def _all(self) -> list:
        if self._sessions is not None:
            return list(self._sessions())
        try:
            from winrt.windows.media.control import GlobalSystemMediaTransportControlsSessionManager as Manager
        except ImportError as error:
            raise MissingProgram("winrt-Windows.Media.Control") from error
        manager = await Manager.request_async()
        return list(manager.get_sessions())

    async def _choose(self):
        sessions = await self._all()
        playing = [s for s in sessions if int(s.get_playback_info().playback_status) == _PLAYING]
        return (playing or sessions or [None])[0]

    def _run(self, coroutine):
        try:
            return asyncio.run(coroutine)
        except (OSError, RuntimeError) as error:
            raise DesktopError(f"Media controls: {error}") from error

    def now_playing(self) -> NowPlaying | None:
        async def read() -> NowPlaying | None:
            session = await self._choose()
            if session is None:
                return None
            properties = await session.try_get_media_properties_async()
            playing = int(session.get_playback_info().playback_status) == _PLAYING
            return NowPlaying(player_name(session.source_app_user_model_id), playing, properties.title or "",
                              properties.artist or "")  # fmt: skip

        return self._run(read())

    def send(self, command: MediaCommand) -> str:
        async def act() -> str:
            session = await self._choose()
            if session is None:
                raise DesktopError("No media session")
            if not await getattr(session, _METHODS[command])():
                raise DesktopError(f"The player refused {command}")
            return player_name(session.source_app_user_model_id)

        return self._run(act())

    def seek(self, seconds: float) -> str:
        async def act(session) -> bool:
            timeline = session.get_timeline_properties()
            start, end = _seconds(timeline.start_time), _seconds(timeline.end_time)
            target = _current_position(session, timeline) + seconds
            target = max(start, min(target, end)) if end > start else max(start, target)
            return await session.try_change_playback_position_async(round(target * _TICKS_PER_SECOND))

        return self._control("is_playback_position_enabled", act)

    def restart_track(self) -> str:
        async def act(session) -> bool:
            start = _seconds(session.get_timeline_properties().start_time)
            return await session.try_change_playback_position_async(round(start * _TICKS_PER_SECOND))

        return self._control("is_playback_position_enabled", act)

    def set_shuffle(self, on: bool) -> str:
        return self._control("is_shuffle_enabled", lambda session: session.try_change_shuffle_active_async(on))

    def set_repeat(self, mode: RepeatMode) -> str:
        # pywinrt takes the enum's number, which spares a dependency on the Windows.Media projection.
        return self._control("is_repeat_enabled",
                             lambda session: session.try_change_auto_repeat_mode_async(_REPEAT[mode]))  # fmt: skip

    def _control(self, ability: str, act) -> str:
        """`ability` names the playback control the player must offer; `act` returns the player's answer."""

        async def run() -> str:
            session = await self._choose()
            if session is None:
                raise DesktopError("No media session")
            name = player_name(session.source_app_user_model_id)
            if not getattr(session.get_playback_info().controls, ability):
                raise NotPossibleHere(f"{name} doesn't offer {ability}")
            if not await act(session):
                raise DesktopError(f"{name} refused the change")
            return name

        return self._run(run())


def _seconds(value) -> float:
    """WinRT time spans arrive as timedelta, or as 100-nanosecond ticks from older projections."""
    if isinstance(value, timedelta):
        return value.total_seconds()
    return int(value or 0) / _TICKS_PER_SECOND


def _current_position(session, timeline) -> float:
    """The timeline is only updated now and then; while playing, the time since then is added, unless that runs past
    the end (a player that never updates it), where seeking from there would skip the track."""
    position = _seconds(timeline.position)
    updated = getattr(timeline, "last_updated_time", None)
    if int(session.get_playback_info().playback_status) != _PLAYING or not isinstance(updated, datetime):
        return position
    moment = updated if updated.tzinfo else updated.replace(tzinfo=UTC)
    estimate = position + max(0.0, (datetime.now(UTC) - moment).total_seconds())
    end = _seconds(timeline.end_time)
    return position if end > 0 and estimate > end else estimate


# The Media Player app of Windows 11 (formerly Groove), then the classic Windows Media Player.
_MEDIA_PLAYER_IDS = ("microsoft.zunemusic", "microsoft.windows.mediaplayer32")


def installed_players(apps: Apps) -> list[AppEntry]:
    """Spotify when installed, otherwise the Media Player that comes with Windows."""
    entries = apps.installed()
    spotify = [entry for entry in entries if is_spotify(entry)]
    builtin = sorted(
        (entry for entry in entries if any(part in entry.id.lower() for part in _MEDIA_PLAYER_IDS)),
        key=lambda entry: next(i for i, part in enumerate(_MEDIA_PLAYER_IDS) if part in entry.id.lower()),
    )
    return spotify + builtin
