// Versions read on 2026-11-25 from developer.android.com (AGP, Compose BOM, activity), gradle.org and the Kotlin releases.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // AGP 9 carries Kotlin 2.2.10; this raises it to the current release (AGP 9 doc: "Upgrade to a higher KGP version").
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
    }
}

plugins {
    id("com.android.application") version "9.5.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21" apply false
}
