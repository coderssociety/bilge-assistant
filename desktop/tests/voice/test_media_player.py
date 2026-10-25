import threading
import time

import numpy as np
import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.media.playback_state import DUCKED, Kind, Source, State
from bilge.tools import web_fetch
from bilge.tools.player import PlaybackError
from bilge.voice.audio_io import BackgroundBuffer
from bilge.voice.media_player import END_MARGIN_SECONDS, MediaPlayer

RATE = 1000
STATION = Source(Kind.RADIO, "TRT FM", "https://trt.example/trtfm")
EPISODE = Source(Kind.EPISODE, "Fularsız Entellik", "https://cdn.example/1.mp3", title="Popülizm")


class FakeSink:
    sample_rate = RATE

    def __init__(self):
        self.background = BackgroundBuffer()


class FakeDecoder:
    """Endless blocks of 0.1 s of ones (a station), or `length` seconds of them (an episode)."""

    def __init__(self, length=None):
        self.length = length
        self.duration = length
        self.time = 0.0
        self.sought = []
        self.closed = threading.Event()

    def blocks(self):
        while not self.closed.is_set() and (self.length is None or self.time < self.length):
            self.time += 0.1
            yield np.ones(RATE // 10, dtype=np.float32), self.time

    def seek(self, seconds):
        self.sought.append(seconds)
        self.time = seconds

    def close(self):
        self.closed.set()


class Opener:
    def __init__(self, length=None, error=None):
        self.length = length
        self.error = error
        self.decoders = []

    def __call__(self, source, rate, stopped):
        if self.error is not None:
            raise self.error
        self.decoders.append(FakeDecoder(self.length))
        return self.decoders[-1]


def wait_for(condition, seconds=2.0):
    deadline = time.monotonic() + seconds
    while not condition() and time.monotonic() < deadline:
        time.sleep(0.01)
    return condition()


@pytest.fixture
def sink():
    return FakeSink()


def player_with(sink, opener):
    return MediaPlayer(AssistantLanguage.TURKISH, sink, opener, start_timeout=2)


def test_a_station_plays_into_the_shared_output_and_is_turned_down_while_bilge_is_busy(sink):
    player = player_with(sink, Opener())
    player.play(STATION)
    assert wait_for(lambda: sink.background.queued > 0)
    assert sink.background.take(10)[-1] == pytest.approx(1.0)
    player.set_busy(True)
    assert sink.background.take(10)[-1] == pytest.approx(DUCKED)
    player.set_busy(False)
    assert sink.background.take(10)[-1] == pytest.approx(1.0)
    player.stop()


def test_decoding_stays_only_a_few_seconds_ahead(sink):
    player = player_with(sink, Opener())
    player.play(STATION)
    time.sleep(0.3)
    assert sink.background.queued <= 3.2 * RATE
    player.stop()


def test_an_episode_waits_while_bilge_is_busy_and_goes_on_from_the_same_place(sink):
    player = player_with(sink, Opener(length=60))
    player.play(EPISODE)
    assert wait_for(lambda: sink.background.queued > 3 * RATE)
    player.set_busy(True)
    queued = sink.background.queued
    assert not sink.background.take(50).any()
    assert sink.background.queued == queued
    player.set_busy(False)
    assert sink.background.take(50)[-1] == pytest.approx(1.0)
    player.stop()


def test_pausing_a_station_lets_go_of_it_and_resuming_tunes_in_again(sink):
    opener = Opener()
    player = player_with(sink, opener)
    player.play(STATION)
    player.pause()
    assert player.playback.state is State.PAUSED
    assert opener.decoders[0].closed.is_set() and sink.background.queued == 0
    player.resume()
    assert len(opener.decoders) == 2 and player.playback.is_playing
    player.stop()
    assert opener.decoders[1].closed.is_set() and player.playback.state is State.STOPPED


def test_an_episode_is_sought_from_where_the_speaker_is(sink):
    opener = Opener(length=600)
    player = player_with(sink, opener)
    player.play(EPISODE)
    assert wait_for(lambda: sink.background.queued >= 3 * RATE)
    position = player.position
    target = player.seek(30)
    assert target == pytest.approx(position + 30, abs=0.2)
    assert wait_for(lambda: opener.decoders[0].sought == [target])
    assert wait_for(lambda: player.position >= target)
    player.stop()


def test_going_back_in_the_last_seconds_still_works_after_decoding_finished(sink):
    opener = Opener(length=2)
    player = player_with(sink, opener)
    player.play(EPISODE)
    assert wait_for(lambda: opener.decoders[0].time >= 2 and sink.background.queued == 2 * RATE)
    sink.background.take(RATE + RATE // 2)
    assert player.seek(-1) == pytest.approx(0.5)
    assert wait_for(lambda: opener.decoders[0].sought == [pytest.approx(0.5)])
    assert wait_for(lambda: sink.background.queued > RATE)
    assert player.playback.is_playing
    player.stop()


def test_a_seek_past_the_end_lands_just_before_it(sink):
    opener = Opener(length=60)
    player = player_with(sink, opener)
    player.play(EPISODE)
    assert player.seek(120) == pytest.approx(60 - END_MARGIN_SECONDS)
    assert wait_for(lambda: opener.decoders[0].sought == [pytest.approx(60 - END_MARGIN_SECONDS)])
    assert player.playback.is_playing
    player.stop()


def test_a_live_station_cannot_be_sought(sink):
    player = player_with(sink, Opener())
    player.play(STATION)
    assert player.seek(30) is None
    player.stop()


def test_a_stream_that_cannot_be_reached_is_reported_and_nothing_plays(sink):
    player = player_with(sink, Opener(error=web_fetch.WebFetchError(web_fetch.Reason.CONNECT)))
    with pytest.raises(PlaybackError) as raised:
        player.play(STATION)
    assert raised.value.fetch.reason is web_fetch.Reason.CONNECT
    assert player.playback.state is State.STOPPED


def test_audio_that_cannot_be_decoded_is_reported(sink):
    player = player_with(sink, Opener(error=ValueError("no audio stream")))
    with pytest.raises(PlaybackError) as raised:
        player.play(STATION)
    assert raised.value.fetch is None


def test_an_episode_played_to_its_end_stops(sink):
    player = player_with(sink, Opener(length=0.3))
    player.play(EPISODE)
    while sink.background.queued:
        sink.background.take(100)
    assert wait_for(lambda: player.playback.state is State.STOPPED)


def test_a_new_source_replaces_the_one_playing(sink):
    opener = Opener()
    player = player_with(sink, opener)
    player.play(STATION)
    player.play(Source(Kind.RADIO, "Power FM", "https://power.example/live"))
    assert opener.decoders[0].closed.is_set() and player.playback.source.name == "Power FM"
    player.stop()


def test_the_background_level_changes_smoothly_over_one_block():
    buffer = BackgroundBuffer()
    buffer.add(np.ones(100, dtype=np.float32))
    buffer.set_level(1.0, holding=False)
    ramp = buffer.take(10)
    assert ramp[0] == 0.0 and ramp[-1] == pytest.approx(1.0) and np.all(np.diff(ramp) > 0)
    assert buffer.take(10).tolist() == [1.0] * 10
    assert buffer.queued == 80
