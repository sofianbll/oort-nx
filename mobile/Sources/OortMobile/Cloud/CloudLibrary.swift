import OortCore
import ShellHost
import SwiftUI

/// The library's cloud side: what runs here, then what does not and why.
struct CloudLibrary: View {
    let cloud: CloudModel
    let model: ShellHostModel
    let nav: OortNav
    let query: String
    let columns: Int
    let focus: FocusGrid<String>

    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedStandardContains(query) }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                CloudFilter(nav: nav)
                VStack(alignment: .leading, spacing: SeleneTokens.Space.large) {
                    status
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SeleneTokens.Space.medium, alignment: .top), count: columns), spacing: SeleneTokens.Space.large) {
                        ForEach(cloud.cloudGames.filter { matches($0.build.name) }) { card($0).id($0.id) }
                    }
                    others
                }
                .padding(.horizontal, SeleneTokens.Space.panel)
                .padding(.vertical, SeleneTokens.Space.medium)
            }
            .refreshable { await cloud.look() }
            .onChange(of: focus.current) { _, id in withAnimation(.snappy) { scroll.scrollTo(id, anchor: .center) } }
        }
        .task { if cloud.listing == nil { await cloud.look() } else { cloud.refreshDevice() } }
    }

    @ViewBuilder private var status: some View {
        let free = cloud.freeSpace.map { Oort.text("\(CloudWords.size($0)) free") } ?? ""
        VStack(alignment: .leading, spacing: SeleneTokens.Space.compact) {
            HStack(spacing: SeleneTokens.Space.compact) {
                Image(systemName: "internaldrive").foregroundStyle(Oort.glyph).accessibilityHidden(true)
                Text(free).foregroundStyle(Oort.ink2).monospacedDigit()
                if cloud.looking { ProgressView().controlSize(.small); Text(Oort.text("Looking for your games…")).foregroundStyle(Oort.ink2) }
            }
            .font(.subheadline)
            if cloud.stage == .signIn || cloud.problem == .signInNeeded {
                notice(CloudWords.why(.signInNeeded), key: Oort.text("Sign in again"), symbol: "person.badge.key") {
                    nav.paths[.settings] = [.integrations, .cloud]
                    nav.tab = .settings
                }
            } else if let problem = cloud.problem {
                notice(CloudWords.why(problem, free: cloud.freeSpace), key: Oort.text("Try again"), symbol: "arrow.clockwise") { Task { await cloud.look() } }
            } else if let listing = cloud.listing, listing.games.isEmpty, cloud.jobs.isEmpty {
                notice(Oort.text("No game for this device in your folder yet. Prepare one on your Mac."), key: Oort.text("Look again"), symbol: "arrow.clockwise") { Task { await cloud.look() } }
            }
        }
    }

    private func notice(_ text: String, key: String, symbol: String, _ run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: SeleneTokens.Space.small) {
            Text(text).foregroundStyle(Oort.ink).fixedSize(horizontal: false, vertical: true)
            Button(action: run) { Label(key, systemImage: symbol) }.buttonStyle(OortKeyStyle())
        }
        .padding(SeleneTokens.Space.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oortPanel()
    }

    private func card(_ game: CloudModel.Game) -> some View {
        let focused = nav.device != nil && focus.current == game.id, state = CloudWords.state(game, cloud)
        return Button {
            nav.device = nil
            nav.sounds.play(.open)
            nav.open(.cloudGame(game.id))
        } label: {
            VStack(alignment: .leading, spacing: SeleneTokens.Space.compact) {
                GeometryReader { CloudTile(game: game, cloud: cloud, artwork: CloudArt.of(game.id, model), side: $0.size.width, focused: focused) }.aspectRatio(1, contentMode: .fit)
                Text(game.build.name).font(.subheadline.weight(.semibold)).foregroundStyle(Oort.ink).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(game.build.gameVersion) · \(CloudWords.size(game.build.bytes))").font(.footnote).foregroundStyle(Oort.ink2).monospacedDigit()
                Text(state).font(.footnote).foregroundStyle(Oort.ink2).monospacedDigit().multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(game.build.name)
        .accessibilityValue("\(game.build.gameVersion), \(CloudWords.size(game.build.bytes)), \(state)")
    }

    @ViewBuilder private var others: some View {
        let rows = rowsElsewhere
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: SeleneTokens.Space.small) {
                Text(Oort.text("Not for this device")).font(.headline).foregroundStyle(Oort.ink).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(rows, id: \.id) { row in
                        VStack(alignment: .leading, spacing: SeleneTokens.Space.seam) {
                            Text(row.name).foregroundStyle(Oort.ink)
                            Text(row.why).font(.footnote).foregroundStyle(Oort.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SeleneTokens.Space.medium)
                        .accessibilityElement(children: .combine)
                        if row.id != rows.last?.id { Divider().overlay(Oort.line) }
                    }
                }
                .oortPanel()
            }
        }
    }

    private var rowsElsewhere: [(id: String, name: String, why: String)] {
        guard let listing = cloud.listing else { return [] }
        let hidden = listing.hidden.filter { matches($0.name) }.map { (id: "h" + $0.titleID, name: $0.name, why: CloudWords.why($0.reason)) }
        // A damaged newest build may hide behind an older one that runs: the game itself is listed above.
        let problems = listing.problems.filter { problem in !listing.games.contains { $0.titleID == problem.titleID } && !listing.hidden.contains { $0.titleID == problem.titleID } }
        return hidden + Dictionary(grouping: problems, by: \.titleID).sorted { $0.key < $1.key }.map { (id: "p" + $0.key, name: $0.value[0].name, why: CloudWords.problem($0.value[0].error)) }
    }
}
