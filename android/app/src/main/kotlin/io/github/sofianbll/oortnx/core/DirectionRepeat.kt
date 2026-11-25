package io.github.sofianbll.oortnx.core

import kotlin.math.hypot

// Port of OortCore's DirectionRepeat (Oort NX, MIT). Time is supplied by the caller, as there.

enum class Dir { Up, Down, Left, Right }

enum class PadSource { Pad, LeftStick, RightStick }

/**
 * A held direction moves once, waits, then repeats, a little faster after a while. The D-pad and both sticks
 * share it; the last one pressed leads.
 */
class DirectionRepeat {
    private data class Held(val source: PadSource, val direction: Dir)

    private val held = ArrayList<Held>()
    private var count = 0

    val current: Dir? get() = held.lastOrNull()?.direction

    /** Seconds to wait before the next repeat of what is held now. */
    val nextDelay: Double
        get() = if (held.lastOrNull()?.source == PadSource.RightStick) {
            if (count == 0) INTERVAL * 1.5 else FAST_INTERVAL
        } else {
            if (count == 0) FIRST_DELAY else if (count < FAST_AFTER) INTERVAL else FAST_INTERVAL
        }

    /** True when this is a new direction: move now. */
    fun press(direction: Dir, from: PadSource): Boolean {
        if (held.any { it.source == from && it.direction == direction }) return false
        held.add(Held(from, direction))
        count = 0
        return true
    }

    fun release(direction: Dir, from: PadSource) {
        held.removeAll { it.source == from && it.direction == direction }
        count = 0
    }

    /**
     * A stick is in one direction or none. A little slack keeps a stick resting on its threshold from
     * chattering. [x] is right-positive and [y] up-positive. Returns the direction to move now, or null.
     */
    fun stick(x: Float, y: Float, deadzone: Float, from: PadSource): Dir? {
        val was = held.lastOrNull { it.source == from }?.direction
        fun pull(d: Dir): Float = when (d) {
            Dir.Up -> y
            Dir.Down -> -y
            Dir.Left -> -x
            Dir.Right -> x
        }
        val strongest = Dir.entries.maxOf { pull(it) }
        if (was != null && pull(was) > deadzone * 0.8f && pull(was) >= strongest * 0.8f) return null
        if (was != null) release(was, from)
        val next = Dir.entries.maxByOrNull { pull(it) } ?: return null
        if (pull(next) <= deadzone) return null
        if (from == PadSource.RightStick && next != Dir.Up && next != Dir.Down) return null
        return if (press(next, from)) next else null
    }

    /** One repeat of what is held, or null when nothing is. */
    fun tick(): Dir? {
        val now = current ?: return null
        count += 1
        return now
    }

    fun reset() {
        held.clear()
        count = 0
    }

    companion object {
        const val FIRST_DELAY = 0.36
        const val INTERVAL = 0.12
        const val FAST_INTERVAL = 0.07
        private const val FAST_AFTER = 8

        /** Radius of a stick push, to compare with a deadzone. */
        fun radius(x: Float, y: Float): Float = hypot(x, y)
    }
}
