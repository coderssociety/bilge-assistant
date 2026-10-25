"""The user's own commands: a name to say and the command line it runs, without a shell."""

import sys

from PySide6.QtWidgets import (
    QAbstractItemView,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from bilge import config
from bilge.app.texts import t
from bilge.core.text import folded
from bilge.core.tools.custom_command import join_command_line, split_command_line

_WINDOWS = sys.platform == "win32"


def commands_from_rows(
    rows: list[tuple[str, str]], windows: bool = _WINDOWS
) -> tuple[list[config.CustomCommand], str | None]:
    """The commands in the table, and the text key of what keeps it from being saved; empty rows are left out."""
    found: list[config.CustomCommand] = []
    for name, line in ((name.strip(), line.strip()) for name, line in rows):
        if not name and not line:
            continue
        if not name or not line:
            return found, "commands.incomplete"
        try:
            argv = split_command_line(line, windows)
        except ValueError:
            return found, "commands.unparsable"
        if not argv:
            return found, "commands.incomplete"
        if any(folded(name) == folded(other.name) for other in found):
            return found, "commands.duplicate"
        found.append(config.CustomCommand(name, argv))
    return found, None


class CommandsPage(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.table = QTableWidget(0, 2)
        self.table.setHorizontalHeaderLabels([t("commands.name"), t("commands.line")])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        add, remove = QPushButton(t("commands.add")), QPushButton(t("commands.remove"))
        # clicked passes whether the button is checked, which isn't a name.
        add.clicked.connect(lambda: self.add_row())
        remove.clicked.connect(self.remove_row)
        buttons = QHBoxLayout()
        buttons.addWidget(add)
        buttons.addWidget(remove)
        buttons.addStretch()
        layout = QVBoxLayout(self)
        layout.addWidget(QLabel(t("commands.intro"), wordWrap=True))
        layout.addWidget(self.table)
        layout.addLayout(buttons)

    def add_row(self, name: str = "", line: str = "") -> None:
        row = self.table.rowCount()
        self.table.insertRow(row)
        self.table.setItem(row, 0, QTableWidgetItem(name))
        self.table.setItem(row, 1, QTableWidgetItem(line))
        if not name:
            self.table.setCurrentCell(row, 0)
            self.table.editItem(self.table.item(row, 0))

    def remove_row(self) -> None:
        row = self.table.currentRow()
        if row >= 0:
            self.table.removeRow(row)

    def _rows(self) -> list[tuple[str, str]]:
        def cell(row: int, column: int) -> str:
            item = self.table.item(row, column)
            return item.text() if item is not None else ""

        return [(cell(row, 0), cell(row, 1)) for row in range(self.table.rowCount())]

    def load(self, settings: config.Settings) -> None:
        self.table.setRowCount(0)
        for command in settings.commands:
            self.add_row(command.name, join_command_line(command.argv, _WINDOWS))

    def problem(self) -> str | None:
        _, key = commands_from_rows(self._rows())
        return t(key) if key else None

    def apply(self, settings: config.Settings) -> None:
        commands, key = commands_from_rows(self._rows())
        # A table problem() refused is never saved half-read.
        if key is None:
            settings.commands = commands

    def save_secrets(self) -> None:
        pass
