import json

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.media.playback_state import Kind, Source
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import radio
from bilge.tools.player import PlaybackError

from .fake_player import FakePlayer

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
POWER = [
    {"name": "Power FM Türkiye", "url_resolved": "https://listen.example/powerfm/chunks.m3u8", "codec": "UNKNOWN",
     "votes": 950, "hls": 1, "lastcheckok": 1},
]  # fmt: skip
TRT = [{"name": "TRT FM", "url_resolved": "https://trt.example/trtfm", "codec": "AAC+", "votes": 1162, "hls": 0}]


def fake_search(monkeypatch, answers, asked):
    """`answers` maps a searched name (with or without the country) to a list of stations or an error."""

    def get_json(url, language, user_agent=""):
        asked.append(url)
        for key, answer in answers.items():
            if key in url:
                if isinstance(answer, Exception):
                    raise answer
                return answer
        return []

    monkeypatch.setattr(radio, "get_json", get_json)


def tool(player, tmp_path=None, language=TR):
    memory = radio.StationMemory(tmp_path / "radio.json" if tmp_path else None)
    return radio.radio_tool(language, player, memory)


def test_a_named_station_is_found_and_played(monkeypatch, tmp_path):
    asked = []
    fake_search(monkeypatch, {"name=Power+FM": POWER}, asked)
    player = FakePlayer()
    assert tool(player, tmp_path).run({"action": "play", "station": "Power FM"}) == "Power FM açıldı."
    assert player.played == [Source(Kind.RADIO, "Power FM", "https://listen.example/powerfm/chunks.m3u8", True)]
    assert asked[0].startswith("https://de1.api.radio-browser.info/json/stations/search?")
    assert "countrycode=TR" in asked[0]
    assert json.loads((tmp_path / "radio.json").read_text(encoding="utf-8")) == {"station": "Power FM"}


def test_radyo_ac_plays_the_last_station_and_trt_fm_the_first_time(monkeypatch, tmp_path):
    fake_search(monkeypatch, {"name=Power+FM": POWER, "name=TRT+FM": TRT}, [])
    (tmp_path / "radio.json").write_text('{"station": "Power FM"}', encoding="utf-8")
    remembered = FakePlayer()
    tool(remembered, tmp_path).run({"action": "play"})
    assert remembered.played[0].name == "Power FM"
    first_time = FakePlayer()
    tool(first_time).run({"action": "play"})
    assert first_time.played[0].name == "TRT FM"


def test_the_next_mirror_is_asked_when_one_fails(monkeypatch):
    asked = []
    error = web_fetch.WebFetchError(web_fetch.Reason.CONNECT)

    def get_json(url, language, user_agent=""):
        asked.append(url)
        if url.startswith(radio.HOSTS[0]):
            raise error
        return TRT

    monkeypatch.setattr(radio, "get_json", get_json)
    tool(FakePlayer()).run({"action": "play", "station": "TRT FM"})
    assert [url.split("/json")[0] for url in asked] == list(radio.HOSTS[:2])


def test_when_every_mirror_fails_it_says_so(monkeypatch):
    fake_search(monkeypatch, {"": web_fetch.WebFetchError(web_fetch.Reason.NOT_FOUND)}, [])
    with pytest.raises(ToolError, match="Radyo listesine ulaşamadım. Adresi bulamadım"):
        tool(FakePlayer()).run({"action": "play", "station": "TRT FM"})


def test_an_unknown_station_is_looked_for_abroad_then_said_as_unknown(monkeypatch):
    asked = []
    fake_search(monkeypatch, {}, asked)
    with pytest.raises(ToolError, match="'Uydurma FM' adında bir radyo istasyonu bulamadım."):
        tool(FakePlayer()).run({"action": "play", "station": "Uydurma FM"})
    assert ["countrycode=TR" in url for url in asked] == [True, False]


def test_a_stream_that_will_not_start_is_said(monkeypatch):
    fake_search(monkeypatch, {"name=TRT+FM": TRT}, [])
    player = FakePlayer(error=PlaybackError(web_fetch.WebFetchError(web_fetch.Reason.TOO_SLOW)))
    with pytest.raises(ToolError, match="TRT FM yayınına bağlanamadım. Sayfa çok geç yanıt verdi."):
        tool(player).run({"action": "play", "station": "TRT FM"})


def test_stop_volume_and_what_is_on():
    player = FakePlayer()
    radio_tool = tool(player, language=EN)
    assert radio_tool.run({"action": "stop"}) == "The radio isn't on."
    player.play(Source(Kind.RADIO, "TRT FM", "https://trt.example/trtfm"))
    assert radio_tool.run({"action": "nowPlaying"}) == "TRT FM is on."
    assert radio_tool.run({"action": "louder"}) == "The radio is already as loud as it goes."
    assert radio_tool.run({"action": "quieter"}) == "The radio is at 80 percent."
    assert radio_tool.run({"action": "stop"}) == "The radio is off."
    assert not player.playback.is_active


def test_an_episode_playing_is_not_the_radio():
    player = FakePlayer()
    player.play(Source(Kind.EPISODE, "Fularsız Entellik", "https://cdn.example/1.mp3"))
    assert tool(player).run({"action": "nowPlaying"}) == "Şu an radyo çalmıyor."


def test_the_command_said_wins_over_the_models_arguments():
    radio_tool = tool(FakePlayer())
    assert radio_tool.refine({"action": "play", "station": "Kral"}, "TRT FM çal") == {
        "action": "play",
        "station": "TRT FM",
    }
    assert radio_tool.refine({"action": "quieter"}, "radyonun sesini kıs") == {"action": "quieter"}
    assert radio_tool.refine({"action": "play", "station": "X"}, "biraz müzik olsa") == {
        "action": "play",
        "station": "X",
    }


def test_a_broken_memory_file_means_no_station_yet(tmp_path):
    (tmp_path / "radio.json").write_text("[1, 2", encoding="utf-8")
    assert radio.StationMemory(tmp_path / "radio.json").last is None


def test_another_listing_of_the_station_is_tried_when_one_will_not_start(monkeypatch):
    listings = [
        {"name": "Radyo Fenomen", "url_resolved": "https://broken-chain.example/fenomen", "codec": "AAC+", "votes": 9},
        {"name": "Radyo Fenomen", "url_resolved": "http://plain.example/fenomen", "codec": "AAC+", "votes": 5},
        {"name": "Radyo Fenomen Clubbin", "url_resolved": "https://other.example/clubbin", "votes": 900},
    ]
    fake_search(monkeypatch, {"name=Radyo+Fenomen": listings}, [])
    tried = []

    class FlakyPlayer(FakePlayer):
        def play(self, source):
            tried.append(source.url)
            if "broken" in source.url:
                raise PlaybackError(web_fetch.WebFetchError(web_fetch.Reason.CONNECT))
            super().play(source)

    assert tool(FlakyPlayer()).run({"action": "play", "station": "Radyo Fenomen"}) == "Radyo Fenomen açıldı."
    assert tried == ["https://broken-chain.example/fenomen", "http://plain.example/fenomen"]


def test_a_cautioned_step_is_asked_in_plain_words():
    radio_tool = tool(FakePlayer())
    assert radio_tool.generic_question({"action": "stop"}) == "Radyoyu kapatayım mı?"
    assert radio_tool.generic_question({"action": "play", "station": "Power FM"}) == "Power FM açayım mı?"
    assert radio_tool.generic_question({"action": "play"}) == "TRT FM açayım mı?"
