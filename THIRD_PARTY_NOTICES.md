# Third-party notices

This file identifies upstream projects and build tooling used by Cruor Sable Compat. The project's MIT license applies to original compatibility code only; it does not change the licenses or ownership of third-party software.

## Upstream Minecraft mods

### Cruor

- Project: [Cruor on CurseForge](https://www.curseforge.com/minecraft/mc-mods/cruor)
- Author: **Raiiiden**
- Development file: [cruor-neoforge-1.21.1-0.1.5-beta.jar](https://www.curseforge.com/minecraft/mc-mods/cruor/files/9484422)
- CurseForge file ID: `9484422`

Cruor remains the property of its author. No Cruor source, compiled classes, textures, models, sounds, logos, or JAR files are copied into this repository or embedded in the compatibility JAR. The Curse Maven coordinate is used only for the local development runtime.

### Sable: Ragdolls

- Project: [Sable: Ragdolls on CurseForge](https://www.curseforge.com/minecraft/mc-mods/sable-ragdolls)
- Author: **leonardoinc22** (GitHub: [Leo-T22](https://github.com/Leo-T22))
- Source repository: [sable-player-ragdoll](https://github.com/Leo-T22/sable-player-ragdoll)
- Development target: 0.7.2, Minecraft 1.21.1; upstream build baseline: NeoForge 21.1.228
- CurseForge development file ID: `8295399`

The upstream source repository declares its code as **All Rights Reserved** and says not to redistribute it. This project does not copy or package Sable source code. It uses runtime mixin targets and reflective access to the methods needed for compatibility. Sable remains a separately installed dependency.

## Automated builder

The project-local automated builder follows the JDK detection, project-local Temurin fallback, SHA-256 verification and Gradle Wrapper approach used by:

- [Fiximizer](https://github.com/MAKAKAIglitch/Fiximizer) — Copyright © 2026 MAKAKAIglitch, MIT License.
- Fiximizer's [BUILDING.md](https://github.com/MAKAKAIglitch/Fiximizer/blob/main/BUILDING.md) records the upstream builder ancestry from [Rusify](https://github.com/MAKAKAIglitch/Rusify), also MIT-licensed.

The builder scripts in this repository are adapted for this mod's Java 21 / NeoForge build. They do not include Fiximizer's or Rusify's mod implementation, native backend, or unrelated project assets.

## Gradle Wrapper

The Gradle Wrapper scripts and wrapper JAR are generated/distributed by the Gradle project and are licensed under the **Apache License, Version 2.0**. The standard Gradle copyright and license headers are retained in the wrapper scripts. See [Gradle's license](https://github.com/gradle/gradle/blob/master/LICENSE).

## Build and runtime dependencies

Minecraft, NeoForge, SpongePowered Mixin, Gradle, ModDevGradle, Curse Maven, Eclipse Temurin and any other dependency retain their respective trademarks, copyrights and licenses. They are not relicensed by this project.

## Affiliation

Cruor Sable Compat is an unofficial community project. It is not affiliated with or endorsed by Raiiiden, leonardoinc22, Mojang, Microsoft, NeoForge or CurseForge.
