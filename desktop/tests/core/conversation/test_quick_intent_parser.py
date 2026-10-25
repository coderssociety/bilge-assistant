import pytest

from bilge.core.conversation import quick_intent_parser
from bilge.core.conversation.quick_intent_parser import (
    Alarm,
    Battery,
    Calculate,
    Calendar,
    CalendarRange,
    ChangeVolume,
    Clipboard,
    DateTime,
    Folder,
    Media,
    MediaAction,
    OpenApp,
    OpenFolder,
    QuickIntent,
    QuitApp,
    Reminders,
    SetVolume,
    System,
    SystemAction,
    Timer,
    TimerAction,
    Timers,
    Volume,
    VolumeStep,
)
from bilge.core.speech import turkish_number_parser, turkish_time_of_day


def parse(text: str) -> QuickIntent | None:
    return quick_intent_parser.parse(turkish_time_of_day.resolve(turkish_number_parser.digitize(text)))


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("Saat kaç", DateTime()),
        ("saat kaç oldu acaba", DateTime()),
        ("Bugün günlerden ne", DateTime()),
        ("ayın kaçı", DateTime()),
        ("Pil durumu nedir", Battery()),
        ("şarjım ne kadar", Battery()),
        ("Sesi yüzde otuz yap", Volume(SetVolume(30))),
        ("sesi elliye getir", Volume(SetVolume(50))),
        ("Sesi biraz kıs", Volume(VolumeStep.DOWN)),
        ("sesi yüzde yirmi artır", Volume(ChangeVolume(up=True, by=20))),
        ("sesi on kıs", Volume(ChangeVolume(up=False, by=10))),
        ("sesi yüzde yirmi düşür", Volume(ChangeVolume(up=False, by=20))),
        ("sesi yüzde yirmiye düşür", Volume(SetVolume(20))),
        ("sesi yükselt", Volume(VolumeStep.UP)),
        ("Sesi kapat", Volume(VolumeStep.MUTE)),
        ("Müziği durdur", Media(MediaAction.PAUSE)),
        ("müziği başlat", Media(MediaAction.PLAY)),
        ("Sonraki şarkıya geç", Media(MediaAction.NEXT)),
        ("şarkıyı geç", Media(MediaAction.NEXT)),
        ("Bir önceki şarkıyı çal", Media(MediaAction.PREVIOUS)),
        ("Bu şarkının adı ne", Media(MediaAction.NOW_PLAYING)),
        ("Ekranı kilitle", System(SystemAction.LOCK_SCREEN)),
        ("Mac'i kilitle", System(SystemAction.LOCK_SCREEN)),
        ("Bilgisayarı uyut", System(SystemAction.SLEEP)),
        ("Karanlık modu aç", System(SystemAction.DARK_MODE_ON)),
        ("aydınlık moda geç", System(SystemAction.DARK_MODE_OFF)),
        ("Bugün takvimde ne var", Calendar(CalendarRange.TODAY)),
        ("Yarın takvimimde ne var", Calendar(CalendarRange.TOMORROW)),
        ("Bu hafta neler var", Calendar(CalendarRange.THIS_WEEK)),
        ("Anımsatıcılarımı oku", Reminders()),
        ("Yüz yirminin yarısı kaç", Calculate("120 / 2")),
        ("on iki çarpı on beş", Calculate("12 * 15")),
        ("On dakikalık zamanlayıcı kur", Timer(seconds=600)),
        ("beş dakika sonra beni uyar", Timer(seconds=300)),
        ("Safari'yi aç", OpenApp("Safari'yi")),
        ("hesap makinesini açar mısın", OpenApp("hesap makinesini")),
        ("Spotify uygulamasını kapat", QuitApp("Spotify")),
        ("Terminali kapat", QuitApp("Terminali")),
        ("Ekranı kilitler misin", System(SystemAction.LOCK_SCREEN)),
        ("Karanlık moda geçer misin", System(SystemAction.DARK_MODE_ON)),
        ("Şu an saat kaç acaba", DateTime()),
        ("Xcode'u açar mısın lütfen", OpenApp("Xcode'u")),
        ("müziği durdurur musun", Media(MediaAction.PAUSE)),
        ("Yarım saat sonra beni uyar", Timer(seconds=1800)),
        ("çeyrek saatlik zamanlayıcı kur", Timer(seconds=900)),
        ("Belgeler klasörünü aç", OpenFolder(Folder.DOCUMENTS)),
        ("İndirilenleri aç", OpenFolder(Folder.DOWNLOADS)),
        ("masaüstünü açar mısın", OpenFolder(Folder.DESKTOP)),
        ("Bütün alarmları kapat", Timers(TimerAction.CANCEL_ALL)),
        ("zamanlayıcıları iptal et", Timers(TimerAction.CANCEL_ALL)),
        ("kurulu zamanlayıcılar neler", Timers(TimerAction.LIST)),
        ("çay zamanlayıcısını iptal et", Timers(TimerAction.CANCEL, "çay")),
        ("alarmı iptal et", Timers(TimerAction.CANCEL)),
        ("zamanlayıcıyı kapat", Timers(TimerAction.CANCEL)),
        ("kaç dakika kaldı", Timers(TimerAction.REMAINING)),
        ("sekize çeyrek kala alarm kur", Alarm(hour=7, minute=45)),
        ("dokuzu çeyrek geçe uyandır", Alarm(hour=9, minute=15)),
        ("bir buçuk saat sonra uyar", Timer(seconds=5400)),
        ("üç çeyrek saat sonra uyar", Timer(seconds=2700)),
        ("Kopyaladığım metni okur musun", Clipboard()),
        ("panodaki yazıyı oku", Clipboard()),
    ],
)
def test_recognizes_everyday_commands_without_the_model(command, expected):
    assert parse(command) == expected


@pytest.mark.parametrize(
    "command",
    [
        "saat yedi alarmını iptal et",  # a time, not a label
        "çay alarmı iptal et",
        "Yirmi dakika sonra çayı hatırlat",  # has a label
        "Yarın saat onda diş hekimi randevusu ekle",  # writes to calendar
        "İndirilenler klasöründeki faturayı aç",  # a file, not the folder
        "Masaüstündeki deneme dosyasını aç",
        "alarmları kapat ve müziği aç",
        "kopyaladığım metni Notlar'a yapıştır",
        "Rahatsız etme modunu aç",  # Focus goes through Shortcuts
        "Sesi biraz aç ve müziği başlat",  # two actions
        "Türkiye'nin başkenti neresi",
        "Bluetooth'u kapat",
        "Bilgisayarı kapat",
        "ondan sonra müziği aç",
        "Saat kaçta toplantım var",
    ],
)
def test_leaves_anything_unusual_or_richer_to_the_model(command):
    assert parse(command) is None
