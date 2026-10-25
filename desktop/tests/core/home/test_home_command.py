import pytest

from bilge.core.home import home_command
from bilge.core.language import AssistantLanguage

from ...fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


@pytest.mark.parametrize(
    "said",
    ["salonun ışığını aç", "klimayı 22 dereceye ayarla", "kapı kilitli mi", "ışıkları kapat", "yatak odasındaki lambayı söndür",
     "mutfağın perdelerini kapat", "garaj kapısını aç", "termostatı 21 yap", "prizi kapat"],
)  # fmt: skip
def test_turkish_home_commands_name_a_device_or_room(said):
    assert home_command.names_home_device(said, TR)


@pytest.mark.parametrize(
    "said",
    ["ekranın ışığını kıs", "bilgisayarı kilitle", "ekranı kilitle", "klavye ışığını aç", "hava nasıl",
     "yarın 7'ye alarm kur", "sesi aç", "haberleri oku", "salı günü toplantım var mı"],
)  # fmt: skip
def test_commands_for_this_computer_or_anything_else_are_not_home_commands(said):
    assert not home_command.names_home_device(said, TR)


def test_english_home_commands():
    assert home_command.names_home_device("turn on the living room lights", EN)
    assert home_command.names_home_device("set the thermostat to 21", EN)
    assert home_command.names_home_device("is the front door locked", EN)
    assert not home_command.names_home_device("lock the screen", EN)
    assert not home_command.names_home_device("what's the weather", EN)


def test_only_changing_a_lock_the_garage_or_the_alarm_guards_the_house():
    assert home_command.guards_the_house("kapıyı kilitle", TR)
    assert home_command.guards_the_house("kapının kilidini aç", TR)
    assert home_command.guards_the_house("garaj kapısını aç", TR)
    assert home_command.guards_the_house("ev alarmını kapat", TR)
    assert not home_command.guards_the_house("kapı kilitli mi", TR)
    assert not home_command.guards_the_house("salonun ışığını aç", TR)
    assert home_command.guards_the_house("unlock the front door", EN)
    assert not home_command.guards_the_house("is the front door locked", EN)


def test_the_address_is_a_plain_http_address():
    assert home_command.base_address("http://homeassistant.local:8123/") == "http://homeassistant.local:8123"
    assert home_command.base_address(" https://ev.example.org/ha ") == "https://ev.example.org/ha"
    assert home_command.base_address("http://192.168.1.20:8123") == "http://192.168.1.20:8123"
    for bad in (
        "homeassistant.local:8123",
        "ftp://ev",
        "http://user:pass@ev:8123",
        "http://ev:8123/?x=1",
        "http://ev:port",
        "",
    ):
        assert home_command.base_address(bad) is None


def test_the_request_and_the_spoken_reply():
    assert home_command.conversation_request("ışığı aç", TR) == {"text": "ışığı aç", "language": "tr"}
    assert home_command.conversation_request("lights on", EN) == {"text": "lights on", "language": "en"}
    assert home_command.spoken_reply(web_json("home_assistant_action_done.json")) == "Salon ışığı açıldı"
    assert home_command.spoken_reply(web_json("home_assistant_no_match.json")) == "Sorry, I couldn't understand that"
    assert home_command.spoken_reply({"response": {"speech": {}}}) is None
    assert home_command.spoken_reply(["not", "a", "dict"]) is None
