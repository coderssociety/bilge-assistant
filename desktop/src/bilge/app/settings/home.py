"""Connecting Home Assistant: the long-lived access token goes to the key store only once the server has accepted it,
and is never shown again or written to the settings file."""

from PySide6.QtWidgets import QFormLayout, QLabel, QLineEdit, QPushButton, QWidget

from bilge import assembly, config
from bilge.app import texts, worker
from bilge.app.texts import t
from bilge.core.home import home_command
from bilge.tools.builtin.home_assistant import HomeAssistant, HomeAssistantError, describe


class HomePage(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.address = QLineEdit(placeholderText="http://homeassistant.local:8123")
        self.token = QLineEdit(echoMode=QLineEdit.EchoMode.Password)
        self.token_state = QLabel()
        self.test = QPushButton(t("home.test"))
        self.test.clicked.connect(self._test)
        self.message = QLabel(wordWrap=True)
        form = QFormLayout(self)
        form.addRow(QLabel(t("home.note"), wordWrap=True))
        form.addRow(t("home.address"), self.address)
        form.addRow(t("home.token"), self.token)
        form.addRow("", self.token_state)
        form.addRow("", self.test)
        form.addRow("", self.message)
        # A token that has passed the test, waiting for Save; changing either field means testing again.
        self._verified: str | None = None
        for field in (self.address, self.token):
            field.textEdited.connect(self._forget_test)

    def _forget_test(self) -> None:
        self._verified = None

    def load(self, settings: config.Settings) -> None:
        self.address.setText(settings.home.address)
        self._verified = None
        stored = config.api_key(assembly.HOME_ASSISTANT_SECRET)
        self.token_state.setText(t("home.token_stored") if stored else t("home.token_missing"))

    def apply(self, settings: config.Settings) -> None:
        settings.home = config.HomeSettings(self.address.text().strip())

    def save_secrets(self) -> None:
        if self._verified is not None:
            config.store_api_key(assembly.HOME_ASSISTANT_SECRET, self._verified)
            self._verified = None
            self.token.clear()
            self.token_state.setText(t("home.token_stored"))

    def problem(self) -> str | None:
        address = self.address.text().strip()
        if address and home_command.base_address(address) is None:
            return t("home.bad_address")
        return None

    def _test(self) -> None:
        self.test.setEnabled(False)
        # Read on the window thread; the check itself runs on another.
        address, typed, language = self.address.text().strip(), self.token.text().strip(), texts.language()

        def check():
            token = typed or config.api_key(assembly.HOME_ASSISTANT_SECRET) or ""
            try:
                HomeAssistant(address, token).check()
            except HomeAssistantError as error:
                raise RuntimeError(describe(error, language)) from error
            return typed or None

        def done(verified) -> None:
            self._verified = verified
            self.message.setText(t("home.ok"))
            self.test.setEnabled(True)

        def failed(error: str) -> None:
            self.message.setText(t("home.failed", error=error))
            self.test.setEnabled(True)

        worker.run(check, done, failed, owner=self)
