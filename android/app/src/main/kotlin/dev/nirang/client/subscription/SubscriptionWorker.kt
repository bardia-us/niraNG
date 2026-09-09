package dev.nirang.client.subscription

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.registration.RemoteAccessException
import dev.nirang.client.registration.RemoteAccessState
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.vpn.NirangVpnService
import java.io.IOException
import java.util.concurrent.TimeUnit

class SubscriptionWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): ListenableWorker.Result {
        return try {
            SubscriptionRepository(applicationContext).refresh()
            SafeLog.info(applicationContext, "Subscription updated")
            ListenableWorker.Result.success()
        } catch (error: RemoteAccessException) {
            if (error.accessState == RemoteAccessState.BLOCKED) {
                NirangVpnService.stop(applicationContext)
                NativeEvents.emit(
                    "accessBlocked",
                    mapOf("reason" to error.apiReason, "message" to error.message.orEmpty()),
                )
                SafeLog.warning(applicationContext, "Subscription access blocked")
                ListenableWorker.Result.failure()
            } else {
                SafeLog.warning(applicationContext, "Subscription update deferred")
                ListenableWorker.Result.retry()
            }
        } catch (_: IOException) {
            SafeLog.warning(applicationContext, "Subscription update deferred")
            ListenableWorker.Result.retry()
        } catch (_: Exception) {
            SafeLog.error(applicationContext, "Subscription update failed")
            ListenableWorker.Result.failure()
        }
    }
}

object SubscriptionScheduler {
    private const val UNIQUE_WORK = "nirang-subscription-update"
    private const val SCHEDULER_PREFS = "nirang_subscription_scheduler"
    private const val SCHEDULED_INTERVAL = "scheduledIntervalHours"

    fun reconcile(context: Context) {
        val settings = NativeSettings(context)
        val manager = WorkManager.getInstance(context)
        val prefs = context.getSharedPreferences(SCHEDULER_PREFS, Context.MODE_PRIVATE)
        if (!settings.autoUpdate) {
            manager.cancelUniqueWork(UNIQUE_WORK)
            prefs.edit().remove(SCHEDULED_INTERVAL).apply()
            return
        }
        val interval = settings.updateIntervalHours
        val request = PeriodicWorkRequestBuilder<SubscriptionWorker>(
            interval.toLong(), TimeUnit.HOURS,
        )
            .setInitialDelay(interval.toLong(), TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()
        val policy = if (prefs.getInt(SCHEDULED_INTERVAL, -1) == interval) {
            ExistingPeriodicWorkPolicy.KEEP
        } else {
            ExistingPeriodicWorkPolicy.UPDATE
        }
        manager.enqueueUniquePeriodicWork(UNIQUE_WORK, policy, request)
        prefs.edit().putInt(SCHEDULED_INTERVAL, interval).apply()
    }
}
