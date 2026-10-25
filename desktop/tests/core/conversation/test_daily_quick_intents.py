import pytest

from bilge.brain import fast_path
from bilge.brain.agent import resolve
from bilge.core.conversation import quick_intent_parser
from bilge.core.conversation.daily_quick_intents import (
    Bluetooth,
    Brightness,
    ConvertUnits,
    DoNotDisturb,
    LevelAction,
    Playback,
    PlaybackAction,
    Power,
    PowerAction,
    Switch,
    WorldClock,
)
from bilge.core.language import AssistantLanguage

TR = AssistantLanguage.TURKISH


def parse(text: str):
    return quick_intent_parser.parse(resolve(text, TR))


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("10 mil kaç kilometre", ConvertUnits("10 mile", "kilometer")),
        ("beş feet on inç kaç santim", ConvertUnits("5 foot 10 inch", "centimeter")),
        ("bir dönüm kaç metrekare", ConvertUnits("1 decare", "square meter")),
        ("Tokyo'da saat kaç", WorldClock("Tokyo")),
        ("New York ile aramızda kaç saat fark var", WorldClock("New York", difference=True)),
        ("Parlaklığı artır", Brightness(LevelAction.INCREASE)),
        ("parlaklığı biraz azalt", Brightness(LevelAction.DECREASE)),
        ("parlaklığı yüzde elli yap", Brightness(LevelAction.SET, 50)),
        ("ekran parlaklığını yüzde yirmi artır", Brightness(LevelAction.INCREASE, 20)),
        ("parlaklığı otuza düşür", Brightness(LevelAction.SET, 30)),
        ("parlaklığı en yükseğe çıkar", Brightness(LevelAction.SET, 100)),
        ("ekranı karart", Brightness(LevelAction.DECREASE)),
        ("Rahatsız etme modunu aç", DoNotDisturb(Switch.ON)),
        ("rahatsız etmeyini kapat", DoNotDisturb(Switch.OFF)),
        ("rahatsız etmeyin açık mı", DoNotDisturb(Switch.STATUS)),
        ("bildirimleri sessize al", DoNotDisturb(Switch.ON)),
        ("Bluetooth'u aç", Bluetooth(Switch.ON)),
        ("Bluetooth'u kapat", Bluetooth(Switch.OFF)),
        ("bluetooth açık mı", Bluetooth(Switch.STATUS)),
        ("Bilgisayarı kapat", Power(PowerAction.SHUT_DOWN)),
        ("bilgisayarı kapatır mısın", Power(PowerAction.SHUT_DOWN)),
        ("bilgisayarı yeniden başlat", Power(PowerAction.RESTART)),
        ("oturumu kapat", Power(PowerAction.LOG_OUT)),
        ("otuz saniye ileri sar", Playback(PlaybackAction.SEEK, 30)),
        ("şarkıyı on saniye geri sar", Playback(PlaybackAction.SEEK, -10)),
        ("bir dakika ileri sar", Playback(PlaybackAction.SEEK, 60)),
        ("yarım dakika geri al", Playback(PlaybackAction.SEEK, -30)),
        ("biraz ileri sarar mısın", Playback(PlaybackAction.SEEK, 10)),
        ("on beş saniye atla", Playback(PlaybackAction.SEEK, 15)),
        ("şarkıyı baştan başlat", Playback(PlaybackAction.RESTART_TRACK)),
        ("başa sar", Playback(PlaybackAction.RESTART_TRACK)),
        ("karışık çal", Playback(PlaybackAction.SHUFFLE_ON)),
        ("karışık çalmayı kapat", Playback(PlaybackAction.SHUFFLE_OFF)),
        ("bu şarkıyı tekrarla", Playback(PlaybackAction.REPEAT_TRACK)),
        ("listeyi tekrarla", Playback(PlaybackAction.REPEAT_ALL)),
        ("tekrarı kapat", Playback(PlaybackAction.REPEAT_OFF)),
    ],
)
def test_recognizes_the_new_everyday_commands(command, expected):
    assert parse(command) == expected


@pytest.mark.parametrize(
    "command",
    [
        "tekrarla",  # "say it again"
        "yeniden başlat ve müziği aç",
        "parlaklığı ayarla",
        "parlaklık ne kadar acaba bugün",
        "10 mil yürüdüm",
        "Tokyo'ya uçak bileti bul",
        "bluetooth kulaklığı bağla",
        "bilgisayarı kapatıp müziği aç",
        "rahatsız etme",
    ],
)
def test_richer_or_vaguer_requests_go_to_the_model(command):
    assert parse(command) is None


def test_a_bare_start_over_is_not_taken_for_the_track():
    # It could be anything; the app rule tries it as an app name and the model gets it when none matches.
    assert not isinstance(parse("baştan başlat"), Playback)


@pytest.mark.parametrize(
    ("command", "tool", "arguments"),
    [
        ("10 mil kaç kilometre", "convertUnits", {"quantity": "10 mile", "to": "kilometer"}),
        ("Tokyo ile New York arasında kaç saat fark var", "worldClock",
         {"place": "Tokyo", "otherPlace": "New York", "kind": "difference"}),
        ("parlaklığı yüzde elli yap", "setBrightness", {"action": "set", "level": 50}),
        ("parlaklığı yüzde yirmi artır", "setBrightness", {"action": "increase", "by": 20}),
        ("parlaklığı azalt", "setBrightness", {"action": "decrease"}),
        ("rahatsız etmeyini aç", "doNotDisturb", {"action": "on"}),
        ("bluetooth'u kapat", "bluetooth", {"action": "off"}),
        ("bilgisayarı yeniden başlat", "power", {"action": "restart"}),
        ("otuz saniye geri sar", "controlPlayback", {"action": "seek", "seconds": -30}),
        ("karışık çal", "controlPlayback", {"action": "shuffleOn"}),
    ],
)  # fmt: skip
def test_fast_path_calls_the_matching_tool(command, tool, arguments):
    call = fast_path.call_for(resolve(command, TR), TR)
    assert call is not None
    assert (call.name, call.arguments) == (tool, arguments)
