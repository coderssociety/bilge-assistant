# Contributing to Bilge

Thank you for helping. Bilge is two apps with one set of rules: the Mac app in `mac/` (Swift) and the Windows and
Linux app in `desktop/` (Python). They share the Turkish and English command sets in `bench/`.

*Türkçe özet aşağıda.*

## Ways to help

- **Report a bug** with the [bug form](https://github.com/serdarvaran/bilge-assistant/issues/new?template=bug_report.yml):
  what you said, what Bilge heard and did, and your system.
- **Suggest a feature** with the [feature form](https://github.com/serdarvaran/bilge-assistant/issues/new?template=feature_request.yml).
- **Add phrasings.** A Turkish or English sentence Bilge misunderstands is a valuable report: it becomes a test case.
- **Translate or improve the READMEs**, and fix a typo anywhere.
- **Code:** issues labelled `good first issue` are a good start.

## Working on the code

| | Mac (`mac/`) | Windows and Linux (`desktop/`) |
|---|---|---|
| Needs | macOS 27, Xcode 27, XcodeGen, the Metal toolchain | Python 3.14 and uv |
| Build | `xcodegen generate && open Asistan.xcodeproj` | `uv sync --extra app && uv run bilge-app` |
| Tests | `cd Packages/AsistanKit && swift test` | `uv run pytest` |
| Lint | — | `uv run ruff check src tests && uv run ruff format --check src tests` |

Rules worth knowing before you change something:

- **A change in one app usually has a twin in the other.** Parsers, confirmation rules and replies are kept the same;
  say in the pull request whether the other app needs the same change.
- **Anything that can't be undone asks first.** Keep that true for every new tool, and keep text read from the web,
  mail or the clipboard from triggering an action on its own.
- **Privacy:** nothing leaves the computer unless the user chose a service for it. Name any new service in the
  README's privacy section.
- **Both languages:** user-facing text is written in Turkish and English (the Mac string catalog, the desktop
  `texts.py`).
- Add a test for parsing, rules and calculations; keep pull requests focused on one change.

## Pull requests

Fork, branch from `main`, make the change with its tests, and open a pull request describing what changed and how
you checked it. CI runs the tests of the app you touched.

## Türkçe özet

Hata bildirmek, özellik önermek, Bilge'nin yanlış anladığı Türkçe ya da İngilizce cümleleri göndermek, README'leri
düzeltmek ve kod katkısı memnuniyetle karşılanır. Bir uygulamada yaptığın değişikliğin genelde diğerinde de karşılığı
olur; geri alınamayan her iş önce sormalı, kullanıcı seçmedikçe hiçbir şey bilgisayardan çıkmamalı ve kullanıcıya
görünen metinler Türkçe ve İngilizce yazılmalı. Derleme ve test komutları yukarıdaki tabloda.
