plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "io.github.sofianbll.oortnx"
    // Compose 1.13's AndroidX libraries ask for API 37.1 (found by the first build); AGP 9.5 supports up to 37.
    compileSdk {
        version = release(37) { minorApiLevel = 1 }
    }

    defaultConfig {
        // The alpha sits beside a later release: the final identifier stays free.
        applicationId = "io.github.sofianbll.oortnx.alpha"
        minSdk = 29      // nx2android's own minimum (mkapk.py MIN_SDK): a launcher for its games needs no more
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0-alpha.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.11.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.13.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.4.21")
}
