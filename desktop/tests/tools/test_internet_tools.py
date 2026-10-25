import json
from datetime import datetime

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import internet

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


def fake_web(monkeypatch, pages):
    def get(url, language=TR, max_bytes=0):
        for prefix, body in pages.items():
            if url.startswith(prefix):
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                return web_fetch.Response(url, 200, "application/json", data)
        raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)

    monkeypatch.setattr(web_fetch, "get", get)


def test_weather_ignores_a_city_nobody_said():
    tool = internet.weather(TR, lambda: "İzmir")
    assert tool.refine({"city": "Ankara"}, "bugün hava nasıl")["city"] is None
    assert tool.refine({"city": "Ankara"}, "Ankara'da hava nasıl") == {"city": "Ankara"}


def test_weather_reads_the_forecast(monkeypatch):
    fake_web(
        monkeypatch,
        {
            "https://geocoding-api": {"results": [{"name": "İzmir", "latitude": 38.4, "longitude": 27.1}]},
            "https://api.open-meteo.com": {
                "current": {"temperature_2m": 21.4, "weather_code": 0},
                "daily": {
                    "time": ["a", "b"],
                    "weather_code": [0, 61],
                    "temperature_2m_max": [24, 19],
                    "temperature_2m_min": [15, 12],
                    "precipitation_probability_max": [0, 80],
                },
            },
        },
    )
    tool = internet.weather(TR, lambda: "İzmir")
    assert "İzmir'de" in tool.run({})
    tomorrow = tool.run({"day_offset": 1})
    assert "yarın" in tomorrow and "80" in tomorrow


def forecast_web(monkeypatch, asked):
    def get(url, language=TR, max_bytes=0):
        asked.append(url)
        if url.startswith("https://geocoding-api"):
            name = "Ankara" if "Ankara" in url else "İzmir"
            body = {"results": [{"name": name, "latitude": 38.4, "longitude": 27.1}]}
        else:
            hours = 48
            body = {
                "current": {"temperature_2m": 21.4, "weather_code": 0},
                "daily": {"time": ["a", "b"], "weather_code": [0, 61], "temperature_2m_max": [24, 19],
                          "temperature_2m_min": [15, 12], "precipitation_probability_max": [10, 80]},
                "hourly": {"temperature_2m": [10 + h % 24 / 2 for h in range(hours)],
                           "precipitation_probability": [5 if h < 24 else 40 + h % 24 for h in range(hours)]},
            }  # fmt: skip
        return web_fetch.Response(url, 200, "application/json", json.dumps(body).encode())

    monkeypatch.setattr(web_fetch, "get", get)


def test_a_follow_up_without_a_city_stays_in_the_city_just_asked_about(monkeypatch):
    asked = []
    forecast_web(monkeypatch, asked)
    now = [datetime(2026, 10, 15, 14, 0)]
    tool = internet.weather(TR, lambda: "Ankara", internet.WeatherFollowUp(clock=lambda: now[0]))
    tool.run(tool.refine({"city": "İzmir"}, "İzmir'de hava nasıl"))
    follow_up = tool.refine({"city": "Ankara"}, "peki yarın?")
    assert (follow_up["city"], follow_up["day_offset"]) == ("İzmir", 1)
    assert tool.run(follow_up).startswith("İzmir'de yarın hava hafif yağmurlu")
    now[0] += internet.FOLLOW_UP_WINDOW
    assert tool.refine({}, "peki yarın?")["city"] is None


def test_will_it_rain_reads_todays_chance_of_rain(monkeypatch):
    forecast_web(monkeypatch, [])
    tool = internet.weather(TR, lambda: "İzmir")
    arguments = tool.refine({}, "yağmur yağacak mı")
    assert arguments == {"city": None, "day_offset": 0, "rain": True}
    assert tool.run(arguments) == (
        "İzmir'de bugün hava açık, sıcaklık 15 ile 24 derece arasında. Yağış ihtimali yüzde 10."
    )


def test_a_part_of_the_day_reads_the_hourly_forecast(monkeypatch):
    asked = []
    forecast_web(monkeypatch, asked)
    tool = internet.weather(TR, lambda: "İzmir")
    evening = tool.refine({}, "akşam yağmur var mı")
    assert evening == {"city": None, "day_offset": 0, "part": "evening", "rain": True}
    assert tool.run(evening) == "İzmir'de bu akşam sıcaklık 19 ile 21 derece arasında, yağış ihtimali en fazla yüzde 5."
    assert "hourly=temperature_2m%2Cprecipitation_probability" in asked[-1]
    english = internet.weather(EN, lambda: "Izmir")
    morning = english.refine({}, "will it rain tomorrow morning")
    assert english.run(morning) == (
        "In İzmir tomorrow morning it will be between 13 and 16 degrees, with at most a 51 percent chance of rain."
    )


def test_weather_without_a_connection_is_a_spoken_error(monkeypatch):
    fake_web(monkeypatch, {})
    with pytest.raises(ToolError, match="Hava durumu alınamadı"):
        internet.weather(TR, lambda: "İzmir").run({})


def test_english_exchange_defaults_to_the_dollar():
    tool = internet.exchange_rate(EN)
    assert tool.refine({"from": "EUR", "to": "TRY"}, "how much is the euro")["to"] == "USD"
    assert tool.refine({"from": "USD", "to": "TRY"}, "how much is the dollar")["to"] == "EUR"
    assert tool.refine({"from": "EUR", "to": "TRY"}, "euro in lira")["to"] == "TRY"


def test_the_amount_and_currencies_come_from_the_words():
    tool = internet.exchange_rate(TR)
    assert tool.refine({"from": "EUR", "to": "USD", "amount": 1}, "100 euro kaç para") == {
        "from": "EUR",
        "to": "TRY",
        "amount": 100.0,
    }
    assert tool.refine({"from": "USD"}, "50 sterlin kaç dolar") == {"from": "GBP", "to": "USD", "amount": 50.0}
    assert tool.refine({"from": "USD", "amount": 3}, "bugün kur ne")["amount"] == 3
    english = internet.exchange_rate(EN)
    assert english.refine({"from": "USD", "to": "TRY"}, "how much is €100") == {
        "from": "EUR",
        "to": "USD",
        "amount": 100.0,
    }


def test_gold_is_sent_to_the_gold_price_tool_rather_than_taken_for_a_currency():
    tool = internet.exchange_rate(TR)
    arguments = tool.refine({"from": "TRY"}, "gram altın kaç lira")
    with pytest.raises(ToolError, match="Altın bir döviz değil"):
        tool.run(arguments)
    with pytest.raises(ToolError, match="Gold isn't a currency"):
        internet.exchange_rate(EN).run({"gold": True})
    assert internet.asks_for_gold(TR)("çeyrek altın ne kadar")
    assert internet.asks_for_gold(TR)("ons kaç dolar")
    assert not internet.asks_for_gold(TR)("dolar ne kadar")


def test_exchange_rate_sentence(monkeypatch):
    fake_web(monkeypatch, {"https://api.frankfurter.app": {"rates": {"TRY": 4123.456}}})
    assert internet.exchange_rate(TR).run({"from": "USD", "amount": 100}) == "100 dolar 4.123,46 lira."


def test_news_reads_headlines(monkeypatch):
    rss = b"<rss><channel><item><title>Birinci</title></item><item><title>Ikinci.</title></item></channel></rss>"
    fake_web(monkeypatch, {"https://www.aa.com.tr": rss})
    assert internet.news(TR).run({}) == "Anadolu Ajansı'ndan son başlıklar. Birinci. Ikinci."


def _feed(count: int) -> bytes:
    items = "".join(f"<item><title>Haber {n}</title></item>" for n in range(1, count + 1))
    return f"<rss><channel>{items}</channel></rss>".encode()


def test_news_names_the_topic_and_goes_on_when_asked_again(monkeypatch):
    fake_web(monkeypatch, {"https://www.aa.com.tr/tr/rss/default?cat=bilim-teknoloji": _feed(7)})
    tool = internet.news(TR)
    arguments = tool.refine({"category": "general"}, "Teknoloji haberlerinden başlık var mı")
    assert arguments == {"category": "technology", "source": None}
    assert tool.run(arguments).startswith("Anadolu Ajansı'ndan son bilim-teknoloji başlıkları. Haber 1.")
    follow_up = tool.refine({"category": "general"}, "Bu kadar mı")
    assert tool.run(follow_up) == "Sıradaki başlıklar. Haber 6. Haber 7."
    assert tool.run(follow_up).startswith("Son okuduğumdan beri yeni başlık yok;")


def test_news_keeps_the_models_topic_when_the_command_asks_for_news(monkeypatch):
    tool = internet.news(TR)
    assert tool.refine({"category": "general"}, "Bugünün önemli haberleri var mı") == {
        "category": "general",
        "source": None,
    }


def test_another_source_after_the_headlines_reads_the_next_one(monkeypatch):
    fake_web(
        monkeypatch,
        {"https://www.aa.com.tr/tr/rss": _feed(3), "https://www.trthaber.com/manset_articles.rss": _feed(2)},
    )
    reading = internet.NewsReading()
    tool = internet.news(TR, reading)
    claims = internet.news_source_rule_claims(TR, reading)
    assert not claims("Başka bir kaynak")
    assert tool.run(tool.refine({}, "Bugünün haberleri")).startswith("Anadolu Ajansı'ndan son başlıklar.")
    assert claims("Başka bir kaynak")
    arguments = tool.refine({}, "Başka bir kaynak")
    assert arguments == {"category": "general", "source": "trtHaber"}
    assert tool.run(arguments) == "TRT Haber'den son başlıklar. Haber 1. Haber 2."
    assert tool.refine({}, "bu kadar mı")["source"] == "trtHaber"


def test_a_named_source_is_read_and_one_without_the_topic_gives_its_general_headlines(monkeypatch):
    fake_web(monkeypatch, {"https://feeds.bbci.co.uk/turkce/rss.xml": _feed(1)})
    tool = internet.news(TR)
    assert internet.news_source_rule_claims(TR, internet.NewsReading())("BBC teknoloji haberleri")
    arguments = tool.refine({"category": "general"}, "BBC teknoloji haberleri")
    assert arguments == {"category": "technology", "source": "bbcTurkish"}
    assert tool.run(arguments) == "BBC Türkçe'den son başlıklar. Haber 1."


def _linked_feed() -> bytes:
    items = "".join(
        f"<item><title>{title}</title><link>https://www.aa.com.tr/tr/haber/{n}</link></item>"
        for n, title in enumerate(["Tesla yeni aracını tanıttı", "Claude'un keşfettiği buluş üzerinde çalışan biyolog"])
    )
    return f"<rss><channel>{items}</channel></rss>".encode()


def test_a_story_from_the_headlines_is_read_and_opened_when_asked(monkeypatch):
    page = "<html><head><title>AA</title></head><body><p>Açık, bir yapay zekâ tarafından bulundu.</p></body></html>"
    fake_web(
        monkeypatch, {"https://www.aa.com.tr/tr/rss": _linked_feed(), "https://www.aa.com.tr/tr/haber/1": page.encode()}
    )
    opened = []
    reading = internet.NewsReading()
    internet.news(TR, reading).run({})
    tool = internet.news_article(TR, reading, opened.append)
    arguments = tool.refine({"headline": "Claude"}, "Cloud'un keşfettiği buluşu açar mısın")
    assert arguments["link"] == "https://www.aa.com.tr/tr/haber/1" and arguments["open"] is True
    story = tool.run(arguments)
    assert story.startswith("Haber: Claude'un keşfettiği buluş üzerinde çalışan biyolog\n(Haber tarayıcıda açıldı.)")
    assert "yapay zekâ tarafından bulundu" in story
    assert opened == ["https://www.aa.com.tr/tr/haber/1"]
    assert tool.untrusted_output


def test_a_story_is_only_opened_from_a_headline_read_out(monkeypatch):
    fake_web(monkeypatch, {"https://www.aa.com.tr/tr/rss": _linked_feed()})
    reading = internet.NewsReading()
    internet.news(TR, reading).run({})
    tool = internet.news_article(TR, reading, lambda link: None)
    arguments = tool.refine({"headline": "başka bir şey", "link": "https://evil.example/?data=x"}, "şunu aç")
    assert "link" not in arguments
    with pytest.raises(ToolError, match="Hangi haberi"):
        tool.run({"headline": "x", "link": "https://evil.example/?data=x"})


def test_an_error_page_is_not_told_as_the_story(monkeypatch):
    fake_web(monkeypatch, {"https://www.aa.com.tr/tr/rss": _linked_feed()})
    reading = internet.NewsReading()
    internet.news(TR, reading).run({})
    monkeypatch.setattr(
        web_fetch, "get", lambda url, language=TR, max_bytes=0: web_fetch.Response(url, 403, "text/html", b"Forbidden")
    )
    tool = internet.news_article(TR, reading, lambda link: None)
    arguments = tool.refine({"headline": ""}, "Claude'un keşfettiği haberi anlat")
    with pytest.raises(ToolError, match="Haber açılamadı. Site erişime izin vermedi."):
        tool.run({**arguments, "open": False})
    assert tool.run({**arguments, "open": True}).startswith("Haberi tarayıcıda açtım:")


def test_the_models_words_find_the_story_when_the_users_dont(monkeypatch):
    fake_web(monkeypatch, {"https://www.aa.com.tr/tr/rss": _linked_feed()})
    reading = internet.NewsReading()
    internet.news(TR, reading).run({})
    tool = internet.news_article(TR, reading)
    assert tool.refine({"headline": "ilk"}, "onu biraz açıklar mısın")["link"] == "https://www.aa.com.tr/tr/haber/0"


def test_web_page_is_untrusted():
    assert internet.read_web_page(TR).untrusted_output
    assert internet.news(TR).untrusted_output


@pytest.mark.parametrize(
    ("value", "expected"), [(1, 1), (1.0, 1), ("1", 1), (True, None), ("yarın", None), (1.5, None)]
)
def test_day_offsets_from_models_are_read_carefully(value, expected):
    assert internet._whole_number(value) == expected


@pytest.mark.parametrize("value", ["abc", "nan", "inf", -5, True])
def test_unreadable_amounts_are_spoken_errors(value):
    with pytest.raises(ToolError, match="Miktarı"):
        internet.exchange_rate(TR).run({"from": "USD", "amount": value})


def test_amount_with_a_decimal_comma(monkeypatch):
    fake_web(monkeypatch, {"https://api.frankfurter.app": {"rates": {"TRY": 61.8}}})
    assert internet.exchange_rate(TR).run({"from": "USD", "amount": "1,5"}) == "1,5 dolar 61,8 lira."


def test_cautioned_questions_are_spoken_sentences():
    assert (
        internet.read_web_page(TR).generic_question({"address": "example.com"})
        == "example.com adresindeki sayfayı açıp okuyayım mı?"
    )
    assert internet.read_web_page(EN).generic_question({"address": "bbc.com"}) == "Shall I open and read bbc.com?"


def test_read_on_continues_the_page_and_the_story(monkeypatch):
    from bilge.tools.reading import TextReading, continue_reading_tool

    paragraphs = "".join(f"<p>Paragraf {n} " + "uzun bir cümle " * 20 + "</p>" for n in range(160))
    page = f"<html><head><title>Uzun Yazı</title></head><body>{paragraphs}</body></html>".encode()
    monkeypatch.setattr(
        web_fetch, "get", lambda url, language=TR, max_bytes=0: web_fetch.Response(url, 200, "text/html", page)
    )
    reading = TextReading(TR)
    tool = internet.read_web_page(TR, reading)
    first = tool.run(tool.refine({"address": "ornek.com"}, "ornek.com sayfasını oku"))
    assert first.startswith("Uzun Yazı\n\nParagraf 0") and first.endswith("(Devamı var.)")
    again = tool.refine({"address": "ornek.com"}, "devamını oku")
    assert tool.run(again).startswith("Uzun Yazı, bölüm 2:\n")
    # The model may pick the dedicated tool instead.
    assert continue_reading_tool(reading, TR).run({}).startswith("Uzun Yazı, bölüm 3:\n")
    assert continue_reading_tool(TextReading(EN), EN).run({}) == "I haven't read anything just now; what should I read?"
    article = internet.news_article(TR, internet.NewsReading(), None, reading)
    assert article.refine({"headline": "x"}, "devam et") == {"headline": "x", "continue": True}
    assert article.run({"continue": True}).startswith("Uzun Yazı, bölüm 4:\n")
