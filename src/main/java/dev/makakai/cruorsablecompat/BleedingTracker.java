package dev.makakai.cruorsablecompat;

import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicLong;

import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;

@EventBusSubscriber(modid = CruorSableCompat.MOD_ID, bus = EventBusSubscriber.Bus.GAME)
public final class BleedingTracker {
    private static final long BLEED_WINDOW_TICKS = 160L;
    private static final long CLEANUP_INTERVAL_TICKS = 128L;

    private static final ConcurrentMap<UUID, Long> LAST_DAMAGE_TICK =
            new ConcurrentHashMap<>();
    private static final AtomicLong LAST_CLEANUP_TICK =
            new AtomicLong(Long.MIN_VALUE);

    private BleedingTracker() {
    }

    @SubscribeEvent
    public static void onLivingDamage(LivingDamageEvent.Post event) {
        LivingEntity entity = event.getEntity();
        if (!(entity.level() instanceof ServerLevel level)) {
            return;
        }

        // Post is fired after health is modified. Absorbed or blocked hits
        // which remove no health do not start the bleeding window.
        if (event.getNewDamage() <= 0.0F) {
            return;
        }

        long now = level.getGameTime();
        LAST_DAMAGE_TICK.put(entity.getUUID(), now);
        cleanupOccasionally(now);
    }

    public static boolean isRecentlyDamaged(UUID sourceId, long gameTime) {
        if (sourceId == null) {
            return false;
        }

        Long lastDamage = LAST_DAMAGE_TICK.get(sourceId);
        if (lastDamage == null) {
            return false;
        }

        long age = gameTime - lastDamage;
        if (age < 0L || age > BLEED_WINDOW_TICKS) {
            LAST_DAMAGE_TICK.remove(sourceId, lastDamage);
            return false;
        }

        return true;
    }

    private static void cleanupOccasionally(long now) {
        long previous = LAST_CLEANUP_TICK.get();
        if (previous != Long.MIN_VALUE && now >= previous
                && now - previous < CLEANUP_INTERVAL_TICKS
                && LAST_DAMAGE_TICK.size() <= 4096) {
            return;
        }

        if (!LAST_CLEANUP_TICK.compareAndSet(previous, now)) {
            return;
        }

        LAST_DAMAGE_TICK.entrySet().removeIf(entry -> {
            long age = now - entry.getValue();
            return age < 0L || age > BLEED_WINDOW_TICKS;
        });
    }
}
