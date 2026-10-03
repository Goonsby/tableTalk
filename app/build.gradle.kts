plugins { id("com.android.application") }

android {
    namespace = "org.tabletalk"
    compileSdk = 35
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "org.tabletalk"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild {
            cmake { arguments += listOf("-DANDROID_STL=c++_shared", "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON") }
        }
    }
    flavorDimensions += "network"
    productFlavors {
        create("setup") {
            dimension = "network"
            buildConfigField("boolean", "ALLOW_MODEL_DOWNLOAD", "true")
        }
        create("poco") {
            dimension = "network"
            applicationIdSuffix = ".poco"
            minSdk = 26
            versionCode = 10
            versionName = "0.2.0-poco"
            signingConfig = signingConfigs.getByName("debug")
            buildConfigField("boolean", "ALLOW_MODEL_DOWNLOAD", "true")
            externalNativeBuild {
                cmake { arguments += "-DTABLETALK_POCO=ON" }
            }
        }
        create("offline") {
            dimension = "network"
            versionCode = 2
            buildConfigField("boolean", "ALLOW_MODEL_DOWNLOAD", "false")
        }
    }
    // Setup/offline share an application ID for in-place provisioning updates.
    // POCO has its own ID and keeps network access for future model setup.
    buildFeatures { buildConfig = true }
    signingConfigs.getByName("debug") {
        // Cloud builds keep their development key inside the writable workspace.
        System.getenv("TABLETALK_DEBUG_KEYSTORE")?.let { storeFile = file(it) }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    externalNativeBuild {
        cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation("com.google.mlkit:translate:17.0.3")
}
