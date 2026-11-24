// Run as a headless executable inside a temporary app with the built app's Info.plist.
// Reading the actual defaults accessor catches startup failures hidden by unmarked unit-test hosts.
// This probe never runs the importer or writes preferences or launcher data.
import Foundation
import NXLibraryCore

try AppData.validateBuildIdentity(Bundle.main.infoDictionary ?? [:])
let defaults = AppData.preferences
precondition(defaults === UserDefaults.standard, "The distinct bundle ID must select the app's own preferences")
precondition(Bundle.main.bundleIdentifier == AppData.profile.preferencesDomain, "Preferences must belong to this profile")
let folder = AppData.profile.isTrial2 ? "NXLibrary-Development-Trial2" :
    AppData.profile.isDevelopment ? "NXLibrary-Development" : "NXLibrary"
precondition(AppData.supportRoot.lastPathComponent == folder)
precondition(AppData.cacheRoot.lastPathComponent == folder)
print("Packaged profile identity, preferences and roots verified without UI or data writes.")
