package io.github.sofianbll.oortnx.cloud

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.Settings
import io.github.sofianbll.oortnx.drive.DriveReceiver
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfException
import io.github.sofianbll.oortnx.shelf.ShelfStop
import java.io.IOException
import java.util.concurrent.CancellationException
import kotlin.concurrent.thread

/** What only this app can ask of Android or of the browser, one step at a time, from Oort NX. Nothing is drawn but the system's own questions. */
class StepActivity : Activity() {
    private val engine get() = CloudEngine.of(this)
    private val id: String get() = intent.getStringExtra("title").orEmpty()
    private var browser: ShelfStop? = null
    private var asked = false

    override fun attachBaseContext(base: Context) = super.attachBaseContext(CloudWords.of(base))

    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        // startActivityForResult names the caller, and Android vouches for it.
        if (!CloudGuard.allows(this, callingPackage)) return finish()
        if (saved != null && intent.action != "install") return finish()
        when (intent.action) {
            "download", "resume" -> download()
            "scan" -> startActivityForResult(Intent(this, ScanActivity::class.java), SCAN)
            "signIn" -> signIn()
            "install" -> install()
            else -> finish()
        }
    }

    // ---- downloading --------------------------------------------------------------------------------------

    private fun download() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            !getSharedPreferences("cloud", MODE_PRIVATE).getBoolean("askedNotices", false)) {
            getSharedPreferences("cloud", MODE_PRIVATE).edit().putBoolean("askedNotices", true).apply()
            return requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTICES)
        }
        begin()
    }

    private fun begin() {
        if (intent.action == "resume") engine.resume(id) else engine.download(id)
        if (engine.hasWork) CloudService.start(this)
        finish()
    }

    override fun onRequestPermissionsResult(request: Int, permissions: Array<String>, results: IntArray) {
        if (request == NOTICES) begin()
    }

    // ---- signing in ---------------------------------------------------------------------------------------

    private fun signIn() {
        val connection = engine.current() ?: return finish()
        val stop = ShelfStop()
        browser = stop
        val dialog = AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert).setMessage(R.string.wait_browser)
            .setNegativeButton(R.string.stop) { _, _ -> stop.stop() }.setOnCancelListener { stop.stop() }.show()
        thread(name = "oort-cloud-sign-in") {
            var error: ShelfError? = null
            var stopped = false
            try {
                DriveReceiver().use { receiver ->
                    val attempt = connection.signIn(receiver)
                    runOnUiThread { browse(attempt.page, stop) }
                    connection.access.finish(attempt, receiver.receive(attempt, stop), stop)
                }
            } catch (failure: ShelfException) {
                error = failure.error
            } catch (_: CancellationException) {
                stopped = true
            } catch (_: IOException) {
                error = ShelfError.LocalFile
            }
            // Stopped by the player: nothing happened, nothing is said.
            if (stopped) engine.changed() else engine.signedIn(error)
            runOnUiThread {
                dialog.dismiss()
                // In front of the browser's tab, which was opened over this activity.
                startActivity(Intent(this, StepActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                finish()
            }
        }
    }

    /** A tab of the player's own browser, over this activity: it keeps its accounts, and closes when the sign-in ends. */
    private fun browse(page: String, stop: ShelfStop) {
        val tab = Intent(Intent.ACTION_VIEW, Uri.parse(page))
        tab.putExtras(Bundle().apply { putBinder("android.support.customtabs.extra.SESSION", null) })
        try {
            startActivity(tab)
        } catch (_: ActivityNotFoundException) {
            engine.message = getString(R.string.no_browser)
            stop.stop()
        }
    }

    override fun onDestroy() {
        if (isFinishing) browser?.stop()
        super.onDestroy()
    }

    // ---- installing ---------------------------------------------------------------------------------------

    private fun install() {
        val build = engine.build(id) ?: return finish()
        val installs = engine.installs
        if (installs.data(build).isNotEmpty() && installs.folder == null) {
            return why(R.string.folder_why) {
                val start = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:Documents")
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).putExtra(DocumentsContract.EXTRA_INITIAL_URI, start), FOLDER)
            }
        }
        if (!packageManager.canRequestPackageInstalls()) {
            if (asked) return finish()
            asked = true
            return why(R.string.unknown_why) {
                startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")), UNKNOWN)
            }
        }
        engine.installing(id)
        thread(name = "oort-cloud-install") {
            try {
                // Installed by a try whose data could not be put in place: only the data is left.
                if (installs.info(build.packageID!!)?.longVersionCode == build.packageVersion && !installs.apk(build).exists()) complete(build.titleID)
                else {
                    installs.check(build)
                    ask(build)
                }
            } catch (failure: ShelfException) {
                engine.installing(null)
                engine.refused(id, failure.error)
                runOnUiThread { finish() }
            } catch (_: IOException) {
                engine.installing(null)
                engine.refused(id, ShelfError.LocalFile)
                runOnUiThread { finish() }
            }
        }
    }

    private fun why(text: Int, then: () -> Unit) {
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert).setMessage(text)
            .setPositiveButton(R.string.go_on) { _, _ -> then() }
            .setNegativeButton(R.string.cancel) { _, _ -> finish() }.setOnCancelListener { finish() }.show()
    }

    /** Android shows its own question; nothing is installed without it. */
    private fun ask(build: io.github.sofianbll.oortnx.shelf.ShelfBuild) {
        val installer = packageManager.packageInstaller
        val parameters = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(build.packageID)
            setSize(engine.installs.apk(build).length())
        }
        val number = installer.createSession(parameters)
        installer.openSession(number).use { session ->
            session.openWrite("game.apk", 0, engine.installs.apk(build).length()).use { out ->
                engine.installs.apk(build).inputStream().use { it.copyTo(out, 1 shl 20) }
                session.fsync(out)
            }
            waiting = this
            val back = Intent(this, InstallReceiver::class.java).putExtra("title", build.titleID)
            session.commit(sender(number, back))
        }
    }

    private fun sender(number: Int, intent: Intent): IntentSender =
        PendingIntent.getBroadcast(this, number, intent, PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)).intentSender

    private fun complete(title: String) {
        val build = engine.build(title) ?: return runOnUiThread { finish() }
        try {
            engine.installs.place(build)
            engine.installs.finish(build)
            engine.installing(null)
            engine.installed(title)
        } catch (failure: ShelfException) {
            engine.installing(null)
            engine.refused(title, failure.error)
        }
        runOnUiThread { finish() }
    }

    internal fun answered(status: Int, title: String, confirm: Intent?) {
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> confirm?.let { startActivityForResult(it, CONFIRM) }
            PackageInstaller.STATUS_SUCCESS -> thread(name = "oort-cloud-place") {
                // Its place is taken by the installed game.
                engine.build(title)?.let { engine.installs.apk(it).delete() }
                complete(title)
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> { engine.installing(null); finish() }
            PackageInstaller.STATUS_FAILURE_STORAGE -> { engine.installing(null); engine.refused(title, ShelfError.NoSpace(0)); finish() }
            else -> { engine.installing(null); engine.refused(title, ShelfError.Unsigned); finish() }
        }
    }

    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        when (request) {
            SCAN -> {
                setResult(result, data)
                finish()
            }
            FOLDER -> {
                val uri = data?.data
                if (result != RESULT_OK || uri == null) return finish()
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                engine.installs.folder = uri
                install()
            }
            UNKNOWN -> install()
            CONFIRM -> Unit
        }
    }

    companion object {
        private const val NOTICES = 1
        private const val SCAN = 2
        private const val FOLDER = 3
        private const val UNKNOWN = 4
        private const val CONFIRM = 5
        internal var waiting: StepActivity? = null
    }
}

/** What Android answers about an installation. */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        @Suppress("DEPRECATION") val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        val activity = StepActivity.waiting
        if (activity == null) CloudEngine.of(context).installing(null) else activity.answered(status, intent.getStringExtra("title").orEmpty(), confirm)
        if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) StepActivity.waiting = null
    }
}
