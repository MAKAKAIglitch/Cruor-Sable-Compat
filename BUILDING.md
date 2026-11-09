# Building Cruor Sable Compat

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
