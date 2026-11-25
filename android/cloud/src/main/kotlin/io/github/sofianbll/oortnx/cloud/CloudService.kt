package io.github.sofianbll.oortnx.cloud

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlin.concurrent.thread

/** Goes on with the screen off, and says so for as long as it does. Started by the player from Oort NX. */
class CloudService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        here = this
        startForeground(ID, notice(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        CloudEngine.of(this).wake()
        Handler(Looper.getMainLooper()).postDelayed({ if (!CloudEngine.of(this).hasWork) stop(this) }, 5_000)
        // Ended by the system: started again, and the queue on the device goes on.
        return START_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) { stop(this) }

    override fun onDestroy() {
        here = null
        super.onDestroy()
    }

    override fun attachBaseContext(base: Context) = super.attachBaseContext(CloudWords.of(base))

    private fun notice(): Notification {
        val notices = getSystemService(NotificationManager::class.java)
        notices.createNotificationChannel(NotificationChannel("now", getString(R.string.channel_now), NotificationManager.IMPORTANCE_LOW))
        val task = CloudEngine.of(this).queue.tasks.firstOrNull { it.state == CloudTask.State.RUNNING }
        val builder = Notification.Builder(this, "now").setSmallIcon(R.drawable.ic_launcher_monochrome).setOngoing(true).setOnlyAlertOnce(true)
            .setContentTitle(task?.let { getString(R.string.downloading, it.build.name) } ?: getString(R.string.app_name)).setContentIntent(CloudEngine.openOort(this))
        if (android.os.Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        if (task != null && task.build.bytes > 0) builder.setProgress(1000, (task.received * 1000 / task.build.bytes).toInt(), false)
        return builder.build()
    }

    companion object {
        private const val ID = 1
        @Volatile private var here: CloudService? = null

        fun start(context: Context) { context.startForegroundService(Intent(context, CloudService::class.java)) }

        fun refresh(context: Context) {
            here?.let { context.getSystemService(NotificationManager::class.java).notify(ID, it.notice()) }
        }

        /** Nothing left to do now: the job takes over when there is. */
        fun settle(context: Context) { Handler(Looper.getMainLooper()).postDelayed({ if (!CloudEngine.of(context).isWorking) stop(context) }, 2_000) }

        fun stop(context: Context) {
            here?.stopForeground(Service.STOP_FOREGROUND_REMOVE)
            context.stopService(Intent(context, CloudService::class.java))
        }
    }
}

/** What the system starts after a restart, or when the network the player allows is back. */
class CloudJob : JobService() {
    override fun onStartJob(parameters: JobParameters): Boolean {
        val engine = CloudEngine.of(this)
        engine.wake()
        if (!engine.isWorking) return false
        thread(name = "oort-cloud-job") {
            while (engine.isWorking) Thread.sleep(1_000)
            jobFinished(parameters, engine.hasWork)
        }
        return true
    }

    /** The system takes its slice back: what was received stays. */
    override fun onStopJob(parameters: JobParameters): Boolean = true
}
