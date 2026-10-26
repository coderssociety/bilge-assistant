import json
import logging
from datetime import datetime

import httpx
import pytest

from bilge import assembly, config
from bilge.brain.agent import Agent
from bilge.core.language import AssistantLanguage
from bilge.llm.messages import Reply
from bilge.tools.base import Registry, ToolError
from bilge.tools.builtin import home_assistant
from bilge.tools.builtin.home_assistant import HomeAssistant, HomeAssistantError, Reason

from ..brain.test_agent import ScriptedProvider, recorder
from ..fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
ADDRESS = "http://homeassistant.local:8123/"
TOKEN = "eyJ-secret-token"


def server(handler):
    sent = []

    def respond(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        return handler(request)

    return HomeAssistant(ADDRESS, TOKEN, httpx.Client(transport=httpx.MockTransport(respond))), sent


def answering(name, status=200):
    return lambda request: httpx.Response(status, json=web_json(name))


def test_the_command_is_posted_with_the_token_and_the_speech_is_returned():
    home, sent = server(answering("home_assistant_action_done.json"))
    assert home.process("salonun ışığını aç", TR) == "Salon ışığı açıldı"
    request = sent[0]
    assert (request.method, str(request.url)) == ("POST", "http://homeassistant.local:8123/api/conversation/process")
    assert request.headers["Authorization"] == f"Bearer {TOKEN}"
    assert json.loads(request.content) == {"text": "salonun ışığını aç", "language": "tr"}


def test_errors_are_named_without_the_token(caplog):
    caplog.set_level(logging.DEBUG)
    cases = [
        (lambda r: httpx.Response(401, text="401: Unauthorized"), Reason.UNAUTHORIZED),
        (lambda r: httpx.Response(500), Reason.STATUS),
        (lambda r: httpx.Response(302, headers={"Location": "http://elsewhere/"}), Reason.UNEXPECTED),
        (lambda r: httpx.Response(200, text="<html>"), Reason.UNEXPECTED),
    ]
    for handler, reason in cases:
        home, _ = server(handler)
        with pytest.raises(HomeAssistantError) as raised:
            home.process("ışığı aç", TR)
        assert raised.value.reason is reason

    def unreachable(request):
        raise httpx.ConnectError("refused", request=request)

    home, _ = server(unreachable)
    with pytest.raises(HomeAssistantError) as raised:
        home.check()
    assert raised.value.reason is Reason.UNREACHABLE
    assert TOKEN not in caplog.text


def test_a_bad_address_or_a_missing_token_is_not_sent_anywhere():
    sent = []
    client = httpx.Client(transport=httpx.MockTransport(lambda r: sent.append(r) or httpx.Response(200)))
    with pytest.raises(HomeAssistantError) as raised:
        HomeAssistant("homeassistant.local:8123", TOKEN, client).check()
    assert raised.value.reason is Reason.ADDRESS
    with pytest.raises(HomeAssistantError) as raised:
        HomeAssistant(ADDRESS, "", client).check()
    assert raised.value.reason is Reason.NO_TOKEN
    assert sent == []


def test_the_tool_speaks_the_reply_and_turns_failures_into_sentences():
    home, _ = server(answering("home_assistant_no_match.json"))
    tool = home_assistant.smart_home_tool(home, EN)
    assert tool.run({"text": "lights on"}) == "Sorry, I couldn't understand that"
    home, _ = server(lambda r: httpx.Response(401))
    with pytest.raises(ToolError, match="erişim anahtarını kabul etmedi"):
        home_assistant.smart_home_tool(home, TR).run({"text": "ışığı aç"})


def agent_with_home(home, answers=()):
    asked, pending = [], list(answers)

    def confirm(question, strict=False):
        asked.append(question)
        return pending.pop(0)

    volume, volume_runs = recorder("setVolume")
    tools = [home_assistant.smart_home_tool(home, TR), volume]
    agent = Agent(ScriptedProvider(Reply("Bilmiyorum.")), Registry(tools), confirm, TR,
                  clock=lambda: datetime(2026, 10, 15, 14, 5), rules=[home_assistant.smart_home_rule(TR)])  # fmt: skip
    return agent, asked, volume_runs


def test_home_commands_go_to_home_assistant_and_others_do_not():
    home, sent = server(answering("home_assistant_action_done.json"))
    agent, asked, volume_runs = agent_with_home(home)
    assert agent.handle("salonun ışığını aç").text == "Salon ışığı açıldı"
    assert json.loads(sent[0].content)["text"] == "salonun ışığını aç"
    # Numbers said as words reach Home Assistant as digits.
    agent.handle("klimayı yirmi iki dereceye ayarla")
    assert json.loads(sent[1].content)["text"] == "klimayı 22 dereceye ayarla"
    agent.handle("sesi yüzde otuz yap")
    assert volume_runs == [{"action": "set", "level": 30}]
    agent.handle("ekranın ışığını kıs")
    assert len(sent) == 2 and asked == []


def test_locks_ask_first_and_asking_about_them_does_not():
    home, sent = server(answering("home_assistant_action_done.json"))
    agent, asked, _ = agent_with_home(home, answers=[False])
    assert agent.handle("kapıyı kilitle").text == "Tamam, yapmıyorum."
    assert asked == ["Home Assistant'a “kapıyı kilitle” diyeyim mi?"] and sent == []
    agent.handle("kapı kilitli mi")
    assert len(sent) == 1 and len(asked) == 1


def test_a_polite_question_to_unlock_asks_first_and_a_routine_never_unlocks():
    home, sent = server(answering("home_assistant_action_done.json"))
    agent, asked, _ = agent_with_home(home, answers=[False])
    agent.handle("Kapının kilidini açar mısın?")
    assert asked == ["Home Assistant'a “Kapının kilidini açar mısın?” diyeyim mi?"] and sent == []
    assert "onayın gerekiyor" in agent.handle("garaj kapısını aç", unattended=True).text
    assert sent == [] and len(asked) == 1


def test_home_assistant_is_set_up_only_with_an_address_and_a_token(monkeypatch):
    keys = {}
    monkeypatch.setattr(config, "api_key", lambda name: keys.get(name))
    assert assembly.home_assistant(config.HomeSettings("")) is None
    assert assembly.home_assistant(config.HomeSettings(ADDRESS)) is None
    keys[assembly.HOME_ASSISTANT_SECRET] = TOKEN
    assert assembly.home_assistant(config.HomeSettings("")) is None
    assert isinstance(assembly.home_assistant(config.HomeSettings(ADDRESS)), HomeAssistant)
