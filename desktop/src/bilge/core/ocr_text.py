"""Text recognized on screen, tidied for reading: recognizers keep the layout's empty lines and stray spaces."""

# Tesseract's names for the languages Bilge reads; a Turkish screen still shows English words, and the other way.
TESSERACT_LANGUAGES = ("tur", "eng")


def cleaned(text: str) -> str:
    """Lines with their spaces collapsed, and at most one empty line between paragraphs."""
    lines: list[str] = []
    for raw in text.splitlines():
        line = " ".join(raw.split())
        if line or (lines and lines[-1]):
            lines.append(line)
    return "\n".join(lines).strip()


def tesseract_languages(listing: str) -> tuple[str, ...]:
    """The wanted languages that `tesseract --list-langs` names; its first line is a heading."""
    installed = {line.strip() for line in listing.splitlines()[1:]}
    return tuple(language for language in TESSERACT_LANGUAGES if language in installed)
