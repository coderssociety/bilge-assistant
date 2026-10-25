"""Meeting recording and audio transcription by voice: "toplantıyı kaydetmeye başla", "kaydı bitir", "son
indirdiğim ses kaydını yazıya dök", "özeti oku"; "start recording the meeting", "stop recording", "transcribe this
audio file", "read the summary"."""

from bilge.core.conversation import confirmation_parser
from bilge.core.conversation.confirmation_parser import Answer
from bilge.core.language import AssistantLanguage
from bilge.core.text import folded

_RECORDING_STEMS = ("kayd", "kayit", "record")
# Starting is the whole command, said in these words only: a date, "takvime", "hatırlat" or "sil" around
# "kaydet" ("yarınki toplantıyı takvime kaydet", "toplantı kaydını sil") means something else.
_START_MEETING = frozenset({"toplanti", "toplantiyi", "toplantinin", "meeting"})
_START_RECORDING = frozenset({"kaydet", "kaydetmeye", "kaydetmek", "kaydetsene", "kaydi", "kaydini", "kayda",
                              "kayit", "kaydina", "record", "recording"})  # fmt: skip
_START_VERBS = frozenset({"basla", "baslat", "baslar", "baslatir", "baslatsana", "al", "start", "begin"})
_START_FILLER = frozenset({"bilge", "lutfen", "misin", "bu", "su", "simdi", "hemen", "the", "this", "please", "now",
                           "can", "could", "you"})  # fmt: skip
# Whole words only: "toplantıyı bitirelim" said in the meeting must not end the recording.
_STOP_WORDS = frozenset(
    {"bitir", "durdur", "kapat", "sonlandir", "birak", "kes", "bitti", "stop", "end", "finish", "off", "done"}
)
_OTHER_RECORDINGS = frozenset({"ekran", "ekrani", "ekranin", "screen", "video", "videoyu"})
# A stop phrase is short; a long sentence in the meeting that happens to hold one is part of the meeting.
MAX_STOP_WORDS = 6

_TRANSCRIBE_STEMS = ("transcri", "transkri", "desifre")
_AUDIO_STEMS = ("ses", "kayd", "kayit", "audio", "record", "voice", "mp3", "m4a", "wav", "mp4", "dosya", "file")
# Words that ask for a file without naming it: "bu ses dosyasını", "son indirdiğim ses kaydını", "my latest download".
_GENERIC_FILE_WORDS = frozenset(
    {
        "bu", "su", "son", "en", "indirdigim", "indirilen", "indirdigin", "kaydettigim", "ses", "sesi", "dosyasi",
        "dosyasini", "dosyayi", "dosya", "kaydi", "kaydini", "kayit", "yaziya", "dok", "doker", "misin", "lutfen",
        "metne", "cevir", "bilge", "this", "that", "the", "a", "my", "last", "latest", "downloaded", "download",
        "audio", "file", "recording", "voice", "please", "into", "text", "to", "i", "just", "most", "recent",
        "transcribe", "can", "you", "desifre", "et",
    }
)  # fmt: skip
_SUMMARY_STEMS = ("ozet", "summar")
_READ_STEMS = ("oku", "soyle", "anlat", "read", "tell")


def _recording(words: list[str]) -> bool:
    return any(word.startswith(_RECORDING_STEMS) for word in words) and not _OTHER_RECORDINGS & set(words)


def is_start(command: str) -> bool:
    """ "toplantıyı kaydetmeye başla", "toplantıyı kaydet", "kaydı başlat", "start recording the meeting"."""
    words = set(folded(command).split())
    if not words <= _START_MEETING | _START_RECORDING | _START_VERBS | _START_FILLER:
        return False
    return bool(words & _START_RECORDING) and bool(words & (_START_MEETING | _START_VERBS))


def is_stop(said: str, addressed: bool = False) -> bool:
    """`addressed`: said with the wake word, when "Bilge, toplantıyı bitir" is clearly meant for it."""
    words = folded(said).split()
    if not 0 < len(words) <= MAX_STOP_WORDS or not _STOP_WORDS & set(words):
        return False
    meeting = any(word.startswith(("toplanti", "meeting")) for word in words)
    return _recording(words) or (addressed and meeting)


def asks_file_transcription(command: str) -> bool:
    folded_command = folded(command)
    words = folded_command.split()
    transcribe = "yaziya dok" in folded_command or any(word.startswith(_TRANSCRIBE_STEMS) for word in words)
    return transcribe and any(word.startswith(_AUDIO_STEMS) for word in words)


def names_no_file(command: str) -> bool:
    """ "Bu ses dosyasını yazıya dök", "son indirdiğim ses kaydını yazıya dök": the newest recording is meant."""
    return all(word in _GENERIC_FILE_WORDS for word in folded(command).split())


def asks_for_summary(command: str, language: AssistantLanguage) -> bool:
    """A yes to "özetini okuyayım mı?", or "özeti oku" itself."""
    words = folded(command).split()
    if any(word.startswith(_SUMMARY_STEMS) for word in words) and any(word.startswith(_READ_STEMS) for word in words):
        return True
    return len(words) <= 3 and confirmation_parser.parse(command, language=language) is Answer.CONFIRMED
