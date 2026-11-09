package dev.makakai.cruorsablecompat;

import java.lang.reflect.Method;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

import org.joml.Vector3f;

import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.phys.Vec3;

/**
 * Temporary visual bridge between Sable's physical ragdoll parts and the
 * server particle system. The source is deliberately reflection-only so this
 * addon does not bundle or link against Sable implementation classes.
 *
 * Cruor's native wound / blood-stain API will replace this visual fallback
 * after its exact 0.1.5-beta bytecode entry points have been verified.
 */
public final class RagdollBloodBridge {
    private static final DustParticleOptions BLOOD_DUST =
            new DustParticleOptions(new Vector3f(0.42F, 0.008F, 0.022F), 0.72F);

    private static final ConcurrentMap<String, Long> LAST_PARTICLE_TICK =
            new ConcurrentHashMap<>();

    private RagdollBloodBridge() {
    }

    /**
     * Called after Sable advances a player's or mob's ragdoll part.
     *
     * @param part the Sable part block entity
     * @param subLevel the Sable physical sublevel containing that part
     */
    public static void onPartPhysicsTick(BlockEntity part, Object subLevel) {
        if (part == null || subLevel == null || !(part.getLevel() instanceof ServerLevel level)) {
            return;
        }

        Object identity = invokeNoArgs(part, "ragdollIdentity");
        UUID sourceId = asUuid(invokeNoArgs(identity, "source"));
        if (sourceId == null) {
            sourceId = asUuid(invokeNoArgs(identity, "owner"));
        }

        long now = level.getGameTime();
        if (!BleedingTracker.isRecentlyDamaged(sourceId, now)) {
            return;
        }

        Object logicalPose = invokeNoArgs(subLevel, "logicalPose");
        if (logicalPose == null) {
            return;
        }

        Vec3 localPosition = Vec3.atCenterOf(part.getBlockPos());
        Vec3 worldPosition = transformPosition(logicalPose, localPosition);
        if (worldPosition == null) {
            return;
        }

        UUID subLevelId = asUuid(invokeNoArgs(subLevel, "getUniqueId"));
        String partKey = (subLevelId == null ? "unknown" : subLevelId.toString())
                + ":" + part.getBlockPos().asLong();

        Long previousTick = LAST_PARTICLE_TICK.putIfAbsent(partKey, now);
        if (previousTick != null) {
            if (now - previousTick < 4L) {
                return;
            }
            LAST_PARTICLE_TICK.put(partKey, now);
        }

        level.sendParticles(
                BLOOD_DUST,
                worldPosition.x,
                worldPosition.y + 0.04D,
                worldPosition.z,
                2,
                0.018D,
                0.012D,
                0.018D,
                0.012D
        );

        if (LAST_PARTICLE_TICK.size() > 2048) {
            LAST_PARTICLE_TICK.entrySet().removeIf(entry ->
                    now - entry.getValue() > 40L);
        }
    }

    private static Vec3 transformPosition(Object pose, Vec3 localPosition) {
        try {
            Method method = pose.getClass().getMethod("transformPosition", Vec3.class);
            Object result = method.invoke(pose, localPosition);
            return result instanceof Vec3 vec ? vec : null;
        } catch (ReflectiveOperationException | RuntimeException ignored) {
            return null;
        }
    }

    private static Object invokeNoArgs(Object target, String methodName) {
        if (target == null) {
            return null;
        }

        try {
            return target.getClass().getMethod(methodName).invoke(target);
        } catch (ReflectiveOperationException | RuntimeException ignored) {
            return null;
        }
    }

    private static UUID asUuid(Object value) {
        return value instanceof UUID uuid ? uuid : null;
    }
}
