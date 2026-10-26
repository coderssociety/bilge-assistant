"""Short encyclopedic facts from Wikipedia's page summaries (Turkish or English Wikipedia), for the model to answer
"X kimdir", "Y nedir" briefly. No account or key."""

from typing import Any
from urllib.parse import quote, urlencode

from bilge.core.language import AssistantLanguage
from bilge.core.web import encyclopedia_request, fuel_prices, gold_prices, prayer_times
from bilge.core.web.encyclopedia_request import Summary
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError

EN = AssistantLanguage.ENGLISH
# Enough for the lead of an article; the model tells it in a sentence or two.
EXTRACT_CHARACTERS = 1_500
SEARCH_RESULTS = 5


def _current(command: str, english: bool) -> bool:
    """Questions another tool answers with today's data."""
    return (
        encyclopedia_request.asks_about_now(command, english)
        or prayer_times.claims(command, english)
        or gold_prices.claims(command, english)
        or fuel_prices.claims(command, english, names_place=False)
    )


def wikipedia(language: AssistantLanguage) -> Tool:
    english = language is EN
    site = f"https://{'en' if english else 'tr'}.wikipedia.org"

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        said = encyclopedia_request.subject(command, english)
        if said is None and _current(command, english):
            return {"subject": None, "current": True}
        return {"subject": said or str(arguments.get("subject") or "").strip() or None}

    def summary(title: str) -> Summary | None:
        try:
            data = web_fetch.get_json(
                f"{site}/api/rest_v1/page/summary/{quote(title.replace(' ', '_'), safe='')}", language
            )
        except web_fetch.WebFetchError as error:
            if error.reason is web_fetch.Reason.STATUS and error.status == 404:
                return None
            raise
        return encyclopedia_request.from_summary(data)

    def look_up(subject: str) -> Summary | None:
        found = summary(subject)
        if found is not None and not found.disambiguation:
            return found
        query = urlencode({"action": "opensearch", "search": subject, "limit": SEARCH_RESULTS, "namespace": 0,
                           "format": "json"})  # fmt: skip
        for title in encyclopedia_request.from_opensearch(web_fetch.get_json(f"{site}/w/api.php?{query}", language)):
            if found is not None and title == found.title:
                continue
            candidate = summary(title)
            if candidate is not None and not candidate.disambiguation:
                return candidate
        # A disambiguation page still opens with the best-known meaning.
        return found

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("current"):
            raise ToolError(
                "That asks for current information, not an encyclopedia entry."
                if english
                else "Bu güncel bir bilgi sorusu, ansiklopedide aranmaz."
            )
        subject = str(arguments.get("subject") or "").strip()
        if not subject:
            raise ToolError("I didn't get what to look up." if english else "Neyi arayacağımı anlayamadım.")
        try:
            found = look_up(subject)
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't reach Wikipedia. " if english else "Vikipedi'ye ulaşılamadı. ")
                + web_fetch.describe(error, language)
            ) from error
        if found is None:
            raise ToolError(
                f"Wikipedia has nothing on '{subject}'."
                if english
                else f"Vikipedi'de '{subject}' ile ilgili bir şey bulamadım."
            )
        heading = f"{found.title} ({found.description})" if found.description else found.title
        return f"{'Wikipedia' if english else 'Vikipedi'}: {heading}\n{found.extract[:EXTRACT_CHARACTERS]}"

    return Tool(
        "wikipedia",
        "Looks up a person, place, thing or idea on Wikipedia for 'who is X', 'what is Y', 'tell me about Z'. Only for "
        "such encyclopedic questions; never for the weather, prices, news, times or anything about today."
        if english
        else "'X kimdir', 'Y nedir', 'Z hakkında bilgi ver' gibi ansiklopedik sorular için bir kişiyi, yeri, şeyi ya da "
        "kavramı Vikipedi'de arar. Yalnızca bu tür sorular için; hava, fiyat, haber, saat ya da bugüne dair "
        "sorularda kullanma.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "subject": {
                    "type": "string",
                    "description": "What to look up, e.g. 'Ada Lovelace'"
                    if english
                    else "Aranacak konu, eksiz: 'Atatürk kimdir' → 'Atatürk'",
                }
            },
            "required": ["subject"],
        },
        refine=refine,
        untrusted_output=True,
        spoken_action=lambda a: (
            f"Shall I look up {a.get('subject') or 'that'} on Wikipedia?"
            if english
            else f"{a.get('subject') or 'Bunu'} için Vikipedi'ye bakayım mı?"
        ),
    )
