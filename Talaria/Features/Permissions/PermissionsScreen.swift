import SwiftUI

struct PermissionsScreen: View {
    @Environment(PermissionsStore.self) private var permissionsStore

    var body: some View {
        ZStack {
            HUDScreenBackground(gridIntensity: 0.35)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    headerText

                    ForEach(permissionsStore.capabilities) { capability in
                        PermissionCard(capability: capability) {
                            if capability.status == .denied {
                                // iOS won't re-prompt after denial — open Settings instead
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } else {
                                Task { await permissionsStore.requestPermission(for: capability.permissionType) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Permissions")
        .task { await permissionsStore.reloadCapabilities() }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(
                "SENSOR ACCESS",
                size: 10,
                weight: .medium,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )

            Text("Hermes works best with your permission. You control what data Hermes can access.")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
        .padding(.horizontal, Design.Spacing.xxs)
        .padding(.bottom, Design.Spacing.xxs)
    }
}
