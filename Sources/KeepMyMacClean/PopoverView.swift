import Charts
import CleanerCore
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @State private var listHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    /// The list grows with its content up to this height, then scrolls.
    private let maxListHeight: CGFloat = 430

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            FilterChips()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            content
            FooterBar()
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(MenuWindowHeight(height: contentHeight))
        // If the window is ever taller than the content, keep the content at the top.
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.2), value: model.phase)
    }

    @ViewBuilder
    private var content: some View {
        let categories = model.visibleCategories
        if categories.isEmpty {
            EmptyState()
                .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(categories) { category in
                        CategoryCard(category: category)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(max(listHeight, 44), maxListHeight))
            .disabled(model.phase != .idle)
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            UsageRing(fraction: model.disk?.usedFraction ?? 0, tint: model.spaceStatus.tint)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.menuBarText)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.isLowOnSpace ? Color.red : Color.primary)
                        .contentTransition(.numericText())
                    Text("free")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TrendLine()
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                if model.isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 26, height: 26)
                        .help("Scanning…")
                } else {
                    IconButton(symbol: "arrow.clockwise", help: "Scan again") {
                        Task { await model.rescan() }
                    }
                }
                IconButton(symbol: "gearshape", help: "Settings") {
                    NSApp.activate()
                    openSettings()
                }
                IconButton(symbol: "power", help: "Quit KeepMyMacClean") {
                    NSApp.terminate(nil)
                }
            }
            .offset(x: 6, y: -4)
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if let disk = model.disk { parts.append("of \(ByteFormat.short(disk.total))") }
        if model.isScanning {
            if let status = model.scanStatus, model.categories.isEmpty {
                parts.append(status.lowercased())
            } else {
                parts.append(model.pendingMeasurements > 0 ? "measuring \(model.pendingMeasurements) more…" : "scanning…")
            }
        } else if let lastScan = model.lastScan {
            parts.append("scanned \(lastScan.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct UsageRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("used")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(fraction * 100)) percent used")
    }
}

/// "−2.1 GB/day · full in ~14 days" with a 7-day sparkline.
private struct TrendLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let trend = model.trend {
            let tint = tint(trend)
            HStack(spacing: 6) {
                Image(systemName: symbol(trend))
                    .foregroundStyle(tint ?? .secondary)
                Text(text(trend))
                    .foregroundStyle(tint ?? .secondary)
                    .lineLimit(1)
                if model.recentSamples.count >= 2 {
                    Sparkline(samples: model.recentSamples, tint: tint ?? .accentColor)
                        .frame(width: 54, height: 14)
                }
            }
            .font(.caption)
        } else {
            Label("Trend shows up after a day", systemImage: "chart.line.flattrend.xyaxis")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func text(_ trend: SpaceTrend) -> String {
        let rate = ByteFormat.short(Int64(abs(trend.bytesPerDay)))
        if trend.bytesPerDay >= SpaceHistory.meaningfulRate {
            if let days = trend.daysUntilFull, days < 60 {
                return "−\(rate)/day · full in ~\(max(Int(days), 1)) days"
            }
            return "Losing about \(rate) a day"
        }
        if trend.bytesPerDay <= -SpaceHistory.meaningfulRate {
            return "Gaining about \(rate) a day"
        }
        return "Stable this week"
    }

    private func symbol(_ trend: SpaceTrend) -> String {
        if trend.bytesPerDay >= SpaceHistory.meaningfulRate { return "chart.line.downtrend.xyaxis" }
        if trend.bytesPerDay <= -SpaceHistory.meaningfulRate { return "chart.line.uptrend.xyaxis" }
        return "chart.line.flattrend.xyaxis"
    }

    /// Warning color when the disk fills up within a month, otherwise none.
    private func tint(_ trend: SpaceTrend) -> Color? {
        guard let days = trend.daysUntilFull else { return nil }
        if days < 7 { return .red }
        if days < 30 { return .orange }
        return nil
    }
}

private struct Sparkline: View {
    let samples: [SpaceSample]
    let tint: Color

    var body: some View {
        Chart(samples, id: \.date) { sample in
            LineMark(
                x: .value("Date", sample.date),
                y: .value("Free", Double(sample.available) / 1e9)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .foregroundStyle(tint)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - Filter chips

/// Totals per kind; tapping one shows only that kind.
private struct FilterChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            chip(.safe, title: "Safe", help: "Rebuilt automatically when needed")
            chip(.review, title: "Review", help: "Probably not needed, worth a look")
            chip(.personal, title: "My files", help: "Your large files and downloads, moved to the Trash")
        }
    }

    private func chip(_ safety: Safety, title: String, help: String) -> some View {
        let isActive = model.filter == safety
        return Button {
            withAnimation(.snappy(duration: 0.2)) { model.toggleFilter(safety) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(safety.tint).frame(width: 6, height: 6)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(safety.tint)
                    }
                }
                Text(ByteFormat.short(model.total(safety)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 10, fill: isActive ? safety.tint.opacity(0.16) : Color.primary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? safety.tint.opacity(0.5) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(isActive ? "Show everything" : "Show only: \(help.lowercased())")
    }
}

// MARK: - Categories

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory
    @State private var isHovering = false

    private var isExpanded: Bool { model.expanded.contains(category.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CheckBox(state: model.selectionState(of: category)) { model.toggle(category) }
                SymbolTile(symbol: category.symbol, tint: category.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(category.items.count == 1 ? "1 item" : "\(category.items.count) items")
                        if let growth = model.growth(ofCategory: category.id) {
                            Label("+\(ByteFormat.short(growth.bytes)) since \(growth.since.formatted(.dateTime.weekday(.abbreviated)))", systemImage: "arrow.up.right")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.orange)
                                .help("Grew by \(ByteFormat.standard(growth.bytes)) since \(growth.since.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(ByteFormat.standard(category.totalSize))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.22)) { model.toggleExpanded(category) }
            }

            if isExpanded {
                Divider()
                    .padding(.leading, 46)
                    .padding(.trailing, 10)
                InactiveRow(category: category)
                VStack(spacing: 0) {
                    ForEach(category.items) { item in
                        ItemRow(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .card(fill: Color.primary.opacity(isHovering && !isExpanded ? 0.07 : 0.045))
        .onHover { isHovering = $0 }
    }
}

/// "5 not used in 3+ months · 6.2 GB  Select" for projects and DerivedData you haven't touched.
private struct InactiveRow: View {
    @Environment(AppModel.self) private var model
    let category: CleanupCategory

    var body: some View {
        let inactive = model.inactiveItems(in: category)
        if !inactive.isEmpty {
            let size = inactive.reduce(Int64(0)) { $0 + $1.size }
            let months = model.settings.inactiveAfterMonths
            Button {
                model.selectInactive(in: category)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.indigo)
                    Text("\(inactive.count) not used in \(months)+ month\(months == 1 ? "" : "s")")
                        .foregroundStyle(.primary)
                    Text(ByteFormat.standard(size))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Select")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .card(cornerRadius: 7, fill: Color.indigo.opacity(0.08))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 40)
            .padding(.trailing, 8)
            .padding(.top, 6)
        }
    }
}

private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem
    @State private var isHovering = false

    private var isSelected: Bool { model.selection.contains(item.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CheckBox(state: isSelected ? .on : .off) { model.toggle(item) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    switch item.safety {
                    case .review: Tag(text: "Review", tint: .orange)
                    case .personal: Tag(text: "To Trash", tint: .blue)
                    case .safe: EmptyView()
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
                .font(.system(size: 11.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(isHovering ? 0.05 : 0))
        }
        .padding(.leading, 32)
        .padding(.trailing, 4)
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
            parts.append("\(item.dateKind.label) \(lastUsed.formatted(.relative(presentation: .named)))")
        }
        if let detail = item.detail, !detail.isEmpty { parts.append(detail) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct EmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text(model.scanStatus ?? "Scanning…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green.gradient)
                Text(model.filter == nil ? "Nothing to clean right now" : "Nothing of this kind to clean")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.filter != nil {
                    Button("Show everything") { model.filter = nil }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                switch model.phase {
                case .idle:
                    idle
                case .confirming:
                    confirming
                case .cleaning(let done, let total, let current):
                    cleaning(done: done, total: total, current: current)
                case .finished(let freed, let trashed, _, let errors):
                    finished(freed: freed, trashed: trashed, errors: errors)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .transition(.opacity)
        }
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var idle: some View {
        HStack(spacing: 10) {
            if model.selection.isEmpty {
                Text("Select what to clean")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select all safe") { model.selectAllSafe() }
                    .secondaryActionStyle()
                    .disabled(model.total(.safe) == 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(model.selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteFormat.standard(model.selectedSize))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                Button("Clear") { model.selection.removeAll() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button {
                    model.requestClean()
                } label: {
                    Label("Clean", systemImage: "sparkles")
                }
                .primaryActionStyle()
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var confirming: some View {
        let selected = model.selectedItems
        let toTrash = selected.filter(\.action.movesToTrash)
        let toDelete = selected.filter { !$0.action.movesToTrash }
        let deleteSize = toDelete.reduce(Int64(0)) { $0 + $1.size }
        let trashSize = toTrash.reduce(Int64(0)) { $0 + $1.size }
        let reviewCount = selected.filter { $0.safety == .review }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: toDelete.isEmpty ? "trash.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(toDelete.isEmpty ? Color.blue : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(deleteCount: toDelete.count, deleteSize: deleteSize, trashCount: toTrash.count, trashSize: trashSize))
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !toDelete.isEmpty {
                        Text("Deleted permanently, not moved to the Trash. Build tools recreate them when needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !toTrash.isEmpty {
                        Text("Your files go to the Trash. Empty it afterwards to get the space back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if reviewCount > 0 {
                        Label("\(reviewCount) marked Review", systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !model.runningBlockers.isEmpty {
                        Label("Quit \(model.runningBlockers.map(\.name).joined(separator: ", ")) first for best results", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelClean() }
                    .secondaryActionStyle()
                    .keyboardShortcut(.cancelAction)
                Button(toDelete.isEmpty ? "Move to Trash" : "Delete", role: .destructive) {
                    Task { await model.clean() }
                }
                .primaryActionStyle(tint: toDelete.isEmpty ? .blue : .red)
            }
        }
    }

    private func headline(deleteCount: Int, deleteSize: Int64, trashCount: Int, trashSize: Int64) -> String {
        func items(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }
        func files(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }
        switch (deleteCount > 0, trashCount > 0) {
        case (true, true):
            return "Delete \(items(deleteCount)) (\(ByteFormat.standard(deleteSize))) and move \(files(trashCount)) (\(ByteFormat.standard(trashSize))) to the Trash?"
        case (false, true):
            return "Move \(files(trashCount)) to the Trash (\(ByteFormat.standard(trashSize)))?"
        default:
            return "Delete \(items(deleteCount)) and free about \(ByteFormat.standard(deleteSize))?"
        }
    }

    private func cleaning(done: Int, total: Int, current: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Cleaning \(current)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(done + 1) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
        }
    }

    private func finished(freed: Int64, trashed: Int64, errors: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(errors.isEmpty ? Color.green : Color.orange)
                .symbolEffect(.bounce, value: freed)
            VStack(alignment: .leading, spacing: 3) {
                if freed > 0 {
                    Text("Freed about \(ByteFormat.standard(freed))")
                        .font(.system(size: 13, weight: .semibold))
                }
                if trashed > 0 {
                    Text(freed > 0
                         ? "\(ByteFormat.standard(trashed)) moved to the Trash. Empty it to get that space back."
                         : "Moved \(ByteFormat.standard(trashed)) to the Trash. Empty it to get the space back.")
                        .font(freed > 0 ? .caption : .system(size: 13, weight: .semibold))
                        .foregroundStyle(freed > 0 ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if freed == 0, trashed == 0 {
                    Text("Nothing was cleaned")
                        .font(.system(size: 13, weight: .semibold))
                }
                ForEach(errors.prefix(3), id: \.self) { error in
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Done") { model.phase = .idle }
                .secondaryActionStyle()
                .keyboardShortcut(.defaultAction)
        }
    }
}
