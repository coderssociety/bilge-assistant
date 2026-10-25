"""Small answers saved from the live services, so parsers are tested without the network."""

import json
from pathlib import Path
from typing import Any

WEB = Path(__file__).parent / "web"


def web_json(name: str) -> Any:
    return json.loads((WEB / name).read_text(encoding="utf-8"))


def web_bytes(name: str) -> bytes:
    return (WEB / name).read_bytes()
