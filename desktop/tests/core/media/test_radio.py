from urllib.parse import parse_qs

import pytest

from bilge.core.media import radio_stations
from bilge.core.media.radio_request import RadioAction, RadioRequest, parse


def entry(name, url, codec="MP3", votes=10, hls=0, ok=1):
    return {"name": name, "url_resolved": url, "codec": codec, "votes": votes, "hls": hls, "lastcheckok": ok}


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("radyo aç", RadioRequest(RadioAction.PLAY)),
        ("radyoyu açar mısın", RadioRequest(RadioAction.PLAY)),
        ("Power FM aç", RadioRequest(RadioAction.PLAY, "Power FM")),
        ("TRT FM çal", RadioRequest(RadioAction.PLAY, "TRT FM")),
        ("Kral FM'i aç", RadioRequest(RadioAction.PLAY, "Kral FM")),
        ("Virgin Radio'yu aç", RadioRequest(RadioAction.PLAY, "Virgin Radio")),
        ("TRT Radyo 1'i aç", RadioRequest(RadioAction.PLAY, "TRT Radyo 1")),
        ("radyo yediyi aç", RadioRequest(RadioAction.PLAY, "Radyo 7")),
        ("Açık Radyo'yu aç", RadioRequest(RadioAction.PLAY, "Açık Radyo")),
        ("Kafa radyosunu aç", RadioRequest(RadioAction.PLAY, "Kafa radyo")),
        ("Number One FM'i çal", RadioRequest(RadioAction.PLAY, "Number One FM")),
        ("radyoyu kapat", RadioRequest(RadioAction.STOP)),
        ("radyoyu durdur", RadioRequest(RadioAction.STOP)),
        ("radyonun sesini kıs", RadioRequest(RadioAction.QUIETER)),
        ("radyoyu biraz kıs", RadioRequest(RadioAction.QUIETER)),
        ("radyonun sesini aç", RadioRequest(RadioAction.LOUDER)),
        ("radyonun sesini artır", RadioRequest(RadioAction.LOUDER)),
        ("hangi radyo çalıyor", RadioRequest(RadioAction.NOW_PLAYING)),
        ("bu hangi radyo", RadioRequest(RadioAction.NOW_PLAYING)),
        ("play the radio", RadioRequest(RadioAction.PLAY)),
        ("play Power FM", RadioRequest(RadioAction.PLAY, "Power FM")),
        ("turn off the radio", RadioRequest(RadioAction.STOP)),
        ("turn the radio down", RadioRequest(RadioAction.QUIETER)),
        ("turn the radio up", RadioRequest(RadioAction.LOUDER)),
        ("which station is this", RadioRequest(RadioAction.NOW_PLAYING)),
    ],
)
def test_radio_commands(command, expected):
    assert parse(command) == expected


@pytest.mark.parametrize(
    "command", ["müziği durdur", "sesi kıs", "radyo programları neler", "Firefox'u aç", "durdur", "sesi aç"]
)
def test_other_commands_are_not_radio(command):
    assert parse(command) is None


def test_station_names_allow_turkish_endings_but_not_longer_words():
    assert radio_stations.mentioned("Süper FM'i aç").name == "Süper FM"
    assert radio_stations.mentioned("super fm çal").name == "Süper FM"
    assert radio_stations.mentioned("radyo dinle") is None


def test_the_closest_name_wins_then_a_plain_https_stream_then_votes():
    results = [
        entry("Power FM Dance", "https://a.example/dance", votes=9000),
        entry("Power FM", "https://b.example/live.m3u8", codec="AAC", hls=1, votes=500),
        entry("Power FM", "http://c.example/stream", votes=100),
        entry("Power FM", "https://d.example/stream", votes=50),
        entry("Power FM", "https://e.example/stream", votes=40),
    ]
    assert radio_stations.choose(results, "power fm") == radio_stations.Stream("https://d.example/stream", False)


def test_a_playlist_is_taken_when_nothing_else_is_listed():
    results = [entry("Power FM Türkiye", "https://listen.example/powerfm/chunks.m3u8", codec="UNKNOWN", hls=1)]
    assert radio_stations.choose(results, "Power FM") == radio_stations.Stream(
        "https://listen.example/powerfm/chunks.m3u8", True
    )


def test_broken_and_malformed_entries_are_skipped():
    results = [
        entry("TRT FM", "https://broken.example/", ok=0),
        entry("TRT FM", "ftp://odd.example/"),
        entry("TRT FM", "http://[bad"),
        "not a station",
        {"name": "TRT FM"},
        entry("TRT FM", "https://trt.example/trtfm", codec="AAC+", votes="many"),
    ]
    assert radio_stations.choose(results, "TRT FM") == radio_stations.Stream("https://trt.example/trtfm", False)
    assert radio_stations.choose({"error": "x"}, "TRT FM") is None


def test_the_search_asks_for_turkish_stations_by_votes():
    asked = parse_qs(radio_stations.search_query("Kral FM"))
    assert asked["name"] == ["Kral FM"] and asked["countrycode"] == ["TR"] and asked["order"] == ["votes"]
    assert "countrycode" not in parse_qs(radio_stations.search_query("BBC Radio 1", None))


def test_only_listings_of_the_closest_name_are_ranked():
    results = [
        entry("Radyo Fenomen Clubbin", "https://a.example/clubbin", votes=900),
        entry("Radyo Fenomen", "https://b.example/fenomen", votes=5),
        entry("Radyo Fenomen", "http://c.example/fenomen", votes=50),
        entry("Radyo Fenomen", "https://b.example/fenomen", votes=5),
    ]
    assert [stream.url for stream in radio_stations.ranked(results, "Radyo Fenomen")] == [
        "https://b.example/fenomen",
        "http://c.example/fenomen",
    ]
