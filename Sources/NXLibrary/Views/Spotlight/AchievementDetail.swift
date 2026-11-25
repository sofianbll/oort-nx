import SwiftUI
import NXLibraryCore

/// One achievement in full, over the Achievements screen (A on a row), as a medallion (maintainer's choice "A",
/// 16 Nov 2026): on one centred axis the achievement's icon large with its tier crystal as a small badge on the
/// corner, the whole name and description the list cuts, then how many players have it and when it was unlocked.
/// The arrows step it through the list, A or B (or a click outside the card) close it. Without Steam's rarity the
/// icon has no badge.
struct AchievementDetail: View {
    @Environment(\.seleneCanvas) private var canvas

    let row: AchievementRow
    let appID: UInt32
    let onClose: () -> Void

    static let width: CGFloat = 720
    static let icon: CGFloat = 200
    static let badge: CGFloat = 64

    var body: some View {
        let unlocked = row.unlockedAt != nil
        let shape = RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.modalRadius), style: .continuous)
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                medal(unlocked: unlocked)
                Text(row.name)
                    .seleneFont(.screen, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, canvas.u(SeleneTokens.Space.section))
                if !row.description.isEmpty {
                    Text(row.description)
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink82)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, canvas.u(SeleneTokens.Space.small))
                }
                Rectangle()
                    .fill(SeleneTheme.ink15)
                    .frame(width: canvas.u(80), height: max(1, canvas.u(1)))
                    .padding(.top, canvas.u(SeleneTokens.Space.large))
                VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    if let tier = row.tier, let percent = row.percent {
                        HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                            Text(tier.displayName())
                                .foregroundColor(SeleneTheme.ink)
                            Text("·").foregroundColor(SeleneTheme.ink60)
                            Text(L10n.format("%@ of players", [AchievementsScreen.percent(percent)]))
                                .foregroundColor(SeleneTheme.ink75)
                                .monospacedDigit()
                        }
                    }
                    if let date = row.unlockedAt {
                        Label {
                            Text(L10n.format("Unlocked on %@", [AchievementsScreen.date(date)]))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundColor(SeleneTheme.ink82)
                    } else {
                        Text(L10n.text("Not unlocked"))
                            .foregroundColor(SeleneTheme.ink75)
                    }
                }
                .seleneFont(.text, .semibold)
                .lineLimit(1)
                .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
            .padding(.horizontal, canvas.u(56))
            .padding(.top, canvas.u(56))
            .padding(.bottom, canvas.u(SeleneTokens.Space.group))
            .frame(width: canvas.u(Self.width))
            .background(shape.fill(SeleneTheme.glassCard))
            .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
            .oortShadow(.floating)
            // A click on the card stays on the card.
            .contentShape(shape)
            .onTapGesture {}
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
        }
    }

    /// The icon, the thing earned, with its grade on the corner as a trophy's: the tier crystal, a little out of
    /// the icon's square, lifted off it by a soft shadow.
    private func medal(unlocked: Bool) -> some View {
        AchievementIcon(appID: appID, file: row.icon, size: Self.icon, dimmed: !unlocked, secret: row.isMasked)
            .overlay(alignment: .bottomTrailing) {
                if let tier = row.tier {
                    TierCrystal(tier: tier, size: Self.badge, dimmed: !unlocked)
                        .oortShadow(.tile)
                        .offset(x: canvas.u(Self.badge * 0.35), y: canvas.u(Self.badge * 0.3))
                }
            }
    }
}
