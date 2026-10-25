"""The user's own commands (the counterpart of Shortcuts on the Mac): which one a request names ("yedekleme komutunu
çalıştır"), whether it asks for the list ("komutlarım neler"), the fingerprint an approval is bound to, and the
command line as typed in the settings."""

import hashlib
import json
import re
import shlex
import subprocess

from bilge.core.language import AssistantLanguage
from bilge.core.text import folded
from bilge.core.tools import phrase_matcher

_COMMAND_WORDS = ("komut", "command")
_RUN_STEMS = ("calistir", "baslat")
_LEADING_FILLERS = frozenset({"bilge", "lutfen", "benim", "su", "bu"})
_MY_COMMANDS = frozenset({"komutlarim", "komutlarimi", "komutlarimiz", "komutlarimin"})
_LIST_CUES = frozenset({"neler", "ne", "listele", "hangi", "hangileri", "say", "goster", "oku", "var"})
_ENGLISH_RUN = re.compile(r"\b(?:run|start|execute)\s+(?:the\s+|my\s+)?(.+?)\s+command\b", re.IGNORECASE)
_ENGLISH_LIST_CUES = frozenset({"list", "what", "which", "show"})


def fingerprint(name: str, argv: list[str]) -> str:
    """Changes whenever the command does, so an edited command is asked about again."""
    return hashlib.sha256(json.dumps([name, argv], ensure_ascii=False).encode()).hexdigest()


def run_request(command: str, language: AssistantLanguage = AssistantLanguage.TURKISH) -> str | None:
    """The name in "yedekleme komutunu çalıştır" or "run the backup command"; None for other requests."""
    if language is AssistantLanguage.ENGLISH:
        found = _ENGLISH_RUN.search(command)
        return found.group(1).strip() if found else None
    words = command.split()
    folds = [folded(word).replace(" ", "") for word in words]
    for index in range(1, len(words) - 1):
        if folds[index].startswith(_COMMAND_WORDS) and folds[index + 1].startswith(_RUN_STEMS):
            start = 0
            while start < index and folds[start] in _LEADING_FILLERS:
                start += 1
            name = " ".join(words[start:index]).strip("\"“”'’,.")
            return name or None
    return None


def asks_for_list(command: str, language: AssistantLanguage = AssistantLanguage.TURKISH) -> bool:
    """ "Komutlarım neler", "hangi komutlarım var"; "list my commands". Only the user's own commands: "hangi komutları
    biliyorsun" asks about Bilge."""
    words = set(folded(command).split())
    if language is AssistantLanguage.ENGLISH:
        return "commands" in words and ("my" in words or "custom" in words) and bool(words & _ENGLISH_LIST_CUES)
    return bool(words & _MY_COMMANDS) and bool(words & _LIST_CUES)


def best_match(spoken: str, names: list[str]) -> str | None:
    """The configured name meant, even when "komutunu" or "command" is said along with it."""
    return phrase_matcher.best_match(_name_words(spoken), names)


def names_exactly(spoken: str, name: str, names: list[str]) -> bool:
    """Whether `spoken` is `name` itself and no other configured name: "sunucu" only resembles "sunucuyu kapat"."""
    said = folded(_name_words(spoken))
    return folded(name) == said and sum(folded(other) == said for other in names) == 1


def _name_words(spoken: str) -> str:
    words = [word for word in spoken.split() if not folded(word).startswith(_COMMAND_WORDS)]
    return " ".join(words) or spoken


def split_command_line(line: str, windows: bool) -> list[str]:
    """The arguments of a command line as typed in the settings; quotes group words. ValueError for an unclosed
    quote. On Windows backslashes are part of paths, not escapes."""
    if not windows:
        return shlex.split(line)
    lexer = shlex.shlex(line, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    lexer.escape = ""
    return list(lexer)


def join_command_line(argv: list[str], windows: bool) -> str:
    return subprocess.list2cmdline(argv) if windows else shlex.join(argv)
