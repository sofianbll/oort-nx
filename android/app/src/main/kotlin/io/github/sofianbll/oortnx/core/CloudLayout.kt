package io.github.sofianbll.oortnx.core

/**
 * Where the cloud sits in a window of [width] x [height] px, and where it keeps quiet so text stays readable.
 * Wide windows follow the Mac: centre at 0.71 of the width, radius half the height, the left side dimmed.
 * Tall windows (a phone held upright) put the cloud in the upper part and dim the lower part, where the games are.
 */
class CloudLayout private constructor(
    val width: Float,
    val height: Float,
    val centreX: Float,
    val centreY: Float,
    /** The cloud's radius in px (the Mac's `cloudRadius` is 0.5 window heights). */
    val radius: Float,
    private val wide: Boolean,
) {
    /** One "window height" of the Mac's shader, in px: lengths in the shader's constants multiply this. */
    val unit: Float get() = radius / 0.5f

    /** 0.1 where text sits, 1 in the open; the Mac's `calm`. */
    fun calm(x: Float, y: Float): Float =
        if (wide) mix(0.10f, 1f, smoothstep(0.30f, 0.62f, x / width))
        else mix(1f, 0.12f, smoothstep(0.50f, 0.80f, y / height))

    companion object {
        /** The aspect ratio at which the layout turns upright. */
        const val UPRIGHT_BELOW = 1.1f

        fun of(width: Float, height: Float): CloudLayout =
            if (width / height >= UPRIGHT_BELOW) CloudLayout(width, height, 0.71f * width, 0.5f * height, 0.5f * height, true)
            else CloudLayout(width, height, 0.5f * width, 0.30f * height, minOf(0.36f * height, 0.46f * width), false)

        fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
            val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
            return t * t * (3f - 2f * t)
        }

        fun mix(a: Float, b: Float, t: Float): Float = a + (b - a) * t
    }
}
