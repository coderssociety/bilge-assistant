"""The music and playback tools reach Bilge's own radio and podcast player first while it has something loaded."""

import pytest

from bilge.brain import fast_path
from bilge.brain.routing import rule
from bilge.core.language import AssistantLanguage
from bilge.core.media.playback_state import Kind, Source, State
from bilge.desktop.base import MediaCommand, NowPlaying
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import podcasts, radio
from bilge.tools.desktop import playback, sound, sources
from bilge.tools.player import PlaybackError

from .fake_player import FakePlayer

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
STATION = Source(Kind.RADIO, "Power FM", "https://power.example/live.m3u8", True)
EPISODE = Source(Kind.EPISODE, "Fularsız Entellik", "https://cdn.example/1.mp3", title="Popülizm")


SONG = NowPlaying("Spotify", True, "Gülümse")
PAUSED_SONG = NowPlaying("Spotify", False, "Gülümse")


class FakeMedia:
    """The desktop player; `now` is None when no player is open."""

    def __init__(self, now=SONG):
        self.now = now
        self.sent = []

    def now_playing(self):
        return self.now

    def send(self, command):
        self.sent.append(command)
        return "Spotify"

    def seek(self, seconds):
        self.sent.append(("seek", seconds))
        return "Spotify"

    def restart_track(self):
        self.sent.append("restart")
        return "Spotify"


def playing(source):
    player = FakePlayer()
    player.play(source)
    return player


def test_durdur_stops_the_radio_and_devam_et_tunes_in_again():
    media, player = FakeMedia(None), playing(STATION)
    music = sound.music_tool(media, TR, player=player)
    assert music.run({"action": "pause"}) == "Power FM kapatıldı."
    assert player.playback.state is State.PAUSED
    assert music.run({"action": "play"}) == "Power FM devam ediyor."
    assert player.playback.is_playing and media.sent == []


def test_an_episode_pauses_and_says_its_title_when_asked():
    player = playing(EPISODE)
    music = sound.music_tool(FakeMedia(None), EN, player=player)
    assert music.run({"action": "nowPlaying"}) == "Playing Fularsız Entellik: Popülizm"
    assert music.run({"action": "toggle"}) == "Fularsız Entellik is paused."
    assert music.run({"action": "toggle"}) == "Fularsız Entellik is playing again."


def test_skipping_tracks_is_not_possible_in_a_station():
    music = sound.music_tool(FakeMedia(), TR, player=playing(STATION))
    assert music.run({"action": "next"}) == "Bunda parça atlanamıyor; başka bir istasyon ya da bölüm isteyebilirsin."


def test_with_nothing_of_its_own_playing_the_desktop_player_is_used():
    media = FakeMedia()
    stopped = playing(STATION)
    stopped.stop()
    assert sound.music_tool(media, TR, player=stopped).run({"action": "pause"}) == "Spotify duraklatıldı."
    assert media.sent == [MediaCommand.PAUSE]


def test_a_paused_station_is_left_alone_by_another_durdur():
    media, player = FakeMedia(), playing(STATION)
    player.pause()
    sound.music_tool(media, TR, player=player).run({"action": "pause"})
    assert media.sent == [MediaCommand.PAUSE]


def test_a_station_that_will_not_come_back_is_said():
    player = playing(STATION)
    player.pause()

    def fail():
        raise PlaybackError(web_fetch.WebFetchError(web_fetch.Reason.CONNECT))

    player.resume = fail
    with pytest.raises(ToolError, match="Power FM yeniden açılamadı. Sunucuya bağlanamadım."):
        sound.music_tool(FakeMedia(None), TR, player=player).run({"action": "play"})


def test_seeking_moves_the_episode_and_not_the_desktop_player():
    media, player = FakeMedia(), playing(EPISODE)
    seek = playback.playback_tool(media, TR, player)
    assert seek.run({"action": "seek", "seconds": 30}) == "Bölüm 30 saniye ileri sarıldı."
    assert seek.run({"action": "seek", "seconds": -10}) == "Bölüm 10 saniye geri sarıldı."
    assert seek.run({"action": "restartTrack"}) == "Bölüm baştan başladı."
    assert player.sought == [30, -10, -12.0] and media.sent == []


def test_a_seek_beyond_either_end_of_the_episode_says_where_it_stopped():
    player = FakePlayer(duration=40.0)
    player.play(EPISODE)
    seek = playback.playback_tool(FakeMedia(None), TR, player)
    assert seek.run({"action": "seek", "seconds": 300}) == "Bölüm o kadar uzun değil; son saniyelerine sarıldı."
    assert seek.run({"action": "seek", "seconds": -90}) == "Bölüm baştan başladı."


def test_a_live_station_cannot_be_sought():
    seek = playback.playback_tool(FakeMedia(), TR, playing(STATION))
    assert seek.run({"action": "seek", "seconds": 30}) == "Canlı yayında ileri ya da geri saramam."


def test_shuffle_with_the_radio_on_still_reaches_the_desktop_player():
    media = FakeMedia()
    media.set_shuffle = lambda on: media.sent.append(("shuffle", on)) or "Spotify"
    playback.playback_tool(media, TR, playing(STATION)).run({"action": "shuffleOn"})
    assert media.sent == [("shuffle", True)]


def test_a_song_paused_in_the_desktop_player_since_is_what_devam_et_resumes():
    media, player = FakeMedia(None), playing(STATION)
    music = sound.music_tool(media, TR, player=player)
    music.run({"action": "pause"})
    media.now = PAUSED_SONG
    assert music.run({"action": "play"}) == "Spotify çalıyor."
    assert media.sent == [MediaCommand.PLAY] and player.resumed == 0


def test_a_paused_episode_does_not_take_a_seek_meant_for_the_desktop_song():
    media, player = FakeMedia(PAUSED_SONG), playing(EPISODE)
    player.pause()
    assert playback.playback_tool(media, TR, player).run({"action": "seek", "seconds": -30}) == (
        "Spotify 30 saniye geri sarıldı."
    )
    assert media.sent == [("seek", -30)] and player.sought == []


def test_a_paused_station_has_nothing_to_seek_in():
    media, player = FakeMedia(None), playing(STATION)
    player.pause()
    assert playback.playback_tool(media, TR, player).run({"action": "seek"}) == "Açık bir müzik çalar bulamadım."


def test_an_unknown_action_is_refused_and_never_starts_a_paused_player():
    media, player = FakeMedia(None), playing(EPISODE)
    player.pause()
    with pytest.raises(ToolError, match="yapamıyorum"):
        sound.music_tool(media, TR, player=player).run({"action": "stop"})
    assert player.playback.state is State.PAUSED and player.resumed == 0 and media.sent == []


def test_muzigi_ac_with_the_radio_on_turns_to_the_waiting_song_and_lets_the_station_go():
    media, player = FakeMedia(PAUSED_SONG), playing(STATION)
    assert sound.music_tool(media, TR, player=player).run({"action": "play"}) == "Spotify çalıyor."
    assert media.sent == [MediaCommand.PLAY] and player.playback.state is State.STOPPED


def test_muzigi_ac_with_the_radio_on_and_no_song_waiting_says_it_already_plays():
    media, player = FakeMedia(None), playing(STATION)
    assert sound.music_tool(media, TR, player=player).run({"action": "play"}) == "Power FM zaten çalıyor."
    assert player.playback.is_playing


def test_the_station_starting_pauses_the_desktop_song_only_once_it_plays():
    media = FakeMedia()
    radio_player = sources.TurnTakingPlayer(FakePlayer(), media)
    radio_player.play(STATION)
    assert media.sent == [MediaCommand.PAUSE]
    media.sent.clear()
    broken = sources.TurnTakingPlayer(FakePlayer(error=PlaybackError()), media)
    with pytest.raises(PlaybackError):
        broken.play(STATION)
    assert media.sent == []


def test_a_named_song_lets_the_station_go_and_pauses_an_episode():
    class Launcher:
        def has_app(self, service):
            return False

        def open(self, address):
            pass

    for source, after in ((STATION, State.STOPPED), (EPISODE, State.PAUSED)):
        player = playing(source)
        search = sound.music_search_tool(Launcher(), TR, lambda: "youtube", lambda *_: [], player=player)
        search.run({"query": "Tarkan"})
        assert player.playback.state is after


@pytest.mark.parametrize(
    ("command", "name"),
    [
        ("Power FM aç", "radio"),
        ("radyonun sesini kıs", "radio"),
        ("radyoyu kapat", "radio"),
        ("hangi radyo çalıyor", "radio"),
        ("Fularsız Entellik podcastinin son bölümünü aç", "podcast"),
        ("Nasıl Olunur'un yeni bölümü var mı", "podcast"),
    ],
)
def test_radio_and_podcast_rules_claim_their_commands_before_the_fast_path(command, name):
    rules = [
        rule("radio", radio.claims, radio.rule_arguments),
        rule("podcast", podcasts.claims, podcasts.rule_arguments),
    ]
    claimed = [call for route in rules if (call := route(command)) is not None]
    assert [call.name for call in claimed] == [name]


def test_durdur_and_seeking_still_go_through_the_fast_path_to_the_media_tools():
    assert fast_path.call_for("müziği durdur", TR).name == "controlMusic"
    assert fast_path.call_for("30 saniye ileri sar", TR).arguments == {"action": "seek", "seconds": 30}
    assert not radio.claims("müziği durdur") and not podcasts.claims("30 saniye ileri sar")
