import Foundation

/// Trimmed responses saved from the live sources on 25 October 2026.
enum GoldFixtures {
    static let truncgil = Data(#"""
    {"Update_Date":"2026-10-25 19:45:03","USD":{"Alış":"49,6090","Tür":"Döviz","Satış":"49,7746","Değişim":"%0,08"},"ons":{"Alış":"$3.995,89","Tür":"Altın","Satış":"$3.996,40","Değişim":"%-0,71"},"gram-altin":{"Alış":"6.383,95","Tür":"Altın","Satış":"6.384,76","Değişim":"%-0,62"},"ceyrek-altin":{"Alış":"10.322,22","Tür":"Altın","Satış":"10.560,44","Değişim":"%-0,55"},"cumhuriyet-altini":{"Alış":"42.823,00","Tür":"Altın","Satış":"43.484,00","Değişim":"%-0,48"},"22-ayar-bilezik":{"Alış":"5.883,67","Tür":"Altın","Satış":"5.890,59","Değişim":"%-0,55"}}
    """#.utf8)

    static let truncgilV4 = Data(#"""
    {"Update_Date":"2026-10-25 19:59:01","gram-altin":{"Buying":6383.95,"Type":"Gold","Selling":6384.76,"Change":-0.62},"yarim-altin":{"Buying":"bozuk","Selling":21120.88}}
    """#.utf8)

    static let altinkaynak = Data(#"""
    [{"Id":24,"Alis":"80,72","Satis":"88,83","Kod":"AG","MobilAciklama":"Has Gümüş","GuncellenmeZamani":"25.10.2026 19:59:37"},{"Id":35,"Alis":"6.399","Satis":"6.510","Kod":"GA","MobilAciklama":"Gram Altın","GuncellenmeZamani":"25.10.2026 19:59:37"},{"Id":28,"Alis":"10.331","Satis":"10.645","Kod":"C","MobilAciklama":"Çeyrek","GuncellenmeZamani":"25.10.2026 19:59:37"},{"Id":23,"Alis":"42.246","Satis":"43.295","Kod":"A_T","MobilAciklama":"Ata Cumhuriyet","GuncellenmeZamani":"25.10.2026 19:59:37"},{"Id":60,"Alis":"100","Satis":"197","Kod":"I_C","MobilAciklama":"Çeyrek","GuncellenmeZamani":"25.10.2026 19:59:37"}]
    """#.utf8)

    static let goldAPI = Data(#"""
    {"currency":"USD","currencySymbol":"$","exchangeRate":1.0,"name":"Gold","price":3996.899902,"symbol":"XAU","updatedAt":"2026-10-25T16:59:39Z"}
    """#.utf8)
}
