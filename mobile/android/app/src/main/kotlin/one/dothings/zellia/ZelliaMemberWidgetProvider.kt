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
 * `SharedPreferences("HomeWidgetPreferences")`.
 *
 * Displays the first cached member's vitals. Multi-member picker can be
 * added later via a widget configuration Activity.
 */
class ZelliaMemberWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) updateAppWidget(context, appWidgetManager, id)
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

        val memberIds = prefs.getString(KEY_CACHED_MEMBERS, null)
            ?.split(',')
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            .orEmpty()

        // Hide the "血压 (mmHg)" label by default; show only when data is available.
        views.setViewVisibility(R.id.widget_bp_label, View.GONE)

        when {
            memberIds.isEmpty() -> {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_empty_title))
                views.setTextViewText(R.id.widget_bp, str(R.string.zellia_widget_empty_hint))
                views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_muted))
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
            }

            prefs.getString("widget_data_${memberIds.first()}", null).isNullOrBlank() -> {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_no_data_title))
                views.setTextViewText(R.id.widget_bp, str(R.string.zellia_widget_no_data_hint))
                views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_muted))
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
            }

            else -> runCatching {
                val rawJson = prefs.getString("widget_data_${memberIds.first()}", null)!!
                val o = JSONObject(rawJson)

                val nickname = o.optString("nickname").ifBlank { "家人" }
                val latestBp = o.optString("latestBp").ifBlank { "暂无" }
                val isBpNormal = o.optBoolean("isBpNormal", true)
                val medTaken = o.optBoolean("medTakenToday", false)
                var footer = o.optString("updatedAt")
                if (memberIds.size > 1) {
                    val hint = str(R.string.zellia_widget_multi_hint).format(memberIds.size)
                    footer = listOf(footer, hint).filter { it.isNotBlank() }.joinToString("  ·  ")
                }

                views.setTextViewText(R.id.widget_nickname, nickname)

                // Show BP label only when real data is present
                views.setViewVisibility(R.id.widget_bp_label, View.VISIBLE)
                views.setTextViewText(R.id.widget_bp, latestBp)
                views.setTextColor(
                    R.id.widget_bp,
                    if (isBpNormal) color(R.color.zellia_widget_bp_normal)
                    else color(R.color.zellia_widget_bp_alert),
                )

                val medLine = str(
                    if (medTaken) R.string.zellia_widget_med_done
                    else R.string.zellia_widget_med_pending,
                )
                views.setTextViewText(R.id.widget_med, medLine)
                views.setTextViewText(R.id.widget_updated, footer)

            }.onFailure {
                views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_error_title))
                views.setTextViewText(R.id.widget_bp, it.message ?: "")
                views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_bp_alert))
                views.setTextViewText(R.id.widget_med, "")
                views.setTextViewText(R.id.widget_updated, "")
            }
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_CACHED_MEMBERS = "cached_widget_members"
    }
}
