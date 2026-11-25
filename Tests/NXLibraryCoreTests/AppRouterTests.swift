import XCTest
@testable import NXLibraryCore

final class AppRouterTests: XCTestCase {
    func testFullScreenBackdropCoverFollowsTheVisibleLayerPriority() {
        XCTAssertEqual(ShellBackdropCover.resolve(setup: true, welcome: true, themePicker: true), .setup)
        XCTAssertEqual(ShellBackdropCover.resolve(setup: false, welcome: true, themePicker: true), .welcome)
        XCTAssertEqual(ShellBackdropCover.resolve(setup: false, welcome: false, themePicker: true), .themePicker)
        XCTAssertEqual(ShellBackdropCover.resolve(setup: false, welcome: false, themePicker: false), .none)
        for priority in [0.0, 0.5, 0.8, 1, 2, 2.4] {
            XCTAssertTrue(ShellBackdropCover.setup.covers(priority))
        }
        XCTAssertFalse(ShellBackdropCover.setup.covers(2.5))
        XCTAssertFalse(ShellBackdropCover.setup.covers(3))
        XCTAssertFalse(ShellBackdropCover.setup.covers(4))
        XCTAssertTrue(ShellBackdropCover.welcome.covers(2))
        XCTAssertFalse(ShellBackdropCover.welcome.covers(2.5))
        XCTAssertTrue(ShellBackdropCover.themePicker.covers(0.8))
        XCTAssertFalse(ShellBackdropCover.themePicker.covers(1))
        XCTAssertFalse(ShellBackdropCover.themePicker.covers(2))
        XCTAssertFalse(ShellBackdropCover.none.covers(0))
    }

    func testInitialRoute() {
        let router = AppRouter()
        XCTAssertEqual(router.route, .library)
        XCTAssertFalse(router.isMenuPresented)
    }

    func testNavigationAndBack() {
        let router = AppRouter()
        let id = UUID()
        router.showDetail(id)
        XCTAssertEqual(router.route, .detail(id))
        router.openSettings(.look)
        XCTAssertEqual(router.route, .settings(.look))
        router.back()
        XCTAssertEqual(router.route, .detail(id))
        router.back()
        XCTAssertEqual(router.route, .library)
        router.back()
        XCTAssertEqual(router.route, .library)
    }

    func testSettingsDepartureDoesNotDiscardOrPopHistoryUntilResolved() {
        let router = AppRouter()
        var dirty = true
        router.hasPendingSettings = { dirty }
        router.openSettings(.look)
        router.openSettings(.multiplayer)
        XCTAssertEqual(router.previousRoute, .library)
        XCTAssertNil(router.settingsDecision)

        router.back()
        XCTAssertEqual(router.settingsDecision, .leave)
        XCTAssertEqual(router.route, .settings(.multiplayer))
        XCTAssertEqual(router.previousRoute, .library)
        router.finishSettingsDecision(proceed: false)
        XCTAssertEqual(router.route, .settings(.multiplayer))
        XCTAssertNil(router.settingsDecision)

        router.openCollection()
        XCTAssertEqual(router.settingsDecision, .leave)
        dirty = false
        router.finishSettingsDecision(proceed: true)
        XCTAssertEqual(router.route, .collection)
    }

    func testSettingsMenuAndQuitDeferOneContinuation() {
        let router = AppRouter()
        var dirty = true
        var quitCalls = 0
        router.hasPendingSettings = { dirty }
        router.openSettings(.look)
        router.isMenuPresented = true
        XCTAssertFalse(router.isMenuPresented)
        XCTAssertEqual(router.settingsDecision, .leave)
        XCTAssertTrue(router.requestSettingsDeparture { quitCalls += 1 })
        dirty = false
        router.finishSettingsDecision(proceed: true)
        XCTAssertTrue(router.isMenuPresented)
        XCTAssertEqual(quitCalls, 0)

        router.closeMenu()
        dirty = true
        XCTAssertTrue(router.requestSettingsDeparture { quitCalls += 1 })
        dirty = false
        router.finishSettingsDecision(proceed: true)
        XCTAssertEqual(quitCalls, 1)

        dirty = true
        router.requestSettingsSave()
        XCTAssertEqual(router.settingsDecision, .save)
        router.finishSettingsDecision(proceed: false)
        XCTAssertEqual(router.route, .settings(.look))
    }

    func testRequestSpotlightSelectIsPending() {
        let router = AppRouter()
        let id = UUID()
        router.requestSpotlightSelect(id)
        XCTAssertEqual(router.pendingSpotlightSelect, id)
    }

    func testShowLibraryClearsHistory() {
        let router = AppRouter()
        router.openAddGame()
        router.showLibrary()
        XCTAssertEqual(router.route, .library)
        router.back()
        XCTAssertEqual(router.route, .library)
    }

    func testCollectionAndBackToSpotlight() {
        let router = AppRouter()
        router.openCollection()
        XCTAssertEqual(router.route, .collection)
        router.back()
        XCTAssertEqual(router.route, .library)
    }

    func testMenuOpenClose() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
    }

    func testClosingTheMenuClosesTheThemePicker() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.isThemePickerOpen = true
        router.closeMenu()
        XCTAssertFalse(router.isThemePickerOpen)
    }

    func testBackFromActivityKeepsTheMenuOpenUnlikeOutsideClick() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.pressMenuIcon(.activityCenter)
        router.activityCenterFocus = ActivityCenterFocus()
        router.menuStep(.back)
        XCTAssertTrue(router.isMenuPresented)
        XCTAssertEqual(router.menuSelection.selected, .activityCenter)
        XCTAssertNil(router.activityCenterFocus)
        router.menuStep(.back)
        XCTAssertFalse(router.isMenuPresented)

        router.isMenuPresented = true
        router.activityCenterFocus = ActivityCenterFocus()
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
        XCTAssertNil(router.activityCenterFocus)
    }

    func testShouldersStepThroughIconsAndSwitchOpenPanelsWithoutOpeningSettings() {
        let router = AppRouter()
        router.isMenuPresented = true
        XCTAssertEqual(router.menuSelection.selected, .power)
        router.menuSelection.selected = .settings
        XCTAssertEqual(router.menuStep(.confirm), .action(.settings))
        XCTAssertEqual(router.menuStep(.next), .none)
        XCTAssertEqual(router.menuSelection.selected, .settings)
        XCTAssertEqual(router.menuStep(.previous), .none)
        XCTAssertEqual(router.menuSelection.selected, .activityCenter)

        router.pressMenuIcon(.profile)
        XCTAssertEqual(router.menuStep(.previous), .none)
        XCTAssertEqual(router.menuStep(.confirm), .entry(.myProfile))
        XCTAssertEqual(router.menuStep(.next), .action(.library))
        router.pressMenuIcon(.library)
        XCTAssertEqual(router.menuStep(.confirm), .entry(.addGame))
        XCTAssertEqual(router.menuStep(.next), .action(.power))
        router.pressMenuIcon(.power)
        XCTAssertEqual(router.menuStep(.confirm), .power(.sleep))
        XCTAssertEqual(router.menuStep(.next), .action(.activityCenter))
        router.pressMenuIcon(.activityCenter)
        router.activityCenterFocus = ActivityCenterFocus()
        XCTAssertEqual(router.menuStep(.next), .none)
        XCTAssertEqual(router.menuStep(.previous), .action(.power))
        router.pressMenuIcon(.power)
        XCTAssertNil(router.activityCenterFocus)
        XCTAssertEqual(router.menuStep(.previous), .action(.library))
    }

    func testMoveMenuMovesPillsWhileOpen() {
        let router = AppRouter()
        router.menuSelection.selected = .power
        router.openPowerMenu()
        router.movePowerMenu(by: 1)
        XCTAssertEqual(router.menuSelection.power, .hide)
        XCTAssertEqual(router.menuSelection.selected, .power)
        // Left and Right do nothing while the pills are open.
        router.moveMenu(by: -1)
        XCTAssertEqual(router.menuSelection.selected, .power)
        XCTAssertEqual(router.menuSelection.power, .hide)
        router.closePowerMenu()
        // Up and Down do nothing while the pills are closed.
        router.movePowerMenu(by: 1)
        XCTAssertEqual(router.menuSelection.power, .hide)
        router.moveMenu(by: -1)
        XCTAssertEqual(router.menuSelection.selected, .library)
    }

    func testCloseMenuClosesPowerPills() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.openPowerMenu()
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
        XCTAssertFalse(router.menuSelection.isPowerOpen)
    }
}

final class MenuSelectionModelTests: XCTestCase {
    func testDisabledInboxIsSkippedByLibraryMenuFocus() {
        var model = MenuSelectionModel(selected: .library)
        model.openEntries()
        model.moveEntry(by: 3)
        XCTAssertEqual(model.entry, .gameInbox)
        model.gameInboxEnabled = false
        XCTAssertEqual(model.entries, [.addGame, .manageSources, .refreshLibrary])
        XCTAssertEqual(model.entry, .refreshLibrary)
        model.moveEntry(by: -1)
        XCTAssertEqual(model.entry, .manageSources)
    }

    func testMenuHasFiveIconsWithPowerInTheMiddle() {
        XCTAssertEqual(MenuAction.allCases, [.profile, .library, .power, .activityCenter, .settings])
        XCTAssertEqual(MenuAction.allCases.map(\.title), ["Profile", "Library", "Power", "Activity center", "Settings"])
        XCTAssertTrue(MenuAction.allCases.allSatisfy { $0.entries.count <= 5 })
        XCTAssertEqual(MenuAction.profile.entries, [.myProfile, .switchProfile, .editProfile, .theme, .players])
        XCTAssertEqual(MenuAction.library.entries, [.addGame, .manageSources, .refreshLibrary, .gameInbox])
        XCTAssertEqual(MenuEntry.allCases.map(\.title),
                       ["My profile", "Switch profile", "Edit profile", "Theme", "Players", "Add Game", "Manage sources",
                        "Library refresh", "Sort incoming files"])
        // Console and the Setup check live in Settings; Activity and Settings act at once.
        XCTAssertTrue(MenuAction.activityCenter.entries.isEmpty && MenuAction.settings.entries.isEmpty)
        XCTAssertEqual(MenuAction.allCases.flatMap(\.entries).count, MenuEntry.allCases.count)
        XCTAssertEqual(PowerAction.allCases, [.sleep, .hide, .relaunch, .quit])
        XCTAssertEqual(PowerAction.allCases.map(\.title), ["Sleep", "Hide", "Restart app", "Quit"])
    }

    func testMoveClampsAtBothEnds() {
        var model = MenuSelectionModel(selected: .profile)
        model.move(by: -1)
        XCTAssertEqual(model.selected, .profile)
        model.move(by: 10)
        XCTAssertEqual(model.selected, .settings)
        model.move(by: 1)
        XCTAssertEqual(model.selected, .settings)
    }

    func testEveryMenuTitleIsTranslatedInSixLanguages() {
        defer { L10n.setContext(AppLocale(language: .english, region: "US")) }
        let english = MenuAction.allCases.map(\.title) + MenuEntry.allCases.map(\.title) + PowerAction.allCases.map(\.title)
        for language in AppLanguage.allCases where language != .english && language != .automatic {
            L10n.setContext(AppLocale(language: language, region: "FR"))
            let translated = MenuAction.allCases.map(\.title) + MenuEntry.allCases.map(\.title) + PowerAction.allCases.map(\.title)
            for (before, after) in zip(english, translated) {
                XCTAssertNotEqual(before, after, "\(language.rawValue): \(before) is not translated")
            }
        }
    }

    func testCardOpensOnItsFirstEntryAndClamps() {
        var model = MenuSelectionModel(selected: .library)
        model.moveEntry(by: 1) // closed: nothing moves
        XCTAssertEqual(model.entry, .myProfile)
        model.openEntries()
        XCTAssertTrue(model.isEntryOpen && model.isSubmenuOpen)
        XCTAssertEqual(model.entry, .addGame)
        model.moveEntry(by: 5)
        XCTAssertEqual(model.entry, .gameInbox)
        model.moveEntry(by: -9)
        XCTAssertEqual(model.entry, .addGame)
        // An icon without a card never opens one.
        var activity = MenuSelectionModel(selected: .activityCenter)
        activity.openEntries()
        XCTAssertFalse(activity.isEntryOpen)
    }

    func testBackClosesTheCardThenTheMenuAndKeepsTheFocus() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.menuSelection.selected = .profile
        router.openEntryMenu()
        router.moveEntryMenu(by: 3)
        XCTAssertEqual(router.menuSelection.entry, .theme)
        // Left and Right wait while the card is open.
        router.moveMenu(by: 1)
        XCTAssertEqual(router.menuSelection.selected, .profile)
        router.closeEntryMenu()
        XCTAssertTrue(router.isMenuPresented)
        XCTAssertFalse(router.menuSelection.isEntryOpen)
        XCTAssertEqual(router.menuSelection.selected, .profile)
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
        XCTAssertEqual(router.menuSelection.selected, .profile)
        // Closing the menu with a card open closes the card too.
        router.isMenuPresented = true
        router.openEntryMenu()
        router.closeMenu()
        XCTAssertFalse(router.menuSelection.isEntryOpen)
        XCTAssertEqual(router.menuSelection.selected, .profile)
    }

    /// Up and Down walk a submenu's lines, A names the focused one, B closes it and leaves the focus on its icon.
    func testEverySubmenuTakesUpDownConfirmAndBack() {
        func check<Line: Equatable>(_ icon: MenuAction, lines: [Line], open: (AppRouter) -> Void,
                                    focused: (AppRouter) -> Line, outcome: (Line) -> MenuOutcome,
                                    isOpen: (AppRouter) -> Bool) {
            let router = AppRouter()
            router.isMenuPresented = true
            router.menuSelection.selected = icon
            open(router)
            XCTAssertEqual(focused(router), lines[0], "\(icon) opens on its first line")
            XCTAssertEqual(router.menuStep(.confirm), outcome(lines[0]))
            for line in lines.dropFirst() {
                router.menuStep(.down)
                XCTAssertEqual(focused(router), line, "\(icon): Down reaches the next line")
                XCTAssertEqual(router.menuStep(.confirm), outcome(line), "\(icon): A runs the focused line")
            }
            router.menuStep(.down)
            XCTAssertEqual(focused(router), lines.last, "\(icon): Down stops on the last line")
            for line in lines.dropLast().reversed() {
                router.menuStep(.up)
                XCTAssertEqual(focused(router), line, "\(icon): Up goes back")
            }
            // Left and Right wait while the submenu holds the focus.
            router.menuStep(.right)
            XCTAssertEqual(router.menuSelection.selected, icon)
            XCTAssertEqual(router.menuStep(.back), .none)
            XCTAssertFalse(isOpen(router), "\(icon): B closes the submenu")
            XCTAssertTrue(router.isMenuPresented)
            XCTAssertEqual(router.menuSelection.selected, icon, "\(icon): the focus is back on its icon")
            // The row answers again, and a second B closes the menu.
            XCTAssertEqual(router.menuStep(.confirm), .action(icon))
            router.menuStep(.back)
            XCTAssertFalse(router.isMenuPresented)
        }
        for icon in [MenuAction.profile, .library] {
            check(icon, lines: icon.entries, open: { $0.openEntryMenu() }, focused: { $0.menuSelection.entry },
                  outcome: { .entry($0) }, isOpen: { $0.menuSelection.isEntryOpen })
        }
        check(.power, lines: PowerAction.allCases, open: { $0.openPowerMenu() }, focused: { $0.menuSelection.power },
              outcome: { .power($0) }, isOpen: { $0.menuSelection.isPowerOpen })
    }

    /// A mouse click on an icon opens its submenu; on another icon it replaces the open one; on the same icon it closes it.
    func testClickingIconsOpensReplacesAndClosesSubmenus() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.pressMenuIcon(.library)
        XCTAssertTrue(router.menuSelection.isEntryOpen)
        XCTAssertEqual(router.menuSelection.selected, .library)
        router.pressMenuIcon(.profile)
        XCTAssertEqual(router.menuSelection.selected, .profile)
        XCTAssertTrue(router.menuSelection.isEntryOpen)
        XCTAssertEqual(router.menuSelection.entry, .myProfile)
        router.pressMenuIcon(.power)
        XCTAssertTrue(router.menuSelection.isPowerOpen && !router.menuSelection.isEntryOpen)
        router.pressMenuIcon(.library)
        XCTAssertTrue(router.menuSelection.isEntryOpen && !router.menuSelection.isPowerOpen)
        router.pressMenuIcon(.library)
        XCTAssertFalse(router.menuSelection.isSubmenuOpen)
        router.pressMenuIcon(.library)
        router.pressMenuIcon(.settings)
        XCTAssertFalse(router.menuSelection.isSubmenuOpen)
        XCTAssertEqual(router.menuSelection.selected, .settings)
    }

    func testActivityCenterUsesMenuLifetime() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.moveMenu(by: 1)
        XCTAssertEqual(router.menuSelection.selected, .activityCenter)
        router.activityCenterFocus = ActivityCenterFocus()
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
        XCTAssertNil(router.activityCenterFocus)
    }

    func testActivityFocusTracksRequestsThroughQueueChanges() {
        let first = UUID(), second = UUID()
        var focus = ActivityCenterFocus()
        let rows = ActivityCenterFocus.rows(isBuilding: true, queuedCloud: [first, second])
        XCTAssertEqual(focus.current(in: rows), .build(nil))
        focus.move(by: -1, in: rows)
        XCTAssertEqual(focus.current(in: rows), .build(nil))
        focus.move(by: 2, in: rows)
        XCTAssertEqual(focus.current(in: rows), .queuedCloud(second))
        let remaining = ActivityCenterFocus.rows(isBuilding: false, queuedCloud: [second])
        XCTAssertEqual(focus.current(in: remaining), .queuedCloud(second))
        let empty = ActivityCenterFocus.rows(isBuilding: false)
        XCTAssertEqual(focus.current(in: empty), .close)
        XCTAssertEqual(focus.current(in: ActivityCenterFocus.rows(isBuilding: false, queuedCloud: [first])), .close)
        let replacement: [ActivityCenterFocus.Row] = [.queuedCloud(first), .queuedCloud(UUID())]
        focus.move(by: 1, in: replacement)
        XCTAssertEqual(focus.current(in: replacement), .queuedCloud(first))
        focus.move(by: 1, in: empty)
        XCTAssertEqual(focus.current(in: empty), .close)
    }

    func testActivityFocusSeparatesActiveAndQueuedCancellations() {
        let build = UUID(), queuedBuild = UUID(), transfer = UUID(), queuedCloud = UUID()
        let rows = ActivityCenterFocus.rows(isBuilding: true, activeBuild: build, queuedBuilds: [queuedBuild],
                                            activeCloud: transfer, queuedCloud: [queuedCloud])
        XCTAssertEqual(rows, [.build(build), .queuedBuild(queuedBuild), .cloud(transfer), .queuedCloud(queuedCloud)])
        XCTAssertEqual(rows.filter(\.opensPorting), [.build(build), .queuedBuild(queuedBuild)])
        XCTAssertEqual(rows.filter { $0.canCancel(isCancellingBuild: true) },
                       [.queuedBuild(queuedBuild), .cloud(transfer), .queuedCloud(queuedCloud)])
        XCTAssertFalse(ActivityCenterFocus.Row.close.canCancel(isCancellingBuild: false))
        var focus = ActivityCenterFocus()
        focus.selected = .queuedBuild(queuedBuild)
        let promoted = ActivityCenterFocus.rows(isBuilding: true, activeBuild: queuedBuild, activeCloud: queuedCloud)
        XCTAssertEqual(focus.current(in: promoted), .close)
        focus.selected = .queuedCloud(queuedCloud)
        XCTAssertEqual(focus.current(in: promoted), .close)
    }

    func testActivityFocusNavigatesResultsAndClearAllWithoutRetargetingClear() {
        let move = UUID(), first = UUID(), second = UUID()
        var focus = ActivityCenterFocus()
        let rows = ActivityCenterFocus.rows(isBuilding: false, move: move, results: [first, second])
        focus.move(by: 1, in: rows)
        XCTAssertEqual(focus.current(in: rows), .result(first))
        let afterClear = ActivityCenterFocus.rows(isBuilding: false, move: move, results: [second])
        XCTAssertEqual(focus.current(in: afterClear), .close)
        focus.move(by: -1, in: afterClear)
        XCTAssertEqual(focus.current(in: afterClear), .clearAll)
        XCTAssertEqual(focus.current(in: [.move(move)]), .close)
    }

    func testPowerSubmenuOpensAndCloses() {
        var model = MenuSelectionModel(selected: .power)
        XCTAssertFalse(model.isPowerOpen)
        model.openPower()
        XCTAssertTrue(model.isPowerOpen)
        XCTAssertEqual(model.power, .sleep)
        model.movePower(by: 1)
        XCTAssertEqual(model.power, .hide)
        model.movePower(by: 5)
        XCTAssertEqual(model.power, .quit)
        model.movePower(by: -9)
        XCTAssertEqual(model.power, .sleep)
        model.closePower()
        XCTAssertFalse(model.isPowerOpen)
        XCTAssertEqual(model.selected, .power)
    }
}

final class AppRouterSpotlightMoveTests: XCTestCase {
    func testRequestSpotlightMoveSetsPendingKey() {
        let router = AppRouter()
        XCTAssertNil(router.pendingSpotlightMove)
        router.requestSpotlightMove("card:activity")
        XCTAssertEqual(router.pendingSpotlightMove, "card:activity")
    }

    func testInitialRouteHonorsStartOn() {
        XCTAssertEqual(AppRouter.initialRoute(for: .spotlight, last: .collection), .library)
        XCTAssertEqual(AppRouter.initialRoute(for: .collection, last: .spotlight), .collection)
        XCTAssertEqual(AppRouter.initialRoute(for: .last, last: .collection), .collection)
        XCTAssertEqual(AppRouter.initialRoute(for: .last, last: .spotlight), .library)
        // `last` is never a place; a stray one falls back to Spotlight.
        XCTAssertEqual(AppRouter.initialRoute(for: .last, last: .last), .library)
    }

    func testSetInitialRouteLeavesNoHistory() {
        let router = AppRouter()
        router.setInitialRoute(.collection)
        XCTAssertEqual(router.route, .collection)
        router.back()
        XCTAssertEqual(router.route, .collection)
    }

    func testUnderlyingRouteSkipsAddGameAndConsole() {
        let router = AppRouter()
        router.openCollection()
        router.openAddGame()
        router.openConsole()
        XCTAssertEqual(router.route, .console)
        // The console opened from Add game blurs the home, not Add game.
        XCTAssertEqual(router.underlyingRoute, .collection)
        router.back()
        XCTAssertEqual(router.route, .addGame)
        XCTAssertEqual(router.underlyingRoute, .collection)
    }

    func testOverlayRoutes() {
        XCTAssertTrue(AppRoute.addGame.isOverlay)
        XCTAssertTrue(AppRoute.console.isOverlay)
        XCTAssertFalse(AppRoute.library.isOverlay)
        XCTAssertFalse(AppRoute.collection.isOverlay)
    }
}
