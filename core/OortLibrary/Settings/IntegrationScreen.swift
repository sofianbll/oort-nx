import Foundation
import OortCore

/// What the gestures of Settings › Integrations ask of an entry's owner, beyond open, back and toggle: a closed list.
/// Each host does every target it offers (its effects table) and refuses an unknown one.
public enum IntegrationTarget: String, CaseIterable, Sendable {
    /// The entry's settings row.
    case settings
    /// The library, on its Switch or Steam games.
    case switchGames, steamGames
    /// The programs' page.
    case programs
    /// Delete what information online found, after its question.
    case clearOnline
}

public extension IntegrationWords {
    var screen: Screen.Text { Screen.Text(key, args: args, count: count) }
}

/// The template of Settings › Integrations, written once for every system: the list by sections, and for each entry
/// a detail with a lead and three boxes, Link, Verify, Continue, always in this order. It decides the focus order, the
/// initial focus and every gesture with its words; the renderers draw it, the hosts do its intents.
public enum IntegrationScreen {
    public static let listID = "integrations"
    static let back = Screen.Gesture(.init("Back"), .back)

    /// The list, then every detail: what a companion sends in one message, so opening a detail asks nothing more.
    public static func all(_ facts: IntegrationFacts) -> [Screen] {
        [list(facts)] + facts.sections.flatMap(\.entries).compactMap { detail($0.id, facts) }
    }

    /// Sources, Engines, Services: a row per offered entry; A opens it, X turns its switch. The first row has the focus.
    public static func list(_ facts: IntegrationFacts) -> Screen {
        let blocks: [Screen.Node] = facts.sections.map { section in
            .section(section.id.rawValue, section.id.title.screen, section.entries.map(row), note: section.upcoming?.screen)
        }
        return Screen(id: listID, title: .init("Integrations"), blocks: blocks, back: back)
    }

    static func row(_ entry: IntegrationRow) -> Screen.Node {
        .row(entry.id.rawValue, icon: entry.id.rawValue, title: entry.id.title.screen, about: about(entry, ofRow: true),
             status: status(entry), on: entry.switchOn, a: .init(IntegrationCatalog.open.screen, .open(entry.id.rawValue)),
             x: entry.switchOn.map { .init(IntegrationCatalog.toggle(on: $0).screen, .toggle(entry.id.rawValue)) })
    }

    /// Consent: an entry that must explain itself before it is on says, while it is off, what it sends: in place of
    /// its capabilities on the row, and under its switch in Link. Never truncated.
    static func about(_ entry: IntegrationRow, ofRow: Bool) -> Screen.Text? {
        if entry.id.explainsBeforeOn, entry.switchOn == false {
            var text = IntegrationCatalog.onlineAbout.screen
            text.whole = true
            return text
        }
        return ofRow ? entry.id.capabilities.screen : nil
    }

    static func status(_ entry: IntegrationRow) -> Screen.Status {
        let tone: Screen.Tone = switch entry.emphasis {
        case .neutral: .neutral
        case .working: .working
        case .attention: .attention
        }
        return .init(.init(entry.status), tone: tone)
    }

    /// The detail of one offered entry: its title and lead, then Link (the sentence, the switch, where it is kept while
    /// nothing links it or when Continue has its own action), Verify (the status first, the date, the checks, what it
    /// reads, writes and sends, then what asks a question) and Continue (the useful action, else where it is kept,
    /// else the sentence). The focus starts on the last node of Link or Continue: never in Verify, never on a question.
    public static func detail(_ id: IntegrationID, _ facts: IntegrationFacts) -> Screen? {
        guard let entry = facts.row(id) else { return nil }
        func button(_ node: String, _ action: IntegrationRow.Action) -> Screen.Node {
            .button(node, .init(action.title), a: .init(.init(action.title), .owner(action.target.rawValue)))
        }
        let manageInLink = entry.manage != nil && (entry.needsLink || entry.browse != nil)
        var link: [Screen.Node] = [.text((entry.says ?? id.link(entry.linked)).screen)]
        if let on = entry.switchOn {
            link.append(.toggle("link.switch", title: id.title.screen, about: about(entry, ofRow: false), on: on,
                                a: .init(IntegrationCatalog.toggle(on: on).screen, .toggle(id.rawValue))))
        }
        if manageInLink, let manage = entry.manage { link.append(button("link.manage", manage)) }

        var verify: [Screen.Node] = [.status(status(entry))]
        if let date = entry.checkDate { verify.append(.quiet(.init("Checked: %@", date: date))) }
        verify += entry.checks.map { .text($0.screen) }
        verify.append(.facts([(IntegrationCatalog.reads, entry.reads), (IntegrationCatalog.writes, entry.writes),
                              (IntegrationCatalog.sends, entry.sends)].map { .init($0.key, words: [.init($1)]) }))
        if entry.clears {
            verify.append(.button("verify.clear", IntegrationCatalog.clearOnline.screen,
                                  a: .init(IntegrationCatalog.clearOnline.screen, .owner(IntegrationTarget.clearOnline.rawValue)),
                                  question: .init(title: IntegrationCatalog.clearOnlineQuestion.screen,
                                                  message: IntegrationCatalog.clearOnlineMessage.screen,
                                                  confirm: .init("Delete"), cancel: .init("Cancel"))))
        }

        let next: [Screen.Node] = if let browse = entry.browse { [button("next.browse", browse)] }
            else if !manageInLink, let manage = entry.manage { [button("next.manage", manage)] }
            else { [.text(IntegrationCatalog.rest(linked: entry.linked).screen)] }

        let boxes: [Screen.Node] = [.box("link", IntegrationCatalog.link.screen, link), .box("verify", IntegrationCatalog.verify.screen, verify),
                                    .box("next", IntegrationCatalog.next.screen, next)]
        let start = (boxes[0].all + boxes[2].all).filter { $0.isFocusable && $0.question == nil }.last?.id
        return Screen(id: "\(listID).\(id.rawValue)", title: id.title.screen, lead: .init(entry.purpose), blocks: boxes,
                      initialFocus: start, back: back)
    }
}
