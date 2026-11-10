# Building Cruor Sable Compat

## Supported build matrix

The declared minimum is **NeoForge 21.1.228**. This matches the NeoForge version used by Sable Ragdolls 0.7.2 to compile its 1.21.1 release. The CI matrix builds against 21.1.228 and 21.1.265 on Linux and Windows.

## One-click build

- Windows: run `build.bat`.
- Linux: run `./build.sh`.

The scripts are project-local launchers adapted from the automated build approach used by [Fiximizer](https://github.com/MAKAKAIglitch/Fiximizer).

### JDK selection

The builder looks for a complete JDK 21, not just a Java runtime. It checks:

- `JAVA_HOME`;
- Java/Javac on `PATH`;
- common Eclipse Adoptium and Oracle JDK directories;
- common Prism Launcher Java runtime directories.

If no matching JDK 21 is found, the builder downloads Eclipse Temurin 21 from the official Adoptium API. The archive is checked against the SHA-256 checksum published by Adoptium before extraction.

The fallback JDK is stored under `.tools/jdk-21-temurin`. It is local to this repository and does not change system Java settings or install system packages.

### Gradle

The repository includes a pinned Gradle Wrapper using Gradle 9.2.1. No separately installed Gradle is required. The wrapper distribution is downloaded from the official Gradle distribution host and verified with its pinned SHA-256 checksum.

Gradle's normal dependency and build caches are reused between builds.

## Preload dependencies for offline builds (Windows)

Run `preload-dependencies.bat` from the project root. The task:

- prepares the Minecraft/NeoForge development artifacts through ModDevGradle's `createMinecraftArtifacts` task;
- resolves the NeoForge runtime, compile, runtime, and test dependency configurations;
- places the downloaded artifacts in Gradle's normal persistent cache (normally `%USERPROFILE%\.gradle\caches`), shared with other Gradle projects on this Windows account.

The default local NeoForge version is **21.1.256**, matching Fiximizer's current build configuration. The mod continues to declare compatibility from **21.1.228** up to (but excluding) 21.2.

After the preloading task succeeds, run `build-offline.bat`. It invokes Gradle with `--offline`, so Gradle must use already cached artifacts and will not attempt Maven network access. If an artifact was not cached, Gradle reports its exact missing coordinate.

The preload command disables Gradle's configuration cache for this task because the local ModDevGradle `createMinecraftArtifacts` task reported a configuration-cache serialization problem in the supplied build log. Gradle's normal dependency and build caches remain enabled.

Preloading is not a manual copy of a single POM: Gradle needs the POM/module metadata, actual JARs, transitive dependencies, and Minecraft/NeoForge generated artifacts. Gradle stores and reuses those files in its own cache.

## Updating project sources

On Windows, run `update-sources.bat` from the project root to refresh the local source tree from the repository's `main` branch. Git is not required; the updater downloads the GitHub ZIP archive directly.

The updater verifies that both the local folder and downloaded archive identify this project through `mod_id=cruor_sable_compat`. Before replacing a changed source file, it saves the previous copy under `.cruor-sable-compat-backups/<timestamp>/`. Files removed from a later repository version are removed only when they were listed in a manifest from an earlier successful update, and they are backed up first.

The updater preserves `.git/`, `.tools/`, `.gradle/`, `.idea/`, `.vscode/`, `build/`, Minecraft instance data folders such as `mods/`, `config/`, `saves/`, and the local updater backup folder. The manifest and backups are excluded from Git.

**Note:** updating replaces changed tracked project files with the current version on GitHub. Keep local source edits in mind; their previous versions are backed up automatically.

## Manual build

With JDK 21 installed:

Windows:

```powershell
.\gradlew.bat build
```

Linux:

```sh
./gradlew build
```

The Java compiler uses `--release 21`, so the output remains Java 21 bytecode.

## Useful tasks

```text
build       Compile, process resources and package the mod
clean       Remove generated Gradle build output
runClient   Launch the NeoForge development client
runServer   Launch the NeoForge development server
```

The `runClient` and `runServer` tasks use the development runtime dependencies from Curse Maven. They do not change the contents or licensing of the published compatibility JAR.

## Output

`build/libs/cruor_sable_compat-0.1.0-alpha.jar`

The sources JAR is generated separately. Only the regular mod JAR should be placed in a Minecraft instance's `mods/` directory.

## Local files ignored by Git

- `.tools/`: project-local Temurin JDK and temporary download files;
- `.gradle/`: Gradle cache and configuration data;
- `build/`: generated classes, resources, JARs and reports;
- `run/` and `runs/`: development game directories.
