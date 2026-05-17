package one.dothings.zellia.family_voice

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Family voice content URIs + locked-screen poke playback (FCM background isolate). */
class FamilyVoicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: android.content.Context
    private var pokePlayer: MediaPlayer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        releasePokePlayer()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "notificationSoundUri" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("ARG", "path is required", null)
                    return
                }
                val file = File(path)
                if (!file.exists() || file.length() == 0L) {
                    result.success(null)
                    return
                }
                try {
                    val authority = "${appContext.packageName}.family_voice_provider"
                    val uri: Uri = FileProvider.getUriForFile(appContext, authority, file)
                    grantSoundUriReadAccess(uri)
                    result.success(uri.toString())
                } catch (e: Exception) {
                    result.error("URI", e.message, null)
                }
            }
            "playPoke" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("ARG", "path is required", null)
                    return
                }
                val file = File(path)
                if (!file.exists() || file.length() == 0L) {
                    result.success(false)
                    return
                }
                try {
                    playPokeFile(file)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("PLAY", e.message, null)
                }
            }
            "stopPoke" -> {
                releasePokePlayer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun playPokeFile(file: File) {
        releasePokePlayer()
        val player = MediaPlayer()
        pokePlayer = player
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        player.setDataSource(file.absolutePath)
        player.prepare()
        player.setOnCompletionListener {
            releasePokePlayer()
        }
        player.start()
    }

    private fun releasePokePlayer() {
        pokePlayer?.let { player ->
            try {
                player.stop()
            } catch (_: Exception) {
            }
            try {
                player.release()
            } catch (_: Exception) {
            }
        }
        pokePlayer = null
    }

    private fun grantSoundUriReadAccess(uri: Uri) {
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val targets = listOf("com.android.systemui", "android")
        for (pkg in targets) {
            try {
                appContext.grantUriPermission(pkg, uri, read)
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "one.dothings.zellia/family_voice"
    }
}
