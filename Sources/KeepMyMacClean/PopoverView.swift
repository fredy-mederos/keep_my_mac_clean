import CleanerCore
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @State private var listHeight: CGFloat = 0

    /// The list grows with its content up to this height, then scrolls.
    private let maxListHeight: CGFloat = 460

    var body: some View {
        VStack(spacing: 0) {
            DiskHeader()
            Divider()
            content
            Divider()
            FooterBar()
        }
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        if model.categories.isEmpty {
            VStack(spacing: 8) {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Text(model.scanStatus ?? "Scanning…").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(.secondary)
                    Text("Nothing to clean right now").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.categories) { category in
                        CategorySection(category: category)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(max(listHeight, 44), maxListHeight))
            .disabled(model.phase != .idle)
        }
    }
}

// MARK: - Header

private struct DiskHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Macintosh HD").font(.headline)
                Spacer()
                if model.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.rescan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Scan again")
                .disabled(model.isScanning || model.phase != .idle)
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit KeepMyMacClean")
            }
            .buttonStyle(.borderless)

            if let disk = model.disk {
                Text("\(ByteFormat.short(disk.available)) free of \(ByteFormat.short(disk.total))")
                    .font(.subheadline)
                    .foregroundStyle(model.isLowOnSpace ? Color.red : Color.secondary)
                UsageBar(disk: disk, safe: model.total(.safe), review: model.total(.review))
                HStack(spacing: 12) {
                    LegendDot(color: .green, text: "Safe \(ByteFormat.short(model.total(.safe)))")
                    LegendDot(color: .orange, text: "Review \(ByteFormat.short(model.total(.review)))")
                    Spacer()
                    if let lastScan = model.lastScan, !model.isScanning {
                        Text("Scanned \(lastScan, format: .relative(presentation: .named))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

private struct UsageBar: View {
    let disk: DiskSpace
    let safe: Int64
    let review: Int64

    var body: some View {
        GeometryReader { geometry in
            let total = max(Double(disk.total), 1)
            let safeShare = min(Double(safe), Double(disk.used))
            let reviewShare = min(Double(review), Double(disk.used) - safeShare)
            let otherShare = Double(disk.used) - safeShare - reviewShare
            HStack(spacing: 0) {
                Rectangle().fill(Color.gray.opacity(0.5)).frame(width: geometry.size.width * otherShare / total)
                Rectangle().fill(Color.green).frame(width: geometry.size.width * safeShare / total)
                Rectangle().fill(Color.orange).frame(width: geometry.size.width * reviewShare / total)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
        .accessibilityLabel("\(Int(disk.usedFraction * 100)) percent used")
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

// MARK: - List

private struct CategorySection: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory

    private var isExpanded: Bool { model.expanded.contains(category.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
                CheckBox(state: model.selectionState(of: category)) { model.toggle(category) }
                Image(systemName: category.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(category.title).fontWeight(.medium)
                Text("\(category.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormat.standard(category.totalSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { model.toggleExpanded(category) }
            }

            if isExpanded {
                ForEach(category.items) { item in
                    ItemRow(item: item)
                }
                .padding(.bottom, 4)
            }
            Divider().padding(.leading, 14)
        }
    }
}

private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CheckBox(state: model.selection.contains(item.id) ? .on : .off) { model.toggle(item) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title).lineLimit(1)
                    if item.safety == .review {
                        Text("Review")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Text(ByteFormat.standard(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 34)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.toggle(item) }
        .help(item.note ?? "")
        .contextMenu {
            Button("Reveal in Finder") { model.reveal(item) }
                .disabled(item.revealURL == nil)
        }
    }

    /// "used 2 days ago" first so it survives truncation.
    private var subtitle: String? {
        var parts: [String] = []
        if let lastUsed = item.lastUsed {
            parts.append("used \(lastUsed.formatted(.relative(presentation: .named)))")
        }
        if let detail = item.detail, !detail.isEmpty { parts.append(detail) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct CheckBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Selected" : state == .mixed ? "Partly selected" : "Not selected")
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                idle
            case .confirming:
                confirming
            case .cleaning(let done, let total, let current):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                    Text("Cleaning \(current)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .finished(let freed, let cleaned, let errors):
                finished(freed: freed, cleaned: cleaned, errors: errors)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var idle: some View {
        HStack {
            if model.selection.isEmpty {
                Text("Select what to clean").foregroundStyle(.secondary)
                Spacer()
                Button("Select all safe") { model.selectAllSafe() }
                    .disabled(model.total(.safe) == 0)
            } else {
                Text("\(model.selection.count) selected · \(ByteFormat.standard(model.selectedSize))")
                Spacer()
                Button("Clear") { model.selection.removeAll() }
                Button("Clean…") { model.requestClean() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var confirming: some View {
        let reviewCount = model.selectedItems.filter { $0.safety == .review }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Delete \(model.selection.count) items and free about \(ByteFormat.standard(model.selectedSize))?")
                .fontWeight(.medium)
            Text("They're deleted permanently, not moved to the Trash. Build tools recreate them when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if reviewCount > 0 {
                Label("\(reviewCount) of them are marked Review.", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !model.runningBlockers.isEmpty {
                Label("Quit \(model.runningBlockers.map(\.name).joined(separator: ", ")) first for best results.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelClean() }
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    Task { await model.clean() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private func finished(freed: Int64, cleaned: Int, errors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Freed about \(ByteFormat.standard(freed))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .fontWeight(.medium)
            ForEach(errors.prefix(3), id: \.self) { error in
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            HStack {
                Spacer()
                Button("Done") { model.phase = .idle }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
