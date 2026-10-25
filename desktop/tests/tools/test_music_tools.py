import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.media.music_request import MusicService
from bilge.core.media.music_search import Track
from bilge.desktop.process import DesktopError
from bilge.tools import music_lookup, web_fetch
from bilge.tools.base import ToolError
from bilge.tools.desktop import sound

from ..fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
KUZU = Track("Kuzu Kuzu", "Tarkan", "https://www.deezer.com/track/16412320")
VIDEO = Track("TARKAN - Kış Güneşi", "", "https://www.youtube.com/watch?v=-CxauCeQ_SQ")


class Launcher:
    def __init__(self, *apps, broken=False):
        self.apps, self.broken, self.opened = set(apps), broken, []

    def start_player(self):
        return None

    def has_app(self, service):
        return service in self.apps

    def open(self, address):
        if self.broken:
            raise DesktopError("no browser")
        self.opened.append(address)


def finder(*tracks, error=None):
    asked = []

    def find(service, query, language):
        asked.append((service, query))
        if error is not None:
            raise error
        return list(tracks)

    return find, asked


def test_the_first_song_found_on_the_named_service_is_opened():
    launcher, (find, asked) = Launcher(), finder(VIDEO)
    tool = sound.music_search_tool(launcher, TR, lambda: "deezer", find)
    assert tool.run({"query": "Tarkan", "service": "youtube"}) == "YouTube'da 'TARKAN - Kış Güneşi' açıldı."
    assert asked == [(MusicService.YOUTUBE, "Tarkan")]
    assert launcher.opened == ["https://www.youtube.com/watch?v=-CxauCeQ_SQ"]
    assert tool.reads_untrusted({"query": "Tarkan"})


def test_the_setting_chooses_when_no_service_is_named_and_deezer_plays_in_its_app():
    launcher, (find, _) = Launcher(MusicService.DEEZER), finder(KUZU)
    tool = sound.music_search_tool(launcher, EN, lambda: "deezer", find)
    assert tool.run({"query": "Kuzu Kuzu", "service": "napster"}) == "Opened 'Tarkan – Kuzu Kuzu' on Deezer."
    assert launcher.opened == ["deezer://www.deezer.com/track/16412320"]
    launcher = Launcher()
    sound.music_search_tool(launcher, TR, lambda: "deezer", find).run({"query": "Kuzu Kuzu"})
    assert launcher.opened == ["https://www.deezer.com/track/16412320"]


def test_auto_shows_spotify_results_in_the_installed_app():
    launcher, (find, asked) = Launcher(MusicService.SPOTIFY), finder(VIDEO)
    tool = sound.music_search_tool(launcher, TR, find=find)
    assert tool.run({"query": "Tarkan"}) == "Spotify'da 'Tarkan' aramasını açtım; listeden bir şarkı seçebilirsin."
    assert launcher.opened == ["spotify:search:Tarkan"] and asked == []


def test_auto_without_spotify_plays_on_youtube_music():
    song = Track("Begonvil", "Sezen Aksu", "https://music.youtube.com/watch?v=tAT2nh_Smx0")
    launcher, (find, asked) = Launcher(), finder(song)
    tool = sound.music_search_tool(launcher, TR, find=find)
    assert tool.run({"query": "Sezen Aksu"}) == "YouTube Music'te 'Sezen Aksu – Begonvil' açıldı."
    assert asked == [(MusicService.YOUTUBE_MUSIC, "Sezen Aksu")] and launcher.opened == [song.url]


def test_spotify_without_its_app_opens_the_web_player_search():
    launcher = Launcher()
    tool = sound.music_search_tool(launcher, EN, find=finder()[0])
    assert tool.run({"query": "Tarkan", "service": "spotify"}) == (
        "I opened a search for 'Tarkan' in Spotify; pick a song from the list."
    )
    assert launcher.opened == ["https://open.spotify.com/search/Tarkan"]


def test_the_search_page_is_opened_when_nothing_is_found_or_the_service_cant_be_reached():
    launcher = Launcher()
    tool = sound.music_search_tool(launcher, TR, lambda: "apple_music", finder()[0])
    assert (
        tool.run({"query": "Kuzu Kuzu"})
        == "Apple Music'te 'Kuzu Kuzu' için bir şarkı bulamadım; arama sayfasını açtım."
    )
    failing = finder(error=web_fetch.WebFetchError(web_fetch.Reason.CONNECT))[0]
    tool = sound.music_search_tool(launcher, TR, lambda: "youtube", failing)
    assert tool.run({"query": "Tarkan"}) == "YouTube'da şarkıyı arayamadım; 'Tarkan' arama sayfasını açtım."
    assert launcher.opened == [
        "https://music.apple.com/tr/search?term=Kuzu+Kuzu",
        "https://www.youtube.com/results?search_query=Tarkan",
    ]


def test_nothing_to_play_or_nothing_to_open_it_with():
    tool = sound.music_search_tool(Launcher(), TR, find=finder(VIDEO)[0])
    with pytest.raises(ToolError):
        tool.run({"query": " "})
    with pytest.raises(ToolError):
        sound.music_search_tool(Launcher(broken=True), TR, lambda: "youtube", finder(VIDEO)[0]).run({"query": "x"})


def test_the_rule_passes_the_song_and_the_service():
    assert sound.music_rule_arguments("YouTube Music'te Sezen Aksu çal") == {
        "query": "Sezen Aksu",
        "service": "youtube_music",
    }
    assert sound.music_claims("play Tarkan on Deezer") and not sound.music_claims("YouTube'u aç")


@pytest.fixture
def services(monkeypatch):
    asked = []
    answers = {}

    def post_json(url, payload, language=TR, user_agent=""):
        asked.append((url, payload["context"]["client"]["clientName"], payload["query"]))
        return answers[url]

    def get_json(url, language, user_agent=""):
        asked.append(url)
        return answers[url.split("?")[0]]

    monkeypatch.setattr(web_fetch, "post_json", post_json)
    monkeypatch.setattr(music_lookup, "get_json", get_json)
    return asked, answers


def test_youtube_is_asked_as_its_web_page_asks(services):
    asked, answers = services
    answers[music_lookup.YOUTUBE_SEARCH] = web_json("youtube_search_tarkan.json")
    assert music_lookup.find(MusicService.YOUTUBE, "Tarkan", TR)[0] == VIDEO
    assert asked == [(music_lookup.YOUTUBE_SEARCH, "WEB", "Tarkan")]


def test_youtube_music_falls_back_to_youtube_videos(services):
    asked, answers = services
    answers[music_lookup.YOUTUBE_MUSIC_SEARCH] = {"contents": {}}
    answers[music_lookup.YOUTUBE_SEARCH] = web_json("youtube_search_tarkan.json")
    found = music_lookup.find(MusicService.YOUTUBE_MUSIC, "Tarkan", TR)
    assert found[0].url == "https://music.youtube.com/watch?v=-CxauCeQ_SQ"
    assert [call[1] for call in asked] == ["WEB_REMIX", "WEB"]


def test_deezer_and_apple_music_are_asked_with_the_query(services):
    asked, answers = services
    answers["https://api.deezer.com/search"] = web_json("deezer_search_kuzu_kuzu.json")
    answers["https://itunes.apple.com/search"] = web_json("itunes_search_kuzu_kuzu.json")
    assert music_lookup.find(MusicService.DEEZER, "Kuzu Kuzu", TR)[0] == KUZU
    assert music_lookup.find(MusicService.APPLE_MUSIC, "Kuzu Kuzu", EN)[0].artist == "Tarkan"
    assert asked[0].startswith("https://api.deezer.com/search?q=Kuzu+Kuzu")
    assert "country=us" in asked[1]
