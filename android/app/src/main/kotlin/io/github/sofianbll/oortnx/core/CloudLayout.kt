package io.github.sofianbll.oortnx.core

/**
 * Where the cloud sits in a window of [width] x [height] px, and where it keeps quiet so text stays readable.
 * Wide windows follow the Mac: centre at 0.71 of the width, radius half the height, the left side dimmed.
 * Tall windows follow the phone app (OortBackdrop): a frame as wide as it is tall, shown from the right, that fades
 * before the bottom, so the cloud is large and its Sun stays behind the games.
 */
class CloudLayout private constructor(
    val width: Float,
    val height: Float,
    /** The frame the Mac's layout is drawn in: the window itself when wide. */
    private val frameLeft: Float,
    private val frameWidth: Float,
    private val frameHeight: Float,
) {
    val centreX: Float get() = frameLeft + 0.71f * frameWidth
    val centreY: Float get() = 0.5f * frameHeight

    /** The cloud's radius in px (the Mac's `cloudRadius` is 0.5 window heights). */
    val radius: Float get() = 0.5f * frameHeight

    /** One "window height" of the Mac's shader, in px: lengths in the shader's constants multiply this. */
    val unit: Float get() = frameHeight

    /** 0.1 where text sits, 1 in the open (the Mac's `calm`), and nothing left at the foot of a tall window. */
    fun calm(x: Float, y: Float): Float =
        mix(0.10f, 1f, smoothstep(0.30f, 0.62f, (x - frameLeft) / frameWidth)) *
            if (frameWidth > width) 1f - smoothstep(0.72f, 1f, y / frameHeight) else 1f

    companion object {
        fun of(width: Float, height: Float): CloudLayout {
            val frameWidth = maxOf(width, minOf(height, width * 1.5f))
            val frameHeight = minOf(height, frameWidth)
            return CloudLayout(width, height, (width - frameWidth) * 0.54f, frameWidth, frameHeight)
        }

        fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
            val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
            return t * t * (3f - 2f * t)
        }

        fun mix(a: Float, b: Float, t: Float): Float = a + (b - a) * t
    }
}
