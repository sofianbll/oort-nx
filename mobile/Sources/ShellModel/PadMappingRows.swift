// From NX2Apple frontend-ios/Sources/ShellUI/PadMappingView.swift at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors): the rows only.
import Foundation

public enum PadMappingRows {
    /// The shell's map as rows: Swap A and B, then the 16 buttons.
    public static func global(_ map: PadMap) -> [SettingRow] {
        let swap = SettingRow(id: "swapAB", label: ShellStrings.text("Swap A and B"),
                              kind: .choice([SettingOption("0", ShellStrings.text("Off")), SettingOption("1", ShellStrings.text("On"))]),
                              value: map.swapAB ? "1" : "0", fromShell: !map.swapAB)
        return [swap] + PadMap.buttons.map { button in
            SettingRow(id: button, label: PadMap.label(button), kind: .choice(PadMap.options), value: map.output(for: button),
                       fromShell: map.output(for: button) == button)
        }
    }
    public static let sectionID = "pad"
    /// The setting a game's card sends to forget the game's own mapping.
    public static let resetID = "pad.reset"
}

extension PadMap {
    /// The four groups of the mapping screen, for Oort NX's views.
    public static var buttonGroups: [(title: String, buttons: [String])] { groups }
    public static func placeName(_ button: String) -> String { place(button) }
}
