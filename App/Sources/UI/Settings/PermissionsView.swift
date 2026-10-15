import SwiftUI

struct PermissionsView: View {
    /// Re-read periodically: grants made in System Settings arrive without any notification.
    private static let refreshInterval = Duration.seconds(2)
    @State private var refreshToken = 0

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(permission: permission, refreshToken: refreshToken) {
                        refreshToken += 1
                    }
                }
            } footer: {
                Text("İzinler yalnızca istediğin işler için kullanılır. Bir izni geri almak için Sistem Ayarları > Gizlilik ve Güvenlik.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                refreshToken += 1
            }
        }
    }
}

struct PermissionRow: View {
    let permission: Permission
    let refreshToken: Int
    let onChange: () -> Void

    var body: some View {
        let state = permission.state
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.tint)
                .font(.title3)
                .accessibilityLabel(state.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title + (permission.isRequired ? " *" : ""))
                Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .notAsked:
                Button("İzin ver") {
                    Task {
                        await permission.request()
                        onChange()
                    }
                }
            case .denied, .askedOnUse:
                Button("Ayarları aç") { permission.openSystemSettings() }
            case .granted:
                EmptyView()
            }
        }
        .id(refreshToken)
    }
}

private extension Permission.State {
    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.octagon.fill"
        case .notAsked: "circle.dashed"
        case .askedOnUse: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .granted: .green
        case .denied: .red
        case .notAsked: .secondary
        case .askedOnUse: .blue
        }
    }

    var label: String {
        switch self {
        case .granted: String(localized: "İzin verildi")
        case .denied: String(localized: "İzin reddedildi")
        case .notAsked: String(localized: "Henüz sorulmadı")
        case .askedOnUse: String(localized: "Kullanımda sorulur")
        }
    }
}
