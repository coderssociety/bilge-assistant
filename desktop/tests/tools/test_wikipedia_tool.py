import json

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import wikipedia

from ..fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
SUMMARY = "https://tr.wikipedia.org/api/rest_v1/page/summary/"
SEARCH = "https://tr.wikipedia.org/w/api.php?"


def fake_web(monkeypatch, pages, asked):
    def get(url, language=TR, max_bytes=0):
        asked.append(url)
        for prefix, body in pages.items():
            if url.startswith(prefix):
                status, data = body if isinstance(body, tuple) else (200, body)
                return web_fetch.Response(url, status, "application/json", json.dumps(data).encode())
        return web_fetch.Response(url, 404, "application/json", b'{"type": "not_found"}')

    monkeypatch.setattr(web_fetch, "get", get)


def test_the_subject_said_wins_and_questions_about_now_are_turned_away():
    tool = wikipedia.wikipedia(TR)
    assert tool.refine({"subject": "Ataturk"}, "Mustafa Kemal Atatürk kimdir") == {"subject": "Mustafa Kemal Atatürk"}
    assert tool.refine({"subject": "Fotosentez"}, "bitkiler nasıl beslenir") == {"subject": "Fotosentez"}
    for command in ("gram altın kaç lira", "akşam ezanı kaçta", "benzin ne kadar", "hava nasıl"):
        arguments = tool.refine({"subject": "x"}, command)
        with pytest.raises(ToolError, match="güncel bir bilgi"):
            tool.run(arguments)
    assert tool.reads_untrusted({"subject": "Mars"})


def test_reads_the_summary(monkeypatch):
    asked = []
    fake_web(monkeypatch, {f"{SUMMARY}Atat%C3%BCrk": web_json("wikipedia_summary_ataturk.json")}, asked)
    told = wikipedia.wikipedia(TR).run({"subject": "Atatürk"})
    assert told.startswith(
        "Vikipedi: Mustafa Kemal Atatürk (Türkiye Cumhuriyeti'nin kurucusu ve ilk cumhurbaşkanı)\nMustafa Kemal Atatürk,"
    )
    assert asked == [f"{SUMMARY}Atat%C3%BCrk"]


def test_searches_for_the_title_when_there_is_no_page_or_only_a_disambiguation(monkeypatch):
    asked = []
    pages = {
        f"{SUMMARY}ankara": web_json("wikipedia_summary_ankara_disambiguation.json"),
        SEARCH: web_json("wikipedia_opensearch_ankara.json"),
        f"{SUMMARY}Ankara": web_json("wikipedia_summary_ataturk.json"),
    }
    fake_web(monkeypatch, pages, asked)
    assert wikipedia.wikipedia(TR).run({"subject": "ankara"}).startswith("Vikipedi: Mustafa Kemal Atatürk")
    assert asked[1].startswith(SEARCH) and "search=ankara" in asked[1]


def test_says_when_nothing_is_found_or_wikipedia_cant_be_reached(monkeypatch):
    fake_web(monkeypatch, {SEARCH: ["xyzzy", [], [], []]}, [])
    with pytest.raises(ToolError, match="Vikipedi'de 'xyzzy' ile ilgili bir şey bulamadım."):
        wikipedia.wikipedia(TR).run({"subject": "xyzzy"})
    fake_web(monkeypatch, {SUMMARY: (503, {}), SEARCH: (503, {})}, [])
    with pytest.raises(ToolError, match="Vikipedi'ye ulaşılamadı. Sunucu şu an yanıt veremiyor."):
        wikipedia.wikipedia(TR).run({"subject": "Mars"})


def test_english_questions_go_to_english_wikipedia(monkeypatch):
    asked = []
    fake_web(monkeypatch, {"https://en.wikipedia.org/w/api.php?": ["Ada Lovelace", [], [], []]}, asked)
    with pytest.raises(ToolError, match="Wikipedia has nothing on 'Ada Lovelace'."):
        english = wikipedia.wikipedia(EN)
        english.run(english.refine({}, "who was Ada Lovelace"))
    assert asked[0] == "https://en.wikipedia.org/api/rest_v1/page/summary/Ada_Lovelace"
