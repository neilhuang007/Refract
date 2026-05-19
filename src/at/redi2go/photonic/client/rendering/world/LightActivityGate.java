package at.redi2go.photonic.client.rendering.world;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.joml.Vector3f;

/**
 * Confirmation-gate for traced-light activity changes.
 *
 * <p>When a sync source proposes an activity change for a light, the gate
 * requires the same change to be observed for {@link #LIGHT_ACTIVITY_CONFIRMATION_SCANS}
 * consecutive scans before reporting it as confirmed. Authoritative block
 * updates bypass this gate entirely (handled by the caller).
 *
 * <p>Thread-safety: all public methods are called while LightRegistry holds
 * its write-lock. The gate itself does not acquire any additional lock.
 */
final class LightActivityGate {

    static final int LIGHT_ACTIVITY_CONFIRMATION_SCANS = 4;

    private final Map<Vector3f, PendingLightActivityChange> pendingLightActivityChanges =
            new ConcurrentHashMap<>();

    LightActivityGate() {}

    /**
     * Returns {@code true} if the proposed activity change for {@code position}
     * has been observed for enough consecutive scans and should be applied.
     * Returns {@code false} if the change is still in its confirmation window.
     * Mutates the internal pending map on every call.
     */
    boolean shouldApplyConfirmedActivityChange(Vector3f position, TracedLightPosition updated) {
        PendingLightActivityChange pending = pendingLightActivityChanges.get(position);
        long semanticHash = updated.semanticHash();
        if (pending == null
                || pending.active() != updated.active()
                || pending.blockId() != updated.blockId()
                || pending.semanticHash() != semanticHash) {
            pendingLightActivityChanges.put(
                    position,
                    new PendingLightActivityChange(updated.active(), updated.blockId(), semanticHash, 1));
            return LIGHT_ACTIVITY_CONFIRMATION_SCANS <= 1;
        }

        int observations = pending.observations() + 1;
        if (observations < LIGHT_ACTIVITY_CONFIRMATION_SCANS) {
            pendingLightActivityChanges.put(position, pending.withObservations(observations));
            return false;
        }

        return true;
    }

    /**
     * Removes any pending confirmation entry for {@code position}.
     * Called when the light descriptor changes (making the pending activity
     * entry stale) or when the change has been applied.
     */
    void cancelPending(Vector3f position) {
        pendingLightActivityChanges.remove(position);
    }

    /** Clears all pending changes — used on full reset / disconnect. */
    void clearPendingChanges() {
        pendingLightActivityChanges.clear();
    }

    /** Returns the count of in-flight pending activity changes (for debug/profiling). */
    int pendingChangeCount() {
        return pendingLightActivityChanges.size();
    }


    record PendingLightActivityChange(boolean active, int blockId, long semanticHash, int observations) {
        PendingLightActivityChange withObservations(int observations) {
            return new PendingLightActivityChange(this.active, this.blockId, this.semanticHash, observations);
        }
    }
}
