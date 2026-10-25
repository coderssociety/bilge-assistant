from bilge.desktop.base import AppEntry, MediaCommand, NowPlaying
from bilge.desktop.linux.media import installed_players as linux_players
from bilge.desktop.music import MusicLauncher
from bilge.desktop.process import Completed, DesktopError
from bilge.desktop.windows.sound import installed_players as windows_players

from .fakes import FakeRunner

SPOTIFY = AppEntry("com.spotify.Client.desktop", "Spotify", ("Spotify",))
RHYTHMBOX = AppEntry("org.gnome.Rhythmbox3.desktop", "Rhythmbox", ("Rhythmbox",))
VLC = AppEntry("vlc.desktop", "VLC", ("VLC",))
EDITOR = AppEntry("org.gnome.TextEditor.desktop", "Metin Düzenleyici", ())


class Apps:
    def __init__(self, entries, media=None):
        self.entries, self.launched, self.media = entries, [], media

    def installed(self):
        return self.entries

    def launch(self, app):
        self.launched.append(app.id)
        if self.media is not None:
            self.media.appears_after = 2


class Media:
    """No player until `appears_after` more polls."""

    def __init__(self, refuses=False):
        self.appears_after, self.refuses, self.sent = None, refuses, []

    def now_playing(self):
        if self.appears_after is None:
            return None
        if self.appears_after > 0:
            self.appears_after -= 1
            return None
        return NowPlaying("Rhythmbox", False)

    def send(self, command):
        if self.refuses:
            raise DesktopError("refused")
        self.sent.append(command)
        return "Rhythmbox"


class Opener:
    def __init__(self):
        self.opened = []

    def open(self, target):
        self.opened.append(target)


def launcher(entries, media=None):
    media = media or Media()
    apps, opener = Apps(entries, media), Opener()
    return (
        MusicLauncher(apps, opener, media, lambda: entries, sleep=lambda _: None, wait_seconds=3),
        apps,
        opener,
        media,
    )


def test_the_first_player_is_started_and_told_to_play_once_it_answers():
    music, apps, _, media = launcher([RHYTHMBOX, VLC])
    started = music.start_player()
    assert (started.name, started.playing) == ("Rhythmbox", True)
    assert apps.launched == [RHYTHMBOX.id]
    assert media.sent == [MediaCommand.PLAY]


def test_a_player_that_never_answers_or_refuses_is_reported_as_not_playing():
    class Silent(Apps):
        def launch(self, app):
            self.launched.append(app.id)

    media = Media()
    music = MusicLauncher(Silent([VLC]), Opener(), media, lambda: [VLC], sleep=lambda _: None, wait_seconds=2)
    assert music.start_player().playing is False
    music, _, _, _ = launcher([VLC], Media(refuses=True))
    assert music.start_player().playing is False


def test_no_player_installed():
    assert launcher([])[0].start_player() is None


def test_search_goes_to_spotify_or_else_the_web():
    music, _, opener, _ = launcher([SPOTIFY, RHYTHMBOX])
    assert music.play_search("Tarkan Şımarık") == "Spotify"
    assert opener.opened == ["spotify:search:Tarkan%20%C5%9E%C4%B1mar%C4%B1k"]
    music, _, opener, _ = launcher([RHYTHMBOX])
    assert music.play_search("Sezen Aksu") == "YouTube Music"
    assert opener.opened == ["https://music.youtube.com/search?q=Sezen+Aksu"]


def test_linux_prefers_spotify_then_the_app_for_music_files_then_other_mpris_players():
    runner = FakeRunner({"xdg-mime"}, {"xdg-mime query default": "vlc.desktop\n"})
    players = linux_players(Apps([EDITOR, RHYTHMBOX, VLC, SPOTIFY]), runner)
    assert [p.id for p in players] == [SPOTIFY.id, VLC.id, RHYTHMBOX.id]
    runner = FakeRunner({"xdg-mime"}, {"xdg-mime": Completed(1, "", "no default")})
    assert [p.id for p in linux_players(Apps([VLC, RHYTHMBOX]), runner)] == [RHYTHMBOX.id, VLC.id]
    assert linux_players(Apps([EDITOR]), FakeRunner()) == []


def test_windows_prefers_spotify_then_media_player():
    zune = AppEntry("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic", "Medya Oynatıcı", ())
    classic = AppEntry("Microsoft.Windows.MediaPlayer32", "Windows Media Player Legacy", ())
    spotify = AppEntry("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "Spotify", ())
    assert windows_players(Apps([classic, zune, EDITOR])) == [zune, classic]
    assert windows_players(Apps([classic, spotify]))[0] == spotify
