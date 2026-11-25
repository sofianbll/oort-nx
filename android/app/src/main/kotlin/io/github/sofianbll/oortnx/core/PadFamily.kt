package io.github.sofianbll.oortnx.core

import android.view.KeyEvent

/**
 * The controller in hand, as far as its keys are marked: [vendor] and [product] are its USB or Bluetooth identifiers.
 * Android names buttons by their place on an Xbox pad (BUTTON_A is the bottom one), whatever is printed on them.
 */
data class PadFamily(val marks: Marks = Marks.Generic, val product: Int = 0) {
    enum class Marks { Generic, Xbox, PlayStation, Nintendo }

    /**
     * The code of the letter printed on the key Android calls [code]. Nintendo prints A on the right and B at the bottom;
     * Android's own key layout for the Pro Controller (Vendor_057e_Product_2009.kl) also names X and Y by place, while
     * the generic layout that the other Nintendo pads get names them as the driver does, by letter.
     */
    fun printed(code: Int): Int = if (marks != Marks.Nintendo) code else when (code) {
        KeyEvent.KEYCODE_BUTTON_A -> KeyEvent.KEYCODE_BUTTON_B
        KeyEvent.KEYCODE_BUTTON_B -> KeyEvent.KEYCODE_BUTTON_A
        KeyEvent.KEYCODE_BUTTON_X -> if (product == PRO_CONTROLLER) KeyEvent.KEYCODE_BUTTON_Y else code
        KeyEvent.KEYCODE_BUTTON_Y -> if (product == PRO_CONTROLLER) KeyEvent.KEYCODE_BUTTON_X else code
        else -> code
    }

    /** What is written on the key of the printed code [code]. */
    fun mark(code: Int): String {
        fun of(generic: String, xbox: String = generic, playStation: String = generic, nintendo: String = generic) = when (marks) {
            Marks.Generic -> generic
            Marks.Xbox -> xbox
            Marks.PlayStation -> playStation
            Marks.Nintendo -> nintendo
        }
        return when (code) {
            KeyEvent.KEYCODE_BUTTON_A -> of("A", playStation = "✕")
            KeyEvent.KEYCODE_BUTTON_B -> of("B", playStation = "○")
            KeyEvent.KEYCODE_BUTTON_X -> of("X", playStation = "□")
            KeyEvent.KEYCODE_BUTTON_Y -> of("Y", playStation = "△")
            KeyEvent.KEYCODE_BUTTON_L1 -> of("L1", xbox = "LB", nintendo = "L")
            KeyEvent.KEYCODE_BUTTON_R1 -> of("R1", xbox = "RB", nintendo = "R")
            KeyEvent.KEYCODE_BUTTON_L2 -> of("L2", xbox = "LT", nintendo = "ZL")
            KeyEvent.KEYCODE_BUTTON_R2 -> of("R2", xbox = "RT", nintendo = "ZR")
            KeyEvent.KEYCODE_BUTTON_START -> of("☰", playStation = "Options", nintendo = "+")
            KeyEvent.KEYCODE_BUTTON_SELECT -> of("Select", xbox = "View", playStation = "Create", nintendo = "−")
            KeyEvent.KEYCODE_BUTTON_THUMBL -> of("L3", xbox = "LS")
            KeyEvent.KEYCODE_BUTTON_THUMBR -> of("R3", xbox = "RS")
            else -> KeyEvent.keyCodeToString(code).removePrefix("KEYCODE_").removePrefix("BUTTON_")
        }
    }

    companion object {
        private const val PRO_CONTROLLER = 0x2009

        /** By maker, then by name for the pads that borrow another's identifiers. Nintendo only by maker: its keys move with it. */
        fun of(vendor: Int, product: Int, name: String): PadFamily {
            val said = name.lowercase()
            return PadFamily(when {
                vendor == 0x057E -> Marks.Nintendo
                vendor == 0x054C || listOf("dualsense", "dualshock", "playstation").any { it in said } -> Marks.PlayStation
                vendor == 0x045E || "xbox" in said -> Marks.Xbox
                else -> Marks.Generic
            }, product)
        }
    }
}
