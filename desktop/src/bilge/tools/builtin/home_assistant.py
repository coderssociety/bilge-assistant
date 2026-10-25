"""The smart home through Home Assistant's conversation API: the command goes to the server the user set up, which
understands it in its own language and answers with a sentence to say.

Home Assistant usually lives on the local network, which web_fetch refuses on purpose. This client talks only to
the one address the user typed in the settings, sends the token only there, follows no redirects and ignores proxy
settings, so the token can't end up anywhere else."""

import logging
from enum import StrEnum
from typing import Any

import httpx

from bilge.brain.routing import Rule, rule
from bilge.core.home import home_command
from bilge.core.language import AssistantLanguage
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import obj, string_argument, text

log = logging.getLogger(__name__)

TIMEOUT = httpx.Timeout(15.0, connect=5.0)
MAX_BYTES = 1_000_000


class Reason(StrEnum):
    ADDRESS = "address"
    NO_TOKEN = "noToken"
    UNREACHABLE = "unreachable"
    TOO_SLOW = "tooSlow"
    UNAUTHORIZED = "unauthorized"
    STATUS = "status"
    UNEXPECTED = "unexpected"


class HomeAssistantError(Exception):
    """A reason, never the request: its headers carry the token."""

    def __init__(self, reason: Reason, status: int | None = None):
        super().__init__(reason.value if status is None else f"{reason.value} {status}")
        self.reason = reason
        self.status = status


_SENTENCES = {
    AssistantLanguage.TURKISH: {
        Reason.ADDRESS: "Home Assistant adresi geçersiz; ayarlarda http:// ya da https:// ile başlayan adresi gir.",
        Reason.NO_TOKEN: "Home Assistant erişim anahtarı kayıtlı değil; ayarlardan ekleyebilirsin.",
        Reason.UNREACHABLE: "Home Assistant'a ulaşamadım; adres doğru mu, bilgisayar aynı ağda mı?",
        Reason.TOO_SLOW: "Home Assistant zamanında yanıt vermedi.",
        Reason.UNAUTHORIZED: "Home Assistant erişim anahtarını kabul etmedi (401); ayarlardan yeni bir uzun ömürlü erişim anahtarı gir.",
        Reason.STATUS: "Home Assistant bir hatayla yanıt verdi ({status}).",
        Reason.UNEXPECTED: "Home Assistant'tan anlayamadığım bir yanıt geldi.",
        "done": "Tamam.",
        "describe": "Akıllı ev cihazlarını Home Assistant üzerinden yönetir ve durumlarını sorar: ışık, lamba, klima, priz, perde, kapı kilidi, termostat, garaj; salon, yatak odası, mutfak gibi odalarda.",
        "text": "Kullanıcının söylediği komut, olduğu gibi: 'salonun ışığını aç'",
        "confirm": "Home Assistant'a “{text}” diyeyim mi?",
    },
    AssistantLanguage.ENGLISH: {
        Reason.ADDRESS: "The Home Assistant address isn't valid; enter one starting with http:// or https:// in the settings.",
        Reason.NO_TOKEN: "No Home Assistant access token is stored; you can add one in the settings.",
        Reason.UNREACHABLE: "I couldn't reach Home Assistant; is the address right and is this computer on the same network?",
        Reason.TOO_SLOW: "Home Assistant didn't answer in time.",
        Reason.UNAUTHORIZED: "Home Assistant didn't accept the access token (401); enter a new long-lived access token in the settings.",
        Reason.STATUS: "Home Assistant answered with an error ({status}).",
        Reason.UNEXPECTED: "Home Assistant sent an answer I couldn't read.",
        "done": "Done.",
        "describe": "Controls smart-home devices through Home Assistant and asks how they are: lights, lamps, air conditioning, plugs, curtains, door locks, thermostat, garage; in rooms such as the living room, bedroom or kitchen.",
        "text": "The user's command, as said: 'turn on the living room lights'",
        "confirm": "Shall I tell Home Assistant “{text}”?",
    },
}  # fmt: skip


def describe(error: HomeAssistantError, language: AssistantLanguage) -> str:
    return str(_SENTENCES[language][error.reason]).replace("{status}", str(error.status))


class HomeAssistant:
    def __init__(self, address: str, token: str, client: httpx.Client | None = None):
        self.address = address
        self._token = token
        self._client = client or httpx.Client(timeout=TIMEOUT, follow_redirects=False, trust_env=False)

    def process(self, said: str, language: AssistantLanguage) -> str | None:
        """What Home Assistant says back; None when it says nothing."""
        payload = self._request("POST", "/api/conversation/process", home_command.conversation_request(said, language))
        if not isinstance(payload, dict) or not isinstance(payload.get("response"), dict):
            raise HomeAssistantError(Reason.UNEXPECTED)
        return home_command.spoken_reply(payload) or None

    def check(self) -> None:
        """Raises unless the address answers and accepts the token."""
        self._request("GET", "/api/", None)

    def _request(self, method: str, path: str, body: dict[str, Any] | None) -> Any:
        base = home_command.base_address(self.address)
        if base is None:
            raise HomeAssistantError(Reason.ADDRESS)
        if not self._token:
            raise HomeAssistantError(Reason.NO_TOKEN)
        headers = {"Authorization": "Bearer " + self._token}
        try:
            response = self._client.request(method, base + path, headers=headers, json=body)
        except httpx.TimeoutException as error:
            raise HomeAssistantError(Reason.TOO_SLOW) from error
        except httpx.HTTPError as error:
            log.info("Home Assistant is unreachable: %s", type(error).__name__)
            raise HomeAssistantError(Reason.UNREACHABLE) from error
        if response.status_code in (401, 403):
            raise HomeAssistantError(Reason.UNAUTHORIZED)
        if response.is_redirect or len(response.content) > MAX_BYTES:
            raise HomeAssistantError(Reason.UNEXPECTED)
        if not response.is_success:
            raise HomeAssistantError(Reason.STATUS, response.status_code)
        try:
            return response.json()
        except ValueError as error:
            raise HomeAssistantError(Reason.UNEXPECTED) from error


def smart_home_tool(home: HomeAssistant, language: AssistantLanguage) -> Tool:
    texts = _SENTENCES[language]

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # Home Assistant understands the user's own words better than the model's paraphrase of them.
        return {**arguments, "text": command} if home_command.names_home_device(command, language) else arguments

    def confirmation(arguments: dict[str, Any]) -> str | None:
        said = string_argument(arguments, "text")
        if not home_command.guards_the_house(said, language):
            return None
        return str(texts["confirm"]).replace("{text}", said)

    def run(arguments: dict[str, Any]) -> str:
        said = string_argument(arguments, "text")
        if not said:
            raise ToolError(str(texts[Reason.UNEXPECTED]))
        try:
            return home.process(said, language) or str(texts["done"])
        except HomeAssistantError as error:
            log.info("Home Assistant failed: %s", error)
            raise ToolError(describe(error, language)) from error

    return Tool("smartHome", str(texts["describe"]), run=run, parameters=obj(["text"], text=text(str(texts["text"]))),
                risk=Risk.CONFIRM, confirmation=confirmation, refine=refine)  # fmt: skip


def smart_home_rule(language: AssistantLanguage) -> Rule:
    """Only added when Home Assistant is set up; then a command naming a home device or room goes straight to it."""
    return rule("smartHome", lambda command: home_command.names_home_device(command, language),
                lambda command: {"text": command})  # fmt: skip
