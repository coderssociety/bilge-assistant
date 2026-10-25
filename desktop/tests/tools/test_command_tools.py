import pytest

from bilge.config import CustomCommand
from bilge.core.language import AssistantLanguage
from bilge.desktop.process import Completed, DesktopError
from bilge.tools.base import Risk, ToolError
from bilge.tools.command_approvals import CommandApprovals
from bilge.tools.desktop.commands import CommandTools, command_rules, command_tools

from ..desktop.fakes import FakeRunner

TR = AssistantLanguage.TURKISH
BACKUP = CustomCommand("Yedekleme", ["rsync", "-a", "/home/ayse/Belgeler", "/mnt/yedek"])
UPDATE = CustomCommand("Sunucu güncelleme", ["ssh", "sunucu", "sudo apt upgrade -y"])


@pytest.fixture
def approvals(tmp_path):
    return CommandApprovals(tmp_path / "command-approvals.json")


def build(approvals, runner=None, commands=(BACKUP, UPDATE)):
    runner = runner or FakeRunner(installed={"rsync", "ssh"})
    tools = CommandTools(list(commands), approvals, runner, TR, windows=False)
    listing, run = command_tools(tools)
    return tools, listing, run, runner


def test_the_list_names_the_users_commands(approvals):
    _, listing, _, _ = build(approvals)
    assert listing.run({}) == "2 komutun var: Yedekleme, Sunucu güncelleme"
    _, empty, _, _ = build(approvals, commands=())
    assert "Komutlar sekmesinden" in empty.run({})


def test_the_first_run_asks_with_the_command_line_and_later_runs_do_not(approvals):
    _, _, run, runner = build(approvals)
    assert run.risk is Risk.CONFIRM and run.reads_untrusted({"name": "yedekleme"})
    question = run.question({"name": "yedekleme komutunu"})
    assert question == (
        "'Yedekleme' komutu ilk kez çalışacak: rsync -a /home/ayse/Belgeler /mnt/yedek. Çalıştırayım mı?"
    )
    assert run.run({"name": "yedekleme komutunu"}) == "'Yedekleme' komutu çalıştı."
    assert runner.commands == [["rsync", "-a", "/home/ayse/Belgeler", "/mnt/yedek"]]
    assert run.question({"name": "yedekleme"}) is None
    run.run({"name": "yedekleme"})
    assert len(runner.commands) == 2
    assert run.generic_question({"name": "yedekleme"}) == "'Yedekleme' komutunu çalıştırayım mı?"


def test_a_changed_command_is_asked_about_again(approvals):
    _, _, run, _ = build(approvals)
    run.question({"name": "yedekleme"})
    run.run({"name": "yedekleme"})
    changed = CustomCommand("Yedekleme", ["rsync", "-a", "/home/ayse", "/mnt/yedek"])
    _, _, run, _ = build(approvals, commands=(changed,))
    assert run.question({"name": "yedekleme"}).startswith("'Yedekleme' komutu ilk kez çalışacak")


def test_a_command_never_asked_about_does_not_run(approvals):
    _, _, run, runner = build(approvals)
    with pytest.raises(ToolError, match="yalnızca sesli onayla"):
        run.run({"name": "yedekleme"})
    assert runner.commands == []
    assert not approvals.approved("anything")


def test_spoken_words_never_reach_the_command(approvals):
    _, _, run, runner = build(approvals)
    arguments = {"name": "sunucu güncelleme", "extra": "; rm -rf ~", "args": ["--force"]}
    run.question(arguments)
    run.run(arguments)
    assert runner.commands == [["ssh", "sunucu", "sudo apt upgrade -y"]]


def test_an_unknown_name_runs_nothing(approvals):
    _, _, run, runner = build(approvals)
    assert run.question({"name": "müzik"}) is None
    with pytest.raises(ToolError, match="'müzik' adında bir komutun yok"):
        run.run({"name": "müzik"})
    assert runner.commands == []


@pytest.mark.parametrize(
    ("answer", "said"),
    [
        (Completed(0, "  1 dosya kopyalandı\n", ""), "'Yedekleme' komutu çalıştı. Çıktısı: 1 dosya kopyalandı"),
        (Completed(23, "", "hata"), "hata verdi \\(çıkış kodu 23\\)"),
    ],
)
def test_the_result_or_the_exit_code_is_told(approvals, answer, said):
    runner = FakeRunner(installed={"rsync"}, answers={"rsync": answer})
    _, _, run, _ = build(approvals, runner)
    run.question({"name": "yedekleme"})
    if answer.ok:
        assert run.run({"name": "yedekleme"}) == said
    else:
        with pytest.raises(ToolError, match=said):
            run.run({"name": "yedekleme"})


class SlowRunner(FakeRunner):
    def run(self, argv, input=None, timeout=15, capture=True):
        self.timeouts = [*getattr(self, "timeouts", []), timeout]
        raise DesktopError(f"{argv[0]} timed out")


def test_a_missing_program_or_a_timeout_is_told(approvals):
    _, _, run, _ = build(approvals, FakeRunner(installed=()))
    run.question({"name": "yedekleme"})
    with pytest.raises(ToolError, match="programı bulunamadı: rsync"):
        run.run({"name": "yedekleme"})
    slow = SlowRunner(installed={"rsync"})
    _, _, run, _ = build(approvals, slow)
    run.question({"name": "yedekleme"})
    with pytest.raises(ToolError, match="60 saniyede bitmedi"):
        run.run({"name": "yedekleme"})
    assert slow.timeouts == [60]


def test_a_home_folder_is_expanded_without_a_shell(approvals, monkeypatch):
    monkeypatch.setenv("HOME", "/home/ayse")
    monkeypatch.setenv("USERPROFILE", "/home/ayse")
    script = CustomCommand("Betik", ["~/bin/yedekle.sh", "~"])
    runner = FakeRunner(installed={"/home/ayse/bin/yedekle.sh"})
    _, _, run, _ = build(approvals, runner, commands=(script,))
    run.question({"name": "betik"})
    run.run({"name": "betik"})
    assert runner.commands == [["/home/ayse/bin/yedekle.sh", "/home/ayse"]]


def test_rules_list_and_run_only_commands_in_the_list(approvals):
    tools, _, _, _ = build(approvals)
    listing, run = command_rules(tools, TR)
    assert listing("komutlarım neler").name == "listShortcuts"
    assert run("yedekleme komutunu çalıştır").arguments == {"name": "yedekleme"}
    assert run("müzik komutunu çalıştır") is None


def test_a_broken_approvals_file_only_means_asking_again(approvals):
    approvals.path.write_text("{bozuk", encoding="utf-8")
    assert not approvals.approved("x")
    approvals.approve("x")
    assert approvals.approved("x")
