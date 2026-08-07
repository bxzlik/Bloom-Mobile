import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ подписи релиза описан в android/key.properties (в git его нет — см.
// android/.gitignore). Файла нет — релиз подписывается отладочным ключом, как в
// шаблоне Flutter: локальная сборка `flutter build apk --release` работает без
// всякой настройки, а настоящий ключ нужен только тому, кто раздаёт APK.
//
// ВАЖНО про отладочный ключ: он генерируется на каждой машине свой (а в CI —
// заново на каждый запуск), поэтому APK из разных сборок не ставятся друг
// поверх друга — Android считает их приложениями от разных авторов.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreFile.inputStream().use(keystoreProperties::load)
}
val releaseKey: String? = keystoreProperties.getProperty("storeFile")

android {
    namespace = "com.bxzlik.bloom"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.bxzlik.bloom"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKey != null) {
            create("release") {
                // Путь считается от папки android/ — так же, как key.properties.
                // Абсолютный путь тоже подойдёт.
                storeFile = rootProject.file(releaseKey)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKey != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
