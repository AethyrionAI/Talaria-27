import SwiftUI

struct PermissionsScreen: View {
    @Environment(PermissionsStore.self) private var permissionsStore

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    headerText

                    ForEach(permissionsStore.capabilities) { capability in
                        PermissionCard(capability: capability) {
                            Task { await permissionsStore.requestPermission(for: capability.permissionType) }
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle("Permissions")
        .task { await permissionsStore.reloadCapabilities() }
    }

    private var headerText: some View {
        Text("Hermes works best with your permission. You control what data Hermes can access.")
            .font(Design.Typography.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Design.Spacing.xxs)
    }

}
