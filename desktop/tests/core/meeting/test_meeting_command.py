import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.meeting.meeting_command import (
    asks_file_transcription,
    asks_for_summary,
    is_start,
    is_stop,
    names_no_file,
)


@pytest.mark.parametrize(
    "command",
    ["toplantıyı kaydetmeye başla", "toplantıyı kaydet", "toplantı kaydını başlat", "kaydı başlat",
     "start recording the meeting", "record the meeting", "start recording", "record this meeting",
     "Bilge, toplantıyı kaydetmeye başlar mısın?"],
)  # fmt: skip
def test_starts_recording_a_meeting(command):
    assert is_start(command)


@pytest.mark.parametrize(
    "command",
    ["kaydı bitir", "ekran kaydını başlat", "son indirdiğim ses kaydını yazıya dök", "stop recording", "saat kaç",
     "start screen recording", "haftalık toplantı kaydını yazıya dök", "transcribe the meeting recording",
     "yarınki toplantıyı takvime kaydet", "toplantı kaydını sil", "remind me to record the meeting tomorrow",
     "her pazartesi 10'da toplantıyı kaydet", "toplantıyı kaydet ve özetle", "dosyayı kaydet", "kaydet",
     "delete the meeting recording", "toplantıyı saat 3'te kaydet"],
)  # fmt: skip
def test_other_requests_do_not_start_a_recording(command):
    assert not is_start(command)


@pytest.mark.parametrize(
    "said", ["kaydı bitir", "Kaydı durdur.", "kaydetmeyi bırak", "toplantı kaydını bitir", "stop recording",
             "end the recording", "recording off"],
)  # fmt: skip
def test_the_stop_phrase_ends_the_recording(said):
    assert is_stop(said)


@pytest.mark.parametrize(
    "said",
    [
        "toplantıyı bitirelim",
        "toplantıyı bitir",
        "let's end the meeting",
        "bu kaydı bitir ve sonra raporu hazırlayıp herkese gönderelim lütfen",
        "kayıtlara geçsin",
        "",
    ],
)
def test_what_is_said_in_the_meeting_does_not_end_it(said):
    assert not is_stop(said)


def test_said_to_bilge_ending_the_meeting_is_enough():
    assert is_stop("toplantıyı bitir", addressed=True)
    assert is_stop("end the meeting", addressed=True)


@pytest.mark.parametrize(
    ("command", "names_nothing"),
    [
        ("bu ses dosyasını yazıya dök", True),
        ("son indirdiğim ses kaydını yazıya dök", True),
        ("transcribe my latest audio download", True),
        ("transcribe this audio file", True),
        ("haftalık toplantı ses kaydını yazıya dök", False),
        ("transcribe the interview recording", False),
    ],
)
def test_asks_for_a_recording_to_be_written_down(command, names_nothing):
    assert asks_file_transcription(command)
    assert names_no_file(command) is names_nothing


@pytest.mark.parametrize("command", ["bunu yazıya dök", "kaydı bitir", "dosyayı aç", "read the file"])
def test_other_requests_are_not_transcriptions(command):
    assert not asks_file_transcription(command)


def test_a_yes_or_read_the_summary_asks_for_the_summary():
    assert asks_for_summary("evet", AssistantLanguage.TURKISH)
    assert asks_for_summary("özeti oku", AssistantLanguage.TURKISH)
    assert asks_for_summary("yes please", AssistantLanguage.ENGLISH)
    assert asks_for_summary("read the summary", AssistantLanguage.ENGLISH)
    assert not asks_for_summary("hayır", AssistantLanguage.TURKISH)
    assert not asks_for_summary("evet ama önce yarın hava nasıl olacak onu söyle", AssistantLanguage.TURKISH)
