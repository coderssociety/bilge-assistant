"""Installs a newer release from inside Bilge when the user asks for it.

The package for this system is fetched from the project's own release and must match the release's SHA256SUMS before
anything is replaced. On Windows the installer then runs silently and starts the new Bilge; a Linux AppImage is put in
place of the running one and started once this Bilge has quit. A copy run from source, or one whose file Bilge may not
replace, is not updated here: the release page is offered instead.
"""

import hashlib
import logging
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import httpx

from bilge.desktop.process import child_environment
from bilge.update import CHECKSUMS, Release, is_project_download, parse_checksums

log = logging.getLogger(__name__)

_TIMEOUT = httpx.Timeout(60.0, connect=15.0)
_CHUNK = 1 << 20
# Installer switches: no windows or questions, Bilge closed if still running, and started again at the end.
INSTALLER_ARGUMENTS = ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS", "/RELAUNCH=1"]
_ARCHITECTURES = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}


class UpdateFailed(Exception):
    """The update could not be installed and nothing was replaced. The message is a reason the app turns into a
    sentence (`update.error.<reason>`); the details go to the log."""

    def __init__(self, reason: str, detail: str = ""):
        super().__init__(reason)
        if detail:
            log.info("Update failed (%s): %s", reason, detail)


@dataclass(frozen=True)
class Target:
    """What this copy of Bilge is: the package that replaces it, and for an AppImage, the file to replace."""

    package: str
    appimage: Path | None = None


def target(
    version: str,
    system: str = sys.platform,
    frozen: bool = bool(getattr(sys, "frozen", False)),
    machine: str = platform.machine(),
    appimage: str | None = os.environ.get("APPIMAGE"),
) -> Target | None:
    """None when this copy can't update itself: run from source, or not from an AppImage on Linux."""
    if not frozen:
        return None
    if system == "win32":
        return Target(f"Bilge-Setup-{version}.exe")
    arch = _ARCHITECTURES.get(machine.lower())
    if system.startswith("linux") and appimage and arch:
        return Target(f"Bilge-{version}-{arch}.AppImage", Path(appimage))
    return None


def can_install(release: Release, found: Target | None = None) -> bool:
    found = found or target(release.version)
    if found is None or found.package not in release.assets or CHECKSUMS not in release.assets:
        return False
    return found.appimage is None or os.access(found.appimage.parent, os.W_OK)


def prepare(release: Release, client: httpx.Client | None = None, found: Target | None = None) -> Callable[[], None]:
    """Downloads and checks the package, and for an AppImage puts it in place. Returns what starts the new Bilge;
    the caller quits right after calling it."""
    found = found or target(release.version)
    if found is None or not can_install(release, found):
        raise UpdateFailed("unsupported")
    client = client or httpx.Client(timeout=_TIMEOUT, follow_redirects=True)
    sums = parse_checksums(_fetch(client, release.assets[CHECKSUMS]).decode("utf-8", errors="replace"))
    expected = sums.get(found.package)
    if expected is None:
        raise UpdateFailed("unlisted", f"{CHECKSUMS} doesn't list {found.package}")
    folder = found.appimage.parent if found.appimage else Path(tempfile.mkdtemp(prefix="bilge-update-"))
    # Next to the AppImage, so putting it in place is a rename on the same disk.
    downloaded = folder / (f".{found.package}.part" if found.appimage else found.package)
    try:
        digest = _download(client, release.assets[found.package], downloaded)
        if digest != expected:
            raise UpdateFailed("checksum", found.package)
        if found.appimage is None:
            return lambda: _run_installer(downloaded)
        downloaded.chmod(0o755)
        os.replace(downloaded, found.appimage)
        return lambda: _start_after_exit(found.appimage)
    except BaseException:
        downloaded.unlink(missing_ok=True)
        if found.appimage is None:
            shutil.rmtree(folder, ignore_errors=True)
        raise


def _fetch(client: httpx.Client, url: str) -> bytes:
    if not is_project_download(url):
        raise UpdateFailed("download", f"not a download of this project: {url}")
    try:
        response = client.get(url)
    except httpx.HTTPError as error:
        raise UpdateFailed("download", str(error)) from error
    if response.status_code != 200:
        raise UpdateFailed("download", f"{url} answered {response.status_code}")
    return response.content


def _download(client: httpx.Client, url: str, destination: Path) -> str:
    """Streams to `destination` and returns the file's SHA-256."""
    if not is_project_download(url):
        raise UpdateFailed("download", f"not a download of this project: {url}")
    digest = hashlib.sha256()
    try:
        with client.stream("GET", url) as response:
            if response.status_code != 200:
                raise UpdateFailed("download", f"{url} answered {response.status_code}")
            with destination.open("wb") as file:
                for chunk in response.iter_bytes(_CHUNK):
                    digest.update(chunk)
                    file.write(chunk)
    except httpx.HTTPError as error:
        raise UpdateFailed("download", str(error)) from error
    except OSError as error:
        raise UpdateFailed("save", str(error)) from error
    return digest.hexdigest()


def _run_installer(installer: Path) -> None:
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    subprocess.Popen([str(installer), *INSTALLER_ARGUMENTS], creationflags=flags, close_fds=True)


def _start_after_exit(appimage: Path) -> None:
    """A second Bilge started while this one runs only hands over to it and exits, so the new one waits for this
    process to end. The path is passed as an argument, never put into the command text."""
    wait = 'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec "$2"'
    subprocess.Popen(
        ["/bin/sh", "-c", wait, "bilge-update", str(os.getpid()), str(appimage)],
        start_new_session=True,
        close_fds=True,
        env=child_environment(),
    )
