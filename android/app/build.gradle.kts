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

    buildTypes {
        release {
            // Local test artifact only. Publishing requires your own release key.
            signingConfig = signingConfigs.getByName("debug")
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
