"""The currencies and amount a conversion request names, in the order said ("100 Euro kaç para" → EUR to TRY, 100;
"50 dolar kaç sterlin" → USD to GBP), and whether it asks about gold, which is not a currency."""

import re

from bilge.core import text

# Folded word stems; a two-word name ("Kanada doları") is matched by its first word.
_STEMS: tuple[tuple[str, str], ...] = (
    ("kanada", "CAD"), ("canadian", "CAD"), ("avustralya", "AUD"), ("australian", "AUD"),
    ("isvicre", "CHF"), ("swiss", "CHF"), ("frang", "CHF"), ("franc", "CHF"),
    ("isvec", "SEK"), ("swedish", "SEK"), ("norvec", "NOK"), ("norwegian", "NOK"), ("danimarka", "DKK"),
    ("danish", "DKK"), ("dolar", "USD"), ("dollar", "USD"), ("euro", "EUR"), ("avro", "EUR"), ("sterlin", "GBP"),
    ("pound", "GBP"), ("lira", "TRY"), ("yuan", "CNY"),
)  # fmt: skip
_EXACT = {"tl": "TRY", "yen": "JPY", "usd": "USD", "eur": "EUR", "gbp": "GBP"}
_SYMBOLS = {"€": "EUR", "$": "USD", "£": "GBP", "₺": "TRY"}
# The second word of a two-word name, skipped after its first so "Kanada doları" is one currency.
_QUALIFIERS = ("kanada", "canadian", "avustralya", "australian", "isvicre", "swiss", "isvec", "swedish", "norvec",
               "norwegian", "danimarka", "danish")  # fmt: skip
_NAME_TAILS = ("dolar", "dollar", "kron", "frang", "franc")
_TOKEN = re.compile(r"\d+(?:[.,]\d+)*|[€$£₺]|[^\W\d_]+")
_TURKISH_GOLD_CONTEXT = ("gram", "ceyrek", "yarim", "tam", "ons", "cumhuriyet", "fiyat", "kac", "kur", "lira", "tl")
_ENGLISH_GOLD_CONTEXT = ("price", "ounce", "gram", "much", "worth", "rate", "cost")
# "Altında" is "under it", not gold.
_UNDER = ("altinda", "altindan", "altindaki", "altina")


def currencies(command: str) -> list[str]:
    """ISO codes in the order said; "kaç para" asks for lira."""
    found: list[str] = []
    qualified = False
    for token in _tokens(command):
        if qualified and token.startswith(_NAME_TAILS):
            qualified = False
            continue
        qualified = token.startswith(_QUALIFIERS)
        code = _code(token)
        if code is not None and (not found or found[-1] != code):
            found.append(code)
    if "TRY" not in found and re.search(r"\bkac para\b", text.folded(command)):
        found.append("TRY")
    return found


def amount(command: str, english: bool) -> float | None:
    """The number said with the first currency: "100 euro", "€100", "1.250,5 lira" (Turkish separators in Turkish,
    English ones in English)."""
    tokens = _tokens(command)
    for index, token in enumerate(tokens):
        if _code(token) is None:
            continue
        if index > 0 and tokens[index - 1][0].isdigit():
            return _number(tokens[index - 1], english)
        if token in _SYMBOLS and index + 1 < len(tokens) and tokens[index + 1][0].isdigit():
            return _number(tokens[index + 1], english)
        return None
    return None


def asks_for_gold(command: str, english: bool) -> bool:
    words = text.folded(command).split()
    if english:
        return "gold" in words and any(w.startswith(_ENGLISH_GOLD_CONTEXT) for w in words)
    if not any(w.startswith("altin") and w not in _UNDER for w in words):
        return False
    return any(w.startswith(_TURKISH_GOLD_CONTEXT) for w in words)


def _tokens(command: str) -> list[str]:
    lowered = text.lowercased(command)
    without_apostrophes = "".join(c for c in lowered if c not in "'’‘`´")
    return [text.folded(t) if t[0].isalpha() else t for t in _TOKEN.findall(without_apostrophes)]


def _code(token: str) -> str | None:
    if token in _SYMBOLS:
        return _SYMBOLS[token]
    if token in _EXACT:
        return _EXACT[token]
    return next((code for stem, code in _STEMS if token.startswith(stem)), None)


def _number(token: str, english: bool) -> float | None:
    thousands, decimal = (",", ".") if english else (".", ",")
    whole, _, fraction = token.partition(decimal)
    groups = whole.split(thousands)
    # A separator that doesn't group thousands ("2.5" in Turkish) was meant as the decimal point.
    whole = "".join(groups) if all(len(g) == 3 for g in groups[1:]) else whole.replace(thousands, ".")
    try:
        return float(f"{whole}.{fraction}" if fraction else whole)
    except ValueError:
        return None
