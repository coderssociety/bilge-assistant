from bilge.core.media import playback_state as state
from bilge.core.media.playback_state import Kind, Playback, Source, State

STATION = Source(Kind.RADIO, "TRT FM", "https://trt.example/trtfm")
EPISODE = Source(Kind.EPISODE, "Fularsız Entellik", "https://cdn.example/1.mp3", title="Popülizm")


def test_a_station_is_turned_down_while_bilge_listens_or_speaks():
    playing = state.started(Playback(), STATION)
    assert playing.gain == 1.0 and not playing.holds
    busy = state.busy(playing, True)
    assert busy.gain == state.DUCKED and not busy.holds
    assert state.busy(busy, False).gain == 1.0


def test_an_episode_waits_while_bilge_listens_or_speaks():
    busy = state.busy(state.started(Playback(), EPISODE), True)
    assert busy.gain == 0.0 and busy.holds and busy.connected


def test_pausing_a_station_lets_it_go_and_resuming_tunes_in_again():
    playing = state.started(Playback(), STATION)
    paused = state.paused(playing)
    assert paused.state is State.PAUSED and paused.is_active and not paused.connected
    assert state.disconnects(playing, paused)
    assert state.restarts(paused, state.resumed(paused))


def test_pausing_an_episode_keeps_it_open_in_place():
    playing = state.started(Playback(), EPISODE)
    paused = state.paused(playing)
    assert paused.connected and paused.holds and paused.gain == 0.0
    assert not state.disconnects(playing, paused)
    assert not state.restarts(paused, state.resumed(paused))


def test_stopping_keeps_the_source_but_nothing_plays():
    stopped = state.stopped(state.started(Playback(), STATION))
    assert stopped.source == STATION and not stopped.is_active and stopped.gain == 0.0
    assert state.paused(stopped) == stopped and state.resumed(stopped) == stopped


def test_a_new_source_restarts_the_stream():
    playing = state.started(Playback(), STATION)
    assert state.restarts(playing, state.started(playing, EPISODE))


def test_volume_moves_in_steps_within_its_bounds():
    playback = state.started(Playback(), STATION)
    assert state.louder(playback).volume == 1.0
    quiet = playback
    for _ in range(10):
        quiet = state.quieter(quiet)
    assert quiet.volume == state.MIN_VOLUME
    assert state.quieter(playback).gain == 0.8
