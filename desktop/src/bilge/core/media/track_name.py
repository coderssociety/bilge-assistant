"""A track's title and artist as they are worth saying: a browser tab's "(3) TARKAN - Kuzu Kuzu (Official Music
Video) - YouTube" by "TarkanVEVO" is "TARKAN - Kuzu Kuzu", and the artist already in the title is not said twice."""

import re

from bilge.core.text import folded

_COUNTER = re.compile(r"^\(\d+\)\s+")
_SITE = re.compile(r"\s+[-–—|·]\s+(YouTube Music|YouTube|Deezer|Spotify|Apple Music|SoundCloud)\s*$", re.IGNORECASE)
_NOISE = re.compile(
    r"\s*[(\[][^)\]]*\b(official|video|audio|lyrics?|klip|clip|sözleri|sozleri|hd|4k|visuali[sz]er)\b[^)\]]*[)\]]",
    re.IGNORECASE,
)
_CHANNEL = re.compile(r"(\s+-\s+(Topic|Konu)|VEVO)$")


def cleaned(title: str, artist: str = "") -> tuple[str, str]:
    """The title without site names and video labels, and the artist; the artist is empty when the title says it."""
    name = _NOISE.sub("", _SITE.sub("", _COUNTER.sub("", title.strip()))).strip()
    by = _CHANNEL.sub("", artist.strip()).strip()
    if by and folded(by) in folded(name):
        by = ""
    return name or title.strip(), by
