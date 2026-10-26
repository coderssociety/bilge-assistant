"""Integration with the operating system's desktop, behind the interfaces in `base`."""

import sys

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import Desktop, Folders


def current(language: AssistantLanguage) -> Desktop | None:
    """None where Bilge has no desktop integration yet; the assistant then runs without those tools."""
    if sys.platform.startswith("linux"):
        from bilge.desktop import linux

        # Menu entries are matched in the assistant's language first, then by their untranslated names.
        languages = ("tr_TR", "tr") if language is AssistantLanguage.TURKISH else ("en_US", "en")
        return linux.build(languages)
    if sys.platform == "win32":
        from bilge.desktop import windows

        return windows.build()
    return None


def folders() -> Folders:
    """The user's folders (Documents, Downloads…), also where Bilge has no other desktop integration."""
    if sys.platform == "win32":
        from bilge.desktop.windows.system import WindowsFolders

        return WindowsFolders()
    from bilge.desktop.linux.system import LinuxFolders

    return LinuxFolders()
