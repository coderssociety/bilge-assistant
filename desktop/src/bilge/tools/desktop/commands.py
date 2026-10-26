"""The user's own commands from Settings → Commands ("yedekleme komutunu çalıştır", "komutlarım neler"), the
counterpart of Shortcuts on the Mac. A command runs exactly as written there: no shell, nothing spoken added to it,
and the first run of each (and of each changed version) needs a spoken yes."""

import os
import sys
from typing import Any

from bilge.brain.routing import Rule, rule
from bilge.config import CustomCommand
from bilge.core.language import AssistantLanguage
from bilge.core.tools import custom_command
from bilge.desktop.process import DesktopError, MissingProgram, Runner
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.command_approvals import CommandApprovals
from bilge.tools.desktop.common import obj, string_argument, text

COMMAND_SECONDS = 60
OUTPUT_CHARACTERS = 300
# The command line is read out in the first question; a very long one is cut there.
SPOKEN_LINE_CHARACTERS = 200

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "list": "Kullanıcının Ayarlar'da tanımladığı kendi komutlarının adlarını söyler ('komutlarım neler').",
        "run": "Kullanıcının Ayarlar'da tanımladığı bir komutu adıyla çalıştırır ('yedekleme komutunu çalıştır'); "
        "başka bir aracın yapmadığı işler için de kullanılır.",
        "name": "Komutun adı: 'yedekleme komutunu çalıştır' → 'yedekleme'",
        "none": "Henüz bir komutun yok; Bilge Ayarları'ndaki Komutlar sekmesinden ekleyebilirsin.",
        "listed": "{count} komutun var: {names}",
        "unknown": "'{name}' adında bir komutun yok.",
        "first": "'{name}' komutu ilk kez çalışacak: {line}. Çalıştırayım mı?",
        "again": "'{name}' komutunu çalıştırayım mı?",
        "needs_yes": "'{name}' komutu ilk kez yalnızca sesli onayla çalışır.",
        "ran": "'{name}' komutu çalıştı.",
        "output": "'{name}' komutu çalıştı. Çıktısı: {output}",
        "exit": "'{name}' komutu hata verdi (çıkış kodu {code}).",
        "missing": "'{name}' komutunun programı bulunamadı: {program}",
        "failed": "'{name}' komutu çalıştırılamadı ya da {seconds} saniyede bitmedi.",
    },
    AssistantLanguage.ENGLISH: {
        "list": "Says the names of the user's own commands set up in Settings ('what are my commands').",
        "run": "Runs one of the user's own commands from Settings by name ('run the backup command'); also for "
        "jobs no other tool does.",
        "name": "The command's name: 'run the backup command' → 'backup'",
        "none": "You have no commands yet; you can add some on the Commands tab of Bilge Settings.",
        "listed": "You have {count} commands: {names}",
        "unknown": "You have no command called '{name}'.",
        "first": "The command '{name}' runs for the first time: {line}. Shall I run it?",
        "again": "Shall I run the command '{name}'?",
        "needs_yes": "The command '{name}' runs the first time only after a spoken yes.",
        "ran": "The command '{name}' ran.",
        "output": "The command '{name}' ran. It printed: {output}",
        "exit": "The command '{name}' failed (exit code {code}).",
        "missing": "The program of the command '{name}' wasn't found: {program}",
        "failed": "The command '{name}' couldn't run or didn't finish within {seconds} seconds.",
    },
}


class CommandTools:
    def __init__(
        self,
        commands: list[CustomCommand],
        approvals: CommandApprovals,
        runner: Runner,
        language: AssistantLanguage,
        windows: bool = sys.platform == "win32",
    ):
        self.commands = commands
        self.approvals = approvals
        self.runner = runner
        self.texts = _TEXTS[language]
        self.windows = windows
        # Fingerprints of commands the user was just asked about for the first time.
        self._asked: set[str] = set()

    def find(self, spoken: str) -> CustomCommand | None:
        name = custom_command.best_match(spoken, [c.name for c in self.commands]) if spoken else None
        return next((c for c in self.commands if c.name == name), None) if name else None

    def listing(self, _: dict[str, Any]) -> str:
        if not self.commands:
            return self.texts["none"]
        return self.texts["listed"].format(count=len(self.commands), names=", ".join(c.name for c in self.commands))

    def question(self, arguments: dict[str, Any]) -> str | None:
        """Only the first run asks, or a name that merely resembles a command ("sunucu" for "sunucuyu kapat"), which
        names the one meant; None also when there is no such command, which running then says."""
        self._asked.clear()
        spoken = string_argument(arguments, "name")
        found = self.find(spoken)
        if found is None:
            return None
        key = custom_command.fingerprint(found.name, found.argv)
        if self.approvals.approved(key):
            names = [command.name for command in self.commands]
            return None if custom_command.names_exactly(spoken, found.name, names) else self.spoken_action(arguments)
        self._asked.add(key)
        line = custom_command.join_command_line(found.argv, self.windows)
        if len(line) > SPOKEN_LINE_CHARACTERS:
            line = line[:SPOKEN_LINE_CHARACTERS] + "…"
        return self.texts["first"].format(name=found.name, line=line)

    def spoken_action(self, arguments: dict[str, Any]) -> str:
        found = self.find(string_argument(arguments, "name"))
        return self.texts["again"].format(name=found.name if found else string_argument(arguments, "name"))

    def run(self, arguments: dict[str, Any]) -> str:
        spoken = string_argument(arguments, "name")
        found = self.find(spoken)
        if found is None:
            raise ToolError(self.texts["unknown"].format(name=spoken))
        key = custom_command.fingerprint(found.name, found.argv)
        if not self.approvals.approved(key):
            if key not in self._asked:
                raise ToolError(self.texts["needs_yes"].format(name=found.name))
            self.approvals.approve(key)
        self._asked.discard(key)
        return self._execute(found)

    def _execute(self, command: CustomCommand) -> str:
        texts = self.texts
        # Without a shell "~" would stay literal; it is the only shell convenience given.
        argv = [os.path.expanduser(part) if part.startswith("~") else part for part in command.argv]
        try:
            done = self.runner.run(argv, timeout=COMMAND_SECONDS)
        except MissingProgram as error:
            raise ToolError(texts["missing"].format(name=command.name, program=argv[0])) from error
        except DesktopError as error:
            raise ToolError(texts["failed"].format(name=command.name, seconds=COMMAND_SECONDS)) from error
        if not done.ok:
            raise ToolError(texts["exit"].format(name=command.name, code=done.status))
        output = done.stdout.strip()
        if not output:
            return texts["ran"].format(name=command.name)
        return texts["output"].format(name=command.name, output=output[:OUTPUT_CHARACTERS])


def command_tools(tools: CommandTools) -> list[Tool]:
    texts = tools.texts
    return [
        Tool("listShortcuts", texts["list"], run=tools.listing),
        Tool(
            "runShortcut",
            texts["run"],
            run=tools.run,
            parameters=obj(["name"], name=text(texts["name"])),
            risk=Risk.CONFIRM,
            confirmation=tools.question,
            spoken_action=tools.spoken_action,
            # A program may print anything, a web page it fetched included.
            untrusted_output=True,
            # Asked only before a command's first run (or for a name that merely resembles one), and it can do anything.
            explicit_yes=True,
        ),
    ]


def command_rules(tools: CommandTools, language: AssistantLanguage) -> list[Rule]:
    """ "Komutlarım neler", and running a command by a name that is in the list."""

    def names_one(command: str) -> bool:
        spoken = custom_command.run_request(command, language)
        return spoken is not None and tools.find(spoken) is not None

    return [
        rule("listShortcuts", lambda command: custom_command.asks_for_list(command, language)),
        rule("runShortcut", names_one, lambda command: {"name": custom_command.run_request(command, language)}),
    ]
