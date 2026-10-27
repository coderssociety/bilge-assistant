# Bilge demo videos: storyboard

## Goal and audience

Show in seconds what Bilge is: you say a sentence, it acts on your computer, it asks before anything it can't undo,
and it answers out loud. Then the reasons to pick it: made for Turkish, private by default, free on three systems.

- **README loop** (`readme-en`, `readme-tr`): visitors of the GitHub page who scroll past the first screenshot.
  Silent, captioned, loops; 24.4 s, 1280×720, also as a 960 px GIF.
- **Social cut** (`social-en`, `social-tr`, `social-tr-vertical`): people who don't know Bilge yet, on X, LinkedIn,
  YouTube, Reels and Shorts. With voice and burned-in captions; 53 s, 1920×1080 and 1080×1920.
- **Posters** (`poster-en.png`, `poster-tr.png`): the thumbnail/first frame, 1280×720.

## Rules

- Only what the app really does. Every reply is the app's own wording: the HUD screenshots, the calendar strings
  (`Added: %@, %@.` / `Ekledim: %@, %@.` in `mac/App/Resources/Localizable.xcstrings`) and the screenshot samples in
  `desktop/scripts/screenshots.py`. Headlines paraphrase README.md / README.tr.md. No invented numbers: the Türkiye
  scene shows the questions from the README, not made-up answers.
- Hook in the first 2–3 s: the command is typed as it is spoken and the real confirmation window rises at 1.3 s.
- One idea per scene, large captions (≥ 25 px at 1280×720), brand colours from the logo (#2A2E7A → #141634,
  accent #FFB547, text #F4F1EA, lavender #C9C6FF), ease-out cubic entrances, cross-fades, no other effects.
- The vertical cut keeps captions between 60 % and 75 % of the height, clear of the Reels/Shorts controls.

## Scenes

| # | Scene | README loop | Social EN | Social TR | Real asset |
|---|---|---|---|---|---|
| 1 | Confirm (hook) | 0.0–6.8 | 0.0–10.9 | 0.0–11.7 | `mac/docs/images/en/hud-confirm.png`, `mac/docs/images/hud-confirm.png` (card cropped) |
| 2 | Asking first | — | 10.9–16.8 | 11.7–17.0 | type and icons only |
| 3 | Answer | 6.8–11.2 | 16.8–27.6 | 17.0–29.7 | `desktop/docs/images/hud-answer.png`, `desktop/docs/images/tr/hud-answer.png` |
| 4 | Made for Turkish | 11.2–15.0 | 27.6–36.4 | 29.7–37.4 | type and icons only |
| 5 | Private by default | 15.0–18.6 | 36.4–43.5 | 37.4–43.8 | type and icons only |
| 6 | Three systems | 18.6–21.3 | 43.5–48.7 | 43.8–48.8 | `mac/docs/images/{en/,}onboarding.png` (window cropped), `desktop/docs/images/{,tr/}setup.png` |
| 7 | End card | 21.3–24.4 | 48.7–52.9 | 48.8–53.0 | `mac/docs/images/logo.svg` |

The README loop fades the end card out in its last 0.45 s, so it restarts on the empty first frame.

## Captions and voice

Bilge's replies are spoken by Supertonic-3 F1, Bilge's own default voice, generated on this Mac through FluidAudio.
Everything else (the user's lines and the narration) is a Microsoft neural voice fetched with edge-tts: Emel
(`tr-TR-EmelNeural`) in Turkish and Andrew (`en-US-AndrewMultilingualNeural`) in English; the local voices
(macOS `say`, Supertonic-3 M1) sounded robotic there. User lines are typed out in the caption as they are heard;
narration captions carry no speaker label. Each clip is loudness-normalised before mixing, so the voices sit at a
similar level. Every claim in the narration is in the README.
The README loop uses only the captions marked “loop”.

### 1. Confirm (hook)

| Who | English | Türkçe | Used in |
|---|---|---|---|
| Kicker / headline | ON THE MAC · It asks before it acts. | MAC'TE · Yapmadan önce sorar. | loop, social |
| You | Bilge, add a dentist appointment tomorrow at ten. | Bilge, yarın saat onda diş hekimi randevusu ekle. | loop, social |
| Bilge | Shall I add “Dentist” to your calendar for tomorrow at 10:00? | Yarın 10:00'da “Diş hekimi” etkinliğini takvime ekleyeyim mi? | social (voice); shown in the HUD in the loop |
| You | Yes. | Evet. | loop, social; the “Yes, do it” / “Evet, yap” button glows |
| Bilge | Added: tomorrow at 10:00, Dentist. | Ekledim: yarın saat 10:00, Diş hekimi. | loop, social |

### 2. Asking first (social only)

- Kicker / headline: SAFE BY DESIGN · Anything it can't undo waits for your yes. / GÜVENLİ TASARIM · Geri
  alınamayan her iş “evet” bekler.
- Cards: Sending a mail or a message · Moving files to the trash · Restarting or shutting down · Locks, garage doors
  and alarms / E-posta ya da mesaj göndermek · Dosyaları çöpe atmak · Yeniden başlatmak ya da kapatmak · Kilit, garaj
  kapısı ve alarm.
- Footer: Sending needs an explicit “yes”, “confirm” or “send”. / Göndermek açık bir “evet”, “onaylıyorum” ya da
  “gönder” ister.
- Narration: Anything Bilge can't undo waits for your yes. / Geri alınamayan her iş, senin evetini bekler.

### 3. Answer

- Kicker / headline: ON WINDOWS · It answers out loud. / WINDOWS'TA · Sesli cevap verir.
- You: Bilge, what's the weather like tomorrow? / Bilge, yarın hava nasıl olacak? (loop, social)
- Bilge (social): Tomorrow in London: partly cloudy, 14 to 19 degrees, a light chance of rain in the evening. /
  Yarın İstanbul'da parçalı bulutlu, sıcaklık 14 ile 19 derece arasında; akşam hafif yağmur ihtimali var.
- Note under the window: Cut in any time: “Bilge, stop.” / Sözünü kesmek için: “Bilge, dur.”

### 4. Made for Turkish

- Kicker / headline: MADE FOR TURKISH · Knows what Türkiye asks. / TÜRKÇE İÇİN YAPILDI · Türkiye'de sorulanı bilir.
- Cards: “when is maghrib” Prayer times · “recent earthquakes” AFAD · Kandilli · “when does Beşiktaş play” Süper Lig ·
  “BIST 100” Borsa İstanbul / “akşam ezanı ne zaman” Namaz vakitleri · “son depremler” AFAD · Kandilli ·
  “Beşiktaş ne zaman oynuyor” Süper Lig · “BIST 100” Borsa İstanbul.
- Narration (social): Made for Turkish: prayer times, earthquake alerts from AFAD, Süper Lig and Borsa
  İstanbul. / Türkçe için yapıldı: namaz vakitleri, AFAD deprem uyarıları, Süper Lig ve Borsa İstanbul.

### 5. Private by default

- Kicker / headline: PRIVATE BY DEFAULT · It can run entirely on your computer. / VARSAYILAN OLARAK GİZLİ · Tamamen
  bilgisayarında çalışabilir.
- Cards: Speech recognition · Language model · Voice, each “on your computer” / Konuşma tanıma · Dil modeli · Ses,
  each “bilgisayarında”.
- Footer: No account · No subscription · No recording kept / Hesap yok · Abonelik yok · Ses kaydı saklanmaz.
- Narration (social): Speech recognition, the language model and the voice can all run on your computer. /
  Konuşma tanıma, dil modeli ve ses tamamen bilgisayarında çalışabilir.

### 6. Three systems

- Kicker / headline: MAC · WINDOWS · LINUX · One assistant, three systems. / Üç sistemde aynı asistan.
- Labels under the setup windows: Mac · Windows and Linux / Mac · Windows ve Linux.
- Narration (social): Free and open source, for Mac, Windows and Linux. / Ücretsiz ve açık kaynak; Mac,
  Windows ve Linux için.

### 7. End card

- Logo, “Bilge”, A Turkish & English voice assistant / Türkçe ve İngilizce konuşan sesli asistan.
- Button: Download / İndir · github.com/coderssociety/bilge-assistant/releases/latest
- Line: Free · Open source · Mac, Windows, Linux / Ücretsiz · Açık kaynak · Mac, Windows, Linux

## Poster

Logo and name with the tagline, the spoken command with “Bilge,” in the accent colour, the real confirmation window,
and two chips: Free · Open source / Ücretsiz · Açık kaynak and Mac · Windows · Linux.

## Production

Frames are HTML/CSS scenes driven by a time parameter, rendered at 30 fps by headless Chrome over the DevTools
protocol and encoded with ffmpeg (H.264, yuv420p, `+faststart`; AAC 160 kb/s for the social cuts; GIF at 15 fps
with a 160-colour palette). The social timeline is built from the measured length of each voice clip, so captions,
the window entrances and the speech stay in sync.
