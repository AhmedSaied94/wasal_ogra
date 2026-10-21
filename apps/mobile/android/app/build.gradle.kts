plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wassalogra.app"
    // Platform levels: specs/001-m03-app-shell/research.md R1 (resolves mobile §24.1).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once uploaded to Google Play (owner decision, 2026-10-18).
        applicationId = "com.wassalogra.app"
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // AGP 9 turns resValue off by default; the flavors below use it for the launcher label.
    buildFeatures {
        resValues = true
    }

    // Build variants (mobile §21, research.md R15). dev and staging install side by side with prod.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "وصّل dev")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "وصّل staging")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "وصّل الأجرة")
        }
    }

    buildTypes {
        release {
            // Store signing is out of scope for M03. The debug key is enough for local
            // release-mode measurement on the reference device (quickstart.md).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Staging and prod bundle only a pack production promoted, so they refuse to build until one is
// committed. Dev bundles the sample instead (specs/006-m04-content-loader/contracts/bundling.md).
val checkBundledPack by tasks.registering {
    val record = rootProject.file("../assets/content/release/bundled.json")
    doLast {
        if (!record.exists()) {
            throw GradleException(
                "No promoted pack is bundled. Run wassal-content bundle release " +
                    "(docs/runbooks/content-publishing.md §3).",
            )
        }
    }
}

tasks.configureEach {
    if (Regex("pre(Staging|Prod)(Debug|Profile|Release)Build").matches(name)) {
        dependsOn(checkBundledPack)
    }
}
