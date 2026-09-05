import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun String.asBuildConfigString(): String =
    "\"" + replace("\\", "\\\\").replace("\"", "\\\"") + "\""

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) FileInputStream(file).use(::load)
}

fun privateBuildInput(name: String): String = providers
    .gradleProperty(name)
    .orElse(providers.environmentVariable(name))
    .orElse(localProperties.getProperty(name, ""))
    .get()

val telegramChannelUrl = privateBuildInput("NIRANG_TELEGRAM_URL")
val telegramContact = privateBuildInput("NIRANG_TELEGRAM_CONTACT")
val apiSpkiPins = privateBuildInput("NIRANG_API_SPKI_PINS").ifBlank {
    "sha256/Z8Ka2UpwypbfyfVFuSq2isahaWuwvepB3/4oxi5achg=,sha256/nWN7PSep5XDQdge5zK24CnCRXHr3KvzhKEGxsdqCX9E="
}
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use(::load)
}

android {
    namespace = "dev.nirang.client"
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
        applicationId = "dev.nirang.client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "TELEGRAM_URL", telegramChannelUrl.asBuildConfigString())
        buildConfigField("String", "TELEGRAM_CONTACT", telegramContact.asBuildConfigString())
        buildConfigField("String", "API_SPKI_PINS", apiSpkiPins.asBuildConfigString())
    }

    buildFeatures {
        buildConfig = true
    }

    sourceSets {
        getByName("test").resources.srcDir("src/main/assets")
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/libv2ray.aar"))
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.work:work-runtime-ktx:2.10.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}

tasks.withType<org.gradle.api.tasks.testing.Test>().configureEach {
    systemProperty("nirang.libv2ray.aar", file("libs/libv2ray.aar").absolutePath)
}
