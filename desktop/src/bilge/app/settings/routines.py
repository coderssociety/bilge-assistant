"""The routines set up by voice, and deleting them. The file is read again whenever the page is shown, so a routine
added by voice while the window was open appears too."""

from PySide6.QtWidgets import QHBoxLayout, QLabel, QListWidget, QListWidgetItem, QPushButton, QVBoxLayout, QWidget

from bilge import assembly
from bilge.app import texts
from bilge.app.texts import t
from bilge.tools.builtin import routines

_ID_ROLE = 256


class RoutinesPage(QWidget):
    def __init__(self, store: routines.RoutineStore | None = None) -> None:
        super().__init__()
        self.store = store or assembly.routine_store()
        self.entries = QListWidget()
        self.message = QLabel(wordWrap=True)
        delete = QPushButton(t("routines.delete"))
        delete.clicked.connect(self._delete)
        buttons = QHBoxLayout()
        buttons.addWidget(delete)
        buttons.addStretch()
        layout = QVBoxLayout(self)
        layout.addWidget(QLabel(t("routines.intro"), wordWrap=True))
        layout.addWidget(self.entries)
        layout.addLayout(buttons)
        layout.addWidget(self.message)
        self.refresh()

    def refresh(self) -> None:
        self.entries.clear()
        try:
            found = self.store.load()
        except routines.RoutineStoreError as error:
            self.message.setText(t("routines.failed", error=error))
            return
        for routine in found:
            item = QListWidgetItem(routines.describe(routine, texts.language()))
            item.setData(_ID_ROLE, routine.id)
            self.entries.addItem(item)
        if not found:
            self.entries.addItem(t("routines.empty"))

    def showEvent(self, event) -> None:  # noqa: N802 - Qt's name
        self.refresh()
        super().showEvent(event)

    def _delete(self) -> None:
        item = self.entries.currentItem()
        if item is None or item.data(_ID_ROLE) is None:
            return
        try:
            self.store.remove({item.data(_ID_ROLE)})
        except routines.RoutineStoreError as error:
            self.message.setText(t("routines.failed", error=error))
            return
        self.refresh()
