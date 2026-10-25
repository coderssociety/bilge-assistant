import re
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.tools import unit_conversion
from bilge.tools.base import Tool, ToolError

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "description": "Birim çevirir: uzunluk (km, mil, feet, inç), ağırlık (kg, pound, ons), hacim (litre, ml, su bardağı = 200 ml, cup), alan (metrekare, dönüm, hektar, akre), hız (km/saat, mph), sıcaklık (santigrat, Fahrenheit, kelvin), veri (MB, GB, TB).",
        "quantity": "Çevrilecek miktar, sayı ve birimle: '10 mil', '5 feet 10 inç'",
        "to": "Hedef birim: 'kilometre', 'santimetre'",
        "unclear": "Neyi neye çevireceğimi anlayamadım; miktarı ve iki birimi söyler misin?",
        "mismatch": "{source} ile {target} birbirine çevrilemez.",
        "result": "{source} {approx}{value} {target} eder.",
        "approx": "yaklaşık ",
    },
    AssistantLanguage.ENGLISH: {
        "description": "Converts units: length (km, miles, feet, inches), weight (kg, pounds, ounces), volume (liters, ml, glasses of 200 ml, cups), area (square meters, decares, hectares, acres), speed (km/h, mph), temperature (Celsius, Fahrenheit, kelvin), data (MB, GB, TB).",
        "quantity": "The amount to convert, with numbers and units: '10 miles', '5 feet 10 inches'",
        "to": "The unit wanted: 'kilometers', 'centimeters'",
        "unclear": "I didn't get what to convert into what; could you say the amount and both units?",
        "mismatch": "{source} can't be converted to {target}.",
        "result": "{source} is {approx}{value} {target}.",
        "approx": "about ",
    },
}  # fmt: skip
_NUMBER = re.compile(r"\d+(?:[.,]\d+)?")


def convert_units(language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # What was said is parsed exactly; the model's own amount is only kept when its numbers were said.
        parsed = unit_conversion.parse(command)
        if parsed is not None:
            return {"quantity": unit_conversion.canonical(parsed.quantities), "to": parsed.target.key}
        given = unit_conversion.quantities(str(arguments.get("quantity") or ""))
        if given is None or not _grounded(given, command):
            return {**arguments, "quantity": ""}
        return arguments

    def run(arguments: dict[str, Any]) -> str:
        given = unit_conversion.quantities(str(arguments.get("quantity") or ""))
        target = unit_conversion.unit_named(str(arguments.get("to") or ""))
        if not given or target is None:
            raise ToolError(texts["unclear"])
        conversion = unit_conversion.checked(given, target)
        source = unit_conversion.spoken(given, language)
        if conversion is None:
            raise ToolError(texts["mismatch"].format(source=source, target=target.name(language, 2)))
        value = unit_conversion.convert(conversion)
        shown = unit_conversion.rounded(value)
        return texts["result"].format(
            source=source,
            approx="" if abs(shown - value) < 1e-9 else texts["approx"],
            value=unit_conversion.number(value, language),
            target=target.name(language, shown),
        )

    return Tool(
        "convertUnits",
        texts["description"],
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "quantity": {"type": "string", "description": texts["quantity"]},
                "to": {"type": "string", "description": texts["to"]},
            },
            "required": ["quantity", "to"],
        },
        refine=refine,
    )


def _grounded(given: tuple[unit_conversion.Quantity, ...], command: str) -> bool:
    said = {float(match.replace(",", ".")) for match in _NUMBER.findall(command)}
    return all(quantity.value in said or quantity.value == 1 for quantity in given)
