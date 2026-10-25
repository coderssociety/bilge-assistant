"""Reading the text on screen with Tesseract: the screenshot goes to a private temporary folder that is removed
straight after."""

import tempfile
from pathlib import Path

from bilge.core import ocr_text
from bilge.desktop.base import ScreenshotArea, Screenshots
from bilge.desktop.process import DesktopError, MissingProgram, Runner

# A 4K screen takes Tesseract a few seconds; much longer means it is stuck.
_RECOGNITION_SECONDS = 60
_LISTING_SECONDS = 10


class TesseractScreenText:
    def __init__(self, runner: Runner, screenshots: Screenshots):
        self._runner = runner
        self._screenshots = screenshots
        self._languages: tuple[str, ...] | None = None

    def read(self, area: ScreenshotArea) -> str:
        languages = self._installed_languages()
        with tempfile.TemporaryDirectory(prefix="bilge-ocr-") as folder:
            picture = Path(folder) / "screen.png"
            if not self._screenshots.capture(area, picture):
                return ""
            argv = ["tesseract", str(picture), "stdout", "-l", "+".join(languages)]
            done = self._runner.run(argv, timeout=_RECOGNITION_SECONDS)
        if not done.ok:
            raise DesktopError(f"tesseract failed (exit {done.status}): {done.stderr.strip()[:200]}")
        return done.stdout

    def _installed_languages(self) -> tuple[str, ...]:
        if self._languages is None:
            if not self._runner.has("tesseract"):
                raise MissingProgram("tesseract")
            done = self._runner.run(["tesseract", "--list-langs"], timeout=_LISTING_SECONDS)
            if not done.ok:
                raise DesktopError(f"tesseract --list-langs failed (exit {done.status})")
            # Tesseract 3 lists them on standard error.
            found = ocr_text.tesseract_languages(done.stdout or done.stderr)
            if not found:
                raise MissingProgram("tesseract-ocr-tur", "tesseract-ocr-eng")
            self._languages = found
        return self._languages
