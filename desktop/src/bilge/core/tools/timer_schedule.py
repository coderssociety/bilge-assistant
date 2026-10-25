from datetime import datetime, timedelta, tzinfo

MAX_DURATION = 24 * 60 * 60
MAX_LABEL_LENGTH = 40


def fire_date(
    minutes: int | None,
    seconds: int | None,
    hour: int | None,
    minute: int | None,
    now: datetime,
    tz: tzinfo | None = None,
) -> datetime | None:
    """A clock time (hour, optional minute) takes precedence; a time already passed today means tomorrow.
    `tz` plays the role of Swift's calendar time zone for the clock time."""
    if hour is not None:
        minute = minute or 0
        if not (0 <= hour < 24 and 0 <= minute < 60):
            return None
        local_now = now.astimezone(tz) if tz is not None else now
        today = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        # Aware datetime arithmetic is wall-clock, so "tomorrow" keeps the hour across DST changes.
        return today if today > now else today + timedelta(days=1)
    duration = (minutes or 0) * 60 + (seconds or 0)
    if not 0 < duration <= MAX_DURATION:
        return None
    return now + timedelta(seconds=duration)


def nearer_half_day(hour: int, minute: int, now: datetime, tz: tzinfo | None = None) -> int:
    """For a clock time said without a part of the day ("sekize çeyrek kala"): of the morning and the evening
    reading, the hour that comes first."""
    other = (hour + 12) % 24
    first = fire_date(None, None, hour, minute, now, tz)
    second = fire_date(None, None, other, minute, now, tz)
    if first is None or second is None:
        return hour
    return hour if first <= second else other


def clean_label(label: str | None) -> str | None:
    trimmed = label.strip() if label is not None else ""
    if not trimmed:
        return None
    if len(trimmed) <= MAX_LABEL_LENGTH:
        return trimmed
    words = [word for word in trimmed[:MAX_LABEL_LENGTH].split(" ") if word][:-1]
    return " ".join(words) if words else trimmed[:MAX_LABEL_LENGTH]
