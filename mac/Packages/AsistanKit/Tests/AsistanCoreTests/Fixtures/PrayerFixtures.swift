import Foundation

/// Trimmed responses saved from the live sources on 25 October 2026.
enum PrayerFixtures {
    static let diyanetCities = Data(#"""
    [{"SehirAdi":"ADANA","SehirAdiEn":"ADANA","SehirID":"500"},{"SehirAdi":"ANKARA","SehirAdiEn":"ANKARA","SehirID":"506"},{"SehirAdi":"İSTANBUL","SehirAdiEn":"ISTANBUL","SehirID":"539"},{"SehirAdi":"İZMİR","SehirAdiEn":"IZMIR","SehirID":"540"}]
    """#.utf8)

    static let diyanetDistricts = Data(#"""
    [{"IlceAdi":"AKYURT","IlceAdiEn":"AKYURT","IlceID":"9205"},{"IlceAdi":"ANKARA","IlceAdiEn":"ANKARA","IlceID":"9206"},{"IlceAdi":"AYAŞ","IlceAdiEn":"AYAS","IlceID":"9207"}]
    """#.utf8)

    /// Ankara; the third day is malformed and must be skipped.
    static let diyanetMonth = Data(#"""
    [{"HicriTarihKisa":"14.5.1448","MiladiTarihKisa":"25.10.2026","MiladiTarihUzun":"25 Ekim 2026 Pazar","GreenwichOrtalamaZamani":3.0,"Aksam":"18:03","Gunes":"07:02","GunesBatis":"17:56","GunesDogus":"07:09","Ikindi":"15:34","Imsak":"05:39","KibleSaati":"11:27","Ogle":"12:38","Yatsi":"19:22"},
     {"HicriTarihKisa":"15.5.1448","MiladiTarihKisa":"26.10.2026","MiladiTarihUzun":"26 Ekim 2026 Pazartesi","GreenwichOrtalamaZamani":3.0,"Aksam":"18:02","Gunes":"07:03","GunesBatis":"17:55","GunesDogus":"07:10","Ikindi":"15:33","Imsak":"05:40","KibleSaati":"11:27","Ogle":"12:38","Yatsi":"19:20"},
     {"MiladiTarihKisa":"27.10.2026","Aksam":"","Imsak":"05:41"}]
    """#.utf8)

    static let aladhanDay = Data(#"""
    {"code":200,"status":"OK","data":{"timings":{"Fajr":"05:39","Sunrise":"07:02","Dhuhr":"12:38","Asr":"15:35","Sunset":"18:02","Maghrib":"18:02","Isha":"19:21","Imsak":"05:29","Midnight":"00:32"},"date":{"readable":"25 Oct 2026","gregorian":{"date":"25-10-2026"}},"meta":{"timezone":"Europe/Istanbul"}}}
    """#.utf8)
}
