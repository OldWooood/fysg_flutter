pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9（Flutter 3.47 模板默认）；app 模块已迁移到 AGP 内置 Kotlin
    id("com.android.application") version "9.1.0" apply false
    // 兼容桥：audio_service / audio_session / just_audio / package_info_plus /
    // share_plus / wakelock_plus 等插件仍以 apply plugin 方式使用 KGP，
    // 需要此声明把 KGP 放进构建 classpath。待上游迁移到内置 Kotlin 后可移除。
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
