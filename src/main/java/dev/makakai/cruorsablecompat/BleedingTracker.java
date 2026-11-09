package dev.makakai.cruorsablecompat;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;

@EventBusSubscriber(modid = CruorSableCompat.MOD_ID, bus = EventBusSubscriber.Bus.GAME)
public final class BleedingTracker {
    private static final long BLEED_WINDOW_TICKS = 160L;
    private static final Map<UUID, Long> LAST_DAMAGE_TICK = new ConcurrentHashMap<>();

    private BleedingTracker() {
    }

    @SubscribeEvent
    public static void onLivingDamage(LivingDamageEvent.Post event) {
        LivingEntity entity = event.getEntity();
        if (!(entity.level() instanceof ServerLevel level)) {
            return;
        }

        // Post is fired after health is modified. Armor, shields and absorption
        // may reduce the hit to zero actual health damage.
        if (event.getNewDamage() <= 0.0F) {
            return;
        }

        LAST_DAMAGE_TICK.put(entity.getUUID(), level.getGameTime());

        if (LAST_DAMAGE_TICK.size() > 4096) {
            long now = level.getGameTime();
            LAST_DAMAGE_TICK.entrySet().removeIf(entry ->
                    now - entry.getValue() > BLEED_WINDOW_TICKS);
        }
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
}
