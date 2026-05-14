package one.dothings.zellia

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * Reads payloads written by Flutter [home_widget] into
 * `SharedPreferences("HomeWidgetPreferences")` (same file as [HomeWidgetPlugin] on Android).
 *
 * Each [appWidgetId] is bound independently via `bound_widget_<id>` → member id, then
 * `member_data_<memberId>` JSON is rendered. In-app pin uses `pending_pin_member_id`
 * once when the first [onUpdate] runs for the new instance.
 */
class ZelliaMemberWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            try {
                updateAppWidget(context, appWidgetManager, id)
            } catch (e: Exception) {
                try {
                    val views = RemoteViews(context.packageName, R.layout.zellia_member_widget)
                    val str = { res: Int -> context.getString(res) }
                    val color = { res: Int -> ContextCompat.getColor(context, res) }
                    views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_error_title))
                    views.setTextViewText(R.id.widget_bp, e.message ?: "")
                    views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_bp_alert))
                    views.setTextViewText(R.id.widget_med, "")
                    views.setTextViewText(R.id.widget_updated, "")
                    appWidgetManager.updateAppWidget(id, views)
                } catch (_: Exception) {
                    // ignore secondary failures
                }
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val ed = prefs.edit()
            for (wid in appWidgetIds) {
                ed.remove(boundKey(wid))
            }
            ed.apply()
        } catch (_: Exception) {
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, R.layout.zellia_member_widget)

        fun color(id: Int) = ContextCompat.getColor(context, id)
        fun str(id: Int) = context.getString(id)

        try {
            views.setViewVisibility(R.id.widget_bp_label, View.GONE)

            val bKey = boundKey(appWidgetId)
            var boundMemberId = prefs.getString(bKey, null)?.trim()?.takeIf { it.isNotEmpty() }

            if (boundMemberId == null) {
                val pending = prefs.getString(KEY_PENDING_PIN, null)?.trim()?.takeIf { it.isNotEmpty() }
                if (pending != null) {
                    prefs.edit()
                        .putString(bKey, pending)
                        .remove(KEY_PENDING_PIN)
                        .apply()
                    boundMemberId = pending
                }
            }

            // Legacy single-member home: only auto-bind when the cache lists exactly one id
            // so we do not assign the same member to multiple unbound widgets.
            if (boundMemberId == null) {
                val legacyIds = prefs.getString(KEY_CACHED_MEMBERS, null)
                    ?.split(',')
                    ?.map { it.trim() }
                    ?.filter { it.isNotEmpty() }
                    .orEmpty()
                if (legacyIds.size == 1) {
                    val mid = legacyIds.first()
                    prefs.edit().putString(bKey, mid).apply()
                    boundMemberId = mid
                }
            }

            if (boundMemberId.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_empty_title))
                views.setTextViewText(R.id.widget_bp, str(R.string.zellia_widget_empty_hint))
                views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_muted))
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
                appWidgetManager.updateAppWidget(appWidgetId, views)
                return
            }

            val dataKeyNew = "member_data_$boundMemberId"
            val dataKeyLegacy = "widget_data_$boundMemberId"
            val rawJson = try {
                prefs.getString(dataKeyNew, null)?.takeIf { it.isNotBlank() }
                    ?: prefs.getString(dataKeyLegacy, null)?.takeIf { it.isNotBlank() }
            } catch (_: Exception) {
                null
            }

            if (rawJson.isNullOrBlank()) {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_no_data_title))
                views.setTextViewText(R.id.widget_bp, str(R.string.zellia_widget_no_data_hint))
                views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_muted))
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
                appWidgetManager.updateAppWidget(appWidgetId, views)
                return
            }

            try {
                val o = JSONObject(rawJson)
                val nickname = o.optString("nickname").ifBlank { str(R.string.zellia_widget_nickname_fallback) }
                val latestBp = o.optString("latestBp").ifBlank { str(R.string.zellia_widget_bp_placeholder) }
                val isBpNormal = o.optBoolean("isBpNormal", true)
                val medTaken = o.optBoolean("medTakenToday", false)
                val footer = o.optString("updatedAt")

                views.setTextViewText(R.id.widget_nickname, nickname)
                views.setViewVisibility(R.id.widget_bp_label, View.VISIBLE)
                views.setTextViewText(R.id.widget_bp, latestBp)
                try {
                    views.setTextColor(
                        R.id.widget_bp,
                        if (isBpNormal) color(R.color.zellia_widget_bp_normal)
                        else color(R.color.zellia_widget_bp_alert),
                    )
                } catch (_: Exception) {
                }

                val medLine = str(
                    if (medTaken) R.string.zellia_widget_med_done
                    else R.string.zellia_widget_med_pending,
                )
                views.setTextViewText(R.id.widget_med, medLine)
                views.setTextViewText(R.id.widget_updated, footer)
            } catch (e: Exception) {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_error_title))
                views.setTextViewText(R.id.widget_bp, e.message ?: "")
                try {
                    views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_bp_alert))
                } catch (_: Exception) {
                }
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            try {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_error_title))
                views.setTextViewText(R.id.widget_bp, e.message ?: "")
                views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_bp_alert))
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (_: Exception) {
            }
        }
    }

    private fun boundKey(widgetId: Int) = "bound_widget_$widgetId"

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_CACHED_MEMBERS = "cached_widget_members"
        private const val KEY_PENDING_PIN = "pending_pin_member_id"
    }
}
