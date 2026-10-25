from datetime import datetime

import pytest

from bilge.brain.agent import Agent
from bilge.core.context.screen_context import Files, Text
from bilge.core.language import AssistantLanguage
from bilge.desktop.windows import office
from bilge.tools.base import Registry, ToolError
from bilge.tools.desktop.context import send_pointed_rule
from bilge.tools.desktop.mail import MAX_BODY, mail_tools

from .test_windows import Outlook, no_com  # noqa: F401 - no_com is a fixture

TR = AssistantLanguage.TURKISH
pytestmark = pytest.mark.usefixtures("no_com")


def send_tool(app, item, asked=None):
    def pointed(body):
        if asked is not None:
            asked.append(body)
        return item

    tools = {t.name: t for t in mail_tools(office.Outlook(application=lambda: app), TR, pointed=pointed)}
    return tools["sendEmail"]


def test_this_is_sent_after_the_question_named_the_recipient_and_the_text_start():
    app, asked = Outlook(), []
    long_text = "Toplantı notları. " + "ayrıntı " * 400
    send = send_tool(app, Text(long_text, copied=True), asked)
    arguments = {"to": "Ahmet", "body": "bunu"}
    question = send.question(arguments)
    assert question.startswith('Gönderilecek panodaki metin şöyle başlıyor: "Toplantı notları. ayrıntı')
    assert question.endswith(
        "… (devamı var)\". Bunu Ahmet Yılmaz (ahmet@example.org) adresine 'Toplantı notları.' konulu e-postayla "
        "göndereyim mi?"
    )
    assert asked == ["bunu"]
    assert len(long_text) > MAX_BODY
    assert send.run(arguments) == "E-postayı Ahmet Yılmaz adresine gönderdim."
    assert app.sent == [("ahmet@example.org", "Toplantı notları.", long_text[:2000])]


def test_selected_files_go_as_attachments(tmp_path):
    report, notes = tmp_path / "rapor.pdf", tmp_path / "notlar.txt"
    report.write_bytes(b"%PDF")
    notes.write_text("x", encoding="utf-8")
    app = Outlook()
    send = send_tool(app, Files((str(report), str(notes), str(tmp_path / "yok.txt"))))
    arguments = {"to": "Ahmet", "body": "bu dosyaları"}
    assert send.question(arguments) == (
        "Ahmet Yılmaz (ahmet@example.org) adresine 'rapor' konulu e-postayı ekinde rapor.pdf ve 1 dosya daha ile "
        "göndereyim mi?"
    )
    send.run(arguments)
    assert app.attached == [str(report), str(notes)] and app.sent == [("ahmet@example.org", "rapor", "")]


def test_nothing_is_sent_when_this_points_at_nothing():
    app = Outlook()
    send = send_tool(app, None)
    assert send.question({"to": "Ahmet", "body": "bunu"}) is None
    with pytest.raises(ToolError, match="ne göndermemi istediğini bulamadım"):
        send.run({"to": "Ahmet", "body": "bunu"})
    assert app.sent == []


def test_dictated_words_are_not_resolved():
    app, asked = Outlook(), []
    send = send_tool(app, Text("seçili"), asked)
    assert send.question({"to": "Ahmet", "body": "Bunu yarın konuşalım."}).endswith("Metin: Bunu yarın konuşalım.")
    assert asked == []


def agent_with(app, item, answers):
    pending, asked = list(answers), []

    def confirm(question):
        asked.append(question)
        return pending.pop(0)

    registry = Registry([send_tool(app, item)])
    agent = Agent(None, registry, confirm, TR, clock=lambda: datetime(2026, 10, 25, 10, 0),
                  rules=[send_pointed_rule(TR)])  # fmt: skip
    return agent, asked


def test_send_this_to_ahmet_is_routed_to_email_and_waits_for_a_yes():
    app = Outlook()
    agent, asked = agent_with(app, Text("Fatura ekte, ödeme cuma."), answers=[False])
    assert agent.handle("bunu Ahmet'e gönder").text == "Tamam, yapmıyorum."
    assert app.sent == []
    assert asked == [
        'Gönderilecek seçili metin şöyle başlıyor: "Fatura ekte, ödeme cuma.". Bunu Ahmet Yılmaz (ahmet@example.org) '
        "adresine 'Fatura ekte, ödeme cuma.' konulu e-postayla göndereyim mi?"
    ]
    agent, _ = agent_with(app, Text("Fatura ekte, ödeme cuma."), answers=[True])
    assert agent.handle("bunu Ahmet'e gönder").text == "E-postayı Ahmet Yılmaz adresine gönderdim."
    assert app.sent == [("ahmet@example.org", "Fatura ekte, ödeme cuma.", "Fatura ekte, ödeme cuma.")]


def test_an_unknown_recipient_is_said_without_sending():
    app = Outlook()
    agent, asked = agent_with(app, Text("metin"), answers=[])
    assert "bulamadım" in agent.handle("bunu Zeynep'e gönder").text
    assert app.sent == [] and asked == []
