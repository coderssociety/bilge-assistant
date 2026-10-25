"""Reads unit conversions from what was said ("10 mil kaç kilometre", "5 feet 10 inç kaç santim", "60 mph in km/h")
and converts them exactly, so neither the numbers nor the units depend on the model. Turkish and English unit words
are both understood, with Turkish case endings ("kilometreye", "km'den")."""

import math
import re
from dataclasses import dataclass
from decimal import Decimal
from enum import StrEnum

from bilge.core.language import AssistantLanguage
from bilge.core.text import folded, lowercased


class Dimension(StrEnum):
    LENGTH = "length"
    MASS = "mass"
    VOLUME = "volume"
    AREA = "area"
    SPEED = "speed"
    TEMPERATURE = "temperature"
    DATA = "data"


@dataclass(frozen=True)
class Unit:
    """`factor` and `offset` give the value in the dimension's base unit (meter, gram, milliliter, square meter,
    meter per second, kelvin, byte): base = value * factor + offset."""

    key: str
    dimension: Dimension
    factor: float
    turkish: str
    english: tuple[str, str]
    names: tuple[str, ...]
    offset: float = 0.0

    def name(self, language: AssistantLanguage, value: float = 1) -> str:
        if language is AssistantLanguage.ENGLISH:
            return self.english[0] if value == 1 else self.english[1]
        return self.turkish


@dataclass(frozen=True)
class Quantity:
    value: float
    unit: Unit


@dataclass(frozen=True)
class Conversion:
    # More than one for "5 feet 10 inç"; all of one dimension, the target's.
    quantities: tuple[Quantity, ...]
    target: Unit


_FAHRENHEIT_FACTOR = 5 / 9
_KELVIN_OF_ZERO_CELSIUS = 273.15
_BINARY = 1024

UNITS: tuple[Unit, ...] = (
    Unit("millimeter", Dimension.LENGTH, 0.001, "milimetre", ("millimeter", "millimeters"),
         ("milimetre", "mm", "millimeter", "millimeters", "millimetre", "millimetres")),
    Unit("centimeter", Dimension.LENGTH, 0.01, "santimetre", ("centimeter", "centimeters"),
         ("santimetre", "santim", "cm", "centimeter", "centimeters", "centimetre", "centimetres")),
    Unit("meter", Dimension.LENGTH, 1, "metre", ("meter", "meters"),
         ("metre", "m", "meter", "meters", "metres")),
    Unit("kilometer", Dimension.LENGTH, 1000, "kilometre", ("kilometer", "kilometers"),
         ("kilometre", "km", "kilometer", "kilometers", "kilometres")),
    Unit("inch", Dimension.LENGTH, 0.0254, "inç", ("inch", "inches"), ("inc", "inch", "inches", "pus")),
    Unit("foot", Dimension.LENGTH, 0.3048, "feet", ("foot", "feet"), ("feet", "foot", "ft", "fit")),
    Unit("yard", Dimension.LENGTH, 0.9144, "yarda", ("yard", "yards"), ("yarda", "yard", "yards")),
    Unit("mile", Dimension.LENGTH, 1609.344, "mil", ("mile", "miles"), ("mil", "mile", "miles")),
    Unit("milligram", Dimension.MASS, 0.001, "miligram", ("milligram", "milligrams"),
         ("miligram", "mg", "milligram", "milligrams")),
    Unit("gram", Dimension.MASS, 1, "gram", ("gram", "grams"), ("gram", "gr", "g", "grams", "gramme", "grammes")),
    Unit("kilogram", Dimension.MASS, 1000, "kilogram", ("kilogram", "kilograms"),
         ("kilogram", "kilo", "kg", "kilograms", "kilos")),
    Unit("ton", Dimension.MASS, 1_000_000, "ton", ("ton", "tons"), ("ton", "tons", "tonne", "tonnes")),
    Unit("ounce", Dimension.MASS, 28.349523125, "ons", ("ounce", "ounces"), ("ons", "ounce", "ounces", "oz")),
    Unit("pound", Dimension.MASS, 453.59237, "pound", ("pound", "pounds"), ("pound", "pounds", "lb", "lbs", "libre")),
    Unit("milliliter", Dimension.VOLUME, 1, "mililitre", ("milliliter", "milliliters"),
         ("mililitre", "ml", "milliliter", "milliliters", "millilitre", "millilitres")),
    Unit("liter", Dimension.VOLUME, 1000, "litre", ("liter", "liters"),
         ("litre", "lt", "l", "liter", "liters", "litres")),
    # A Turkish water glass, the cup of Turkish recipes.
    Unit("glass", Dimension.VOLUME, 200, "su bardağı", ("glass", "glasses"),
         ("bardak", "su bardagi", "glass", "glasses")),
    Unit("tea glass", Dimension.VOLUME, 100, "çay bardağı", ("tea glass", "tea glasses"), ("cay bardagi", "tea glass")),
    Unit("cup", Dimension.VOLUME, 236.5882365, "cup", ("cup", "cups"), ("cup", "cups")),
    Unit("tablespoon", Dimension.VOLUME, 15, "yemek kaşığı", ("tablespoon", "tablespoons"),
         ("yemek kasigi", "tablespoon", "tablespoons", "tbsp")),
    Unit("teaspoon", Dimension.VOLUME, 5, "çay kaşığı", ("teaspoon", "teaspoons"),
         ("cay kasigi", "teaspoon", "teaspoons", "tsp")),
    Unit("fluid ounce", Dimension.VOLUME, 29.5735295625, "sıvı ons", ("fluid ounce", "fluid ounces"),
         ("sivi ons", "fluid ounce", "fluid ounces", "fl oz")),
    Unit("gallon", Dimension.VOLUME, 3785.411784, "galon", ("gallon", "gallons"), ("galon", "gallon", "gallons")),
    Unit("square meter", Dimension.AREA, 1, "metrekare", ("square meter", "square meters"),
         ("metrekare", "metre kare", "m2", "square meter", "square meters", "square metre", "square metres")),
    Unit("square kilometer", Dimension.AREA, 1_000_000, "kilometrekare", ("square kilometer", "square kilometers"),
         ("kilometrekare", "kilometre kare", "km2", "square kilometer", "square kilometers", "square kilometre",
          "square kilometres")),
    Unit("square foot", Dimension.AREA, 0.09290304, "feet kare", ("square foot", "square feet"),
         ("feet kare", "fit kare", "square foot", "square feet", "sq ft")),
    Unit("decare", Dimension.AREA, 1000, "dönüm", ("decare", "decares"),
         ("donum", "dekar", "decare", "decares", "dunam", "dunams")),
    Unit("hectare", Dimension.AREA, 10_000, "hektar", ("hectare", "hectares"), ("hektar", "hectare", "hectares")),
    Unit("acre", Dimension.AREA, 4046.8564224, "akre", ("acre", "acres"), ("akre", "acre", "acres")),
    Unit("kilometers per hour", Dimension.SPEED, 1 / 3.6, "kilometre/saat", ("kilometer per hour", "kilometers per hour"),
         ("km saat", "kilometre saat", "km sa", "km h", "kmh", "kph", "kilometers per hour", "kilometer per hour",
          "kilometres per hour", "km per hour")),
    Unit("miles per hour", Dimension.SPEED, 0.44704, "mil/saat", ("mile per hour", "miles per hour"),
         ("mph", "mil saat", "miles per hour", "mile per hour")),
    Unit("meters per second", Dimension.SPEED, 1, "metre/saniye", ("meter per second", "meters per second"),
         ("metre saniye", "m s", "meters per second", "meter per second", "metres per second")),
    Unit("knot", Dimension.SPEED, 1852 / 3600, "knot", ("knot", "knots"), ("knot", "knots", "kts", "deniz mili saat")),
    Unit("celsius", Dimension.TEMPERATURE, 1, "santigrat derece", ("degree Celsius", "degrees Celsius"),
         ("derece", "santigrat", "santigrat derece", "derece santigrat", "celsius", "selsiyus", "celsius derece",
          "derece celsius", "degree celsius", "degrees celsius", "degrees c", "derece c"),
         _KELVIN_OF_ZERO_CELSIUS),
    Unit("fahrenheit", Dimension.TEMPERATURE, _FAHRENHEIT_FACTOR, "Fahrenheit derece",
         ("degree Fahrenheit", "degrees Fahrenheit"),
         ("fahrenheit", "fahrenayt", "farenhayt", "fahrenheit derece", "derece fahrenheit", "degree fahrenheit",
          "degrees fahrenheit", "degrees f", "derece f"),
         _KELVIN_OF_ZERO_CELSIUS - 32 * _FAHRENHEIT_FACTOR),
    Unit("kelvin", Dimension.TEMPERATURE, 1, "kelvin", ("kelvin", "kelvins"), ("kelvin", "kelvins")),
    Unit("byte", Dimension.DATA, 1, "bayt", ("byte", "bytes"), ("bayt", "byte", "bytes")),
    Unit("kilobyte", Dimension.DATA, _BINARY, "kilobayt", ("kilobyte", "kilobytes"),
         ("kilobayt", "kb", "kilobyte", "kilobytes")),
    Unit("megabyte", Dimension.DATA, _BINARY**2, "megabayt", ("megabyte", "megabytes"),
         ("megabayt", "mb", "megabyte", "megabytes")),
    Unit("gigabyte", Dimension.DATA, _BINARY**3, "gigabayt", ("gigabyte", "gigabytes"),
         ("gigabayt", "gb", "giga", "gigabyte", "gigabytes")),
    Unit("terabyte", Dimension.DATA, _BINARY**4, "terabayt", ("terabyte", "terabytes"),
         ("terabayt", "tb", "tera", "terabyte", "terabytes")),
)  # fmt: skip

_NAMES: dict[tuple[str, ...], Unit] = {tuple(name.split()): unit for unit in UNITS for name in unit.names}
_LONGEST_NAME = max(len(words) for words in _NAMES)
# Case endings after the apostrophe Turkish writes ("km'ye") or joined to the word ("kilometreye", "galondan"),
# folded; the n-forms follow compounds ("su bardağına").
_SUFFIXES = (
    "e", "a", "ye", "ya", "i", "u", "yi", "yu", "de", "da", "te", "ta", "den", "dan", "ten", "tan", "dir", "dur",
    "tir", "tur", "le", "la", "yle", "yla", "in", "un", "nin", "nun", "na", "ne", "ni", "nu", "nda", "nde", "ndan",
    "nden", "lik", "luk",
)  # fmt: skip
# Words a conversion request may hold besides numbers and units; anything else means it is about something else.
_FILLERS = frozenset({
    "kac", "eder", "yapar", "olur", "ediyor", "yapiyor", "acaba", "ne", "kadar", "nedir", "cevir", "donustur",
    "hesapla", "soyle", "bana", "lutfen", "olarak", "karsiligi", "how", "many", "much", "is", "are", "in", "to",
    "into", "convert", "what", "whats", "equals", "equal", "make", "makes", "does", "do", "the", "me", "tell",
    "please", "of", "as", "there",
})  # fmt: skip
# The unit after these is the one asked for: "kaç kilometre", "how many feet", "to km", "in Celsius".
_TARGET_MARKERS = frozenset({"kac", "many", "much", "to", "into", "in"})
_NEGATIVE = frozenset({"eksi", "minus", "negative"})
_WORD_NUMBERS = {"bir": 1.0, "a": 1.0, "an": 1.0, "one": 1.0, "yuz": 100.0, "yarim": 0.5, "half": 0.5}
_TOKEN = re.compile(r"-?\d+(?:\.\d+)?|[^\W\d_]+2(?!\d)|[^\W\d_]+")
# A dot or comma before exactly three digits groups thousands ("1.000", "1,000"); otherwise it is a decimal point.
_THOUSANDS = re.compile(r"(?<=\d)[.,](?=\d{3}(?!\d))")
_DECIMAL_COMMA = re.compile(r"(?<=\d),(?=\d)")


def parse(text: str) -> Conversion | None:
    """None unless the whole request is a conversion: numbers, units and the words of a question."""
    items = _items(_tokens(text))
    if items is None:
        return None
    quantities: list[Quantity] = []
    bare: list[tuple[Unit, bool]] = []
    for index, item in enumerate(items):
        if isinstance(item, Unit):
            continue
        if isinstance(item, float):
            following = items[index + 1] if index + 1 < len(items) else None
            if not isinstance(following, Unit):
                return None
            quantities.append(Quantity(item, following))
    for index, item in enumerate(items):
        if isinstance(item, Unit) and not (index > 0 and isinstance(items[index - 1], float)):
            marked = index > 0 and items[index - 1] in _TARGET_MARKERS
            bare.append((item, marked))
    target = _target(quantities, bare)
    if target is None:
        return None
    if not quantities:
        quantities = [Quantity(1.0, unit) for unit, _ in bare if unit is not target]
    return _checked(Conversion(tuple(quantities), target))


def quantities(text: str) -> tuple[Quantity, ...] | None:
    """ "5 foot 10 inch": numbers each followed by a unit, as the tool's argument gives them."""
    items = _items(_tokens(text))
    if not items or len(items) % 2:
        return None
    pairs = list(zip(items[::2], items[1::2], strict=True))
    if not all(isinstance(value, float) and isinstance(unit, Unit) for value, unit in pairs):
        return None
    return tuple(Quantity(value, unit) for value, unit in pairs)


def unit_named(text: str) -> Unit | None:
    items = _items(_tokens(text))
    return items[0] if items is not None and len(items) == 1 and isinstance(items[0], Unit) else None


def checked(quantities_given: tuple[Quantity, ...], target: Unit) -> Conversion | None:
    return _checked(Conversion(quantities_given, target))


def convert(conversion: Conversion) -> float:
    target = conversion.target
    base = sum(q.value * q.unit.factor + q.unit.offset for q in conversion.quantities)
    return (base - target.offset) / target.factor


def spoken(quantities_given: tuple[Quantity, ...], language: AssistantLanguage) -> str:
    """ "5 feet 10 inç" / "5 feet 10 inches"."""
    return " ".join(f"{number(q.value, language)} {q.unit.name(language, q.value)}" for q in quantities_given)


def canonical(quantities_given: tuple[Quantity, ...]) -> str:
    """The tool argument for these quantities; `quantities` reads it back."""
    return " ".join(f"{format(q.value, 'g')} {q.unit.key}" for q in quantities_given)


def rounded(value: float) -> float:
    """Two decimals, or three significant digits below one ("0,0254")."""
    if value == 0 or abs(value) >= 1:
        return round(value, 2)
    return round(value, 2 - math.floor(math.log10(abs(value))))


def number(value: float, language: AssistantLanguage) -> str:
    """Decimal comma in Turkish; the minus sign as a word, since it is read aloud."""
    text = format(Decimal(repr(abs(rounded(value)))), "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    turkish = language is AssistantLanguage.TURKISH
    if turkish:
        text = text.replace(".", ",")
    if rounded(value) < 0:
        text = ("eksi " if turkish else "minus ") + text
    return text


def _checked(conversion: Conversion) -> Conversion | None:
    dimension = conversion.target.dimension
    if not conversion.quantities or any(q.unit.dimension is not dimension for q in conversion.quantities):
        return None
    # "5 feet 10 inç" adds up; two temperatures don't.
    if len(conversion.quantities) > 1 and dimension is Dimension.TEMPERATURE:
        return None
    return conversion


def _target(quantities_found: list[Quantity], bare: list[tuple[Unit, bool]]) -> Unit | None:
    if quantities_found:
        return bare[0][0] if len(bare) == 1 else None
    if len(bare) != 2:
        return None
    marked = [unit for unit, is_marked in bare if is_marked]
    if len(marked) == 1:
        return marked[0]
    return None


def _tokens(text: str) -> list[str]:
    text = lowercased(text).replace("²", "2").replace("°", " degrees ")
    text = _DECIMAL_COMMA.sub(".", _THOUSANDS.sub("", text))
    text = "".join(ch for ch in text if ch not in "'’‘`´")
    return [token if token[-1].isdigit() and token[0] in "-0123456789" else folded(token) for token in
            _TOKEN.findall(text)]  # fmt: skip


def _items(tokens: list[str]) -> list[float | Unit | str] | None:
    """Numbers, units and filler words; None when a word belongs to neither."""
    items: list[float | Unit | str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        value = _number_at(tokens, index)
        if value is not None:
            amount, used = value
            items.append(amount)
            index += used
            continue
        unit = _unit_at(tokens, index)
        if unit is not None:
            items.append(unit[0])
            index += unit[1]
            continue
        if token not in _FILLERS:
            return None
        items.append(token)
        index += 1
    return items


def _number_at(tokens: list[str], index: int) -> tuple[float, int] | None:
    """A number and how many tokens it took: "2,5", "2 buçuk", "0 virgül 5", "bir", "eksi 10", "yarım"."""
    sign, start = (-1.0, index + 1) if tokens[index] in _NEGATIVE else (1.0, index)
    if start >= len(tokens):
        return None
    token = tokens[start]
    if _is_digits(token):
        value, used = float(token), 1
        rest = tokens[start + 1 :]
        if rest[:1] == ["bucuk"]:
            value, used = value + 0.5, 2
        elif len(rest) >= 2 and rest[0] in ("virgul", "point") and rest[1].isdigit():
            value, used = float(f"{token}.{rest[1]}"), 3
        return sign * value, start - index + used
    # Only before a unit: "bir" is also "a", "yüz" also "face".
    word_value = _WORD_NUMBERS.get(token)
    if sign < 0 or word_value is None or _unit_at(tokens, start + 1) is None:
        return None
    return word_value, 1


def _is_digits(token: str) -> bool:
    return bool(re.fullmatch(r"-?\d+(?:\.\d+)?", token))


def _unit_at(tokens: list[str], index: int) -> tuple[Unit, int] | None:
    for size in range(min(_LONGEST_NAME, len(tokens) - index), 0, -1):
        words = tokens[index : index + size]
        unit = _NAMES.get(tuple(words)) or _with_suffix(words)
        if unit is not None:
            return unit, size
    return None


def _with_suffix(words: list[str]) -> Unit | None:
    *head, last = words
    for suffix in _SUFFIXES:
        if not last.endswith(suffix) or len(last) <= len(suffix):
            continue
        stem = last[: -len(suffix)]
        candidates = [stem, stem[:-1] + "k"] if stem.endswith("g") else [stem]
        for candidate in candidates:
            # A one-letter abbreviation with an ending is a word: "me", "de", "mi".
            unit = _NAMES.get((*head, candidate)) if len(candidate) > 1 else None
            if unit is not None:
                return unit
    return None
