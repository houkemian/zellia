package one.dothings.zellia

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Exposes content:// URIs for family voice files (notification sounds). */
class FamilyVoicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: android.content.Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
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
            else -> result.notImplemented()
        }
    }

    private fun grantSoundUriReadAccess(uri: Uri) {
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val targets =
            listOf(
                "com.android.systemui",
                "android",
            )
        for (pkg in targets) {
            try {
                appContext.grantUriPermission(pkg, uri, read)
            } catch (_: Exception) {
                // Best-effort; some OEMs use different SystemUI package names.
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "one.dothings.zellia/family_voice"
    }
}
