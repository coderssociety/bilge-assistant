import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.speech import turkish_number_parser
from bilge.core.tools import unit_conversion

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


def converted(command: str) -> tuple[str, str, str] | None:
    conversion = unit_conversion.parse(turkish_number_parser.digitize(command))
    if conversion is None:
        return None
    value = unit_conversion.convert(conversion)
    return unit_conversion.spoken(conversion.quantities, TR), unit_conversion.number(value, TR), conversion.target.key


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("10 mil kaç kilometre", ("10 mil", "16,09", "kilometer")),
        ("on mil kaç kilometre", ("10 mil", "16,09", "kilometer")),
        ("100 fahrenheit kaç derece", ("100 Fahrenheit derece", "37,78", "celsius")),
        ("yüz fahrenheit kaç derece", ("100 Fahrenheit derece", "37,78", "celsius")),
        ("eksi 40 derece kaç fahrenheit", ("eksi 40 santigrat derece", "eksi 40", "fahrenheit")),
        ("2 litre kaç bardak", ("2 litre", "10", "glass")),
        ("3 su bardağı kaç ml", ("3 su bardağı", "600", "milliliter")),
        ("5 feet 10 inç kaç santim", ("5 feet 10 inç", "177,8", "centimeter")),
        ("1 GB kaç MB", ("1 gigabayt", "1024", "megabyte")),
        ("bir terabayt kaç gigabayt", ("1 terabayt", "1024", "gigabyte")),
        ("60 mph kaç km/saat", ("60 mil/saat", "96,56", "kilometers per hour")),
        ("1 dönüm kaç metrekare", ("1 dönüm", "1000", "square meter")),
        ("12 ons kaç gram", ("12 ons", "340,19", "gram")),
        ("2 buçuk kilo kaç pound", ("2,5 kilogram", "5,51", "pound")),
        ("1 pound kaç kilo", ("1 pound", "0,454", "kilogram")),
        ("1 cup kaç ml", ("1 cup", "236,59", "milliliter")),
        ("2,5 litre kaç mililitre", ("2,5 litre", "2500", "milliliter")),
        ("0 virgül 5 litre kaç mililitre", ("0,5 litre", "500", "milliliter")),
        ("mil kaç kilometre", ("1 mil", "1,61", "kilometer")),
        ("10 mili kilometreye çevir", ("10 mil", "16,09", "kilometer")),
        ("500 metre kaç km'dir", ("500 metre", "0,5", "kilometer")),
        ("1 inç kaç kilometre", ("1 inç", "0,0000254", "kilometer")),
    ],
)
def test_turkish_conversions_are_parsed_and_computed_exactly(command, expected):
    assert converted(command) == expected


@pytest.mark.parametrize(
    ("command", "spoken", "target"),
    [
        ("how many feet in a mile", "1 mile", "foot"),
        ("10 miles to km", "10 miles", "kilometer"),
        ("what's 100°F in Celsius", "100 degrees Fahrenheit", "celsius"),
        ("convert 5 kg to pounds", "5 kilograms", "pound"),
        ("how many cups is 1 liter", "1 liter", "cup"),
        ("1,000 meters in miles", "1000 meters", "mile"),
    ],
)
def test_english_phrasings_are_understood(command, spoken, target):
    conversion = unit_conversion.parse(command)
    assert conversion is not None
    assert unit_conversion.spoken(conversion.quantities, EN) == spoken
    assert conversion.target.key == target


@pytest.mark.parametrize(
    "command",
    [
        "saat kaç",
        "2 litre süt al",
        "10 kilo kaç kalori",
        "5 metre kaç kilogram",
        "10 derece 5 fahrenheit kaç kelvin",
        "10 mil",
        "kilometre",
        "Tokyo'da saat kaç",
        "10 dakika sonra uyar",
        "me",
    ],
)
def test_anything_but_a_whole_conversion_is_left_alone(command):
    assert unit_conversion.parse(command) is None


def test_canonical_arguments_read_back_to_the_same_quantities():
    conversion = unit_conversion.parse("5 feet 10 inç kaç santim")
    assert conversion is not None
    text = unit_conversion.canonical(conversion.quantities)
    assert text == "5 foot 10 inch"
    assert unit_conversion.quantities(text) == conversion.quantities
    assert unit_conversion.unit_named("centimeter") is conversion.target
    assert unit_conversion.unit_named("kilometreye") is unit_conversion.unit_named("km")


def test_mismatched_dimensions_do_not_convert():
    meters = unit_conversion.quantities("5 meter")
    kilograms = unit_conversion.unit_named("kilogram")
    assert meters is not None and kilograms is not None
    assert unit_conversion.checked(meters, kilograms) is None


@pytest.mark.parametrize(
    ("value", "turkish", "english"),
    [(16.0934, "16,09", "16.09"), (0.000254, "0,000254", "0.000254"), (-3.5, "eksi 3,5", "minus 3.5"), (0, "0", "0")],
)
def test_numbers_are_rounded_for_speech(value, turkish, english):
    assert unit_conversion.number(value, TR) == turkish
    assert unit_conversion.number(value, EN) == english
