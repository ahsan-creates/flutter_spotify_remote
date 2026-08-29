group = "com.spotifyappremote.spotify_app_remote"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.13.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.spotifyappremote.spotify_app_remote"
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 21
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.3.20")
    // Spotify authorization library — App Remote alone never yields a Web API
    // token, so OAuth runs through AuthorizationClient. Available on Maven
    // Central (unlike the App Remote .aar), and it contributes the
    // <queries> package-visibility entries Android 11+ requires.
    implementation("com.spotify.android:auth:5.0.0")
    // Spotify Android App Remote SDK (.aar) — user must download and place in android/libs/
    // See README for download instructions.
    compileOnly(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}
