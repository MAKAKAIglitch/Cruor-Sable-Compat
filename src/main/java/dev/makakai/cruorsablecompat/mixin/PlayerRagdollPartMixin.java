package dev.makakai.cruorsablecompat.mixin;

import dev.makakai.cruorsablecompat.RagdollBloodBridge;
import net.minecraft.world.level.block.entity.BlockEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Pseudo;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Coerce;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Pseudo
@Mixin(
        targets = "dev.leo.sableplayerragdoll.block.entity.RagdollPartBlockEntity",
        remap = false
)
abstract class PlayerRagdollPartMixin {
    @Inject(
            method = "sable$physicsTick",
            at = @At("TAIL"),
            remap = false,
            require = 0
    )
    private void cruorSableCompat$afterPlayerPartPhysicsTick(
            @Coerce Object subLevel,
            @Coerce Object handle,
            double timeStep,
            CallbackInfo callbackInfo
    ) {
        RagdollBloodBridge.onPartPhysicsTick((BlockEntity) (Object) this, subLevel);
    }
}
