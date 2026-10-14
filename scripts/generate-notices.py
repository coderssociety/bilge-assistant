#!/usr/bin/env python3
"""Writes THIRD_PARTY_NOTICES.md from the resolved Swift packages and the models Bilge downloads.

Run after `xcodebuild -resolvePackageDependencies -derivedDataPath build` whenever a dependency changes:
    python3 -I scripts/generate-notices.py
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECKOUTS = ROOT / "build/SourcePackages/checkouts"
RESOLVED = ROOT / "Asistan.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
OUTPUT = ROOT / "THIRD_PARTY_NOTICES.md"

# Build-time only (macro plug-ins); nothing from them ships inside Bilge.app.
BUILD_ONLY = {"swift-syntax"}

# Third-party code that packages carry inside them, with its own terms.
EMBEDDED = {
    "mlx-swift": ["ACKNOWLEDGMENTS.md"],
    "argmax-oss-swift": ["NOTICES"],
    "swift-crypto": ["NOTICE.txt"],
    "swift-asn1": ["NOTICE.txt"],
    "FluidAudio": ["ThirdPartyLicenses"],
}

MODELS = """\
## Çalışırken indirilen modeller

Bilge bu modelleri ilk kullanımda Hugging Face'ten indirir; uygulamanın içinde gelmezler.

| Model | Kaynak | Lisans |
|---|---|---|
| Supertonic-3 Türkçe ses (TTS) | [Supertone/supertonic-3](https://huggingface.co/Supertone/supertonic-3), Core ML dönüşümü [FluidInference/supertonic-3-coreml](https://huggingface.co/FluidInference/supertonic-3-coreml) | BigScience OpenRAIL-M (metni aşağıda) |
| Silero VAD (konuşma algılama) | [snakers4/silero-vad](https://github.com/snakers4/silero-vad), [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml) | MIT |
| LocalVQE (yankı giderme) | [LocalAI-io/LocalVQE](https://huggingface.co/LocalAI-io/LocalVQE), [FluidInference/localvqe-coreml](https://huggingface.co/FluidInference/localvqe-coreml) | Apache 2.0 |
| CAM++ (ses kimliği) | Alibaba DAMO Academy, FunASR / 3D-Speaker: ModelScope `iic/speech_campplus_sv_zh-cn_16k-common`; [FluidInference/campplus-coreml](https://huggingface.co/FluidInference/campplus-coreml) | FunASR Model License 1.1 (metni aşağıda) |
| Whisper large-v3 turbo (konuşma tanıma, isteğe bağlı) | OpenAI, [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) | MIT |
| Sohbet modelleri (isteğe bağlı) | Kurulumda seçilen [mlx-community](https://huggingface.co/mlx-community) modeli: Qwen (Alibaba Cloud), Gemma (Google) | Apache 2.0 |

### Supertonic-3 kullanım kısıtları

Supertonic-3 sesi OpenRAIL-M lisansıyla kullanılır. Lisansın 5. maddesi gereği Bilge'yi kullanan herkes
Ek A'daki kullanım kısıtlarına uymayı kabul eder. Bu kısıtlar, aşağıdaki lisans metninde eksiksiz yer alır.
Özetle model; yasalara aykırı biçimde, çocuklara zarar vermek için, başkalarına zarar vermek amacıyla yanlış
bilgi ya da kişisel veri üretip yaymak için, makine tarafından üretildiği açıkça belirtilmeden içerik yaymak
için, başkalarını karalamak, taciz etmek ya da rızaları olmadan taklit etmek için, ayrımcılık için, tıbbi
tavsiye vermek için ve lisansta sayılan diğer amaçlar için kullanılamaz.
"""


def versions():
    pins = json.loads(RESOLVED.read_text())["pins"]
    return {pin["location"].rstrip("/").removesuffix(".git").rsplit("/", 1)[-1]: (pin["location"], pin["state"].get("version", "?"))
            for pin in pins}


def license_file(folder):
    for name in sorted(p.name for p in folder.iterdir()):
        if re.match(r"(?i)^licen[cs]e", name):
            return folder / name
    sys.exit(f"{folder.name}: lisans dosyası yok")


def kind(text):
    if "Apache License" in text and "Version 2.0" in text:
        return "Apache 2.0"
    if "Permission is hereby granted, free of charge" in text:
        return "MIT"
    if "Redistribution and use in source and binary forms" in text:
        return "BSD"
    sys.exit("tanınmayan lisans")


def runtime_exception(text):
    match = re.search(r"(?s)(#+\s*)?Runtime Library Exception.*", text)
    return match.group(0).strip() if match else None


def embedded_notices(folder, names):
    parts = []
    for name in names:
        path = folder / name
        files = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
        for file in files:
            parts.append(f"#### {file.relative_to(folder)}\n\n```\n{file.read_text(errors='replace').strip()}\n```\n")
    return parts


def main():
    pins = versions()
    sections, rows, apache_text = [], [], None
    for folder in sorted(CHECKOUTS.iterdir(), key=lambda p: p.name.lower()):
        if not folder.is_dir() or folder.name in BUILD_ONLY:
            continue
        url, version = pins.get(folder.name, (f"https://github.com/{folder.name}", "?"))
        text = license_file(folder).read_text(errors="replace").strip()
        name = kind(text)
        rows.append(f"| [{folder.name}]({url.removesuffix('.git')}) | {version} | {name} |")
        body = [f"### {folder.name} {version}\n\n{url.removesuffix('.git')}\n"]
        if name == "Apache 2.0":
            apache_text = apache_text or text.split("END OF TERMS AND CONDITIONS")[0].strip()
            body.append("Apache 2.0 lisansıyla dağıtılır; tam metin dosyanın sonunda.\n")
            exception = runtime_exception(text)
            if exception:
                body.append(f"```\n{exception}\n```\n")
        else:
            body.append(f"```\n{text}\n```\n")
        body += embedded_notices(folder, EMBEDDED.get(folder.name, []))
        sections.append("\n".join(body))

    licenses = ROOT / "licenses"
    out = [
        "# Üçüncü taraf bildirimleri\n",
        "Bilge GNU GPL 3.0 ile dağıtılır (LICENSE). Aşağıdaki açık kaynak bileşenleri ve modelleri kullanır;",
        "her biri kendi lisansıyla dağıtılır. Bu dosya `scripts/generate-notices.py` ile üretilir.\n",
        "## Swift paketleri\n",
        "| Paket | Sürüm | Lisans |", "|---|---|---|", *rows, "",
        *sections,
        MODELS,
        "## Lisans metinleri\n",
        f"### BigScience OpenRAIL-M (Supertonic-3)\n\n```\n{(licenses / 'Supertonic-3-OpenRAIL-M.txt').read_text().strip()}\n```\n",
        f"### FunASR Model License 1.1 (CAM++)\n\n```\n{(licenses / 'FunASR-Model-License-1.1.txt').read_text().strip()}\n```\n",
        f"### Apache License 2.0\n\n```\n{apache_text}\n```\n",
    ]
    OUTPUT.write_text("\n".join(out))
    print(f"{OUTPUT.name}: {len(rows)} paket, {OUTPUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
