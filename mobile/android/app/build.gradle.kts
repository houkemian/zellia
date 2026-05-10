plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = file("../key.properties")
val keystoreProperties: Map<String, String> =
    if (!keystorePropertiesFile.exists()) {
        emptyMap()
    } else {
        keystorePropertiesFile
            .readLines()
            .mapNotNull { raw ->
                val line = raw.trim()
                if (line.isEmpty() || line.startsWith("#")) return@mapNotNull null
                val eq = line.indexOf('=')
                if (eq < 1) return@mapNotNull null
                val key = line.substring(0, eq).trim()
                val value = line.substring(eq + 1).trim()
                key to value
            }
            .toMap()
    }
val keystoreConfigured = keystoreProperties.isNotEmpty()

android {
    namespace = "one.dothings.zellia"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "one.dothings.zellia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreConfigured) {
                keyAlias = keystoreProperties.getValue("keyAlias")
                keyPassword = keystoreProperties.getValue("keyPassword")
                storeFile = file(keystoreProperties.getValue("storeFile"))
                storePassword = keystoreProperties.getValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystoreConfigured) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    jvmToolchain(21)
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))
    implementation("com.google.firebase:firebase-analytics")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
