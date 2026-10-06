package dev.nirang.client.feedback

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import dev.nirang.client.R

/** Optional, preloaded action and navigation sounds owned by the activity. */
class InteractionSound(context: Context) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()
    private val readySounds = java.util.concurrent.ConcurrentHashMap.newKeySet<Int>()
    @Volatile private var released = false
    private val soundId: Int
    private val navigationSoundId: Int

    init {
        pool.setOnLoadCompleteListener { _, loadedId, status ->
            if (status == 0 && !released) readySounds.add(loadedId)
        }
        soundId = try {
            pool.load(context, R.raw.interaction_pop, 1)
        } catch (error: Exception) {
            pool.release()
            throw error
        }
        navigationSoundId = try {
            pool.load(context, R.raw.navigation_pop, 1)
        } catch (error: Exception) {
            pool.release()
            throw error
        }
    }

    fun play() {
        if (released || soundId !in readySounds) return
        pool.play(soundId, .45f, .45f, 1, 0, 1f)
    }

    fun playNavigation() {
        if (released || navigationSoundId !in readySounds) return
        pool.play(navigationSoundId, .7f, .7f, 1, 0, 1f)
    }

    fun release() {
        released = true
        readySounds.clear()
        pool.setOnLoadCompleteListener(null)
        pool.release()
    }
}
