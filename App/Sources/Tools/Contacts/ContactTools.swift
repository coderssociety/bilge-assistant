import AsistanCore
import Contacts
import FoundationModels

struct ContactSummary: Sendable {
    let name: String
    let phones: [String]
    let emails: [String]
}

enum ContactsAccessError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Kişilere erişim izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Kişiler'den Bilge'ye izin ver."
    }
}

/// CNContact is not Sendable, so only value summaries leave this actor.
actor ContactsAccess {
    static let shared = ContactsAccess()
    private let store = CNContactStore()

    func find(_ query: String) async throws -> ContactSummary? {
        try await requireAccess()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var contacts: [ContactSummary] = []
        var names: [String] = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let name = full.isEmpty ? contact.organizationName : full
            guard !name.isEmpty else { return }
            let summary = ContactSummary(name: name,
                                         phones: contact.phoneNumbers.map(\.value.stringValue),
                                         emails: contact.emailAddresses.map { $0.value as String })
            contacts.append(summary)
            names.append(name)
            if !contact.nickname.isEmpty {
                contacts.append(summary)
                names.append(contact.nickname)
            }
        }
        guard let match = PhraseMatcher.bestMatch(for: query, in: names),
              let index = names.firstIndex(of: match)
        else { return nil }
        return contacts[index]
    }

    private func requireAccess() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return
        case .notDetermined:
            guard try await store.requestAccess(for: .contacts) else { throw ContactsAccessError.denied }
        default:
            throw ContactsAccessError.denied
        }
    }
}

struct FindContactTool: AssistantTool {
    let name = "findContact"
    let description = "Kişiler'de birinin telefon numarasını ya da e-posta adresini bulup söyler."

    @Generable
    enum Detail {
        case phone, email, both
    }

    @Generable
    struct Arguments {
        @Guide(description: "Kişinin adı, eksiz: 'Ahmet'in' → 'Ahmet'")
        var name: String
        @Guide(description: "İstenen bilgi; belirtilmediyse both")
        var detail: Detail
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            guard let contact = try await ContactsAccess.shared.find(arguments.name) else {
                return ToolReply.failure("Kişilerinde '\(arguments.name)' adında birini bulamadım.")
            }
            var parts: [String] = []
            if arguments.detail != .email {
                parts.append(contact.phones.first.map { "telefonu \($0)" } ?? "kayıtlı telefonu yok")
            }
            if arguments.detail != .phone {
                parts.append(contact.emails.first.map { "e-postası \($0)" } ?? "kayıtlı e-postası yok")
            }
            return "\(contact.name): \(parts.joined(separator: ", "))."
        } catch {
            return ToolReply.failure(error)
        }
    }
}
