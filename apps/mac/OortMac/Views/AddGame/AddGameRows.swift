import SwiftUI
import NXLibraryCore

/// One line of Add game's list, top to bottom. Rows take the focus; headings and
/// notes only read. Up/Down move between rows, Left/Right change a switch or a
/// choice, A runs the row (a field starts editing).
struct AddGameRow: Identifiable {
    enum Kind {
        case action(() -> Void)
        case toggle(Binding<Bool>)
        /// Steps through `values`, the current one at `index`.
        case choice(values: [String], index: Int, select: (Int) -> Void)
        case field(Binding<String>, placeholder: String)
        case heading
        case note
        case warning(action: (() -> Void)?)
    }

    let id: String
    var kind: Kind
    var icon: MaterialIcon? = nil
    var title: String
    var about: String? = nil
    var enabled = true
    var destructive = false
    /// Smaller type and padding: sources, switches, fields.
    var compact = false
    /// A check at the end (the selected game of a folder).
    var checked = false

    var focusable: Bool {
        switch kind {
        case .heading, .note: return false
        case .warning(let action): return action != nil
        default: return true
        }
    }
}

/// Draws one `AddGameRow` in Game options' glass row look, a size smaller.
struct AddGameRowView: View {
    @Environment(\.seleneCanvas) private var canvas

    let row: AddGameRow
    let focused: Bool
    var editing: FocusState<String?>.Binding

    var body: some View {
        switch row.kind {
        case .heading:
            Text(row.title)
                .seleneFont(.badge, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, canvas.u(SeleneTokens.Space.small))
                .padding(.top, canvas.u(SeleneTokens.Space.control))
                .padding(.bottom, canvas.u(SeleneTokens.Space.seam))
        case .note:
            Text(row.title)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
                .padding(.top, canvas.u(SeleneTokens.Space.small))
        case .warning:
            warning
        default:
            glassRow
        }
    }

    private var glassRow: some View {
        let radius = canvas.u(row.compact ? 13 : 16)
        let ink = row.destructive ? PortingPillCopy.softRed : (row.enabled ? SeleneTheme.ink : SeleneTheme.ink60)
        return HStack(spacing: canvas.u(row.compact ? 14 : 18)) {
            if let icon = row.icon {
                MaterialIconView(icon, size: row.compact ? 19 : 22)
                    .foregroundColor(iconColor)
                    .frame(width: canvas.u(row.compact ? 22 : 26))
            }
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                Text(row.title)
                    .seleneFont(row.compact ? 16 : 19, .medium)
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let about = row.about, !about.isEmpty {
                    Text(about)
                        .seleneFont(row.compact ? 13 : 14)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: canvas.u(14))
            trailing
        }
        .padding(.leading, canvas.u(row.compact ? 20 : 24))
        .padding(.trailing, canvas.u(row.compact ? 18 : 22))
        .padding(.vertical, canvas.u(row.compact ? 10 : 15))
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(row.compact ? SeleneTheme.glassLight : SeleneTheme.glass))
        .seleneRowFocus(focused, radius: radius)
        .opacity(row.enabled ? 1 : 0.7)
    }

    private var iconColor: Color {
        if row.destructive { return PortingPillCopy.softRed }
        guard row.enabled else { return SeleneTheme.ink60 }
        return SeleneTheme.rowIcon
    }

    @ViewBuilder private var trailing: some View {
        switch row.kind {
        case .toggle(let isOn):
            SeleneSwitch(isOn: isOn)
                .scaleEffect(0.85)
                .allowsHitTesting(false)
        case .choice(let values, let index, let select):
            SeleneCycleValue(title: row.title, value: values.indices.contains(index) ? values[index] : "—") { step in
                guard !values.isEmpty else { return }
                select((index + step % values.count + values.count) % values.count)
                SoundEffectService.shared.play(.key)
            }
        case .field(let text, let placeholder):
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .seleneFont(.text, .regular, design: .monospaced)
                .foregroundColor(SeleneTheme.ink)
                .multilineTextAlignment(.trailing)
                .focused(editing, equals: row.id)
                .frame(width: canvas.u(320))
        case .action where row.checked:
            MaterialIconView(.check, size: 20)
                .foregroundColor(SeleneTheme.ink)
        default:
            EmptyView()
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.small)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.untested.opacity(SeleneTokens.Alpha.near))
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                Text(row.title)
                    .seleneFont(.text, .medium)
                    .foregroundColor(SeleneTheme.ink)
                if let about = row.about {
                    Text(about)
                        .seleneFont(.badge)
                        .foregroundColor(SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
        .padding(.vertical, canvas.u(SeleneTokens.Space.small))
        .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
            .fill(SeleneTheme.untested.opacity(SeleneTokens.Alpha.faint)))
        .seleneRowFocus(focused, radius: canvas.u(13))
    }
}
