package dev.makakai.cruorsablecompat;

import com.mojang.logging.LogUtils;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.Mod;
import org.slf4j.Logger;

@Mod(CruorSableCompat.MOD_ID)
public final class CruorSableCompat {
    public static final String MOD_ID = "cruor_sable_compat";
    public static final Logger LOGGER = LogUtils.getLogger();

    public CruorSableCompat() {
        LOGGER.info("[Cruor Sable Compat] Runtime diagnostics enabled.");
        boolean sableLoaded = ModList.get().isLoaded("sable_player_ragdoll");
        LOGGER.info("[Cruor Sable Compat] Sable Ragdolls detected: {}", sableLoaded);
        if (!sableLoaded) {
            LOGGER.warn("[Cruor Sable Compat] Sable Ragdolls was not detected. The compatibility bridge cannot process ragdoll parts.");
        }
    }
}
