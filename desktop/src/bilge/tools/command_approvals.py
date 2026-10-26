"""Which of the user's commands they have already said yes to, kept apart from the settings: an approval is bound to
the exact command (core.tools.custom_command.fingerprint), so a command changed afterwards is asked about again."""

import json
import logging
import os
from pathlib import Path

log = logging.getLogger(__name__)


class CommandApprovals:
    def __init__(self, path: Path):
        self.path = path

    def _load(self) -> set[str]:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return set()
        except (OSError, ValueError) as error:
            # Forgetting approvals only means asking again.
            log.warning("Could not read %s: %s", self.path, error)
            return set()
        return {item for item in data if isinstance(item, str)} if isinstance(data, list) else set()

    def approved(self, fingerprint: str) -> bool:
        return fingerprint in self._load()

    def approve(self, fingerprint: str) -> None:
        approved = sorted(self._load() | {fingerprint})
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(approved, file)
        temporary.replace(self.path)
