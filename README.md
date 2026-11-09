# Cruor × Sable Compat

Unofficial NeoForge compatibility addon for **Minecraft 1.21.1**.

The project connects Sable's physics-driven ragdoll parts to bleeding effects while keeping both original mods installed and unmodified.

## Current status

**0.1.0-alpha — physics-side prototype**

- Hooks the server physics tick of Sable player and mob ragdoll parts.
- Reads the physical part's world position from Sable's `logicalPose`.
- Associates a ragdoll part with its original living entity UUID.
- Tracks recent real damage and emits dark-red particles from the corresponding moving ragdoll parts.
- Uses optional Mixin targets so a missing Sable class does not hard-crash unrelated environments.

**Important:** this first prototype uses Minecraft's red dust particle as a temporary bleeding visual. It does **not** yet invoke Cruor's private wound, droplet, stain, or blood-pool pipeline. Cruor's published file is All Rights Reserved and its binary could not be retrieved in this environment for bytecode inspection. The native Cruor bridge is the next implementation milestone; no Cruor code is copied into this project.

## Target setup

| Component | Target |
|---|---|
| Minecraft | 1.21.1 |
| Mod loader | NeoForge 21.1.x |
| Java | 21 |
| Sable: Ragdolls | 0.7.2 (the public 1.21.1 CurseForge release) |
| Cruor | 0.1.5-beta (1.21.1 NeoForge) |

The build resolves the two mods from Curse Maven for local development. Neither mod is bundled into the published compatibility JAR.

## Build

Install JDK 21 and Gradle 8.12 or newer, then run:

```powershell
gradle build
```

The distributable JAR is written to `build/libs/`.

## What comes next

1. Inspect the exact Cruor 0.1.5-beta bytecode and identify its bleeding / droplet / stain entry points.
2. Replace the temporary red-dust emitter with calls into Cruor's existing effect pipeline.
3. Preserve per-wound bleeding state across Sable's player and mob ragdoll conversion.
4. Verify severed limbs, server synchronization, and cleanup when a ragdoll despawns.

## License

This repository's original code is MIT-licensed. Cruor and Sable remain separate third-party dependencies and retain their own licenses. No third-party source code is copied into this repository.
