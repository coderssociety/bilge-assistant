"""HLS playlists (.m3u8), as many Turkish stations stream: a master list of variants, or a media list of segments
that a live stream keeps extending."""

from dataclasses import dataclass
from urllib.parse import urljoin

DEFAULT_TARGET_SECONDS = 6.0
_VIDEO_CODECS = ("avc", "hvc", "hev", "vp0", "av01")


class UnsupportedPlaylist(ValueError):
    """Encrypted segments, which would need keys fetched and applied."""


@dataclass(frozen=True)
class Segment:
    sequence: int
    url: str


@dataclass(frozen=True)
class Playlist:
    # A master playlist lists variants and nothing else.
    variants: tuple[str, ...]
    segments: tuple[Segment, ...]
    target_seconds: float
    # A finished list (an episode); a live one is fetched again for new segments.
    ended: bool
    # The initialization section fragmented MP4 segments need before the first of them.
    init: str | None = None


def is_playlist(data: bytes) -> bool:
    return data.lstrip(b"\xef\xbb\xbf \r\n\t").startswith(b"#EXTM3U")


def parse(text: str, base: str) -> Playlist:
    """Addresses are resolved against `base`, the playlist's own address."""
    variants: list[tuple[tuple[bool, int], str]] = []
    segments: list[Segment] = []
    sequence = 0
    target = DEFAULT_TARGET_SECONDS
    ended = False
    init = None
    pending_variant: tuple[bool, int] | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXT-X-STREAM-INF:"):
            pending_variant = _variant_rank(_attributes(line))
        elif line.startswith("#EXT-X-MEDIA-SEQUENCE:"):
            sequence = _number(line, 0)
        elif line.startswith("#EXT-X-TARGETDURATION:"):
            target = float(_number(line, int(DEFAULT_TARGET_SECONDS))) or DEFAULT_TARGET_SECONDS
        elif line.startswith("#EXT-X-ENDLIST"):
            ended = True
        elif line.startswith("#EXT-X-KEY:"):
            if _attributes(line).get("METHOD", "NONE").upper() != "NONE":
                raise UnsupportedPlaylist("encrypted segments")
        elif line.startswith("#EXT-X-MAP:"):
            uri = _attributes(line).get("URI")
            init = urljoin(base, uri) if uri else None
        elif not line.startswith("#"):
            if pending_variant is not None:
                variants.append((pending_variant, urljoin(base, line)))
                pending_variant = None
            else:
                segments.append(Segment(sequence, urljoin(base, line)))
                sequence += 1
    ordered = tuple(url for _, url in sorted(variants, key=lambda variant: variant[0], reverse=True))
    return Playlist(ordered, tuple(segments), target, ended, init)


def _variant_rank(attributes: dict[str, str]) -> tuple[bool, int]:
    """Audio-only variants first, the best of them first; among video ones the lightest, for its sound."""
    codecs = attributes.get("CODECS", "").lower()
    bandwidth = _int(attributes.get("BANDWIDTH", ""), 0)
    has_video = any(codec in codecs for codec in _VIDEO_CODECS) or "RESOLUTION" in attributes
    return (not has_video, -bandwidth if has_video else bandwidth)


def _attributes(line: str) -> dict[str, str]:
    """`#TAG:KEY=VALUE,KEY="quoted, value"` into a dict."""
    _, _, rest = line.partition(":")
    found: dict[str, str] = {}
    key, value, quoted, reading_key = "", "", False, True
    for character in rest + ",":
        if reading_key:
            if character == "=":
                reading_key = False
            elif character != ",":
                key += character
        elif character == '"':
            quoted = not quoted
        elif character == "," and not quoted:
            found[key.strip().upper()] = value
            key, value, reading_key = "", "", True
        else:
            value += character
    return found


def _number(line: str, default: int) -> int:
    return _int(line.partition(":")[2].split(",")[0], default)


def _int(text: str, default: int) -> int:
    try:
        return int(float(text.strip()))
    except ValueError:
        return default
