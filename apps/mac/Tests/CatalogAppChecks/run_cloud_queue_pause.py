#!/usr/bin/env python3
"""Check the pause snapshot and render its unchanged Activity rows, with no backend, on the shared Debug app."""
from audit_probe_host import run_host
from run_cloud_screens import capture_destination
from screen_host import ICON, header, package_name, render

SCENARIO = r'''
        let store = CloudTransferQueue()
        let scope = CloudDriveScope(remote: "fixture", account: "fixture-account",
            library: .init(path: "Games", id: "fixture-games"))
        let head = CloudTransferQueue.Entry(id: UUID(), action: .restore(.app), token: UUID(),
            storage: "fixture:Games", driveScope: scope, toolIdentity: "fixture-tool")
        let next = CloudTransferQueue.Entry(id: UUID(), action: .downloadSources, token: UUID(),
            storage: "fixture:Files", driveScope: scope, toolIdentity: "fixture-tool")
        let paused = ProcessInfo.processInfo.environment["OORT_QUEUE_PAUSED"] == "1"
        var saved = head
        saved.isUserPaused = paused
        let wireEntry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        // An unpaused entry must retain the pre-pause shape.
        precondition(paused ? wireEntry["userPaused"] as? Bool == true : wireEntry["userPaused"] == nil)
        store.save([saved, next])
        await store.flush()
        let reopened = await CloudTransferQueue().load()
        let entries = CloudTransferQueue.restoring(reopened, gameIDs: [head.id, next.id])
        precondition(entries == [saved, next])
        precondition(entries[0].token == head.token && entries[0].driveScope == scope)
        precondition(entries[0].permitsTool("fixture-tool") && !entries[0].permitsTool("replaced-tool"))
        var resumed = entries[0]
        precondition(resumed.isUserPaused == paused && !entries[1].isUserPaused)
        resumed.isUserPaused = false
        precondition(resumed == head)

        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        for (entry, name) in zip(entries, ["Observatoire lunaire", "Jardin orbital"]) {
            vm.cloudLibrary.queue.append(.init(token: entry.token!, id: entry.id, name: name, action: entry.action,
                storage: entry.storage, scope: .init(title: "", urls: []), importDestination: nil,
                sourceFiles: nil, onSuccess: nil, driveScope: entry.driveScope, toolIdentity: entry.toolIdentity))
            vm.cloudLibrary.update(entry.id) { $0.action = entry.action; $0.queued = true }
        }
        var focus = ActivityCenterFocus()
        focus.selected = .queuedCloud(head.token!)
        let activity = ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: vm.cloudLibrary,
            focus: focus, onFocus: { _ in }, onOpen: { _ in }, onCancel: { _ in },
            onBack: {}, onOutside: {}).environment(\.nxAppLocale, fr)
        try render("activite-large-fr", output, activity, size: .init(width: 1440, height: 800))
        try render("activite-etroite-fr", output, activity, size: .init(width: 960, height: 600))
    }
'''


def main():
    output = capture_destination("cloud-queue-pause-captures-")
    output.mkdir(parents=True, exist_ok=True)
    # ImageRenderer draws neither the Activity list's ScrollView nor its lazy stack.
    host = (header() + "        ActivityCenterView.oortProbeRendersFlat = true\n" + SCENARIO
            + render().replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)"))
    for paused, phase in enumerate(("avant", "apres")):
        run_host(host, save_model=True, capture=output / phase, resources=(ICON,), package_name=package_name(),
                 environment={"OORT_QUEUE_PAUSED": str(paused)})
    for name in ("activite-large-fr.png", "activite-etroite-fr.png"):
        assert (output / "avant" / name).read_bytes() == (output / "apres" / name).read_bytes(), name
    print("Pause snapshot reopens with its original identity; French Activity screenshots are unchanged.")


if __name__ == "__main__":
    main()
