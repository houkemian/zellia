package one.dothings.zellia

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object WidgetTimeFormat {
    private val isoParser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    private val isoParserNoMillis = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    fun format(context: Context, raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""

        if (trimmed.contains('T')) {
            val parsed = parseIso(trimmed)
            if (parsed != null) {
                val local = Calendar.getInstance().apply { time = parsed }
                val now = Calendar.getInstance()
                val timeFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
                val timePart = timeFmt.format(parsed)
                val sameDay =
                    local.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
                        local.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
                if (sameDay) {
                    return context.getString(R.string.zellia_widget_time_today, timePart)
                }
                val dateFmt = SimpleDateFormat("MM-dd HH:mm", Locale.getDefault())
                return dateFmt.format(parsed)
            }
        }

        if (trimmed.startsWith("今天 ")) {
            return context.getString(
                R.string.zellia_widget_time_today,
                trimmed.removePrefix("今天 ").trim(),
            )
        }
        return trimmed
    }

    private fun parseIso(value: String): Date? {
        return try {
            isoParser.parse(value)
        } catch (_: Exception) {
            try {
                isoParserNoMillis.parse(value)
            } catch (_: Exception) {
                null
            }
        }
    }
}
