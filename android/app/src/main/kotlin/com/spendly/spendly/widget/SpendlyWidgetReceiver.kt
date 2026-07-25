package com.spendly.spendly.widget

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/// AppWidget receiver bound to [SpendlyGlanceWidget]. home_widget's base class
/// re-reads the shared prefs snapshot and re-renders on each update broadcast.
class SpendlyWidgetReceiver : HomeWidgetGlanceWidgetReceiver<SpendlyGlanceWidget>() {
    override val glanceAppWidget = SpendlyGlanceWidget()
}
