import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI and local tests remain buildable before the Firebase project exists.
// A real google-services.json enables the native resource path; dart defines
// documented in mobile/readme.md provide the configuration otherwise.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing uses key.properties (gitignored). CI writes it from secrets;
// locally, release builds fall back to the debug key so `flutter run --release`
// keeps working. APKs signed with different keys cannot update in place, so CI
// must always use the release key. ALERA_ANDROID_KEYSTORE can override the
// keystore path for CI.
val keystorePropertiesFile = rootProject.file("key.properties")
val releaseSigningAvailable = keystorePropertiesFile.exists()

android {
    namespace = "dev.leynier.alera_mobile"
    // Secure storage v11 needs API 37; device support and target behavior stay unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    if (releaseSigningAvailable) {
        val keystoreProperties = Properties()
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(
                    System.getenv("ALERA_ANDROID_KEYSTORE")
                        ?: keystoreProperties.getProperty("storeFile"),
                )
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.leynier.alera_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningAvailable) {
                signingConfigs.getByName("release")
            } else {
                println("INFO: key.properties not found; signing release with the debug key. APKs signed this way cannot update over release-signed installs.")
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
