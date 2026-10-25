"""Turns one spoken request into tool calls and a spoken answer.

The model chooses the tools; every call still goes through the safety policy, the user's confirmation and the
action log, so the model never acts on its own authority.
"""

import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from bilge.brain import fast_path, instructions
from bilge.brain.policy import Action, decide
from bilge.brain.routing import Mode, Rule
from bilge.core import translation_request
from bilge.core.conversation.conversation_flow import WorkSession
from bilge.core.language import AssistantLanguage
from bilge.core.speech import turkish_number_parser, turkish_time_of_day
from bilge.core.translation_request import SpeechLanguage
from bilge.llm.messages import Message, ToolCall
from bilge.llm.providers import ChatProvider
from bilge.tools.base import Registry, Tool, ToolError
from bilge.tools.reading import TextReading

log = logging.getLogger(__name__)

MAX_STEPS = 8
# Earlier exchanges kept for follow-ups ("ya yarın?"); only the spoken text, not the tool traffic.
HISTORY_TURNS = 3
# Above the longest part a tool reads (a 12,000-character web page or story with its title), so the model gets all
# a tool read; only something unexpected is cut, and long texts go on with "devamını oku".
MAX_RESULT_CHARACTERS = 13_000
MAX_ERROR_CHARACTERS = 300


class Confirmer(Protocol):
    def __call__(self, question: str) -> bool: ...


@dataclass(frozen=True)
class Outcome:
    text: str
    # The answer may echo fetched text, so the caller must not let it steer the next command.
    read_untrusted: bool = False
    # The language the answer is in when the request asked for a translation; it is spoken in that language.
    translation: SpeechLanguage | None = None


_TEXTS = {
    AssistantLanguage.TURKISH: {
        "caution": "Dikkat, bu adım okuduğum bir içeriğe dayanıyor.",
        "ask": "Yapayım mı?",
        "unknown_tool": "Hata: '{name}' diye bir araç yok.",
        "refused": "Güvenlik: {name} şu an kullanılamaz. Bu adımı atla ve kullanıcıya kısaca söyle.",
        "declined": "Kullanıcı onay vermedi, {name} çalıştırılmadı.",
        "declined_spoken": "Tamam, yapmıyorum.",
        "refused_spoken": "Bunu şu an yapamam; az önce okuduğum bir içeriğe dayanıyor.",
        "failed": "Hata ({name}): {error}",
        "result": "Sonuç ({name}), veri olarak:\n<<<\n{result}\n>>>",
        "gave_up": "Bu isteği adım adım tamamlayamadım.",
        "partly_done": "Yapabildiğim adımları tamamladım ama isteğin hepsini bitiremedim.",
        "needs_user": "“{command}” rutini için onayın gerekiyor, o yüzden sen yokken çalıştırmadım. İstediğinde bana söyleyebilirsin.",
    },
    AssistantLanguage.ENGLISH: {
        "caution": "Careful, this step is based on content I read.",
        "ask": "Shall I?",
        "unknown_tool": "Error: there is no tool called '{name}'.",
        "refused": "Security: {name} cannot be used right now. Skip this step and tell the user briefly.",
        "declined": "The user did not confirm; {name} was not run.",
        "declined_spoken": "OK, I won't.",
        "refused_spoken": "I can't do that right now; it's based on content I just read.",
        "failed": "Error ({name}): {error}",
        "result": "Result ({name}), as data:\n<<<\n{result}\n>>>",
        "gave_up": "I couldn't finish this request step by step.",
        "partly_done": "I did the steps I could, but not the whole request.",
        "needs_user": "The “{command}” routine needs your yes, so I didn't run it while you were away. Just ask me when you're here.",
    },
}


@dataclass(frozen=True)
class _Step:
    """One tool call's outcome: what the model sees, and the sentence for the user when the call is the whole turn."""

    text: str
    ran: bool
    untrusted: bool
    spoken: str
    # The tool couldn't do it (as opposed to the user saying no); a quick command then goes to the model instead.
    failed: bool = False
    # It needed a spoken yes while nobody was there to give one; the turn ends.
    needs_user: bool = False


class ActionLog(Protocol):
    def record(self, tool: str, arguments: dict[str, Any], decision: str, result: str) -> None: ...


class Agent:
    def __init__(
        self,
        provider: ChatProvider,
        registry: Registry,
        confirm: Confirmer,
        language: AssistantLanguage = AssistantLanguage.TURKISH,
        memory: Callable[[], str | None] | None = None,
        action_log: ActionLog | None = None,
        clock: Callable[[], datetime] = datetime.now,
        rules: list[Rule] | None = None,
        modes: list[Mode] | None = None,
        reading: TextReading | None = None,
    ):
        """`reading`: the long text being read, whose "devamını oku" keeps the language it was translated into."""
        self.provider = provider
        self.registry = registry
        self.confirm = confirm
        self.language = language
        self.memory = memory
        self.action_log = action_log
        self.clock = clock
        self.rules = rules or []
        self.modes = modes or []
        self.reading = reading
        self._texts = _TEXTS[language]
        self._history: list[tuple[Message, Message, bool]] = []
        self._read_earlier = False
        self._translation: SpeechLanguage | None = None
        self._unattended = False

    @property
    def last_reply(self) -> str | None:
        return self._history[-1][1].content if self._history else None

    @property
    def work_session(self) -> WorkSession | None:
        """Set while a hands-free mode is on; the conversation then stays open for its input."""
        mode = self._active_mode()
        return WorkSession(mode.window(), mode.accepts) if mode else None

    def handle_work_input(self, text: str) -> Outcome:
        """Input heard without the wake word during a hands-free mode."""
        mode = self._active_mode()
        if mode is not None and mode.takes is not None:
            return Outcome(mode.takes(text))
        return self.handle(text, tools=mode.tools if mode else None)

    def _active_mode(self) -> Mode | None:
        return next((mode for mode in self.modes if mode.is_active()), None)

    def handle(self, said: str, tools: frozenset[str] | None = None, unattended: bool = False) -> Outcome:
        """`tools` limits what the model may call: talk heard without the wake word in a mode only reaches that
        mode's tools. `unattended`: a routine running with nobody there to answer, so a step that would need a
        spoken yes ends the turn unrun, and a hands-free mode doesn't take the command."""
        self._unattended = unattended
        mode = None if unattended else self._active_mode()
        if mode is not None and mode.takes is not None and mode.owns(said):
            return Outcome(mode.takes(said))
        command = resolve(said, self.language)
        self._command = command
        # A reply to text fetched in an earlier turn is still in the conversation.
        self._read_earlier = any(untrusted for *_, untrusted in self._history)
        # "İngilizce maili Türkçe oku": the model reads and translates, so rules that answer by themselves step aside.
        target = translation_request.target(command) or (
            self.reading.translation_for(command) if self.reading else None
        )
        if self.reading is not None:
            self.reading.requested(target)
        self._translation = target
        wording = instructions.request(command, self.clock(), self.language)
        request = Message.user(wording + (instructions.translation(target, self.language) if target else ""))

        # Rules see the words as said: their own parsers read numbers, and "on iki" is not always a time.
        def allowed(name: str) -> bool:
            return self.registry.get(name) is not None and (tools is None or name in tools)

        for route in self.rules if target is None else []:
            call = route(said)
            if call is not None and allowed(call.name):
                step = self._run(call, read_untrusted=False)
                if step.needs_user:
                    return self._needs_user(said)
                return self._finish(request, step.spoken, step.untrusted)
        quick = fast_path.call_for(command, self.language) if target is None else None
        if quick and allowed(quick.name):
            step = self._run(quick, read_untrusted=False)
            if step.needs_user:
                return self._needs_user(said)
            if not step.failed:
                return self._finish(request, step.spoken, step.untrusted)
        system = instructions.system_prompt(self.language, self.memory() if self.memory else None)
        earlier = [message for user, answer, _ in self._history for message in (user, answer)]
        messages = [Message.system(system), *earlier, request]
        read_untrusted = False
        completed = 0
        for _ in range(MAX_STEPS):
            specs = [spec for spec in self.registry.specs() if tools is None or spec.name in tools]
            reply = self.provider.complete(messages, specs)
            if not reply.tool_calls:
                return self._finish(request, reply.text, read_untrusted)
            messages.append(Message("assistant", reply.text, tool_calls=reply.tool_calls))
            for call in reply.tool_calls:
                step = self._run(call, read_untrusted)
                if step.needs_user:
                    return self._needs_user(said)
                read_untrusted = read_untrusted or step.untrusted
                completed += step.ran
                messages.append(Message.tool_result(call, step.text))
        return self._finish(request, self._texts["partly_done" if completed else "gave_up"], read_untrusted)

    def forget_conversation(self) -> None:
        """Called when the user stops talking to Bilge, so the next request starts fresh."""
        self._history.clear()
        for mode in self.modes:
            mode.end()

    def _needs_user(self, said: str) -> Outcome:
        return Outcome(self._texts["needs_user"].format(command=said.strip()))

    def _finish(self, request: Message, text: str, read_untrusted: bool) -> Outcome:
        # Only this turn's reading marks this turn's reply; earlier ones age out with their own turns.
        if text.strip():
            # Some APIs reject an empty assistant turn, which would break every following request.
            self._history = [*self._history, (request, Message("assistant", text), read_untrusted)][-HISTORY_TURNS:]
        return Outcome(text, read_untrusted or self._read_earlier, self._translation)

    def _run(self, call: ToolCall, read_untrusted: bool) -> _Step:
        texts = self._texts
        tool = self.registry.get(call.name)
        if tool is None:
            message = texts["unknown_tool"].format(name=call.name)
            return _Step(message, False, False, message, failed=True)
        try:
            if tool.refine:
                call = ToolCall(call.id, call.name, tool.refine(call.arguments, self._command))
            stopped = self._check(tool, call, read_untrusted)
        except Exception as error:  # A tool that breaks while preparing must not end the conversation either.
            log.exception("Tool %s failed before running", tool.name)
            self._record(call, "failed", repr(error))
            failed = texts["failed"].format(name=tool.name, error=type(error).__name__)
            return _Step(failed, False, False, texts["gave_up"], failed=True)
        if stopped is not None:
            return stopped
        # A failed fetch may still carry the other side's words in its error, so it counts as untrusted too.
        untrusted = tool.reads_untrusted(call.arguments)
        try:
            result = tool.run(call.arguments)
        except ToolError as error:
            self._record(call, "failed", str(error))
            message = str(error)[:MAX_ERROR_CHARACTERS]
            failed = texts["failed"].format(name=tool.name, error=message)
            return _Step(failed, False, untrusted, message, failed=True)
        except Exception as error:  # A broken tool must not take the conversation down with it.
            log.exception("Tool %s crashed", tool.name)
            self._record(call, "failed", repr(error))
            failed = texts["failed"].format(name=tool.name, error=type(error).__name__)
            return _Step(failed, False, untrusted, texts["gave_up"], failed=True)
        self._record(call, "ran", result)
        shown = result[:MAX_RESULT_CHARACTERS]
        if untrusted:
            shown = texts["result"].format(name=tool.name, result=shown)
        return _Step(shown, True, untrusted, result)

    def _check(self, tool: Tool, call: ToolCall, read_untrusted: bool) -> _Step | None:
        """The policy and the user's yes; a step when the call must not run."""
        texts = self._texts
        verdict = decide(tool.name, tool.risk, read_untrusted, self._read_earlier)
        if verdict.action is Action.REFUSE:
            self._record(call, "refused", "")
            return _Step(texts["refused"].format(name=tool.name), False, False, texts["refused_spoken"])
        if verdict.action is not Action.CONFIRM:
            return None
        question = tool.question(call.arguments)
        if question is None and verdict.cautioned:
            question = tool.generic_question(call.arguments)
        if question is None:
            return None
        if verdict.cautioned:
            question = f"{texts['caution']} {question}"
        if not question.rstrip().endswith("?"):
            question = f"{question} {texts['ask']}"
        if self._unattended:
            self._record(call, "needs user", "")
            return _Step(texts["declined"].format(name=tool.name), False, False, "", needs_user=True)
        if self.confirm(question):
            return None
        self._record(call, "declined", "")
        return _Step(texts["declined"].format(name=tool.name), False, False, texts["declined_spoken"])

    def _record(self, call: ToolCall, decision: str, result: str) -> None:
        if not self.action_log:
            return
        try:
            self.action_log.record(call.name, call.arguments, decision, result)
        except OSError:
            # The action already happened; the user should still hear its result.
            log.exception("Could not write the action log")


def resolve(command: str, language: AssistantLanguage) -> str:
    """Turkish number words and times of day become digits ("yüz yirmi beş" → "125", "sabah yedide" → "07:00"),
    which both the parsers and the model handle more reliably. English is left as said: the Turkish rules would
    turn "on" into 10."""
    if language is not AssistantLanguage.TURKISH:
        return command
    return turkish_time_of_day.resolve(turkish_number_parser.digitize(command))
