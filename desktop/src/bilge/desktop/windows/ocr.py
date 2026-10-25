"""Reading the text on screen with the OCR built into Windows (Windows.Media.Ocr). The capture stays in memory."""

import asyncio
from collections.abc import Callable

from bilge.desktop import image
from bilge.desktop.base import ScreenshotArea
from bilge.desktop.process import DesktopError, NotPossibleHere


class WindowsScreenText:
    def __init__(self, screenshots, recognize: Callable[[image.Pixels], str] | None = None):
        """`screenshots` is a WindowsScreenshots, whose captures can be had as pixels."""
        self._screenshots = screenshots
        self._recognize = recognize or recognize_text

    def read(self, area: ScreenshotArea) -> str:
        pixels = self._screenshots.pixels(area)
        if pixels is None:
            return ""
        return self._recognize(pixels)


def recognize_text(pixels: image.Pixels) -> str:
    async def recognize() -> str:
        from winrt.windows.graphics.imaging import BitmapPixelFormat, SoftwareBitmap
        from winrt.windows.media.ocr import OcrEngine

        # Windows recognizes the languages of the user's profile that have OCR data (Turkish and English do).
        engine = OcrEngine.try_create_from_user_profile_languages()
        if engine is None:
            raise NotPossibleHere("No OCR language installed", desktop="windows")
        fitted = image.shrunk(pixels, int(OcrEngine.max_image_dimension))
        bitmap = SoftwareBitmap.create_copy_from_buffer(
            fitted.bgra, BitmapPixelFormat.BGRA8, fitted.width, fitted.height
        )
        result = await engine.recognize_async(bitmap)
        return "\n".join(line.text for line in result.lines)

    try:
        return asyncio.run(recognize())
    except (OSError, RuntimeError) as error:
        raise DesktopError(f"Windows OCR: {error}") from error
