package io.github.sofianbll.oortnx.cloud

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader

/** The camera, only while this page is open, and only for a code. No picture is kept. */
class ScanActivity : Activity() {
    private val work = HandlerThread("oort-cloud-scan")
    private lateinit var handler: Handler
    private lateinit var view: TextureView
    private lateinit var words: TextView
    private var camera: CameraDevice? = null
    private var reader: ImageReader? = null

    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        work.start()
        handler = Handler(work.looper)
        view = TextureView(this)
        words = TextView(this).apply {
            setText(R.string.scan_point)
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
        }
        val close = Button(this).apply {
            setText(R.string.scan_close)
            minHeight = (48 * resources.displayMetrics.density).toInt()
            setOnClickListener { finish() }
        }
        val edge = (24 * resources.displayMetrics.density).toInt()
        val foot = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(edge, edge, edge, edge * 2)
            setBackgroundColor(0xD9000000.toInt())
            addView(words)
            addView(close)
        }
        setContentView(FrameLayout(this).apply {
            addView(view)
            addView(foot, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        })
        when {
            !packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) -> words.setText(R.string.scan_none)
            checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> whenReady()
            else -> requestPermissions(arrayOf(Manifest.permission.CAMERA), 1)
        }
    }

    override fun onRequestPermissionsResult(request: Int, permissions: Array<String>, results: IntArray) {
        if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED) whenReady() else words.setText(R.string.scan_refused)
    }

    private fun whenReady() {
        if (view.isAvailable) return open()
        view.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) = open()
            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit
            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture) = true
            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
        }
    }

    @SuppressLint("MissingPermission")
    private fun open() {
        val manager = getSystemService(CameraManager::class.java)
        try {
            val id = manager.cameraIdList.firstOrNull { manager.getCameraCharacteristics(it)[CameraCharacteristics.LENS_FACING] == CameraCharacteristics.LENS_FACING_BACK }
                ?: manager.cameraIdList.firstOrNull() ?: return words.setText(R.string.scan_none)
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) { camera = device; look(device) }
                override fun onDisconnected(device: CameraDevice) = device.close()
                override fun onError(device: CameraDevice, error: Int) { device.close(); runOnUiThread { words.setText(R.string.scan_none) } }
            }, handler)
        } catch (_: Exception) {
            words.setText(R.string.scan_none)
        }
    }

    @Suppress("DEPRECATION")
    private fun look(device: CameraDevice) {
        val texture = view.surfaceTexture ?: return
        texture.setDefaultBufferSize(1280, 720)
        val preview = Surface(texture)
        val images = ImageReader.newInstance(1280, 720, ImageFormat.YUV_420_888, 2).also { reader = it }
        images.setOnImageAvailableListener({ source ->
            source.acquireLatestImage()?.use { image ->
                val plane = image.planes[0]
                val bytes = ByteArray(plane.buffer.remaining()).also { plane.buffer.get(it) }
                read(bytes, plane.rowStride, image.height, image.width)?.let { found(it) }
            }
        }, handler)
        device.createCaptureSession(listOf(preview, images.surface), object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                    addTarget(preview)
                    addTarget(images.surface)
                    set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                }
                try { session.setRepeatingRequest(request.build(), null, handler) } catch (_: Exception) { /* Closed meanwhile. */ }
            }
            override fun onConfigureFailed(session: CameraCaptureSession) = runOnUiThread { words.setText(R.string.scan_none) }
        }, handler)
    }

    private fun found(text: String) = runOnUiThread {
        if (isFinishing) return@runOnUiThread
        setResult(RESULT_OK, Intent().putExtra("code", text))
        finish()
    }

    override fun onDestroy() {
        camera?.close()
        reader?.close()
        work.quitSafely()
        super.onDestroy()
    }

    internal companion object {
        fun read(luminance: ByteArray, stride: Int, height: Int, width: Int): String? = try {
            val source = PlanarYUVLuminanceSource(luminance, stride, luminance.size / stride, 0, 0, width, minOf(height, luminance.size / stride), false)
            QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)), mapOf(DecodeHintType.TRY_HARDER to true)).text
        } catch (_: ReaderException) {
            null
        }
    }
}
