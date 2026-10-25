"""Connecting an IMAP account for reading mail where there is no Outlook: the app password goes to the key store only
once the server has answered."""

from PySide6.QtWidgets import QFormLayout, QLabel, QLineEdit, QPushButton, QWidget

from bilge import assembly, config, mailboxes
from bilge.app import worker
from bilge.app.texts import t


class MailPage(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.server = QLineEdit(placeholderText="imap.example.org")
        self.user = QLineEdit()
        self.secret = QLineEdit(echoMode=QLineEdit.EchoMode.Password)
        self.test = QPushButton(t("mail.test"))
        self.test.clicked.connect(self._test)
        self.message = QLabel(wordWrap=True)
        form = QFormLayout(self)
        form.addRow(QLabel(t("mail.note"), wordWrap=True))
        form.addRow(t("mail.server"), self.server)
        form.addRow(t("mail.user"), self.user)
        form.addRow(t("mail.password"), self.secret)
        form.addRow("", self.test)
        form.addRow("", self.message)
        # A password that has passed the test, waiting for Save; changing any field means testing again.
        self._verified: str | None = None
        for field in (self.server, self.user, self.secret):
            field.textEdited.connect(self._forget_test)

    def _forget_test(self) -> None:
        self._verified = None

    def load(self, settings: config.Settings) -> None:
        self.server.setText(settings.mail.server)
        self.user.setText(settings.mail.username)
        self._verified = None

    def _chosen(self) -> config.MailSettings:
        return config.MailSettings(self.server.text().strip(), self.user.text().strip())

    def apply(self, settings: config.Settings) -> None:
        settings.mail = self._chosen()

    def save_secrets(self) -> None:
        if self._verified is not None:
            config.store_api_key(assembly.IMAP_SECRET, self._verified)
            self._verified = None
            self.secret.clear()

    def _test(self) -> None:
        self.test.setEnabled(False)
        # Read on the window thread; the check itself runs on another.
        chosen, typed = self._chosen(), self.secret.text().strip()

        def check():
            password = typed or config.api_key(assembly.IMAP_SECRET) or ""
            count, _ = mailboxes.IMAPMailbox(chosen.server, chosen.username, password).unread(0, 0)
            return count, typed or None

        def done(result) -> None:
            count, self._verified = result
            self.message.setText(t("mail.ok", count=count))
            self.test.setEnabled(True)

        def failed(error: str) -> None:
            self.message.setText(t("mail.failed", error=error))
            self.test.setEnabled(True)

        worker.run(check, done, failed, owner=self)
