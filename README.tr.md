<p align="center">
  <img src="mac/docs/images/logo.svg" width="128" height="128" alt="Bilge logosu">
</p>

<h1 align="center">Bilge</h1>

<p align="center">
  Mac, Windows ve Linux için Türkçe ve İngilizce konuşan sesli asistan.
</p>

<p align="center">
  <a href="https://github.com/coderssociety/bilge-assistant/releases/latest"><img src="https://img.shields.io/github/v/release/coderssociety/bilge-assistant?label=%C4%B0ndir&style=for-the-badge&color=2A2E7A" alt="Bilge'yi indir"></a>
  <br>
  <sub>Ücretsiz ve açık kaynak · Mac, Windows ve Linux · hesap ve abonelik yok</sub>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/lisans-GPL--3.0-blue" alt="Lisans: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-black?logo=apple" alt="macOS 27+">
  <img src="https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/Linux-AppImage-FCC624?logo=linux&logoColor=black" alt="Linux AppImage">
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Türkçe</b>
</p>

<p align="center">
  <img src="mac/docs/images/hud-confirm.png" width="760" alt="Bilge takvime etkinlik eklemeden önce onay istiyor">
</p>

“Bilge” de, isteğini söyle; işi bilgisayarında yapar ve sesle cevap verir: takvim, e-posta, mesajlar, dosyalar,
belgeler, müzik, tarayıcı ve akıllı ev. Geri alınamayan her iş sesli bir “evet” bekler.

## İndir

Her sürümde üçü de var, [Sürümler](https://github.com/coderssociety/bilge-assistant/releases/latest) sayfasında:

| Sistem | Dosya | Gerekenler |
|---|---|---|
| **Mac** | `Bilge-<sürüm>.dmg` | Apple Silicon'lı Mac'te macOS 27 ve sonrası, Apple Intelligence açık |
| **Windows** | `Bilge-Setup-<sürüm>.exe` | Windows 10 ya da 11, 64 bit; yönetici izni olmadan senin kullanıcın için kurulur |
| **Linux** | `Bilge-<sürüm>-x86_64.AppImage`, `Bilge-<sürüm>-aarch64.AppImage` | glibc 2.34+ (Ubuntu 22.04, Debian 12, Fedora 36 ve sonrası); arm64 için 2.39+ |

**Hemen başla:** sistemine uygun dosyayı indir, aç, dili seç ve “Bilge, saat kaç?” de. Yeni sürümler uygulamanın
içinde sunulur: “Güncelle ve yeniden başlat” kurar.

`SHA256SUMS` dosyası sağlama toplamlarını içerir. Paketler henüz imzalı olmadığından macOS ve Windows ilk açılışta
uyarır; nasıl açılacağı her uygulamanın sayfasında yazılı.

## Neden Bilge?

- **Türkçe için yapıldı.** Günlük Türkçe konuşmayı anlar ve Türkiye'de sorulanı bilir: namaz vakitleri, AFAD deprem
  uyarıları, Süper Lig, Borsa İstanbul, altın ve akaryakıt fiyatları. İngilizce de konuşur.
- **Varsayılan olarak gizli.** Konuşma tanıma, dil modeli ve ses tamamen bilgisayarında çalışabilir. Hesap ve abonelik
  yok, ses kaydı saklanmaz.
- **Beyni sen seç.** Bilgisayarındaki bir model (Mac'te MLX; Ollama, LM Studio ya da llama.cpp) ya da kendi
  anahtarınla bir API (OpenAI, Anthropic, Google Gemini, OpenRouter, Groq, DeepSeek).
- **Güvenli tasarım.** Gönderme, silme, kapatma ve evdeki kilitler önce sorar; bir web sayfasından ya da e-postadan
  okunan metin kendi başına hiçbir şey gönderemez.

## İki uygulama

Mac uygulaması Apple'ın kendi parçalarıyla (cihaz içi dil modeli, dikte, MLX) yapıldı; Windows ve Linux uygulaması
aynı asistanın Python ile yeniden yazılmış hâli. Aynı kurallara uyarlar ve aynı Türkçe ve İngilizce komut setlerini
paylaşırlar.

| | Mac | Windows ve Linux |
|---|---|---|
| Yapabildiği her şey, ayarlar, gizlilik | [mac/README.tr.md](mac/README.tr.md) | [desktop/README.tr.md](desktop/README.tr.md) |
| Kaynak kod | [`mac/`](mac) (Swift 6, Xcode) | [`desktop/`](desktop) (Python 3.14, uv) |

## Depo yapısı

| Klasör | İçerik |
|---|---|
| `mac/` | Mac uygulaması ve test edilen çekirdek paketi (`mac/Packages/AsistanKit`) |
| `desktop/` | Windows ve Linux uygulaması, testleri ve kurulum paketleri |
| `bench/` | İki uygulamanın da ölçüldüğü konuşma tanıma, yönlendirme ve uçtan uca komut setleri |

Sürümler `.github/workflows/release.yml` ile bir `v*` etiketinden üretilir: DMG macOS'ta, kurulum Windows'ta,
AppImage'lar Docker'da derlenir ve tek bir taslak sürümde birlikte yayımlanır. Kaynaktan derlemeyi her uygulamanın
README'si anlatır.

## Lisans

GPL-3.0, bkz. [LICENSE](LICENSE). Her uygulama kullandığı açık kaynak bileşenleri ve modelleri listeler.
