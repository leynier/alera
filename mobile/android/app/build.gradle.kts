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

// Read this at Project scope. Inside defaultConfig, findProperty hits the
// flavor extras and never sees -PaleraAbiFilters.
//
// The Flutter Gradle plugin's configureAbiWithoutSplits() then clears
// ndk.abiFilters and writes [armeabi-v7a, arm64-v8a, x86_64] whenever
// --split-per-abi is off. --target-platform only controls engine/app
// compilation, so plugin JNI for the other ABIs still lands in the APK.
// afterEvaluate plus jniLibs excludes keep the default APK arm64-only
// without dropping split builds or emulator flutter run.
val aleraAbiFilters = (findProperty("aleraAbiFilters") as String?)
    ?.split(',')
    ?.map(String::trim)
    ?.filter(String::isNotEmpty)
    .orEmpty()
val aleraExcludedJniAbis = listOf("armeabi", "armeabi-v7a", "x86", "x86_64", "arm64-v8a")
    .filter { it !in aleraAbiFilters }

android {
    namespace = "dev.leynier.alera_mobile"
    // Secure storage v11 needs API 37; device support and target behavior stay unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // AGP 8 omits v1 when minSdk >= 24. Sideload installers on several
        // OEMs still look for the JAR signature and reject a v2-only APK
        // with a generic "App not installed".
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        if (releaseSigningAvailable) {
            val keystoreProperties = Properties()
            keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(
                    System.getenv("ALERA_ANDROID_KEYSTORE")
                        ?: keystoreProperties.getProperty("storeFile"),
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
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
        if (aleraAbiFilters.isNotEmpty()) {
            ndk {
                abiFilters += aleraAbiFilters
            }
        }
    }

    packaging {
        jniLibs {
            if (aleraAbiFilters.isNotEmpty()) {
                for (abi in aleraExcludedJniAbis) {
                    excludes += "lib/$abi/**"
                }
            }
        }
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

afterEvaluate {
    if (aleraAbiFilters.isNotEmpty()) {
        android.defaultConfig.ndk {
            abiFilters.clear()
            abiFilters.addAll(aleraAbiFilters)
        }
        println("INFO: packaging only ${aleraAbiFilters.joinToString()} native libraries")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
