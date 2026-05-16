package one.dothings.zellia

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import org.json.JSONArray
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
                    showError(context, appWidgetManager, id, e.message ?: "")
                } catch (_: Exception) {
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

    private fun showError(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        message: String,
    ) {
        val views = RemoteViews(context.packageName, R.layout.zellia_member_widget)
        val str = { res: Int -> context.getString(res) }
        val color = { res: Int -> ContextCompat.getColor(context, res) }
        hideVitalsAndMed(views)
        views.setTextViewText(R.id.widget_nickname, str(R.string.zellia_widget_error_title))
        views.setTextViewText(R.id.widget_bp, message)
        views.setTextColor(R.id.widget_bp, color(R.color.zellia_widget_bp_alert))
        views.setViewVisibility(R.id.widget_bp, View.VISIBLE)
        views.setTextViewText(R.id.widget_updated, "")
        views.setViewVisibility(R.id.widget_updated, View.GONE)
        views.setViewVisibility(R.id.widget_refresh, View.GONE)
        appWidgetManager.updateAppWidget(appWidgetId, views)
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
        fun strFmt(id: Int, vararg args: Any) = context.getString(id, *args)

        try {
            hideVitalsAndMed(views)

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
                views.setViewVisibility(R.id.widget_bp, View.VISIBLE)
                views.setTextViewText(R.id.widget_updated, "")
                views.setViewVisibility(R.id.widget_updated, View.GONE)
                views.setViewVisibility(R.id.widget_refresh, View.GONE)
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
                views.setViewVisibility(R.id.widget_bp, View.VISIBLE)
                views.setTextViewText(R.id.widget_updated, "")
                views.setViewVisibility(R.id.widget_updated, View.GONE)
                views.setViewVisibility(R.id.widget_refresh, View.GONE)
                appWidgetManager.updateAppWidget(appWidgetId, views)
                return
            }

            try {
                val o = JSONObject(rawJson)
                val placeholder = str(R.string.zellia_widget_bp_placeholder)
                val nickname = o.optString("nickname").ifBlank { str(R.string.zellia_widget_nickname_fallback) }
                val latestBp = o.optString("latestBp").ifBlank { placeholder }
                val latestBpAt = o.optString("latestBpRecordedAtIso")
                    .ifBlank { o.optString("latestBpRecordedAt") }
                val latestBs = o.optString("latestBs").ifBlank { placeholder }
                val latestBsAt = o.optString("latestBsRecordedAtIso")
                    .ifBlank { o.optString("latestBsRecordedAt") }
                val isBpNormal = o.optBoolean("isBpNormal", true)
                val medTaken = o.optBoolean("medTakenToday", false)
                val medPlans = o.optJSONArray("medicationPlans")
                val syncedAt = o.optString("syncedAtIso")
                    .ifBlank { o.optString("syncedAt").ifBlank { o.optString("updatedAt") } }

                views.setTextViewText(R.id.widget_nickname, nickname)

                bindReading(
                    context = context,
                    views = views,
                    labelId = R.id.widget_bp_label,
                    valueId = R.id.widget_bp,
                    timeId = R.id.widget_bp_time,
                    value = latestBp,
                    recordedAt = latestBpAt,
                    placeholder = placeholder,
                    isNormal = isBpNormal,
                    normalColor = color(R.color.zellia_widget_bp_normal),
                    alertColor = color(R.color.zellia_widget_bp_alert),
                    recordedAtFormat = { at ->
                        strFmt(
                            R.string.zellia_widget_recorded_at,
                            WidgetTimeFormat.format(context, at),
                        )
                    },
                )

                bindReading(
                    context = context,
                    views = views,
                    labelId = R.id.widget_bs_label,
                    valueId = R.id.widget_bs,
                    timeId = R.id.widget_bs_time,
                    value = latestBs,
                    recordedAt = latestBsAt,
                    placeholder = placeholder,
                    isNormal = true,
                    normalColor = color(R.color.zellia_widget_bp_normal),
                    alertColor = color(R.color.zellia_widget_bp_alert),
                    recordedAtFormat = { at ->
                        strFmt(
                            R.string.zellia_widget_recorded_at,
                            WidgetTimeFormat.format(context, at),
                        )
                    },
                )

                bindMedicationPlans(
                    context = context,
                    views = views,
                    plans = medPlans,
                    legacyMedDisplay = o.optString("medDisplay").trim(),
                    allTakenFallback = medTaken,
                )

                if (syncedAt.isNotBlank()) {
                    views.setTextViewText(
                        R.id.widget_updated,
                        strFmt(
                            R.string.zellia_widget_synced_at,
                            WidgetTimeFormat.format(context, syncedAt),
                        ),
                    )
                    views.setViewVisibility(R.id.widget_updated, View.VISIBLE)
                } else {
                    views.setTextViewText(R.id.widget_updated, "")
                    views.setViewVisibility(R.id.widget_updated, View.GONE)
                }

                attachRefreshAction(context, views, boundMemberId)
            } catch (e: Exception) {
                showError(context, appWidgetManager, appWidgetId, e.message ?: "")
                return
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            showError(context, appWidgetManager, appWidgetId, e.message ?: "")
        }
    }

    private fun hideVitalsAndMed(views: RemoteViews) {
        views.setViewVisibility(R.id.widget_bp_label, View.GONE)
        views.setViewVisibility(R.id.widget_bp_time, View.GONE)
        views.setViewVisibility(R.id.widget_bs_label, View.GONE)
        views.setViewVisibility(R.id.widget_bs, View.GONE)
        views.setViewVisibility(R.id.widget_bs_time, View.GONE)
        views.setViewVisibility(R.id.widget_med_label, View.GONE)
        views.setTextViewText(R.id.widget_med, "")
    }

    private fun bindReading(
        context: Context,
        views: RemoteViews,
        labelId: Int,
        valueId: Int,
        timeId: Int,
        value: String,
        recordedAt: String,
        placeholder: String,
        isNormal: Boolean,
        normalColor: Int,
        alertColor: Int,
        recordedAtFormat: (String) -> String,
    ) {
        val trimmed = value.trim()
        val noData = trimmed.isEmpty() ||
            trimmed == placeholder ||
            trimmed == "暂无" ||
            trimmed.equals("No reading", ignoreCase = true)

        if (noData) {
            views.setViewVisibility(labelId, View.GONE)
            views.setViewVisibility(valueId, View.GONE)
            views.setViewVisibility(timeId, View.GONE)
            return
        }

        views.setViewVisibility(labelId, View.VISIBLE)
        views.setViewVisibility(valueId, View.VISIBLE)
        views.setViewVisibility(timeId, View.GONE)

        val separator = context.getString(R.string.zellia_widget_vital_separator)
        val at = recordedAt.trim()
        val line = if (at.isNotEmpty()) {
            "$trimmed$separator${recordedAtFormat(at)}"
        } else {
            trimmed
        }
        views.setTextViewText(valueId, line)
        try {
            views.setTextColor(valueId, if (isNormal) normalColor else alertColor)
        } catch (_: Exception) {
        }
    }

    private fun bindMedicationPlans(
        context: Context,
        views: RemoteViews,
        plans: JSONArray?,
        legacyMedDisplay: String,
        allTakenFallback: Boolean,
    ) {
        if (plans != null && plans.length() > 0) {
            val sb = StringBuilder()
            for (i in 0 until plans.length()) {
                val p = plans.getJSONObject(i)
                val name = p.optString("name").trim()
                if (name.isEmpty()) continue
                val taken = p.optInt("takenSlots", 0)
                val total = p.optInt("totalSlots", 0)
                val line = when {
                    total > 0 && taken >= total ->
                        context.getString(R.string.zellia_widget_med_line_done, name)
                    taken > 0 ->
                        context.getString(
                            R.string.zellia_widget_med_line_partial,
                            name,
                            taken,
                            total,
                        )
                    else ->
                        context.getString(R.string.zellia_widget_med_line_pending, name)
                }
                if (sb.isNotEmpty()) sb.append('\n')
                sb.append(line)
            }
            if (sb.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_med_label, View.VISIBLE)
                views.setTextViewText(R.id.widget_med, sb.toString())
                views.setViewVisibility(R.id.widget_med, View.VISIBLE)
                return
            }
        }

        if (legacyMedDisplay.isNotEmpty()) {
            views.setViewVisibility(R.id.widget_med_label, View.VISIBLE)
            views.setTextViewText(R.id.widget_med, legacyMedDisplay)
            views.setViewVisibility(R.id.widget_med, View.VISIBLE)
            return
        }

        views.setViewVisibility(R.id.widget_med_label, View.GONE)
        views.setTextViewText(
            R.id.widget_med,
            context.getString(
                if (allTakenFallback) R.string.zellia_widget_med_done
                else R.string.zellia_widget_med_pending,
            ),
        )
        views.setViewVisibility(R.id.widget_med, View.VISIBLE)
    }

    private fun attachRefreshAction(
        context: Context,
        views: RemoteViews,
        memberId: String,
    ) {
        val uri = Uri.Builder()
            .scheme("zellia")
            .authority("refresh")
            .appendQueryParameter("memberId", memberId)
            .build()
        val pendingIntent = HomeWidgetBackgroundIntent.getBroadcast(context, uri)
        views.setOnClickPendingIntent(R.id.widget_refresh, pendingIntent)
        views.setViewVisibility(R.id.widget_refresh, View.VISIBLE)
    }

    private fun boundKey(widgetId: Int) = "bound_widget_$widgetId"

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_CACHED_MEMBERS = "cached_widget_members"
        private const val KEY_PENDING_PIN = "pending_pin_member_id"
    }
}
