import pytest

from bilge.core.media.music_request import MusicRequest, chosen_service, parse
from bilge.core.media.music_request import MusicService as S


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("YouTube'da Tarkan aç", MusicRequest("Tarkan", S.YOUTUBE)),
        ("youtubeda tarkan aç", MusicRequest("tarkan", S.YOUTUBE)),
        ("You Tube'da Kuzu Kuzu'yu çal", MusicRequest("Kuzu Kuzu", S.YOUTUBE)),
        ("YouTube Music'te Sezen Aksu çal", MusicRequest("Sezen Aksu", S.YOUTUBE_MUSIC)),
        ("YouTube Müzik'ten Sezen Aksu çalar mısın", MusicRequest("Sezen Aksu", S.YOUTUBE_MUSIC)),
        ("Deezer'da Kuzu Kuzu çal", MusicRequest("Kuzu Kuzu", S.DEEZER)),
        ("Spotify'da Tarkan'ın şarkılarını çal", MusicRequest("Tarkan", S.SPOTIFY)),
        ("Kuzu Kuzu'yu Spotify'dan çal", MusicRequest("Kuzu Kuzu", S.SPOTIFY)),
        ("Bilge, Apple Music'te Tarkan çal lütfen", MusicRequest("Tarkan", S.APPLE_MUSIC)),
        ("Spotify üzerinden Şımarık çal", MusicRequest("Şımarık", S.SPOTIFY)),
        ("YouTube'da bir Barış Manço şarkısı aç", MusicRequest("Barış Manço", S.YOUTUBE)),
        ("play Tarkan on YouTube", MusicRequest("Tarkan", S.YOUTUBE)),
        ("play Kuzu Kuzu on YouTube Music", MusicRequest("Kuzu Kuzu", S.YOUTUBE_MUSIC)),
        ("can you play some Sezen Aksu on Deezer", MusicRequest("Sezen Aksu", S.DEEZER)),
        ("put on Kuzu Kuzu in Apple Music", MusicRequest("Kuzu Kuzu", S.APPLE_MUSIC)),
        ("listen to Tarkan on Spotify", MusicRequest("Tarkan", S.SPOTIFY)),
    ],
)
def test_a_song_asked_for_on_a_named_service(command, expected):
    assert parse(command) == expected


@pytest.mark.parametrize(
    "command",
    [
        # The service itself is what is opened.
        "YouTube'u aç",
        "YouTube'u açar mısın",
        "Spotify'ı aç",
        "open YouTube",
        "open Spotify",
        # Nothing named to play.
        "Spotify'da müzik çal",
        "YouTube'da bir video aç",
        "play something on Deezer",
        # No service named: the usual music tool, or the model.
        "Tarkan çal",
        "play Tarkan",
        "YouTube'da ne var",
    ],
)
def test_not_a_song_on_a_service(command):
    assert parse(command) is None


def test_the_service_said_wins_then_the_setting_then_spotify_if_installed():
    assert chosen_service("deezer", "youtube", lambda: True) is S.DEEZER
    assert chosen_service(None, "apple_music", lambda: True) is S.APPLE_MUSIC
    assert chosen_service(None, "auto", lambda: True) is S.SPOTIFY
    assert chosen_service(None, "auto", lambda: False) is S.YOUTUBE_MUSIC
    assert chosen_service("napster", "something old", lambda: False) is S.YOUTUBE_MUSIC


def test_installed_apps_are_looked_at_only_for_auto():
    def never():
        raise AssertionError("asked")

    assert chosen_service("youtube", "auto", never) is S.YOUTUBE
