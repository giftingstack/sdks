plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    `maven-publish`
    signing
}

group = "com.giftingstack"
version = "0.1.0"

// The conformance fixtures live in the sibling package packages/sdk-spec. They are used by the tests
// only; a checkout without that folder still builds and publishes the library.
val specDir: File = rootProject.projectDir.resolve("../sdk-spec")

android {
    namespace = "com.giftingstack"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            all {
                if (specDir.exists()) {
                    it.systemProperty("giftingstack.spec.dir", specDir.canonicalPath)
                    // Without this Gradle replays a cached test result when only a fixture changed.
                    it.inputs.dir(specDir.resolve("conformance")).withPropertyName("conformanceFixtures")
                    it.inputs.file(specDir.resolve("recipes.json")).withPropertyName("recipesJson")
                }
            }
        }
    }

    sourceSets {
        // The picture-gate fixture is read from the shared spec on the device too (androidTest only).
        if (specDir.exists()) getByName("androidTest").assets.srcDir(specDir.resolve("conformance"))
    }

    publishing {
        // One variant, with its sources and Javadoc jars; the POM is filled in below.
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }

    lint {
        abortOnError = true
        warningsAsErrors = false
        // AGP writes local.properties itself with an unescaped Windows path (git-ignored, Windows only).
        disable += "PropertyEscape"
    }
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // The public API shows these types (Modifier, Dp, Color, ImageBitmap, JsonObject, StateFlow), so an
    // app that depends on the library sees them without declaring them itself.
    api(platform(libs.compose.bom))
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
    api(libs.compose.ui)
    api(libs.compose.ui.graphics)
    api(libs.compose.foundation)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.lifecycle.runtime.compose)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)

    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.kotlinx.coroutines.test)
    debugImplementation(libs.compose.ui.test.manifest)
}

// Publishing (not run by the tests): `./gradlew :giftingstack:publishReleasePublicationToMavenLocal` for a
// local check. The coordinates are com.giftingstack:giftingstack:0.1.0. Releasing to Maven Central needs
// the signing key and the repository credentials from the environment; nothing is published from CI yet.
afterEvaluate {
    publishing {
        publications {
            register<MavenPublication>("release") {
                from(components["release"])
                groupId = "com.giftingstack"
                artifactId = "giftingstack"
                version = "0.1.0"
                pom {
                    name.set("GiftingStack Android SDK")
                    description.set(
                        "Gift tray, effects, gift wall, inbox, leaderboard and live gift rooms for Jetpack Compose apps that use the GiftingStack virtual gifting API.",
                    )
                    url.set("https://giftingstack.com")
                    licenses {
                        license {
                            name.set("MIT License")
                            url.set("https://opensource.org/licenses/MIT")
                            distribution.set("repo")
                        }
                    }
                    developers {
                        developer {
                            id.set("giftingstack")
                            name.set("GiftingStack")
                            url.set("https://giftingstack.com")
                        }
                    }
                    scm {
                        url.set("https://github.com/giftingstack/sdks")
                        connection.set("scm:git:https://github.com/giftingstack/sdks.git")
                        developerConnection.set("scm:git:ssh://git@github.com/giftingstack/sdks.git")
                    }
                }
            }
        }
        repositories {
            // Set MAVEN_REPO_URL (and the credentials) to release; without it only mavenLocal is used.
            System.getenv("MAVEN_REPO_URL")?.let { repoUrl ->
                maven {
                    name = "release"
                    url = uri(repoUrl)
                    credentials {
                        username = System.getenv("MAVEN_USERNAME")
                        password = System.getenv("MAVEN_PASSWORD")
                    }
                }
            }
        }
    }
}

signing {
    val key = System.getenv("SIGNING_KEY")
    val password = System.getenv("SIGNING_PASSWORD")
    // Sign only when a key is given (a release); local builds and the tests are unsigned.
    isRequired = false
    if (key != null) {
        useInMemoryPgpKeys(key, password)
        afterEvaluate { sign(publishing.publications) }
    }
}
