import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

private let shareLog = Logger(subsystem: "org.aethyrion.talaria", category: "TalariaShare")

/// #123 — the TalariaShare principal controller. Loads the shared items,
/// hosts the SwiftUI sheet, and hands the completion callbacks down. The
/// extension NEVER touches the network: "Send to Talaria" serializes one
/// `ShareEnvelope` into the app-group `SharedInbox/` and completes; the app
/// stages it into the composer on next foreground.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var model: ShareSheetModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = ShareSheetModel(
            onComplete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )
        self.model = model

        let host = UIHostingController(rootView: ShareSheetView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        Task { await model.load(from: providers) }
    }
}

// MARK: - Model

@MainActor
@Observable
final class ShareSheetModel {
    enum Phase: Equatable {
        case loading
        case ready
        case sending
        case failed(String)
    }

    struct LoadedItem: Identifiable {
        enum Payload {
            case webURL(String)
            case text(String)
            case fileBlob(fileName: String, data: Data)
            case refused(name: String, reason: String)
        }

        let id = UUID()
        var payload: Payload

        var isSendable: Bool {
            if case .refused = payload { return false }
            return true
        }

        var symbolName: String {
            switch payload {
            case .webURL: "link"
            case .text: "text.alignleft"
            case .fileBlob(let fileName, _):
                StageableTypeCatalog.mimeType(
                    forFileExtension: (fileName as NSString).pathExtension
                ).hasPrefix("image/") ? "photo" : "doc"
            case .refused: "xmark.octagon"
            }
        }

        var title: String {
            switch payload {
            case .webURL(let url): url
            case .text(let body): body
            case .fileBlob(let fileName, _): fileName
            case .refused(let name, _): name
            }
        }

        var detail: String? {
            switch payload {
            case .webURL, .text: nil
            case .fileBlob(_, let data): Self.byteLabel(data.count)
            case .refused(_, let reason): reason
            }
        }

        static func byteLabel(_ count: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        }
    }

    private(set) var phase: Phase = .loading
    private(set) var items: [LoadedItem] = []
    var note = ""

    private let onComplete: () -> Void
    private let onCancel: () -> Void
    /// Injectable for a hosted-app smoke run; the real sheet writes to the
    /// app-group store.
    private let store: SharedInboxStore?

    init(
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        store: SharedInboxStore? = SharedInboxStore.appGroup()
    ) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.store = store
    }

    var canSend: Bool {
        phase == .ready && items.contains(where: \.isSendable)
    }

    // MARK: Loading

    /// Activation-rule ceilings (1 URL / 4 images / 1 file / text) keep this
    /// list tiny; the prefix is a defensive cap, not a policy.
    func load(from providers: [NSItemProvider]) async {
        var loaded: [LoadedItem] = []
        var budget = SharedInboxStore.defaultMaxEnvelopeBytes
        for provider in providers.prefix(8) {
            let item = await loadItem(provider, remainingBytes: budget)
            if case .fileBlob(_, let data) = item.payload {
                budget -= data.count
            }
            loaded.append(item)
        }
        items = loaded
        phase = .ready
    }

    private func loadItem(_ provider: NSItemProvider, remainingBytes: Int) async -> LoadedItem {
        let fallbackName = provider.suggestedName ?? "Shared item"

        // Order matters: movies refuse early with an honest reason; file URLs
        // conform to public.url, so the file branch must come before the
        // web-URL branch.
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            return LoadedItem(payload: .refused(
                name: fallbackName,
                reason: "Audio and video can't be sent to Talaria"))
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let (data, name) = await loadBlob(provider, type: .image, fallbackName: fallbackName) {
                return blobItem(fileName: name, data: data, remainingBytes: remainingBytes)
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            if let (data, name) = await loadBlob(provider, type: .pdf, fallbackName: fallbackName) {
                return blobItem(fileName: name, data: data, remainingBytes: remainingBytes)
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadURL(provider), url.isFileURL {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    return blobItem(fileName: url.lastPathComponent, data: data, remainingBytes: remainingBytes)
                }
            }
            return LoadedItem(payload: .refused(name: fallbackName, reason: "Couldn't read this file"))
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(provider) {
                return LoadedItem(payload: .webURL(url.absoluteString))
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let data = await loadDataRepresentation(provider, type: .plainText) {
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
                    ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return LoadedItem(payload: .text(text))
                }
            }
        }

        return LoadedItem(payload: .refused(
            name: fallbackName,
            reason: "Talaria can't accept this type"))
    }

    /// Size + stageability gate for every file payload — refusals here are
    /// the honest counterpart of what the app's staging path would reject at
    /// drain time.
    private func blobItem(fileName: String, data: Data, remainingBytes: Int) -> LoadedItem {
        guard StageableTypeCatalog.isStageable(fileName: fileName) else {
            return LoadedItem(payload: .refused(
                name: fileName,
                reason: "Talaria can't accept this file type"))
        }
        guard data.count <= remainingBytes else {
            return LoadedItem(payload: .refused(
                name: fileName,
                reason: "Too large to hand off (limit \(LoadedItem.byteLabel(SharedInboxStore.defaultMaxEnvelopeBytes)))"))
        }
        return LoadedItem(payload: .fileBlob(fileName: fileName, data: data))
    }

    private func loadBlob(
        _ provider: NSItemProvider,
        type: UTType,
        fallbackName: String
    ) async -> (Data, String)? {
        // File representation first (Photos/Files hand a temp copy; the name
        // is real), data representation as fallback for in-memory providers.
        let fromFile: (Data, String)? = await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                // The temp copy only lives for this handler — read it here.
                guard let url, let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data, url.lastPathComponent))
            }
        }
        if let fromFile { return fromFile }
        guard let data = await loadDataRepresentation(provider, type: type) else { return nil }
        return (data, fallbackName)
    }

    private func loadDataRepresentation(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: Actions

    func send() {
        guard canSend, let store else {
            if store == nil {
                phase = .failed("App group unavailable — reinstall Talaria")
            }
            return
        }
        phase = .sending

        var envelopeItems: [ShareEnvelope.Item] = []
        var blobs: [String: Data] = [:]
        for (index, item) in items.enumerated() {
            switch item.payload {
            case .webURL(let url):
                envelopeItems.append(.webURL(url))
            case .text(let body):
                envelopeItems.append(.text(body))
            case .fileBlob(let fileName, let data):
                let blobName = "\(index)-\(fileName)"
                blobs[blobName] = data
                envelopeItems.append(.file(blobFileName: blobName, fileName: fileName))
            case .refused:
                continue
            }
        }

        let envelope = ShareEnvelope(
            id: UUID(),
            createdAt: Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            items: envelopeItems
        )
        do {
            try store.write(envelope, blobs: blobs)
            shareLog.notice("TalariaShare: queued envelope with \(envelopeItems.count) item(s)")
            onComplete()
        } catch {
            shareLog.notice("TalariaShare: write failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed("Couldn't queue the share — try again")
        }
    }

    func cancel() {
        onCancel()
    }
}

// MARK: - Sheet UI

/// Minimal, self-contained sheet — the extension can't reach the app's
/// ThemeRuntime, so this is a fixed Deep-Field-flavored skin (dark navy,
/// cyan accent), not a themed surface.
struct ShareSheetView: View {
    @Bindable var model: ShareSheetModel

    private let accent = Color(red: 0x54 / 255.0, green: 0xE6 / 255.0, blue: 0xF0 / 255.0)
    private let background = Color(red: 0x06 / 255.0, green: 0x10 / 255.0, blue: 0x18 / 255.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("SEND TO TALARIA")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(accent)
            Spacer()
            Button {
                model.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .accessibilityLabel("Cancel")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading shared items…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .padding(.vertical, 12)
        case .ready, .sending:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.items) { item in
                    itemRow(item)
                }
                TextField("Add a note (optional)", text: $model.note, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
                    .padding(.top, 6)
            }
        }
    }

    private func itemRow(_ item: ShareSheetModel.LoadedItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbolName)
                .foregroundStyle(item.isSendable ? accent : .orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(2)
                if let detail = item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(item.isSendable ? .secondary : Color.orange)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }

    private var footer: some View {
        Button {
            model.send()
        } label: {
            HStack {
                if model.phase == .sending {
                    ProgressView().tint(.black)
                }
                Text(model.phase == .sending ? "QUEUEING…" : "SEND TO TALARIA")
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .kerning(1.1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(model.canSend ? accent : Color.white.opacity(0.12))
            )
            .foregroundStyle(model.canSend ? .black : .secondary)
        }
        .disabled(!model.canSend)
        .accessibilityLabel("Send to Talaria")
    }
}
