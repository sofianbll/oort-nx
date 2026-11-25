pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "oort-android"
include(":app")
// The phone library: the contract and its optional Google Drive connector. Only Oort Cloud, an app of its own, holds them.
include(":shelf", ":drive", ":cloud")
