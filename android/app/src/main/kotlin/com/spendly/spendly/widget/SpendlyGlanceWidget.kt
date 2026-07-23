package com.spendly.spendly.widget

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.spendly.spendly.MainActivity
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import org.json.JSONArray

/// Single responsive Glance widget (Android home widgets are resizable, so one
/// adaptive layout is idiomatic rather than three fixed sizes). Reads the same
/// snapshot the Flutter app writes via home_widget; a quick-add tap deep-links
/// into Quick Add (spendly://quickadd?category=<id>), handled in app.dart.
class SpendlyGlanceWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    private val indigo = Color(0xFF4F46E5)
    private val white = ColorProvider(Color.White)

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Body(context) }
    }

    @Composable
    private fun Body(context: Context) {
        val prefs = currentState<HomeWidgetGlanceState>().preferences
        val monthTotal = prefs.getString("monthTotal", "₹0") ?: "₹0"
        val todayTotal = prefs.getString("todayTotal", "₹0") ?: "₹0"
        val hasBudget = prefs.getString("hasBudget", "false") == "true"
        val budgetPct = prefs.getString("budgetPct", "0") ?: "0"
        val budgetLeft = prefs.getString("budgetLeft", "") ?: ""
        val quickAdd = parseQuick(prefs.getString("quickAdd", "[]") ?: "[]")

        Column(
            modifier = GlanceModifier.fillMaxSize().background(indigo).padding(16.dp)
        ) {
            Text(
                "THIS MONTH",
                style = TextStyle(color = white, fontSize = 11.sp, fontWeight = FontWeight.Medium),
            )
            Text(
                monthTotal,
                style = TextStyle(color = white, fontSize = 24.sp, fontWeight = FontWeight.Bold),
            )
            if (hasBudget) {
                Text(
                    "$budgetPct% used · $budgetLeft left",
                    style = TextStyle(color = white, fontSize = 11.sp),
                )
            }
            Text("Today $todayTotal", style = TextStyle(color = white, fontSize = 12.sp))
            Spacer(GlanceModifier.height(10.dp))
            Row {
                quickAdd.take(4).forEach { (id, icon) ->
                    Text(
                        icon,
                        style = TextStyle(fontSize = 22.sp),
                        modifier = GlanceModifier.padding(6.dp).clickable(
                            actionStartActivity<MainActivity>(
                                context,
                                Uri.parse("spendly://quickadd?category=$id"),
                            ),
                        ),
                    )
                }
            }
        }
    }

    private fun parseQuick(json: String): List<Pair<Int, String>> {
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                o.getInt("id") to o.getString("icon")
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
