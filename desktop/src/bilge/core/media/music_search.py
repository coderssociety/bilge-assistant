"""The first matching tracks in the answers of the music services' public searches (YouTube, YouTube Music, Deezer,
iTunes), the address that plays each, and each service's search page when nothing is found. The answers are
someone else's data: anything missing or odd is skipped, and only the services' own addresses come out."""

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote, quote_plus, urlencode, urlsplit

from bilge.core.media import track_name
from bilge.core.media.music_request import MusicService

_VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")
_ARTIST_PAGE = "MUSIC_PAGE_TYPE_ARTIST"
_APPLE_HOSTS = frozenset({"music.apple.com", "itunes.apple.com"})


@dataclass(frozen=True)
class Track:
    title: str
    artist: str
    # What plays it: a watch page, a Deezer or Apple Music track page.
    url: str

    @property
    def spoken(self) -> str:
        return f"{self.artist} – {self.title}" if self.artist else self.title


def youtube_videos(answer: Any) -> list[Track]:
    """Videos of a youtubei search on the WEB client; channels, playlists, shorts, ads and shelves are passed over."""
    found = []
    for section in _list(_path(answer, "contents", "twoColumnSearchResultsRenderer", "primaryContents",
                               "sectionListRenderer", "contents")):  # fmt: skip
        for item in _list(_path(section, "itemSectionRenderer", "contents")):
            video = _path(item, "videoRenderer")
            if not isinstance(video, dict) or _path(video, "navigationEndpoint", "reelWatchEndpoint") is not None:
                continue
            video_id = _video_id(video.get("videoId"))
            title = _runs(_path(video, "title"))
            if video_id and title and "upcomingEventData" not in video:
                name, artist = track_name.cleaned(title, _runs(_path(video, "ownerText")))
                # "Artist - Song" already; a channel's name before any other title says little.
                artist = "" if re.search(r"\s[-–]\s", name) else artist
                found.append(Track(name, artist, f"https://www.youtube.com/watch?v={video_id}"))
    return found


def youtube_music_songs(answer: Any) -> list[Track]:
    """Songs of a youtubei search on YouTube Music's WEB_REMIX client."""
    found = []
    for tab in _list(_path(answer, "contents", "tabbedSearchResultsRenderer", "tabs")):
        for section in _list(_path(tab, "tabRenderer", "content", "sectionListRenderer", "contents")):
            for item in _list(_path(section, "musicShelfRenderer", "contents")):
                song = _path(item, "musicResponsiveListItemRenderer")
                columns = _list(_path(song, "flexColumns"))
                video_id = _video_id(_path(song, "playlistItemData", "videoId"))
                if not video_id or not columns:
                    continue
                title = _runs(_path(columns[0], "musicResponsiveListItemFlexColumnRenderer", "text"))
                artist = _artists(columns[1] if len(columns) > 1 else None)
                if title:
                    found.append(Track(title, artist, f"https://music.youtube.com/watch?v={video_id}"))
    return found


def deezer_tracks(answer: Any) -> list[Track]:
    """Tracks of api.deezer.com/search that can be played."""
    found = []
    for item in _list(_path(answer, "data")):
        if not isinstance(item, dict) or item.get("type", "track") != "track" or item.get("readable") is False:
            continue
        track_id, title = item.get("id"), str(item.get("title") or "").strip()
        if isinstance(track_id, int) and not isinstance(track_id, bool) and track_id > 0 and title:
            artist = str(_path(item, "artist", "name") or "").strip()
            found.append(Track(title, artist, f"https://www.deezer.com/track/{track_id}"))
    return found


def itunes_tracks(answer: Any) -> list[Track]:
    """Songs of the iTunes Search API, by their Apple Music page."""
    found = []
    for item in _list(_path(answer, "results")):
        if not isinstance(item, dict) or item.get("kind") != "song":
            continue
        url, title = str(item.get("trackViewUrl") or ""), str(item.get("trackName") or "").strip()
        parts = urlsplit(url)
        if parts.scheme == "https" and parts.hostname in _APPLE_HOSTS and title:
            found.append(Track(title, str(item.get("artistName") or "").strip(), url))
    return found


def deezer_app_url(track: Track) -> str:
    """The same track for the Deezer app, which takes its web addresses under its own scheme."""
    return "deezer://" + track.url.removeprefix("https://")


def youtube_search_body(
    query: str, client: str, version: str, language: str, country: str, songs_only: bool = False
) -> dict:
    """What youtubei's search is sent; `songs_only` narrows a YouTube Music search to songs."""
    body: dict[str, Any] = {
        "context": {"client": {"clientName": client, "clientVersion": version, "hl": language, "gl": country.upper()}},
        "query": query,
    }
    if songs_only:
        body["params"] = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
    return body


def deezer_search_url(query: str) -> str:
    return "https://api.deezer.com/search?" + urlencode({"q": query, "limit": 10})


def itunes_search_url(query: str, country: str) -> str:
    return "https://itunes.apple.com/search?" + urlencode(
        {"term": query, "entity": "song", "country": country, "limit": 10}
    )


def search_page(service: MusicService, query: str, country: str) -> str:
    """Where the user can pick from the results themselves."""
    match service:
        case MusicService.YOUTUBE:
            return "https://www.youtube.com/results?" + urlencode({"search_query": query})
        case MusicService.YOUTUBE_MUSIC:
            return "https://music.youtube.com/search?q=" + quote_plus(query)
        case MusicService.DEEZER:
            return "https://www.deezer.com/search/" + quote(query, safe="")
        case MusicService.APPLE_MUSIC:
            return f"https://music.apple.com/{country}/search?" + urlencode({"term": query})
    return "https://open.spotify.com/search/" + quote(query, safe="")


def spotify_search(query: str) -> str:
    return "spotify:search:" + quote(query, safe="")


def _path(value: Any, *keys: str) -> Any:
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def _list(value: Any) -> list:
    return value if isinstance(value, list) else []


def _runs(text: Any) -> str:
    """ "runs" pieces joined, or a "simpleText"."""
    if isinstance(_path(text, "simpleText"), str):
        return text["simpleText"].strip()
    return "".join(str(run.get("text") or "") for run in _list(_path(text, "runs")) if isinstance(run, dict)).strip()


def _artists(column: Any) -> str:
    runs = [run for run in _list(_path(column, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"))
            if isinstance(run, dict)]  # fmt: skip
    named = [str(run.get("text") or "").strip() for run in runs if _page_type(run) == _ARTIST_PAGE]
    named = [name for name in named if name]
    if named:
        return ", ".join(named)
    return str(runs[0].get("text") or "").strip() if runs else ""


def _page_type(run: dict) -> Any:
    return _path(run, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
                 "browseEndpointContextMusicConfig", "pageType")  # fmt: skip


def _video_id(value: Any) -> str | None:
    return value if isinstance(value, str) and _VIDEO_ID.fullmatch(value) else None
