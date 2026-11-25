// Oort Cloud: the optional cloud library, an app of its own so that Oort NX keeps asking Android for nothing.
plugins {
    id("com.android.application")
}

android {
    namespace = "io.github.sofianbll.oortnx.cloud"
    compileSdk {
        version = release(37) { minorApiLevel = 1 }
    }

    defaultConfig {
        applicationId = "io.github.sofianbll.oortnx.alpha.cloud"
        minSdk = 29
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.0-alpha.2"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
        // The release with a stand-in for Google on the machine that runs the checks. Never published.
        create("check") {
            initWith(getByName("release"))
            signingConfig = null
            matchingFallbacks += "release"
        }
    }
}

dependencies {
    implementation(project(":shelf"))
    implementation(project(":drive"))
    implementation("com.google.zxing:core:3.5.4")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.4.21")
}
