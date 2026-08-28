plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "opensource.jmtt2mic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Independent data/signing identity: this build coexists with upstream.
        applicationId = "opensource.jasmine.local"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = "${flutter.versionName}-local"
    }

    val ciSigningStore = System.getenv("ANDROID_SIGNING_STORE_FILE")
    if (ciSigningStore != null) {
        signingConfigs {
            create("ciRelease") {
                storeFile = file(ciSigningStore)
                storePassword = System.getenv("ANDROID_SIGNING_STORE_PASSWORD")
                    ?: error("Missing CI signing store password")
                keyAlias = System.getenv("ANDROID_SIGNING_KEY_ALIAS")
                    ?: error("Missing CI signing key alias")
                keyPassword = System.getenv("ANDROID_SIGNING_KEY_PASSWORD")
                    ?: error("Missing CI signing key password")
            }
        }
    }

    buildTypes {
        release {
            // CI uses a stable repository secret; local builds keep their own key.
            signingConfig = signingConfigs.getByName(if (ciSigningStore != null) "ciRelease" else "debug")
        }
    }

    packaging {
        jniLibs {
            // Rust controls stripping; preserve an exact hash match to our build.
            keepDebugSymbols += "**/librust.so"
        }
    }
}

flutter {
    source = "../.."
}
