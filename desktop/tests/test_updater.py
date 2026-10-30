import hashlib
import os
from pathlib import Path

import httpx
import pytest

from bilge import updater
from bilge.update import Release

BASE = "https://github.com/serdarvaran/bilge-assistant/releases/download/v0.6.0/"
PAGE = "https://github.com/serdarvaran/bilge-assistant/releases/tag/v0.6.0"


def release(*names: str) -> Release:
    return Release("0.6.0", PAGE, {name: BASE + name for name in names})


def serving(files: dict[str, bytes], sums: dict[str, str] | None = None) -> httpx.Client:
    listed = sums if sums is not None else {name: hashlib.sha256(body).hexdigest() for name, body in files.items()}
    body = "".join(f"{digest}  {name}\n" for name, digest in listed.items()).encode()

    def handler(request: httpx.Request) -> httpx.Response:
        name = request.url.path.rsplit("/", 1)[-1]
        if name == "SHA256SUMS":
            return httpx.Response(200, content=body)
        return httpx.Response(200, content=files[name]) if name in files else httpx.Response(404)

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_only_a_packaged_copy_updates_itself():
    assert updater.target("0.6.0", "win32", True) == updater.Target("Bilge-Setup-0.6.0.exe")
    assert updater.target("0.6.0", "linux", True, "x86_64", "/home/a/Bilge.AppImage") == updater.Target(
        "Bilge-0.6.0-x86_64.AppImage", Path("/home/a/Bilge.AppImage")
    )
    assert updater.target("0.6.0", "linux", True, "arm64", "/a.AppImage").package == "Bilge-0.6.0-aarch64.AppImage"
    assert updater.target("0.6.0", "win32", False) is None
    assert updater.target("0.6.0", "linux", True, "x86_64", None) is None
    assert updater.target("0.6.0", "darwin", True) is None


def test_installing_needs_the_package_and_the_checksums():
    found = updater.Target("Bilge-Setup-0.6.0.exe")
    assert updater.can_install(release("Bilge-Setup-0.6.0.exe", "SHA256SUMS"), found)
    assert not updater.can_install(release("Bilge-Setup-0.6.0.exe"), found)
    assert not updater.can_install(release("Bilge-0.6.0.dmg", "SHA256SUMS"), found)


def test_an_appimage_is_put_in_place_and_started_after_this_one_quits(tmp_path, monkeypatch):
    current = tmp_path / "Bilge.AppImage"
    current.write_bytes(b"old")
    found = updater.Target("Bilge-0.6.0-x86_64.AppImage", current)
    started = []
    monkeypatch.setattr(updater.subprocess, "Popen", lambda args, **_: started.append(args))
    client = serving({found.package: b"new appimage"})
    start = updater.prepare(release(found.package, "SHA256SUMS"), client, found)
    assert current.read_bytes() == b"new appimage"
    assert os.access(current, os.X_OK)
    assert list(tmp_path.iterdir()) == [current]
    start()
    assert started[0][-1] == str(current) and started[0][-2] == str(os.getpid())


def test_a_package_that_does_not_match_its_checksum_replaces_nothing(tmp_path):
    current = tmp_path / "Bilge.AppImage"
    current.write_bytes(b"old")
    found = updater.Target("Bilge-0.6.0-x86_64.AppImage", current)
    client = serving({found.package: b"tampered"}, {found.package: "0" * 64})
    with pytest.raises(updater.UpdateFailed, match="checksum"):
        updater.prepare(release(found.package, "SHA256SUMS"), client, found)
    assert current.read_bytes() == b"old"
    assert list(tmp_path.iterdir()) == [current]


def test_a_package_missing_from_the_checksums_is_refused(tmp_path):
    current = tmp_path / "Bilge.AppImage"
    found = updater.Target("Bilge-0.6.0-x86_64.AppImage", current)
    client = serving({found.package: b"x"}, {})
    with pytest.raises(updater.UpdateFailed, match="unlisted"):
        updater.prepare(release(found.package, "SHA256SUMS"), client, found)


def test_the_windows_installer_runs_silently_and_restarts_bilge(monkeypatch):
    found = updater.Target("Bilge-Setup-0.6.0.exe")
    started = []
    monkeypatch.setattr(updater.subprocess, "Popen", lambda args, **_: started.append(args))
    start = updater.prepare(release(found.package, "SHA256SUMS"), serving({found.package: b"installer"}), found)
    start()
    installer = Path(started[0][0])
    assert installer.read_bytes() == b"installer"
    assert started[0][1:] == updater.INSTALLER_ARGUMENTS and "/RELAUNCH=1" in started[0]
    installer.unlink()
    installer.parent.rmdir()


def test_files_outside_the_project_are_never_fetched(tmp_path):
    current = tmp_path / "Bilge.AppImage"
    found = updater.Target("Bilge-0.6.0-x86_64.AppImage", current)
    foreign = Release("0.6.0", PAGE, {found.package: "https://example.com/x", "SHA256SUMS": BASE + "SHA256SUMS"})
    with pytest.raises(updater.UpdateFailed, match="download"):
        updater.prepare(foreign, serving({found.package: b"x"}), found)
