import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun secret(propertyName: String, envName: String): String? =
    keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envName)?.takeIf { it.isNotBlank() }

val storeFileValue = secret("storeFile", "ANDROID_KEYSTORE_PATH")
val storePasswordValue = secret("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val keyAliasValue = secret("keyAlias", "ANDROID_KEY_ALIAS")
val keyPasswordValue = secret("keyPassword", "ANDROID_KEY_PASSWORD")

// Release signing needs the whole set. When any part is missing — a fork, a
// clean checkout, or CI without the keystore secrets — the release build falls
// back to debug signing so it still produces an installable APK.
val hasReleaseSigning =
    listOf(storeFileValue, storePasswordValue, keyAliasValue, keyPasswordValue)
        .none { it.isNullOrBlank() }

android {
    namespace = "com.sailrace.sail_race_computer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sailrace.sail_race_computer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = storeFileValue?.let { file(it) }
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Kotlin 2.4 removed the string-valued `android.kotlinOptions.jvmTarget`; the
// compilerOptions DSL is the replacement. Keep this in step with the Java
// sourceCompatibility/targetCompatibility above.
kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
