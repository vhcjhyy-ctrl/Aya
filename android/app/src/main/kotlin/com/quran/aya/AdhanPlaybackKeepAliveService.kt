package com.quran.aya

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground-service lifetime guard for AdhanBroadcastReceiver's MediaPlayer.
 *
 * The exact alarm receiver owns playback controls and completion handling; this
 * service ensures Android does not reclaim the app process while the audio is
 * playing after onReceive() returns.
 */
class AdhanPlaybackKeepAliveService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prayerName = intent?.getStringExtra("PRAYER_NAME") ?: "الأذان"
        val channelId = "adhan_playback_foreground_v1"
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            notificationManager.getNotificationChannel(channelId) == null
        ) {
            val channel = NotificationChannel(
                channelId,
                "Adhan Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Adhan audio playing reliably in the background"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val iconId = resources.getIdentifier("ic_notification", "drawable", packageName)
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(if (iconId != 0) iconId else android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("قلم مسلم")
            .setContentText("يُشغَّل الأذان — $prayerName")
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()

        startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val FOREGROUND_NOTIFICATION_ID = 97001

        fun stop(context: Context) {
            context.stopService(Intent(context, AdhanPlaybackKeepAliveService::class.java))
        }
    }
}
