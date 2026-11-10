package dev.makakai.cruorsablecompat;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import org.joml.Vector3f;

import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.phys.Vec3;

/**
 * Compatibility bridge for Sable's server-side physics ticks.
 *
 * Sable 0.7.2 exposes player skinProfile() and mob sourceEntityId().
 * Later builds may additionally expose RagdollBlockIdentity. Reflection keeps
 * the addon binary independent from Sable's implementation classes.
 *
 * The red-dust emitter is a temporary visual fallback. It is not Cruor's
 * native wound / droplet / stain pipeline.
 */
public final class RagdollBloodBridge {
    private static final DustParticleOptions BLOOD_DUST =
            new DustParticleOptions(new Vector3f(0.42F, 0.008F, 0.022F), 0.72F);

    private static final long PARTICLE_INTERVAL_TICKS = 8L;
    private static final long SOURCE_RETENTION_TICKS = 1200L;
    private static final long PARTICLE_CACHE_RETENTION_TICKS = 200L;
    private static final long CLEANUP_INTERVAL_TICKS = 200L;

    /*
     * Cache reflective lookups once per runtime class. ClassValue avoids
     * pinning classes from optional mod classloaders in a global static map.
     */
    private static final ClassValue<Map<String, Method>> NO_ARG_METHODS = new ClassValue<>() {
        @Override
        protected Map<String, Method> computeValue(Class<?> type) {
            Map<String, Method> methods = new HashMap<>();
            for (Method method : type.getMethods()) {
                if (method.getParameterCount() == 0) {
                    methods.putIfAbsent(method.getName(), method);
                }
            }
            return Map.copyOf(methods);
        }
    };

    private static final ClassValue<Map<String, Method>> STRING_ARG_METHODS = new ClassValue<>() {
        @Override
        protected Map<String, Method> computeValue(Class<?> type) {
            Map<String, Method> methods = new HashMap<>();
            for (Method method : type.getMethods()) {
                if (method.getParameterCount() == 1
                        && method.getParameterTypes()[0] == String.class) {
                    methods.putIfAbsent(method.getName(), method);
                }
            }
            return Map.copyOf(methods);
        }
    };

    private static final ClassValue<Optional<Method>> VEC3_TRANSFORM_METHOD = new ClassValue<>() {
        @Override
        protected Optional<Method> computeValue(Class<?> type) {
            try {
                return Optional.of(type.getMethod("transformPosition", Vec3.class));
            } catch (NoSuchMethodException | SecurityException ignored) {
                return Optional.empty();
            }
        }
    };

    private static final ConcurrentMap<PartKey, Long> LAST_PARTICLE_TICK =
            new ConcurrentHashMap<>();

    // Keeps source UUIDs available briefly after Sable detaches or clears a part.
    private static final ConcurrentMap<UUID, SourceRecord> SOURCE_BY_PART =
            new ConcurrentHashMap<>();

    private static final AtomicLong LAST_CLEANUP_TICK = new AtomicLong(Long.MIN_VALUE);
    private static final ConcurrentMap<String, Boolean> REPORTED_DIAGNOSTICS =
            new ConcurrentHashMap<>();
    private static final ConcurrentMap<String, Boolean> REPORTED_PART_CLASSES =
            new ConcurrentHashMap<>();
    private static final AtomicBoolean FIRST_PARTICLE_EMITTED = new AtomicBoolean();

    private RagdollBloodBridge() {
    }

    /**
     * Called from the tail of Sable's player or mob part physics tick.
     *
     * @param part the Sable part block entity
     * @param subLevel the physical sublevel containing that part
     */
    public static void onPartPhysicsTick(BlockEntity part, Object subLevel) {
        if (part == null || subLevel == null || !(part.getLevel() instanceof ServerLevel level)) {
            return;
        }

        String partClassName = part.getClass().getName();
        if (REPORTED_PART_CLASSES.putIfAbsent(partClassName, Boolean.TRUE) == null) {
            CruorSableCompat.LOGGER.info(
                    "[Cruor Sable Compat] Sable ragdoll physics hook reached for part class {}.",
                    partClassName
            );
        }

        long now = level.getGameTime();
        UUID partId = asUuid(invokeNoArgs(subLevel, "getUniqueId"));
        Object identity = invokeNoArgs(part, "ragdollIdentity");
        UUID liveSourceId = resolveSourceId(part, identity);
        UUID sourceId = resolveSourceIdFromCache(partId, liveSourceId, now);

        if (sourceId == null) {
            warnOnce(
                    "source-id:" + partClassName,
                    "Could not resolve a source entity UUID for Sable part class {}. Known player, mob and ragdoll identity accessors were checked; this can indicate an API mismatch or an identity that is not initialized yet.",
                    partClassName
            );
            return;
        }

        if (!BleedingTracker.isRecentlyDamaged(sourceId, now)) {
            return;
        }

        Object logicalPose = invokeNoArgs(subLevel, "logicalPose");
        if (logicalPose == null) {
            warnOnce(
                    "logical-pose:" + subLevel.getClass().getName(),
                    "Sable sublevel class {} returned no logicalPose(); the ragdoll particle position cannot be calculated.",
                    subLevel.getClass().getName()
            );
            return;
        }

        Vec3 worldPosition = transformPosition(
                logicalPose,
                Vec3.atCenterOf(part.getBlockPos())
        );
        if (worldPosition == null) {
            return;
        }

        PartKey key = new PartKey(partId, part.getBlockPos().asLong());
        if (!shouldEmitParticle(key, now)) {
            return;
        }

        // One small particle per physical part every eight game ticks.
        // No client-side entity scans, per-tick random allocation or timers.
        level.sendParticles(
                BLOOD_DUST,
                worldPosition.x,
                worldPosition.y + 0.04D,
                worldPosition.z,
                1,
                0.012D,
                0.008D,
                0.012D,
                0.008D
        );

        if (FIRST_PARTICLE_EMITTED.compareAndSet(false, true)) {
            CruorSableCompat.LOGGER.info(
                    "[Cruor Sable Compat] First compatibility blood particle emitted successfully."
            );
        }

        cleanupCachesOccasionally(now);
    }

    private static UUID resolveSourceIdFromCache(UUID partId, UUID liveSourceId, long now) {
        if (partId == null) {
            return liveSourceId;
        }

        if (liveSourceId != null) {
            SourceRecord cached = SOURCE_BY_PART.get(partId);
            if (cached == null
                    || !liveSourceId.equals(cached.sourceId())
                    || isExpired(cached.lastSeenTick(), now, SOURCE_RETENTION_TICKS)
                    || now - cached.lastSeenTick() >= CLEANUP_INTERVAL_TICKS) {
                SOURCE_BY_PART.put(partId, new SourceRecord(liveSourceId, now));
            }
            return liveSourceId;
        }

        SourceRecord cached = SOURCE_BY_PART.get(partId);
        if (cached == null) {
            return null;
        }

        if (isExpired(cached.lastSeenTick(), now, SOURCE_RETENTION_TICKS)) {
            SOURCE_BY_PART.remove(partId, cached);
            return null;
        }

        return cached.sourceId();
    }

    private static UUID resolveSourceId(BlockEntity part, Object identity) {
        // Sable 0.7.2 player parts retain their original GameProfile.
        Object profile = invokeNoArgs(part, "skinProfile");
        UUID profileId = asUuid(invokeNoArgs(profile, "getId"));
        if (profileId != null) {
            return profileId;
        }

        // Sable 0.7.2 mob parts expose the original entity UUID directly.
        UUID mobSourceId = asUuid(invokeNoArgs(part, "sourceEntityId"));
        if (mobSourceId != null) {
            return mobSourceId;
        }

        // Compatibility with later Sable versions using persistent identities.
        UUID source = asUuid(invokeNoArgs(identity, "source"));
        if (source != null) {
            return source;
        }

        Object session = invokeNoArgs(identity, "session");
        if (session == null) {
            return null;
        }

        Object hasPlayerId = invokeStringArg(session, "hasUUID", "playerId");
        if (!Boolean.TRUE.equals(hasPlayerId)) {
            return null;
        }

        return asUuid(invokeStringArg(session, "getUUID", "playerId"));
    }

    private static boolean shouldEmitParticle(PartKey key, long now) {
        Long previous = LAST_PARTICLE_TICK.putIfAbsent(key, now);
        if (previous == null) {
            return true;
        }

        long elapsed = now - previous;
        if (elapsed >= 0L && elapsed < PARTICLE_INTERVAL_TICKS) {
            return false;
        }

        // Compare-and-replace makes the throttle safe if physics ticks are concurrent.
        return LAST_PARTICLE_TICK.replace(key, previous, now);
    }

    private static Vec3 transformPosition(Object pose, Vec3 localPosition) {
        Class<?> poseClass = pose.getClass();
        Optional<Method> optional = VEC3_TRANSFORM_METHOD.get(poseClass);
        if (optional.isEmpty()) {
            warnOnce(
                    "pose-method:" + poseClass.getName(),
                    "Sable pose class {} does not expose transformPosition(Vec3); the ragdoll particle position cannot be calculated.",
                    poseClass.getName()
            );
            return null;
        }

        try {
            Object result = optional.get().invoke(pose, localPosition);
            if (result instanceof Vec3 vec) {
                return vec;
            }

            warnOnce(
                    "pose-result:" + poseClass.getName(),
                    "Sable pose class {} returned {} from transformPosition(Vec3), expected Vec3.",
                    poseClass.getName(),
                    result == null ? "null" : result.getClass().getName()
            );
            return null;
        } catch (ReflectiveOperationException | RuntimeException exception) {
            warnFailureOnce(
                    "pose-invoke:" + poseClass.getName(),
                    "Could not invoke transformPosition(Vec3) on {}.",
                    poseClass,
                    exception
            );
            return null;
        }
    }

    private static Object invokeNoArgs(Object target, String methodName) {
        if (target == null) {
            return null;
        }

        Method method = NO_ARG_METHODS.get(target.getClass()).get(methodName);
        if (method == null) {
            return null;
        }

        try {
            return method.invoke(target);
        } catch (ReflectiveOperationException | RuntimeException ignored) {
            return null;
        }
    }

    private static Object invokeStringArg(Object target, String methodName, String value) {
        if (target == null) {
            return null;
        }

        Method method = STRING_ARG_METHODS.get(target.getClass()).get(methodName);
        if (method == null) {
            return null;
        }

        try {
            return method.invoke(target, value);
        } catch (ReflectiveOperationException | RuntimeException ignored) {
            return null;
        }
    }

    private static void cleanupCachesOccasionally(long now) {
        long previous = LAST_CLEANUP_TICK.get();
        if (previous != Long.MIN_VALUE && now >= previous
                && now - previous < CLEANUP_INTERVAL_TICKS) {
            return;
        }

        if (!LAST_CLEANUP_TICK.compareAndSet(previous, now)) {
            return;
        }

        LAST_PARTICLE_TICK.entrySet().removeIf(entry ->
                isExpired(entry.getValue(), now, PARTICLE_CACHE_RETENTION_TICKS));

        SOURCE_BY_PART.entrySet().removeIf(entry ->
                isExpired(entry.getValue().lastSeenTick(), now, SOURCE_RETENTION_TICKS));
    }

    private static void warnOnce(String key, String message, Object... arguments) {
        if (REPORTED_DIAGNOSTICS.putIfAbsent(key, Boolean.TRUE) == null) {
            CruorSableCompat.LOGGER.warn("[Cruor Sable Compat] " + message, arguments);
        }
    }

    private static void warnFailureOnce(
            String key,
            String message,
            Class<?> targetClass,
            Throwable exception
    ) {
        if (REPORTED_DIAGNOSTICS.putIfAbsent(key, Boolean.TRUE) == null) {
            CruorSableCompat.LOGGER.warn(
                    "[Cruor Sable Compat] " + message,
                    targetClass.getName(),
                    exception
            );
        }
    }

    private static boolean isExpired(long previousTick, long now, long retentionTicks) {
        long age = now - previousTick;
        return age < 0L || age > retentionTicks;
    }

    private static UUID asUuid(Object value) {
        return value instanceof UUID uuid ? uuid : null;
    }

    private record PartKey(UUID subLevelId, long blockPos) {
    }

    private record SourceRecord(UUID sourceId, long lastSeenTick) {
    }
}
