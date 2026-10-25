from bilge.core import ocr_text


def test_recognized_text_keeps_paragraphs_but_drops_layout_noise():
    raw = "  Hata:   dosya\tbulunamadı \n\n\n\n  Tamam  \n \n"
    assert ocr_text.cleaned(raw) == "Hata: dosya bulunamadı\n\nTamam"
    assert ocr_text.cleaned(" \n\n ") == ""


def test_only_installed_tesseract_languages_are_asked_for():
    listing = 'List of available languages in "/usr/share/tesseract-ocr/5/tessdata/" (3):\neng\nosd\ntur\n'
    assert ocr_text.tesseract_languages(listing) == ("tur", "eng")
    assert ocr_text.tesseract_languages("List of available languages (2):\neng\nosd") == ("eng",)
    assert ocr_text.tesseract_languages("List of available languages (1):\nosd") == ()
