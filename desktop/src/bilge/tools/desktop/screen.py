"""Reading the text on screen ("ekranda ne yazıyor", "bu hatayı oku", "bu sayfayı özetle") with OCR. Whatever the
screen shows may have been written by anyone, so the text is untrusted: the model only summarizes or reads it."""

from typing import Any

from bilge.core import ocr_text
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import ScreenshotArea, ScreenText
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import choice, failure, obj, string_argument
from bilge.tools.reading import TextReading, continued

SCREEN_CHARACTERS = 2500

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Ekranda, öndeki pencerede yazanları okur (OCR): 'ekranda ne yazıyor', 'bu hatayı oku', 'bu sayfayı "
        "özetle'. Metni özetle ya da sorulan kısmı söyle.",
        "scope": "Öndeki pencere mi (frontWindow), tüm ekran mı (wholeScreen); belirtilmediyse frontWindow",
        "title": "Ekran",
        "content": "Ekrandaki yazı:\n{text}",
        "nothing": "Ekranda okunabilir bir yazı bulamadım.",
        "failed": "Ekrandaki yazıyı okuyamadım; bir kez daha dener misin?",
        "install_tesseract": "Ekrandaki yazıyı okumak için Tesseract ve Türkçe dil verisi gerekiyor. Ubuntu ya da "
        "Debian'da 'sudo apt install tesseract-ocr tesseract-ocr-tur', Fedora'da 'sudo dnf install tesseract "
        "tesseract-langpack-tur', Arch'ta 'sudo pacman -S tesseract tesseract-data-tur tesseract-data-eng' ile "
        "kurabilirsin.",
        "install_language": "Windows'ta yazı tanıma dili yüklü değil. Ayarlar > Saat ve dil > Dil ve bölge'den "
        "Türkçe ya da İngilizce dil paketini eklemen gerekiyor.",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Reads the text shown in the front window or on screen (OCR): 'what does the screen say', 'read this "
        "error', 'summarize this page'. Summarize the text or say the part asked about.",
        "scope": "The front window (frontWindow) or the whole screen (wholeScreen); frontWindow if not said",
        "title": "Screen",
        "content": "Text on screen:\n{text}",
        "nothing": "I couldn't find any readable text on screen.",
        "failed": "I couldn't read the text on screen; could you try again?",
        "install_tesseract": "Reading the screen needs Tesseract and its language data. Install it with 'sudo apt "
        "install tesseract-ocr tesseract-ocr-tur' on Ubuntu or Debian, 'sudo dnf install tesseract "
        "tesseract-langpack-tur' on Fedora, or 'sudo pacman -S tesseract tesseract-data-eng tesseract-data-tur' "
        "on Arch.",
        "install_language": "Windows has no text recognition language installed. Add the English or Turkish "
        "language pack under Settings > Time & language > Language & region.",
    },
}
_AREAS = {"frontWindow": ScreenshotArea.FRONT_WINDOW, "wholeScreen": ScreenshotArea.WHOLE_SCREEN}


def read_screen_tool(screen: ScreenText, language: AssistantLanguage, reading: TextReading | None = None) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("continue") and reading is not None:
            return reading.more()
        area = _AREAS.get(string_argument(arguments, "scope"), ScreenshotArea.FRONT_WINDOW)
        content = ocr_text.cleaned(read_text(screen, area, language))
        if not content:
            raise ToolError(texts["nothing"])
        if reading is None:
            return texts["content"].format(text=content[:SCREEN_CHARACTERS])
        return texts["content"].format(text=reading.start(texts["title"], content, SCREEN_CHARACTERS))

    return Tool(
        "readScreen",
        texts["tool"],
        run=run,
        parameters=obj(scope=choice(list(_AREAS), texts["scope"])),
        untrusted_output=True,
        refine=lambda arguments, command: continued(reading, arguments, command),
    )


def read_text(screen: ScreenText, area: ScreenshotArea, language: AssistantLanguage) -> str:
    """The recognized text, with the missing piece named in words the user can act on."""
    texts = _TEXTS[language]
    try:
        return screen.read(area)
    except MissingProgram as error:
        if any(program.startswith("tesseract") for program in error.programs):
            raise ToolError(texts["install_tesseract"]) from error
        raise failure(error, language) from error
    except NotPossibleHere as error:
        raise ToolError(texts["install_language"]) from error
    except DesktopError as error:
        raise failure(error, language, texts["failed"]) from error
