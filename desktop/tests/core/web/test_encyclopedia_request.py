import pytest

from bilge.core.web import encyclopedia_request

from ...fixtures import web_json


@pytest.mark.parametrize(
    ("command", "english", "subject"),
    [
        ("Atatürk kimdir", False, "Atatürk"),
        ("Mustafa Kemal Atatürk kimdir?", False, "Mustafa Kemal Atatürk"),
        ("fotosentez nedir", False, "fotosentez"),
        ("peki kuantum fiziği ne demek", False, "kuantum fiziği"),
        ("Mars hakkında bilgi ver", False, "Mars"),
        ("bana İstanbul'un fethi hakkında bilgi verir misin", False, "İstanbul'un fethi"),
        ("who was Ada Lovelace", True, "Ada Lovelace"),
        ("what is a black hole?", True, "black hole"),
        ("tell me about the Ottoman Empire", True, "Ottoman Empire"),
    ],
)
def test_finds_what_an_encyclopedic_question_is_about(command, english, subject):
    assert encyclopedia_request.subject(command, english) == subject


@pytest.mark.parametrize(
    ("command", "english"),
    [
        ("bugün hava nedir", False),
        ("senin adın nedir", False),
        ("dolar kuru nedir", False),
        ("altın fiyatı nedir", False),
        ("akşam ezanı vakti nedir", False),
        ("nedir", False),
        ("dolar ne kadar", False),
        ("Mars hakkında", False),
        ("what's the weather like", True),
        ("what is the time", True),
        ("who are you", True),
        ("what is", True),
    ],
)
def test_questions_about_now_or_the_assistant_are_not_encyclopedic(command, english):
    assert encyclopedia_request.subject(command, english) is None


def test_knows_a_question_about_now():
    assert encyclopedia_request.asks_about_now("hava nasıl", english=False)
    assert encyclopedia_request.asks_about_now("altın fiyatları", english=False)
    assert encyclopedia_request.asks_about_now("what's the news", english=True)
    assert not encyclopedia_request.asks_about_now("Atatürk'ün doğum yeri", english=False)


def test_reads_page_summaries_and_search_results():
    summary = encyclopedia_request.from_summary(web_json("wikipedia_summary_ataturk.json"))
    assert summary.title == "Mustafa Kemal Atatürk"
    assert summary.description == "Türkiye Cumhuriyeti'nin kurucusu ve ilk cumhurbaşkanı"
    assert summary.extract.startswith("Mustafa Kemal Atatürk, Türk mareşal")
    assert not summary.disambiguation
    assert encyclopedia_request.from_summary(web_json("wikipedia_summary_ankara_disambiguation.json")).disambiguation
    assert (
        encyclopedia_request.from_summary({"type": "https://mediawiki.org/wiki/HyperSwitch/errors/not_found"}) is None
    )
    assert encyclopedia_request.from_summary({"type": "standard", "title": "Boş", "extract": ""}) is None
    assert encyclopedia_request.from_opensearch(web_json("wikipedia_opensearch_ankara.json"))[:2] == [
        "Ankara",
        "Ankara Garı Saldırısı",
    ]
    assert encyclopedia_request.from_opensearch({"error": "x"}) == []
