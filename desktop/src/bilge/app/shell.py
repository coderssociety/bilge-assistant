"""Ties the windows to the assistant: the tray (or a small window where the desktop has no tray), the corner window,
the settings and the setup."""

from collections.abc import Callable

from PySide6.QtCore import Qt, QTimer, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QApplication, QLabel, QMessageBox, QPushButton, QSystemTrayIcon, QVBoxLayout, QWidget

from bilge import config, update, updater
from bilge.app import texts, worker
from bilge.app.controller import AssistantController
from bilge.app.hud import Hud
from bilge.app.settings import SettingsWindow
from bilge.app.setup import SetupWizard
from bilge.app.shortcut import ListeningShortcut, listen_command
from bilge.app.texts import t
from bilge.app.tray import Tray, app_icon
from bilge.app.updates import UpdateWatcher

# At login the tray may come up after Bilge; it is looked for this long before the small window is used instead.
TRAY_WAIT_MS = 30_000
TRAY_POLL_MS = 2_000


class ControlWindow(QWidget):
    """Instead of the tray on desktops without one (GNOME without the AppIndicator extension)."""

    def __init__(self, shell: "Shell") -> None:
        super().__init__()
        self.setWindowTitle("Bilge")
        self.setWindowIcon(app_icon())
        self.status = QLabel()
        layout = QVBoxLayout(self)
        layout.addWidget(QLabel(t("tray.missing"), wordWrap=True))
        layout.addWidget(self.status)
        for key, action in (("menu.listen", shell.toggle_listening), ("menu.settings", shell.open_settings),
                            ("menu.quit", shell.quit)):  # fmt: skip
            button = QPushButton(t(key))
            button.clicked.connect(action)
            layout.addWidget(button)
        self.resize(320, 200)

    def show_status(self, status: str) -> None:
        self.status.setText(texts.status(status))


class Shell:
    def __init__(self, app: QApplication, controller: AssistantController | None = None, settings_path=None) -> None:
        self.app = app
        self.settings_path = settings_path
        self.controller = controller or AssistantController(load=lambda: config.load_settings(settings_path))
        self.hud = Hud()
        self.hud.answered.connect(self.controller.answer)
        self.controller.status_changed.connect(self._status)
        self.controller.heard.connect(lambda text: self.hud.show_heard(text))
        self.controller.replied.connect(lambda text: self.hud.show_reply(text))
        self.controller.failed.connect(self._failed)
        self.tray: Tray | None = None
        self.control: ControlWindow | None = None
        self.settings_window: SettingsWindow | None = None
        self.wizard: SetupWizard | None = None
        # Whether listening was on before a window paused it, so closing the window puts it back as it was.
        self._was_on = False
        self._tray_waited = 0
        self._tray_timer = QTimer(interval=TRAY_POLL_MS, timeout=self._look_for_tray)
        self.shortcut = ListeningShortcut()
        self.shortcut.pressed.connect(self.shortcut_pressed)
        self.shortcut.failed.connect(self._shortcut_failed)
        self.updates = UpdateWatcher(lambda: self._settings().check_updates)
        self.updates.found.connect(self._update_found)
        self._release: update.Release | None = None
        self._installing = False
        self._update_box: QMessageBox | None = None
        self._build_menus()

    def _settings(self) -> config.Settings:
        """A broken settings file was already reported at start; the windows then work from the defaults."""
        try:
            return config.load_settings(self.settings_path)
        except RuntimeError:
            return config.Settings()

    # Menus

    def _build_menus(self) -> None:
        if self.tray is not None:
            self.tray.icon.hide()
        self.tray = None
        if QSystemTrayIcon.isSystemTrayAvailable():
            self._use_tray()
        elif self.control is None and not self._tray_timer.isActive():
            self._tray_timer.start()
        self.hud.yes.setText(t("hud.yes"))
        self.hud.no.setText(t("hud.no"))

    def _use_tray(self) -> None:
        self._tray_timer.stop()
        if self.control is not None:
            self.control.close()
            self.control = None
        self.tray = Tray()
        self.tray.listen_toggled.connect(lambda on: self.controller.start() if on else self.controller.stop())
        self.tray.settings_requested.connect(self.open_settings)
        self.tray.setup_requested.connect(self.open_setup)
        self.tray.quit_requested.connect(self.quit)
        self.tray.install_requested.connect(self.install_update)
        self.tray.show()
        if self._release is not None:
            self.tray.show_update(self._release, announce=False, installable=updater.can_install(self._release))
        self._status(self.controller.status)

    def _look_for_tray(self) -> None:
        if QSystemTrayIcon.isSystemTrayAvailable():
            self._use_tray()
            return
        self._tray_waited += TRAY_POLL_MS
        if self._tray_waited >= TRAY_WAIT_MS:
            self._tray_timer.stop()
            self.control = ControlWindow(self)
            self.control.show()
            self._status(self.controller.status)

    # Start

    def begin(self) -> None:
        settings = self._settings()
        self.hud.enabled = settings.show_hud
        self._use_texts(settings)
        self.shortcut.apply(settings.voice.hotkey)
        self.updates.start()
        if settings.setup_done:
            self.controller.start()
        else:
            self.open_setup()

    def bring_forward(self) -> None:
        """Another start of Bilge knocked: show whatever is open, or the settings."""
        for window in (self.wizard, self.settings_window, self.control):
            if window is not None and window.isVisible():
                window.raise_()
                window.activateWindow()
                return
        if self.control is not None:
            self.control.show()
            return
        self.open_settings()

    def shortcut_pressed(self) -> None:
        """The listening shortcut, or `Bilge --listen`. While settings or setup are open, Bilge stays paused."""
        if any(window is not None and window.isVisible() for window in (self.settings_window, self.wizard)):
            return
        self.controller.shortcut_pressed()

    def _shortcut_failed(self, reason: str) -> None:
        settings = self._settings()
        message = t(f"hotkey.{reason}", shortcut=settings.voice.hotkey, command=listen_command())
        if not settings.voice.wake_word:
            # Without the shortcut and the wake word nothing would make Bilge listen.
            settings.voice.wake_word = True
            config.save_settings(settings, self.settings_path)
            self._use_texts(settings)
            self.controller.restart()
            message = f"{message}\n{t('hotkey.wake_word_back')}"
        self._failed(message)

    def _update_found(self, release: update.Release) -> None:
        self._release = release
        installable = updater.can_install(release)
        if self.tray is not None:
            self.tray.show_update(release, announce=False, installable=installable)
        # The window comes once per version; after "Later" the menu keeps the offer.
        if self.updates.record.announced() != release.version:
            self.updates.record.mark_announced(release.version)
            self._offer_update(release, installable)

    def _offer_update(self, release: update.Release, installable: bool) -> None:
        """A window that doesn't block anything: Bilge keeps listening while it is open."""
        box = QMessageBox(QMessageBox.Icon.Information, "Bilge", t("update.prompt_title", version=release.version))
        box.setWindowIcon(app_icon())
        box.setInformativeText(t("update.prompt_install" if installable else "update.prompt_page"))
        main = box.addButton(t("update.install_now" if installable else "update.open_page"),
                             QMessageBox.ButtonRole.AcceptRole)  # fmt: skip
        news = box.addButton(t("menu.whats_new"), QMessageBox.ButtonRole.ActionRole)
        box.addButton(t("update.later"), QMessageBox.ButtonRole.RejectRole)
        box.setDefaultButton(main)
        box.setWindowModality(Qt.WindowModality.NonModal)
        box.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)

        def clicked(button: object) -> None:
            if button is main and installable:
                self.install_update()
            elif button is main or button is news:
                QDesktopServices.openUrl(QUrl(release.url))

        box.buttonClicked.connect(clicked)
        self._update_box = box
        box.show()
        box.raise_()

    def install_update(self) -> None:
        """Downloads and checks the new version in the background; once it is in place the new Bilge is started and
        this one quits."""
        release = self._release
        if release is None or self._installing:
            return
        self._installing = True
        if self.tray is not None:
            self.tray.install.setEnabled(False)
        self._failed(t("update.installing", version=release.version))
        worker.run(lambda: updater.prepare(release), self._update_ready, self._update_failed)

    def _update_ready(self, start_new_bilge: Callable[[], None]) -> None:
        start_new_bilge()
        self.quit()

    def _update_failed(self, reason: str) -> None:
        try:
            error = t(f"update.error.{reason}")
        except KeyError:
            error = reason
        self._installing = False
        if self.tray is not None:
            self.tray.install.setEnabled(True)
        self._failed(t("update.install_failed", error=error))

    def toggle_listening(self) -> None:
        if self.controller.is_on:
            self.controller.stop()
        else:
            self.controller.start()

    def _pause(self) -> None:
        """While settings or setup are open, Bilge doesn't listen: recording a voice sample or hearing the voice
        preview must not be taken as a command."""
        self._was_on = self._was_on or self.controller.is_on
        self.controller.stop()

    def _resume(self) -> None:
        if self._was_on:
            self._was_on = False
            self.controller.start()

    # Windows

    def open_settings(self) -> None:
        if self.settings_window is not None and self.settings_window.isVisible():
            self.settings_window.raise_()
            self.settings_window.activateWindow()
            return
        self._pause()
        self.settings_window = SettingsWindow(self._settings(), self.settings_path)
        self.settings_window.saved.connect(self._settings_saved)
        self.settings_window.finished.connect(lambda _: self._resume())
        self.settings_window.show()

    def open_setup(self, language: str | None = None) -> None:
        self._pause()
        settings = self._settings()
        if language:
            settings.language = language
            self._use_texts(settings)
        self._discard_wizard()
        self.wizard = SetupWizard(settings, self.settings_path)
        self.wizard.language_chosen.connect(self._setup_language)
        self.wizard.finished_setup.connect(self._setup_finished)
        self.wizard.rejected.connect(self._setup_closed)
        self.wizard.show()

    def _discard_wizard(self) -> None:
        """The old wizard goes without its signals: closing it must not count as the user giving up the setup."""
        if self.wizard is None:
            return
        old, self.wizard = self.wizard, None
        for signal in (old.language_chosen, old.finished_setup, old.rejected):
            signal.disconnect()
        old.close()
        old.deleteLater()

    def _setup_language(self, language: str) -> None:
        # The wizard is built again in the chosen language, and the choice is kept for the rest of the setup.
        settings = self._settings()
        settings.language = language
        config.save_settings(settings, self.settings_path)
        self.open_setup(language)
        self._build_menus()

    def _setup_closed(self) -> None:
        if self._settings().setup_done:
            self._resume()

    def _setup_finished(self, settings: config.Settings) -> None:
        self._apply(settings)
        # Finishing setup means the user wants Bilge listening.
        self._was_on = True
        self._resume()

    def _settings_saved(self, settings: config.Settings) -> None:
        self._apply(settings)

    def _apply(self, settings: config.Settings) -> None:
        self._use_texts(settings)
        self.hud.enabled = settings.show_hud
        self.shortcut.apply(settings.voice.hotkey)
        self._build_menus()

    @staticmethod
    def _use_texts(settings: config.Settings) -> None:
        texts.use(settings.assistant_language, wake_word=settings.voice.wake_word or not settings.voice.hotkey)

    # Events

    def _status(self, status: str) -> None:
        if self.tray is not None:
            self.tray.show_status(status)
        if self.control is not None:
            self.control.show_status(status)
        self.hud.show_status(status)

    def _failed(self, message: str) -> None:
        if self.tray is not None:
            self.tray.notify(message)
        elif self.control is not None:
            self.control.status.setText(message)

    def quit(self) -> None:
        self.app.quit()

    def shut_down(self) -> None:
        """On every way out (the menu, the session ending): whisper.cpp must not keep the graphics card's memory."""
        self.shortcut.release()
        self.controller.stop()
