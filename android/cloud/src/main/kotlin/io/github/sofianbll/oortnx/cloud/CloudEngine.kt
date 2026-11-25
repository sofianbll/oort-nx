package io.github.sofianbll.oortnx.cloud

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.github.sofianbll.oortnx.drive.DriveClient
import io.github.sofianbll.oortnx.drive.DriveConnection
import io.github.sofianbll.oortnx.drive.DriveInvite
import io.github.sofianbll.oortnx.drive.DriveKeystore
import io.github.sofianbll.oortnx.drive.DriveSealedVault
import io.github.sofianbll.oortnx.shelf.ShelfBuild
import io.github.sofianbll.oortnx.shelf.ShelfCatalog
import io.github.sofianbll.oortnx.shelf.ShelfChoices
import io.github.sofianbll.oortnx.shelf.ShelfConnectors
import io.github.sofianbll.oortnx.shelf.ShelfCrypto
import io.github.sofianbll.oortnx.shelf.ShelfDevice
import io.github.sofianbll.oortnx.shelf.ShelfDownload
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfException
import io.github.sofianbll.oortnx.shelf.ShelfListing
import io.github.sofianbll.oortnx.shelf.ShelfPlatform
import io.github.sofianbll.oortnx.shelf.ShelfRules
import io.github.sofianbll.oortnx.shelf.ShelfStop
import io.github.sofianbll.oortnx.shelf.ShelfStore
import io.github.sofianbll.oortnx.shelf.fail
import java.io.File
import java.util.concurrent.CancellationException
import kotlin.concurrent.thread

/** The whole of the cloud library: off until the player turns it on, and nothing is opened before that. */
internal class CloudEngine private constructor(private val context: Context) : ShelfChoices {
    enum class Network { NONE, METERED, FREE }

    private val prefs: SharedPreferences = context.getSharedPreferences("cloud", Context.MODE_PRIVATE)
    private val root = File(context.noBackupFilesDir, "cloud")
    private val scratch = File(root, "scratch")
    private val vault = DriveSealedVault(File(root, "sign-in"), DriveKeystore::key, DriveKeystore::erase)
    val queue = CloudQueue(File(root, "queue.json"))
    val store = ShelfStore(File(root, "builds")) { free() }
    val installs = CloudInstalls(context, store, File(root, "receipts"))
    private var connection: DriveConnection? = null
    private var crypto: ShelfCrypto? = null
    private var listing: ShelfListing? = null
    private var problem: ShelfError? = null
    private var looking = false
    private var running: Pair<String, ShelfStop>? = null
    var installing: String? = null
        private set
    var message: String? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())
    private val retry = Runnable { pump() }

    // ---- on and off ---------------------------------------------------------------------------------------

    private val connectors get() = ShelfConnectors(listOf(connection?.connector ?: DriveConnection.outline), this)
    private val isOn get() = connectors.isOn(DriveConnection.ID)
    private val code: String? get() = prefs.getString("code", null)
    val wifiOnly: Boolean get() = prefs.getBoolean("wifiOnly", true)
    val stage: String
        @Synchronized get() = when {
            !isOn -> "off"
            connection == null -> "code"
            connection?.isSignedIn != true -> "signIn"
            else -> "ready"
        }

    override fun permissions(connector: String): Set<String>? = prefs.getStringSet("on.$connector", null)
    override fun set(permissions: Set<String>?, connector: String) { prefs.edit().putStringSet("on.$connector", permissions).commit() }

    init { if (isOn) open() }

    @Synchronized fun turnOn() {
        connectors.turnOn(DriveConnection.ID, DriveConnection.outline.permissions)
        open()
        changed()
    }

    /** "good", "otherDevice" or "wrong". */
    @Synchronized fun take(text: String): String {
        val clean = text.trim().replace(Regex("[“”«»]"), "\"")
        val invite = DriveInvite.parse(clean) ?: return "wrong"
        if (invite.client.kind != DriveClient.Kind.DESKTOP) return "otherDevice"
        if (!isOn) return "wrong"
        prefs.edit().putString("code", clean).commit()
        open()
        changed()
        return "good"
    }

    fun changeCode() {
        stopRunning()
        synchronized(this) {
            connection?.connector?.forget?.invoke()
            prefs.edit().remove("code").commit()
            forget()
        }
        changed()
    }

    fun turnOff(deleting: Boolean) {
        stopRunning()
        synchronized(this) {
            connectors.turnOff(DriveConnection.ID)
            vault.erase()
            prefs.edit().remove("code").remove("wifiOnly").commit()
            queue.clear()
            forget()
            if (deleting) store.root.deleteRecursively()
            scratch.deleteRecursively()
        }
        context.getSystemService(JobScheduler::class.java).cancelAll()
        CloudService.stop(context)
        changed()
    }

    private fun forget() {
        connection = null
        crypto = null
        listing = null
        problem = null
        message = null
        callback?.let { context.getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) }
        callback = null
    }

    private fun open() {
        val invite = code?.let { DriveInvite.parse(it) }?.takeIf { it.client.kind == DriveClient.Kind.DESKTOP } ?: return
        crypto = ShelfCrypto(invite.signer)
        connection = DriveConnection(invite, vault, scratch, CloudBuild.endpoints)
        if (callback == null) {
            callback = object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: android.net.Network, capabilities: NetworkCapabilities) { wake() }
                override fun onLost(network: android.net.Network) { changed() }
            }.also { context.getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(it) }
        }
    }

    fun saveWifiOnly(on: Boolean) {
        prefs.edit().putBoolean("wifiOnly", on).commit()
        wake()
    }

    // ---- sign-in and listing ------------------------------------------------------------------------------

    fun current(): DriveConnection? = synchronized(this) { connection }

    fun signedIn(error: ShelfError?) {
        synchronized(this) { problem = error }
        changed()
        if (error == null) { look(); pump() }
    }

    fun look() {
        synchronized(this) {
            if (looking || stage != "ready") return
            looking = true
        }
        changed()
        thread(name = "oort-cloud-look") {
            try {
                val source = connectors.source(DriveConnection.ID)
                val found = ShelfCatalog(source, crypto!!, scratch).list(device(), installs.digests())
                synchronized(this) { listing = found; problem = null }
            } catch (failure: ShelfException) {
                synchronized(this) { problem = failure.error }
            } catch (_: CancellationException) {
                // Turned off meanwhile.
            } catch (_: RuntimeException) {
                synchronized(this) { problem = ShelfError.BadResponse }
            }
            synchronized(this) { looking = false }
            changed()
        }
    }

    private fun device(): ShelfDevice {
        val features = buildSet {
            val packages = context.packageManager
            if (packages.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x401000)) add("vulkan1.1")
            if (packages.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x403000)) add("vulkan1.3")
        }
        val abi = Build.SUPPORTED_64_BIT_ABIS.firstOrNull().orEmpty()
        return ShelfDevice(ShelfPlatform.ANDROID, Build.VERSION.SDK_INT.toString(), if (abi == "arm64-v8a") "arm64" else abi, features, 0)
    }

    // ---- the queue ----------------------------------------------------------------------------------------

    fun build(id: String): ShelfBuild? = synchronized(this) { queue[id]?.build ?: listing?.games?.firstOrNull { it.titleID == id }?.build }

    /** From an activity the player sees, so Android lets the service start. */
    fun download(id: String) {
        synchronized(this) {
            val build = listing?.games?.firstOrNull { it.titleID == id }?.build ?: return
            queue.add(build)
        }
        wake()
    }

    fun resume(id: String) {
        synchronized(this) { queue.set(id, CloudTask.State.WAITING) }
        wake()
    }

    fun pause(id: String) {
        synchronized(this) {
            queue.set(id, CloudTask.State.PAUSED)
            running?.takeIf { it.first == id }?.second?.stop()
        }
        changed()
    }

    /** Only what this download kept goes. */
    fun cancel(id: String) {
        val task = synchronized(this) {
            val task = queue[id]
            queue.remove(id)
            running?.takeIf { it.first == id }?.second?.stop()
            task
        } ?: return
        thread(name = "oort-cloud-cancel") {
            while (synchronized(this) { running?.first == id }) Thread.sleep(50)
            store.discard(task.build)
            File(store.root, id).deleteRecursively()
            changed()
            pump()
        }
    }

    fun wake() {
        main.removeCallbacks(retry)
        pump()
    }

    val isWorking: Boolean get() = synchronized(this) { running != null }
    val hasWork: Boolean get() = synchronized(this) { running != null || queue.next != null }

    fun pump() {
        val (task, stop) = synchronized(this) {
            if (stage != "ready" || running != null) return changed()
            val task = queue.next ?: return changed()
            val stop = ShelfStop()
            running = task.id to stop
            queue.set(task.id, CloudTask.State.RUNNING)
            task to stop
        }
        changed()
        schedule()
        thread(name = "oort-cloud-download") {
            var error: ShelfError? = null
            var stopped = false
            try {
                if (network() == Network.NONE) fail(ShelfError.Offline)
                val rules = ShelfRules(allowsMeteredNetwork = !wifiOnly, chunk = CloudBuild.CHUNK)
                ShelfDownload(connectors.source(DriveConnection.ID), store, rules, isMetered = { network() == Network.METERED }).run(task.build, stop) {
                    synchronized(this) { queue.progress(task.id, it.received) }
                    changed()
                }
            } catch (failure: ShelfException) {
                error = failure.error
            } catch (_: CancellationException) {
                stopped = true
            } catch (_: RuntimeException) {
                error = ShelfError.BadResponse
            }
            ended(task, error, stopped)
        }
    }

    private fun ended(task: CloudTask, error: ShelfError?, stopped: Boolean) {
        var wait = false
        synchronized(this) {
            running = null
            // Paused or taken away meanwhile: the player's word stays.
            if (queue[task.id]?.state == CloudTask.State.RUNNING) when {
                stopped -> queue.set(task.id, CloudTask.State.WAITING)
                error == null -> {
                    queue.progress(task.id, task.build.bytes)
                    queue.set(task.id, CloudTask.State.READY)
                }
                error.waits || error == ShelfError.SignInNeeded -> {
                    queue.set(task.id, CloudTask.State.WAITING, error)
                    wait = true
                }
                else -> queue.set(task.id, CloudTask.State.FAILED, error)
            }
        }
        changed()
        if (error == null && !stopped) tell(task.build.name)
        if (wait) main.postDelayed(retry, 30_000) else if (!stopped || synchronized(this) { queue.next != null && stage == "ready" }) pump()
        if (!hasWork || wait) CloudService.settle(context)
    }

    /** The system runs the rest when the process is gone: after a restart, or when the network the player allows is back. */
    private fun schedule() {
        val jobs = context.getSystemService(JobScheduler::class.java)
        if (!synchronized(this) { queue.tasks.any { it.state == CloudTask.State.WAITING || it.state == CloudTask.State.RUNNING } }) return jobs.cancel(JOB)
        jobs.schedule(JobInfo.Builder(JOB, ComponentName(context, CloudJob::class.java))
            .setRequiredNetworkType(if (wifiOnly) JobInfo.NETWORK_TYPE_UNMETERED else JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true).build())
    }

    fun stopRunning() {
        synchronized(this) { running?.second?.stop() }
        while (synchronized(this) { running != null }) Thread.sleep(20)
    }

    // ---- installing ---------------------------------------------------------------------------------------

    fun installing(id: String?) {
        synchronized(this) { installing = id }
        changed()
    }

    fun installed(id: String) {
        synchronized(this) { queue.remove(id); message = null }
        changed()
    }

    fun refused(id: String, error: ShelfError) {
        synchronized(this) { queue.set(id, CloudTask.State.FAILED, error) }
        changed()
    }

    // ---- this device --------------------------------------------------------------------------------------

    fun free(): Long = CloudBuild.free ?: generateSequence(root) { it.parentFile }.first { it.exists() }.usableSpace

    fun network(): Network {
        if (CloudBuild.metered) return Network.METERED
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val here = manager.getNetworkCapabilities(manager.activeNetwork) ?: return Network.NONE
        if (!here.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return Network.NONE
        return if (here.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) Network.FREE else Network.METERED
    }

    /** Everything Oort NX draws. No address, no identifier of a file, no credential. */
    @Synchronized fun state(): String {
        val here = installs.all()
        val builds = listing?.games?.map { it.build }.orEmpty()
        val all = builds + queue.tasks.map { it.build }.filter { b -> builds.none { it.titleID == b.titleID } }
        return CloudQueue.write(mapOf(
            "stage" to stage, "hosts" to DriveConnection.outline.hosts, "wifiOnly" to wifiOnly, "free" to free(),
            "used" to queue.tasks.sumOf { if (it.state == CloudTask.State.READY) it.build.bytes else it.received },
            "looking" to looking, "listed" to (listing != null), "problem" to problem?.code, "needed" to (problem as? ShelfError.NoSpace)?.needed,
            "network" to if (stage == "off") "free" else network().name.lowercase(), "installing" to installing, "message" to message,
            "games" to all.map { listed ->
                val task = queue[listed.titleID]
                val build = task?.build ?: listed
                val receipt = here[build.titleID]
                mapOf(
                    "title" to build.titleID, "name" to build.name, "version" to build.gameVersion, "bytes" to build.bytes, "system" to build.minimumSystem,
                    "package" to build.packageID, "installed" to (receipt != null && receipt.present && receipt.digest == build.digest),
                    "here" to receipt?.takeIf { it.present }?.version, "left" to (receipt != null && !receipt.present && receipt.files.isNotEmpty()),
                    "job" to task?.let { mapOf("state" to it.state.id, "reason" to it.reason, "needed" to it.needed, "received" to it.received) },
                )
            },
            "hidden" to listing?.hidden?.map { mapOf("title" to it.titleID, "name" to it.name, "reason" to it.reason.id) }.orEmpty(),
            "problems" to listing?.problems?.map { mapOf("title" to it.titleID, "name" to it.name, "error" to it.error.code) }.orEmpty(),
        ))
    }

    fun changed() {
        context.contentResolver.notifyChange(CloudProvider.URI, null)
        CloudService.refresh(context)
    }

    private fun tell(name: String) {
        val notices = context.getSystemService(NotificationManager::class.java)
        notices.createNotificationChannel(NotificationChannel("done", context.getString(R.string.channel_done), NotificationManager.IMPORTANCE_DEFAULT))
        notices.notify(name.hashCode(), Notification.Builder(context, "done").setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(context.getString(R.string.ready, name)).setAutoCancel(true)
            .setContentIntent(openOort(context)).build())
    }

    companion object {
        private const val JOB = 1
        @Volatile private var kept: CloudEngine? = null

        fun of(context: Context): CloudEngine = kept ?: synchronized(this) { kept ?: CloudEngine(context.applicationContext).also { kept = it } }

        fun openOort(context: Context): android.app.PendingIntent? = context.packageManager.getLaunchIntentForPackage(CloudGuard.OORT)?.let {
            android.app.PendingIntent.getActivity(context, 0, it, android.app.PendingIntent.FLAG_IMMUTABLE)
        }

        fun uri(text: String): Uri = Uri.parse(text)
    }
}
