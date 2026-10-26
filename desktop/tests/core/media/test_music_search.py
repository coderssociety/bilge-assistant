from urllib.parse import parse_qs, urlsplit

import pytest

from bilge.core.media import music_search, track_name
from bilge.core.media.music_request import MusicService
from bilge.core.media.music_search import Track

from ...fixtures import web_json


def video(video_id, title, owner="Kanal", **extra):
    return {"videoRenderer": {"videoId": video_id, "title": {"runs": [{"text": title}]},
                              "ownerText": {"runs": [{"text": owner}]}, **extra}}  # fmt: skip


def search_answer(*items):
    section = {"itemSectionRenderer": {"contents": list(items)}}
    return {"contents": {"twoColumnSearchResultsRenderer": {"primaryContents": {
        "sectionListRenderer": {"contents": [section]}}}}}  # fmt: skip


def test_the_first_videos_of_a_youtube_search():
    found = music_search.youtube_videos(web_json("youtube_search_tarkan.json"))
    assert found[0] == Track("TARKAN - Kış Güneşi", "", "https://www.youtube.com/watch?v=-CxauCeQ_SQ")
    assert found[0].spoken == "TARKAN - Kış Güneşi"
    found = music_search.youtube_videos(web_json("youtube_search_kuzu_kuzu.json"))
    assert [track.url for track in found][:2] == [
        "https://www.youtube.com/watch?v=NAHRpEqgcL4",
        "https://www.youtube.com/watch?v=_xgryOIbJj4",
    ]
    assert found[1].spoken == "Tarkan – Kuzu Kuzu"


def test_shorts_live_premieres_ads_and_channels_are_passed_over():
    short = video("AAAAAAAAAAA", "Kısa", navigationEndpoint={"reelWatchEndpoint": {"videoId": "AAAAAAAAAAA"}})
    upcoming = video("BBBBBBBBBBB", "Yakında", upcomingEventData={"startTime": "1"})
    answer = search_answer(
        {"adSlotRenderer": {}},
        {"channelRenderer": {"channelId": "UC1"}},
        {"playlistRenderer": {"playlistId": "PL1"}},
        short,
        upcoming,
        video("not-an-id", "Bozuk"),
        video("CCCCCCCCCCC", "Sezen Aksu - Gidiyorum (Official Audio)", "Sezen Aksu - Topic"),
    )
    assert music_search.youtube_videos(answer) == [
        Track("Sezen Aksu - Gidiyorum", "", "https://www.youtube.com/watch?v=CCCCCCCCCCC")
    ]


@pytest.mark.parametrize("answer", [None, [], {"contents": "x"}, search_answer({"videoRenderer": "x"})])
def test_odd_youtube_answers_give_nothing(answer):
    assert music_search.youtube_videos(answer) == []


def test_the_songs_of_a_youtube_music_search():
    found = music_search.youtube_music_songs(web_json("youtube_music_search_sezen_aksu.json"))
    assert found[0] == Track("Begonvil", "Sezen Aksu", "https://music.youtube.com/watch?v=tAT2nh_Smx0")
    assert found[0].spoken == "Sezen Aksu – Begonvil"
    assert music_search.youtube_music_songs({"contents": {}}) == []


def test_deezer_tracks_that_can_be_played():
    found = music_search.deezer_tracks(web_json("deezer_search_kuzu_kuzu.json"))
    assert found[0] == Track("Kuzu Kuzu", "Tarkan", "https://www.deezer.com/track/16412320")
    assert music_search.deezer_app_url(found[0]) == "deezer://www.deezer.com/track/16412320"
    odd = {"data": [{"id": 1, "title": "Kilitli", "readable": False}, {"id": "2", "title": "Metin"},
                    {"id": True, "title": "Doğru"}, {"type": "album", "id": 3, "title": "Albüm"}, "x"]}  # fmt: skip
    assert music_search.deezer_tracks(odd) == []


def test_apple_music_songs_from_the_itunes_search():
    found = music_search.itunes_tracks(web_json("itunes_search_kuzu_kuzu.json"))
    assert found[0].spoken == "Tarkan – Kuzu Kuzu"
    assert found[0].url.startswith("https://music.apple.com/tr/album/kuzu-kuzu/499333901?i=499334149")
    elsewhere = {"results": [{"kind": "song", "trackName": "X", "trackViewUrl": "https://evil.example/x"},
                             {"kind": "song", "trackName": "Y", "trackViewUrl": "http://music.apple.com/y"},
                             {"kind": "music-video", "trackName": "Z", "trackViewUrl": "https://music.apple.com/z"}]}  # fmt: skip
    assert music_search.itunes_tracks(elsewhere) == []


def test_search_addresses_carry_the_query_encoded():
    assert parse_qs(urlsplit(music_search.deezer_search_url("Kuzu & Kuzu")).query)["q"] == ["Kuzu & Kuzu"]
    itunes = parse_qs(urlsplit(music_search.itunes_search_url("Şımarık", "tr")).query)
    assert itunes["term"] == ["Şımarık"] and itunes["entity"] == ["song"] and itunes["country"] == ["tr"]
    body = music_search.youtube_search_body("Tarkan", "WEB_REMIX", "1.2", "tr", "tr", songs_only=True)
    assert body["context"]["client"]["gl"] == "TR" and body["query"] == "Tarkan" and "params" in body
    assert "params" not in music_search.youtube_search_body("Tarkan", "WEB", "2.2", "tr", "tr")


@pytest.mark.parametrize(
    ("service", "page"),
    [
        (MusicService.YOUTUBE, "https://www.youtube.com/results?search_query=Sezen+Aksu"),
        (MusicService.YOUTUBE_MUSIC, "https://music.youtube.com/search?q=Sezen+Aksu"),
        (MusicService.DEEZER, "https://www.deezer.com/search/Sezen%20Aksu"),
        (MusicService.APPLE_MUSIC, "https://music.apple.com/tr/search?term=Sezen+Aksu"),
        (MusicService.SPOTIFY, "https://open.spotify.com/search/Sezen%20Aksu"),
    ],
)
def test_each_services_search_page(service, page):
    assert music_search.search_page(service, "Sezen Aksu", "tr") == page


def test_spotify_search_in_the_app():
    assert music_search.spotify_search("Tarkan Şımarık") == "spotify:search:Tarkan%20%C5%9E%C4%B1mar%C4%B1k"


@pytest.mark.parametrize(
    ("title", "artist", "expected"),
    [
        ("(3) TARKAN - Kuzu Kuzu (Official Music Video) - YouTube", "TarkanVEVO", ("TARKAN - Kuzu Kuzu", "")),
        ("Begonvil - YouTube Music", "Sezen Aksu", ("Begonvil", "Sezen Aksu")),
        ("Kuzu Kuzu - Deezer", "Tarkan", ("Kuzu Kuzu", "Tarkan")),
        ("Gidiyorum [Sözleri]", "Sezen Aksu - Topic", ("Gidiyorum", "Sezen Aksu")),
        ("Gesi Bağları", "Zeki Müren", ("Gesi Bağları", "Zeki Müren")),
        ("YouTube", "", ("YouTube", "")),
    ],
)
def test_track_names_without_site_and_video_labels(title, artist, expected):
    assert track_name.cleaned(title, artist) == expected
