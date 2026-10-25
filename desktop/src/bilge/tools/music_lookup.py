"""Finding the song to play on each service through its public, keyless search: youtubei for YouTube and YouTube
Music (as their web pages ask it), api.deezer.com, and the iTunes Search API for Apple Music. Spotify has no such
search."""

from bilge.core.language import AssistantLanguage
from bilge.core.media import music_search
from bilge.core.media.music_request import MusicService
from bilge.core.media.music_search import Track
from bilge.tools import web_fetch
from bilge.tools.feed_cache import get_json

YOUTUBE_SEARCH = "https://www.youtube.com/youtubei/v1/search?prettyPrint=false"
YOUTUBE_MUSIC_SEARCH = "https://music.youtube.com/youtubei/v1/search?prettyPrint=false"
# The web pages' own clients; YouTube still answers these versions without a key.
WEB_CLIENT = ("WEB", "2.20250101.00.00")
MUSIC_CLIENT = ("WEB_REMIX", "1.20250101.01.00")


def country(language: AssistantLanguage) -> str:
    """The store and region results are ranked for."""
    return "us" if language is AssistantLanguage.ENGLISH else "tr"


def find(service: MusicService, query: str, language: AssistantLanguage) -> list[Track]:
    """The matching tracks, best first; WebFetchError when the service can't be asked."""
    region = country(language)
    match service:
        case MusicService.YOUTUBE:
            return _youtube_videos(query, language, region)
        case MusicService.YOUTUBE_MUSIC:
            body = music_search.youtube_search_body(query, *MUSIC_CLIENT, language.code, region, songs_only=True)
            songs = music_search.youtube_music_songs(web_fetch.post_json(YOUTUBE_MUSIC_SEARCH, body, language))
            # Any YouTube video plays in YouTube Music too.
            return songs or [_on_youtube_music(video) for video in _youtube_videos(query, language, region)]
        case MusicService.DEEZER:
            return music_search.deezer_tracks(get_json(music_search.deezer_search_url(query), language))
        case MusicService.APPLE_MUSIC:
            return music_search.itunes_tracks(get_json(music_search.itunes_search_url(query, region), language))
    return []


def _youtube_videos(query: str, language: AssistantLanguage, region: str) -> list[Track]:
    body = music_search.youtube_search_body(query, *WEB_CLIENT, language.code, region)
    return music_search.youtube_videos(web_fetch.post_json(YOUTUBE_SEARCH, body, language))


def _on_youtube_music(video: Track) -> Track:
    return Track(video.title, video.artist, video.url.replace("https://www.youtube.com/", "https://music.youtube.com/"))
