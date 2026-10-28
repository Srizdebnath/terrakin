allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// privy_flutter 0.11.0 pins compileSdk 34, but its androidx.credentials 1.5.0
// dependency needs 35+. Raise every plugin module to the app's level.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            if ((compileSdk ?: 0) < 36) compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
