// How a phone reads the Mac's library, whatever holds it: no network, no permission, no Android class.
plugins {
    id("com.android.library")
}

android {
    namespace = "io.github.sofianbll.oortnx.shelf"
    compileSdk {
        version = release(37) { minorApiLevel = 1 }
    }
    defaultConfig { minSdk = 29 }
}
