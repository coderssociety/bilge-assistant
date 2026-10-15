# Bilge

Mac için tamamen yerel çalışan Türkçe ve İngilizce sesli asistan. “Bilge” dediğinde uyanır, komutunu
anlar, Mac'te işi yapar ve sesle cevap verir. Sesin ve komutların Mac'inden dışarı çıkmaz; internet
yalnızca hava durumu, döviz, haber gibi veriler ve modellerin ilk indirmesi için kullanılır.

*A fully local voice assistant for macOS that speaks Turkish and English. Speech recognition,
language models and speech synthesis all run on the Mac. See [English](#english) below.*

## Neler yapar

- **Mac komutları:** uygulama açma/kapatma, ses düzeyi, müzik, ekran görüntüsü, Wi-Fi, karanlık mod,
  Kestirmeler, dosya bulma ve açma, Çöp Kutusu'na taşıma.
- **Takvim ve anımsatıcılar:** sorma, ekleme, tamamlama; yaklaşan etkinlikleri kendiliğinden hatırlatma.
- **İletişim:** kişi bulma, Mail ve Mesajlar ile gönderme (gönderme her zaman açık bir “evet” ister).
- **Excel:** “D3'e B2 ile B1'i topla”, “B sütununun toplamı kaç”, “geri al”.
- **Bağlam:** seçili metin, Finder'da seçili dosya ya da açık sayfa için “bunu özetle”, “bunu Ahmet'e gönder”.
- **Tarayıcı:** sekmeler arasında geçme, geri/ileri, kaydırma, sayfada arama.
- **Dikte:** öndeki uygulamaya sesle yazma; “virgül”, “yeni satır”, “son cümleyi sil”.
- **Günlük özet:** hava, bugünkü etkinlikler, anımsatıcılar, okunmamış e-postalar.
- **Hafıza:** “bunu hatırla”, “unut”; hatırladıklarını Ayarlar'da görürsün.
- **Ses kimliği:** sesini tanıtırsan yalnızca senin komutlarına ve onaylarına uyar.

Silme, gönderme ve ekleme gibi geri alınamayan işlerde her zaman önce sesli onay ister.

## Gereksinimler

- Apple Silicon Mac, **macOS 27** veya üstü.
- **Apple Intelligence açık olmalı.** Komutları Apple'ın cihaz içi dil modeli anlar; bu model
  olmadan Bilge çalışmaz.
- İlk kurulumda ses modelleri için küçük bir indirme (Whisper tanımayı seçersen ayrıca 1,5 GB).
  İsteğe bağlı sohbet modeli için 16–19 GB indirme ve en az 32 GB bellek.

## Kurulum

1. [Releases](../../releases) sayfasından son `Bilge-<sürüm>.dmg` dosyasını indir, Bilge'yi
   Uygulamalar klasörüne sürükle.
2. Açınca kurulum sihirbazı gereken izinleri (mikrofon, konuşma tanıma, Erişilebilirlik ve
   istersen takvim, kişiler) ister, ses modellerini hazırlar ve sohbet modelini seçtirir.
3. “Bilge, saat kaç?” diyerek dene.

> Sürümler henüz Apple tarafından onaylanmış (notarize) değil. İlk açılışta macOS uyarı verirse
> Sistem Ayarları > Gizlilik ve Güvenlik'te “Yine de Aç”a bas. İstersen kaynaktan kendin derleyebilirsin.

Bilge menü çubuğunda çalışır; Dock'ta simgesi görünmez.

## Modeller

Komutları **her zaman** Apple'ın cihaz içi modeli yönlendirir: hızlıdır ve testlerde komutların
hepsini doğru araca gönderdi. Sohbet, genel bilgi soruları ve ekran özetleri için istersen daha
bilgili bir model indirebilirsin. Bilge bu modeli **kendi içinde, MLX ile** çalıştırır; LM Studio
gibi ayrı bir program gerekmez. Model “Bilge” dediğinde yüklenir, konuşma bitince bellekten çıkar
(bu süre ayarlanabilir).

| Seçenek | İndirme | En az bellek | Not |
|---|---|---|---|
| Apple cihaz içi model | yok | – | Bütün komutlar, kısa sohbet. Genel bilgide daha sık yanılır, birbirine bağlı çok adımlı işleri planlayamaz. |
| Qwen3.6 27B (4-bit) | 16,1 GB | 32 GB | Qwen 3.8'in bir önceki sürümü. |
| Qwen3.8 27B (4-bit) | 16,1 GB | 32 GB | 20 Türkçe genel bilgi sorusunun 19'unu bildi (aynı konuşma içinde 20/20); ilk kelime ~2,2 sn. |
| Gemma 4 31B (4-bit) | 18,4 GB | 32 GB | Aynı testte 19/20 (vMLX ile ölçüldü); ilk kelimeye çabuk başlar. |

Ölçümler M5 Pro, 48 GB bellekte yapıldı. Qwen3.8 ölçümü aynı modelin bir topluluk türeviyle
Bilge'nin içinde, Gemma ölçümü başka bir 4-bit sürümüyle vMLX'te yapıldı. Apple modeli aynı testte 14/20 bildi.

### Kendi modelin

Listede olmayan bir modeli de kullanabilirsin. Hugging Face'ten MLX biçiminde bir model indir
(örneğin [mlx-community](https://huggingface.co/mlx-community)) ve klasörünü şuraya koy:

```
~/Library/Application Support/Asistan/Models/Kendi Modellerim/<model adı>/
```

Klasörde `config.json`, `tokenizer.json` (ya da `tokenizer.model`) ve `.safetensors` dosyaları
olmalı. Ayarlar > Model'deki “Klasörü aç” düğmesi bu klasörü Finder'da açar, “Yenile” listeyi
günceller. Modeli kopyalamak yerine başka yerdeki klasörüne (örneğin LM Studio'nunkine) bir
kısayol (sembolik bağ) da koyabilirsin. Bilge'nin MLX sürümünün desteklemediği bir model türü
açılamazsa o cevabı Apple modeli verir.

Listedeki modeller Hugging Face'ten, belirli bir sürüme sabitlenerek indirilir ve büyük dosyalar
SHA-256 ile doğrulanır. Uzun talimatlar ve araç listesi bir kez okunup saklandığı için çok adımlı
işlerde her adım birkaç saniye sürer. LM Studio ya da vMLX kullanıyorsan oradaki modelleri de Ayarlar > Model'den seçebilirsin.

## Dil

Kurulumun ilk adımında Türkçe ya da İngilizce seçilir; Ayarlar > Genel'den değiştirilebilir (uygulama
yeniden başlar). Bilge seçilen dilde dinler, konuşur ve menülerini gösterir. Komutlar, Excel, dikte,
tarayıcı, hafıza ve günlük özet iki dilde de çalışır. İngilizcede:

- Konuşma tanıma varsayılan olarak Whisper'dır (1,5 GB indirme). Apple Dikte İngilizce modunda Türkçe
  söylenen “Bilge” adını neredeyse hiç tanımadı; Whisper 20 denemenin 17'sinde tanıdı.
- Haberler BBC News'ten okunur; döviz sorularında hedef söylenmezse dolar alınır.
- Bilge konuşurken araya girmek (“Bilge, stop”) Türkçedekinden daha az güvenilirdir: Whisper, Bilge'nin
  kendi sesinin yankısı arasında uyandırma kelimesini daha sık kaçırır.

## Gizlilik

- Ses kaydı saklanmaz. Uyandırma kelimesinden öncesi dinlenmez.
- Konuşma tanıma, dil modelleri ve ses üretimi Mac'te çalışır.
- Ağ bağlantıları yalnızca istediğin veriler (hava durumu, döviz, haber, web sayfası) ve model
  indirmeleri içindir. Web sayfası okurken yerel ağ adreslerine erişim engellenir.
- Hafıza, ses kimliği ve işlem kaydı `~/Library/Application Support/Asistan` altında, yalnızca senin
  okuyabileceğin dosyalarda durur.

## Kaynaktan derleme

Gerekenler: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) ve Xcode'un Metal araçları.

```bash
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
xcodegen generate
open Asistan.xcodeproj
```

İzinlerin her derlemede sıfırlanmaması için Apple ID'nle imzala: `Config/Signing.local.xcconfig`
dosyasını oluşturup içine `DEVELOPMENT_TEAM = <takım kimliğin>` yaz (bu dosya git'e girmez).

Testler:

```bash
cd Packages/AsistanKit && swift test
```

Dağıtım paketi (`build/release/Bilge-<sürüm>.dmg`):

```bash
scripts/release.sh
```

Developer ID sertifikası varsa uygulama dağıtım için imzalanır; `NOTARY_PROFILE` ortam değişkeni
`xcrun notarytool store-credentials` ile kaydedilmiş bir profili gösteriyorsa Apple onayından da
geçirilir. Sertifika yoksa DMG yalnızca geliştirme imzalıdır.

## Lisans

Bilge [GNU GPL 3.0](LICENSE) ile dağıtılır. Kullandığı açık kaynak bileşenler ve modeller,
lisanslarıyla birlikte [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) dosyasında listelenir;
aynı liste uygulamada Ayarlar > Hakkında'da da görünür. Özellikle:

- Ses algılama, Türkçe ses üretimi, yankı giderme ve ses kimliği [FluidAudio](https://github.com/FluidInference/FluidAudio)
  (Apache 2.0) ile yapılır.
- Konuşma tanıma [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (MIT) ya da Apple Dikte ile yapılır.
- Sohbet modelleri [MLX Swift](https://github.com/ml-explore/mlx-swift) ve
  [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (MIT) ile çalışır.
- Türkçe ses [Supertonic-3](https://huggingface.co/Supertone/supertonic-3) modelidir (OpenRAIL-M);
  kullanım kısıtları bildirim dosyasında yazılıdır.

## English

Bilge is a local voice assistant for the Mac. Choose English in the first setup step (or later in
Settings > General); Bilge then listens, speaks and shows its menus in English. Say “Bilge” (as it is
pronounced in Turkish: *BIL-geh*) followed by a command: “Bilge, what time is it?”, “Bilge, put the sum of
B1 and B2 into D3”, “Bilge, summarize this”, “Bilge, start dictation”.

- Requirements: Apple Silicon, macOS 27, Apple Intelligence turned on.
- Speech recognition in English defaults to Whisper (about 1.5 GB download).
- Optional larger conversation models (Qwen 3.6/3.8 27B, Gemma 4 31B) run inside the app with MLX, or
  drop your own MLX model into `~/Library/Application Support/Asistan/Models/Kendi Modellerim/`.
- Everything stays on your Mac; the internet is used only for weather, exchange rates, news, web pages you
  ask for, and model downloads.
- Licensed under GPL-3.0; third-party notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
