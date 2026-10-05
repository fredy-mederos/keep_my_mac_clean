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
            DigestCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            FilterChips()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            content
            FooterBar()
        }
        .frame(width: 400)
        .background(Palette.popoverBackground)
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

            // The buttons sit beside the big number only, so the lines below get the full width.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(model.menuBarText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(model.isLowOnSpace ? Palette.red : Color.primary)
                            .contentTransition(.numericText())
                        Text("free")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    buttons
                        .offset(x: 6)
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                TrendLine()
                    .padding(.top, 2)
            }
        }
    }

    private var buttons: some View {
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
                    .foregroundStyle(Palette.secondaryText)
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
                    .foregroundStyle(tint ?? Palette.secondaryText)
                Text(text(trend))
                    .foregroundStyle(tint ?? Palette.secondaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                if model.recentSamples.count >= 2 {
                    Sparkline(samples: model.recentSamples, tint: tint ?? .accentColor)
                        .frame(width: 54, height: 14)
                }
            }
            .font(.caption)
        } else {
            Label("Trend shows up after a day", systemImage: "chart.line.flattrend.xyaxis")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
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
        if days < 7 { return Palette.red }
        if days < 30 { return Palette.orange }
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

// MARK: - Weekly summary

/// "Free space down 9 GB this week" with what grew, and a shortcut to the biggest grower.
private struct DigestCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let facts = model.digestFacts, let text = model.digestText {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: facts.netChange < 0 ? "chart.bar.xaxis.ascending" : "chart.bar.xaxis")
                        .foregroundStyle(Color.accentColor)
                    Text(text.headline)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                if !text.body.isEmpty {
                    Text(text.body)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let grower = facts.biggestGrower, let item = model.allItems.first(where: { $0.id == grower.id }) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { model.focus(onItem: item.id) }
                    } label: {
                        Label("Select \(item.title) · \(ByteFormat.short(item.size))", systemImage: "scope")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 10, fill: Color.accentColor.opacity(0.07))
        }
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
                        .foregroundStyle(Palette.secondaryText)
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
            .card(cornerRadius: 10, fill: isActive ? safety.tint.opacity(0.18) : Palette.card)
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
                                .foregroundStyle(Palette.orange)
                                .help("Grew by \(ByteFormat.standard(growth.bytes)) since \(growth.since.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
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
        .card(fill: isHovering && !isExpanded ? Palette.cardHover : Palette.card)
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
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                    Text("Select")
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.blue)
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
    @State private var showsInfo = false

    private var isSelected: Bool { model.selection.contains(item.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CheckBox(state: isSelected ? .on : .off) { model.toggle(item) }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                costLine
                suggestionLine
                projectLine
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormat.standard(item.size))
                    .font(.system(size: 11.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
                switch item.safety {
                case .review: Tag(text: "Review", color: Palette.orange)
                case .personal: Tag(text: "To Trash", color: Palette.blue)
                case .safe: EmptyView()
                }
            }
            infoButton
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
        .onAppear { model.requestSuggestion(for: item) }
        .contextMenu {
            Button("About this item") { showsInfo = true }
            Button("Reveal in Finder") { model.reveal(item) }
                .disabled(item.revealURL == nil)
        }
    }

    /// On Review rows: what cleaning costs, colored by how serious it is.
    @ViewBuilder
    private var costLine: some View {
        if item.safety == .review, let cost = item.cost, let level = item.costLevel {
            Label {
                Text(cost)
            } icon: {
                Image(systemName: level.symbol)
            }
            .font(.caption)
            .foregroundStyle(level.textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .labelStyle(CompactLabelStyle())
        }
    }

    /// On your own files: the suggestion, written on-device when Smarter suggestions is on.
    @ViewBuilder
    private var suggestionLine: some View {
        if item.safety == .personal, let suggestion = model.suggestion(for: item) {
            Label {
                Text(suggestion.text)
            } icon: {
                Image(systemName: suggestion.isGenerated ? "sparkles" : "lightbulb")
            }
            .font(.caption)
            .foregroundStyle(suggestion.isGenerated ? Palette.purple : Palette.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .labelStyle(CompactLabelStyle())
        }
    }

    /// On project rows: what the project is.
    @ViewBuilder
    private var projectLine: some View {
        if let blurb = model.projectBlurb(for: item) {
            Label {
                Text(blurb.text)
            } icon: {
                Image(systemName: blurb.isGenerated ? "sparkles" : "text.alignleft")
            }
            .font(.caption)
            .foregroundStyle(blurb.isGenerated ? Palette.purple : Palette.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .labelStyle(CompactLabelStyle())
        }
    }

    @ViewBuilder
    private var infoButton: some View {
        if item.reason != nil || item.cost != nil || item.afterCleaning != nil {
            Button {
                showsInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isHovering || showsInfo ? Palette.secondaryText : Palette.secondaryText.opacity(0.6))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("What cleaning this costs")
            .accessibilityLabel("About \(item.title)")
            .popover(isPresented: $showsInfo, arrowEdge: .leading) {
                ItemInfoView(item: item)
                    .environment(model)
            }
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

/// Icon and text close together, icon sized to the text.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// The ⓘ popover: why an item is listed, what cleaning it costs, and what happens afterwards.
private struct ItemInfoView: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem

    var body: some View {
        let suggestion = item.safety == .personal ? model.suggestion(for: item) : nil
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(ByteFormat.standard(item.size))
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }

            if let project = item.project {
                let blurb = model.projectBlurb(for: item)
                section("About this project", symbol: "folder") {
                    if let blurb {
                        Text(blurb.text)
                    }
                    Text([project.stack, project.activity()].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                    if let subject = project.lastCommitSubject, project.description != nil || blurb?.isGenerated == true {
                        Text("Latest commit: \(subject)")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    if blurb?.isGenerated == true {
                        Label("Summarized on this Mac by Apple Intelligence", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Palette.purple)
                    }
                }
            }

            if let text = suggestion?.text ?? item.reason {
                section(item.safety == .personal ? "Suggestion" : "Why it's listed", symbol: item.safety == .personal ? "lightbulb" : "questionmark.circle") {
                    Text(text)
                    if suggestion?.isGenerated == true {
                        Label("Written on this Mac by Apple Intelligence", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Palette.purple)
                    }
                }
            }

            if let cost = item.cost {
                section("What it costs", symbol: item.costLevel?.symbol ?? "checkmark.circle") {
                    if let level = item.costLevel {
                        Tag(text: level.label, color: level.textColor)
                    }
                    Text(cost)
                        .foregroundStyle(item.costLevel == .dataLoss ? Palette.red : Color.primary)
                }
            }

            ActionTargets(item: item)

            if let after = item.afterCleaning {
                section("After cleaning", symbol: "arrow.triangle.2.circlepath") {
                    Text(after)
                }
            }

            if !item.blockers.isEmpty {
                Label("Quit \(item.blockers.map(\.name).joined(separator: " and ")) before cleaning for best results.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            if item.revealURL != nil {
                Button("Reveal in Finder") { model.reveal(item) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }

    private func section(_ title: String, symbol: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
                .textCase(.uppercase)
            content()
        }
    }
}

/// Exactly what cleaning touches: the folders deleted, the files moved to the Trash, or the command run.
private struct ActionTargets: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem
    @State private var showsAll = false

    /// Shown before "Show all".
    private let previewCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
                .textCase(.uppercase)
            switch item.action {
            case .removePaths(let urls), .moveToTrash(let urls):
                if item.checkedWithGit {
                    Label(urls.count == 1 ? "Ignored by git, nothing tracked inside" : "All ignored by git, nothing tracked inside",
                          systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.green)
                }
                paths(urls)
                if !item.skipped.isEmpty {
                    skippedList
                }
            case .command(let executable, let arguments):
                Text(([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var title: String {
        switch item.action {
        case .removePaths(let urls): urls.count == 1 ? "Deletes this folder" : "Deletes these \(urls.count) folders"
        case .moveToTrash: "Moves to the Trash"
        case .command: "Runs"
        }
    }

    private var symbol: String {
        switch item.action {
        case .removePaths: "trash"
        case .moveToTrash: "arrow.up.trash"
        case .command: "terminal"
        }
    }

    @ViewBuilder
    private func paths(_ urls: [URL]) -> some View {
        let sorted = urls.sorted { display($0) < display($1) }
        let visible = showsAll ? sorted : Array(sorted.prefix(previewCount))
        let list = VStack(alignment: .leading, spacing: 2) {
            ForEach(visible, id: \.self) { url in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Text(display(url))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal \(PathFormat.abbreviated(url)) in Finder")
            }
        }
        if showsAll, sorted.count > 12 {
            // Explicit height: inside a self-sizing popover a ScrollView has no natural height.
            ScrollView { list }.frame(height: 200)
        } else {
            list
        }
        if sorted.count > previewCount {
            Button(showsAll ? "Show fewer" : "Show all \(sorted.count)") {
                showsAll.toggle()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    /// Folders a rule matched but git didn't confirm, so they're kept.
    private var skippedList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(item.skipped.count == 1 ? "Kept 1 folder" : "Kept \(item.skipped.count) folders", systemImage: "hand.raised")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
                .padding(.top, 6)
            ForEach(item.skipped, id: \.self) { folder in
                HStack(spacing: 6) {
                    Text(display(folder.url))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(folder.reason)
                        .font(.caption)
                        .foregroundStyle(Palette.orange)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
    }

    /// Inside a project, paths are relative to it ("app/build"); otherwise "~/…".
    private func display(_ url: URL) -> String {
        if item.project != nil, let base = item.revealURL?.standardizedFileURL.path {
            let path = url.standardizedFileURL.path
            if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) + "/" }
        }
        return PathFormat.abbreviated(url)
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
                    .foregroundStyle(Palette.secondaryText)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green.gradient)
                Text(model.filter == nil ? "Nothing to clean right now" : "Nothing of this kind to clean")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
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
                case .verifying:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking that everything is gone…")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                    }
                case .finished(let freed, let trashed, _, let errors):
                    finished(freed: freed, trashed: trashed, errors: errors)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .transition(.opacity)
        }
        .background(Color.primary.opacity(0.035))
    }

    @ViewBuilder
    private var idle: some View {
        HStack(spacing: 10) {
            if model.selection.isEmpty {
                Text("Select what to clean")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Button("Select all safe") { model.selectAllSafe() }
                    .secondaryActionStyle()
                    .disabled(model.total(.safe) == 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(model.selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                    Text(ByteFormat.standard(model.selectedSize))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                Button("Clear") { model.selection.removeAll() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.secondaryText)
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
        let dataLoss = selected.filter { $0.costLevel == .dataLoss }

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
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !toTrash.isEmpty {
                        Text("Your files go to the Trash. Empty it afterwards to get the space back.")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dataLoss.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.octagon.fill")
                            Text(dataLossWarning(dataLoss))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(cornerRadius: 8, fill: Color.red.opacity(0.1))
                    }
                    if reviewCount > 0 {
                        Label("\(reviewCount) marked Review", systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(Palette.orange)
                    }
                    if !model.runningBlockers.isEmpty {
                        Label("Quit \(model.runningBlockers.map(\.name).joined(separator: ", ")) first for best results", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Palette.orange)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelClean() }
                    .secondaryActionStyle()
                    .keyboardShortcut(.cancelAction)
                Button(toDelete.isEmpty ? "Move to Trash" : (dataLoss.isEmpty ? "Delete" : "Delete anyway"), role: .destructive) {
                    Task { await model.clean() }
                }
                .primaryActionStyle(tint: toDelete.isEmpty ? .blue : .red)
            }
        }
    }

    /// "2 can't be recovered: Unused Docker volumes, Emulator: Pixel 8."
    private func dataLossWarning(_ items: [CleanupItem]) -> String {
        let names = items.prefix(3).map(\.title).joined(separator: ", ")
        let more = items.count > 3 ? " and \(items.count - 3) more" : ""
        let subject = items.count == 1 ? "1 item loses data" : "\(items.count) items lose data"
        return "\(subject) that can't be recovered: \(names)\(more)."
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
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("\(done + 1) of \(total)")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
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
                        .foregroundStyle(freed > 0 ? Palette.secondaryText : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if freed == 0, trashed == 0 {
                    Text("Nothing was cleaned")
                        .font(.system(size: 13, weight: .semibold))
                }
                ForEach(errors.prefix(3), id: \.self) { error in
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Palette.red)
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
