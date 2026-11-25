// The optional Google Drive connector. The app does not depend on it yet: its manifest is the only one that asks for the network.
plugins {
    id("com.android.library")
}

android {
    namespace = "io.github.sofianbll.oortnx.drive"
    compileSdk {
        version = release(37) { minorApiLevel = 1 }
    }
    defaultConfig { minSdk = 29 }
}

dependencies {
    implementation(project(":shelf"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.4.21")
}

tasks.withType<Test>().configureEach {
    val cases = rootProject.projectDir.resolve("../Tests/PhoneLibrary")
    inputs.dir(cases)
    systemProperty("oort.cases", cases.canonicalPath)
}
