"""Summarizing a YouTube video from its captions: "şu videoyu özetle: <adres>", "panodaki videoyu özetle". The
captions come from YouTube's player service as its Android app asks for them (no key needed; the web page's own
caption links now need a token only a browser makes). The text goes to the model as text someone else wrote."""

from collections.abc import Callable, Iterable
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.media import youtube_video
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.reading import TextReading, continued

PLAYER_URL = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
# Tried in turn; YouTube changes which clients get captions without a token every few months.
CLIENTS = (
    {"clientName": "ANDROID", "clientVersion": "20.10.38"},
    {"clientName": "IOS", "clientVersion": "20.10.4"},
)
PART_CHARACTERS = 12_000
CAPTION_BYTES = 4_000_000

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Bir YouTube videosunu altyazısından özetlemek için videonun konuşulanlarını getirir. Adres "
        "söylenmediyse ('panodaki videoyu özetle') panodaki ya da seçili metindeki adresi kullanır. Sonucu kısaca "
        "özetle; 'devamını özetle' sonraki bölümü getirir.",
        "address": "Video adresi; panodaki ya da seçili video için boş bırak",
        "no_address": "Panoda ya da seçili metinde bir YouTube adresi bulamadım. Video adresini kopyalayıp yine "
        "söyler misin?",
        "fetch_failed": "Videonun bilgilerini alamadım. ",
        "unavailable": "Bu videoyu açamadım; özel, kaldırılmış ya da yaş sınırlı olabilir.",
        "no_captions": "Bu videonun altyazısı yok, o yüzden özetleyemiyorum.",
        "captions_failed": "Videonun altyazısını alamadım. ",
        "heading": "Video: {title}\n({language} altyazı{automatic})\n\n{text}",
        "automatic": ", otomatik",
        "ask": "{address} videosunun altyazısını alıp özetleyeyim mi?",
        "ask_pasted": "Panodaki videonun altyazısını alıp özetleyeyim mi?",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Fetches what is said in a YouTube video, from its captions, to summarize it. With no address ('sum "
        "up the video on the clipboard') it uses the address on the clipboard or in the selected text. Summarize "
        "the result briefly; 'summarize the rest' fetches the next part.",
        "address": "The video's address; empty for the one on the clipboard or selected",
        "no_address": "I couldn't find a YouTube address on the clipboard or in the selected text. Copy the "
        "video's address and ask again?",
        "fetch_failed": "I couldn't get the video's details. ",
        "unavailable": "I couldn't open this video; it may be private, removed or age-restricted.",
        "no_captions": "This video has no captions, so I can't summarize it.",
        "captions_failed": "I couldn't get the video's captions. ",
        "heading": "Video: {title}\n({language} captions{automatic})\n\n{text}",
        "automatic": ", automatic",
        "ask": "Shall I get the captions of {address} and sum it up?",
        "ask_pasted": "Shall I get the captions of the video on the clipboard and sum it up?",
    },
}


def player_answer(video_id: str, language: AssistantLanguage) -> youtube_video.Video:
    """The first client whose answer is playable with captions; the last answer otherwise."""
    found = youtube_video.Video("", False, ())
    last_error: web_fetch.WebFetchError | None = None
    for client in CLIENTS:
        payload = {"context": {"client": {**client, "hl": language.code}}, "videoId": video_id}
        try:
            found = youtube_video.video(web_fetch.post_json(PLAYER_URL, payload, language))
        except web_fetch.WebFetchError as error:
            last_error = error
            continue
        if found.playable and found.tracks:
            return found
    if not found.playable and last_error is not None:
        raise last_error
    return found


def captions(track: youtube_video.Track, language: AssistantLanguage) -> str:
    response = web_fetch.get(track.url, language, max_bytes=CAPTION_BYTES)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    return youtube_video.transcript(response.body)


def summarize_video_tool(
    language: AssistantLanguage, reading: TextReading, pasted: Callable[[], Iterable[str]] | None = None
) -> Tool:
    """`pasted`: the clipboard's text, then the selection, where to look when no address is given; read lazily, as
    reading the selection on Windows means pressing Ctrl+C in the app in front."""
    texts = _TEXTS[language]

    def address_in(arguments: dict[str, Any]) -> str | None:
        found = youtube_video.video_id(str(arguments.get("address") or ""))
        if found or pasted is None:
            return found
        return next(filter(None, (youtube_video.video_id(text) for text in pasted())), None)

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("continue"):
            return reading.more()
        video_id = address_in(arguments)
        if video_id is None:
            raise ToolError(texts["no_address"])
        try:
            video = player_answer(video_id, language)
        except web_fetch.WebFetchError as error:
            raise ToolError(texts["fetch_failed"] + web_fetch.describe(error, language)) from error
        if not video.playable:
            raise ToolError(texts["unavailable"])
        track = youtube_video.choose(video.tracks, language.code)
        if track is None:
            raise ToolError(texts["no_captions"])
        try:
            text = captions(track, language)
        except web_fetch.WebFetchError as error:
            raise ToolError(texts["captions_failed"] + web_fetch.describe(error, language)) from error
        if not text:
            raise ToolError(texts["no_captions"])
        title = video.title or video_id
        body = reading.start(title, text, PART_CHARACTERS)
        automatic = texts["automatic"] if track.automatic else ""
        return texts["heading"].format(title=title, language=track.language, automatic=automatic, text=body)

    parameters = {"type": "object", "properties": {"address": {"type": "string", "description": texts["address"]}}}
    return Tool(
        "summarizeVideo",
        texts["tool"],
        run=run,
        parameters=parameters,
        refine=lambda arguments, command: continued(reading, arguments, command),
        # Captions are written (or spoken) by whoever made the video.
        untrusted_output=True,
        spoken_action=lambda arguments: (
            texts["ask"].format(address=arguments["address"]) if arguments.get("address") else texts["ask_pasted"]
        ),
    )
