"""Whether a newer Bilge has been published on GitHub, the page about it, and the files it comes in.

GitHub is asked at most once a day, and only for the newest published release (drafts and pre-releases are left out
by GitHub itself). Installing one is `bilge.updater`'s job, and only when the user asks for it.
"""

import json
import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from packaging.version import InvalidVersion, Version

log = logging.getLogger(__name__)

REPOSITORY = "coderssociety/bilge"
LATEST_URL = f"https://api.github.com/repos/{REPOSITORY}/releases/latest"
RELEASE_PAGES = f"https://github.com/{REPOSITORY}/releases/"
DOWNLOADS = f"https://github.com/{REPOSITORY}/releases/download/"
CHECKSUMS = "SHA256SUMS"
CHECK_EVERY = timedelta(days=1)
_TIMEOUT = httpx.Timeout(15.0, connect=10.0)


@dataclass(frozen=True)
class Release:
    version: str
    url: str
    # File name → download address, only for files under this project's release downloads.
    assets: dict[str, str] = field(default_factory=dict, compare=False)


class UpdateError(Exception):
    """GitHub could not be asked; the message is for the log and the settings window."""


def current_version() -> str | None:
    try:
        return version("bilge")
    except PackageNotFoundError:
        return None


def _parsed(text: str) -> Version | None:
    try:
        return Version(text.strip().removeprefix("v"))
    except InvalidVersion:
        return None


def is_newer(published: str, running: str) -> bool:
    remote, local = _parsed(published), _parsed(running)
    return remote is not None and local is not None and remote > local


def latest_release(client: httpx.Client | None = None) -> Release | None:
    """The newest published release; None when there is none yet."""
    client = client or httpx.Client(timeout=_TIMEOUT, follow_redirects=True)
    try:
        response = client.get(LATEST_URL, headers={"Accept": "application/vnd.github+json"})
    except httpx.HTTPError as error:
        raise UpdateError(f"GitHub could not be reached: {error}") from error
    if response.status_code == 404:
        return None
    if response.status_code != 200:
        raise UpdateError(f"GitHub answered {response.status_code}")
    try:
        data = response.json()
        tag, page = str(data["tag_name"]), str(data["html_url"])
        files = data.get("assets") or []
        assets = {str(f["name"]): str(f["browser_download_url"]) for f in files if isinstance(f, dict)}
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise UpdateError("Unexpected answer from GitHub") from error
    if not is_project_page(page) or _parsed(tag) is None:
        raise UpdateError(f"Unexpected release: {tag} at {page}")
    return Release(tag.removeprefix("v"), page, _project_downloads(assets))


def _project_downloads(assets: object) -> dict[str, str]:
    if not isinstance(assets, dict):
        return {}
    return {str(name): str(url) for name, url in assets.items() if is_project_download(str(url))}


def is_project_download(url: str) -> bool:
    """Files are only fetched from this project's own release downloads; GitHub then redirects to its file storage."""
    parts = urlsplit(url)
    path = parts.path.lower()
    return (url.startswith(DOWNLOADS) and parts.hostname == "github.com" and parts.port is None
            and parts.username is None and ".." not in path and "%2e" not in path and "%2f" not in path)  # fmt: skip


def parse_checksums(text: str) -> dict[str, str]:
    """The SHA-256 of each file in a SHA256SUMS file (`sha256sum` output: "<hex>  <name>" or "<hex> *<name>")."""
    sums = {}
    for line in text.splitlines():
        parts = line.strip().split(maxsplit=1)
        if len(parts) != 2:
            continue
        digest, name = parts[0].lower(), parts[1].strip().lstrip("*")
        if len(digest) == 64 and all(c in "0123456789abcdef" for c in digest) and name:
            sums[name] = digest
    return sums


def is_project_page(url: str) -> bool:
    """Only this project's own release pages are ever opened: https on github.com, under its releases, with no ".."
    that a browser would resolve into another repository."""
    parts = urlsplit(url)
    path = parts.path.lower()
    return (url.startswith(RELEASE_PAGES) and parts.hostname == "github.com" and parts.port is None
            and parts.username is None and ".." not in path and "%2e" not in path and "%2f" not in path)  # fmt: skip


def newer_release(running: str | None, client: httpx.Client | None = None) -> Release | None:
    """The newest release if it is newer than the running Bilge. A build without a version (run from source as a
    development copy) is never told to update."""
    if running is None:
        return None
    found = latest_release(client)
    return found if found is not None and is_newer(found.version, running) else None


class CheckRecord:
    """When GitHub was last asked and what it offered, kept beside the settings: a restart neither asks again nor
    forgets a newer release it was told about."""

    def __init__(self, path: Path):
        self.path = path

    def _read(self) -> dict:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}

    def last(self) -> datetime | None:
        try:
            return datetime.fromisoformat(self._read()["checked"])
        except (KeyError, TypeError, ValueError):
            return None

    def is_due(self, now: datetime) -> bool:
        last = self.last()
        # A clock set back makes the last check look like the future; it is then due.
        return last is None or not (now - CHECK_EVERY < last <= now)

    def found(self, running: str | None) -> Release | None:
        """The release found last time, if it is still newer than what runs now."""
        offered = self._read().get("newer")
        try:
            release = Release(str(offered["version"]), str(offered["url"]), _project_downloads(offered.get("assets")))
        except (KeyError, TypeError, AttributeError):
            return None
        if running is None or not is_project_page(release.url) or not is_newer(release.version, running):
            return None
        return release

    def record(self, now: datetime, newer: Release | None) -> None:
        data = {"checked": now.astimezone(UTC).isoformat(), "newer": vars(newer) if newer else None}
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(data), encoding="utf-8")
        except OSError:
            log.info("Could not record the update check", exc_info=True)
