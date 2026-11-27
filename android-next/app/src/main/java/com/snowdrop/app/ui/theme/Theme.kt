package com.snowdrop.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

@Immutable
data class SnowdropPalette(
    val isDark: Boolean,
    val background: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val hairline: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textMuted: Color,
    val accent: Color,
    val onAccent: Color,
    val positive: Color,
    val warning: Color,
    val critical: Color,
    val glassTint: Color,
    val glassFallback: Color,
    val specularTop: Color,
    val specularBottom: Color
)

val LightSnowdropPalette = SnowdropPalette(
    isDark = false,
    background = Color(0xFFF6F8FA),
    surface = Color(0xFFFFFFFF),
    surfaceElevated = Color(0xFFEEF2F6),
    hairline = Color(0x140F172A),       // 8% slate
    textPrimary = Color(0xFF0F172A),
    textSecondary = Color(0xFF475569),
    textMuted = Color(0xFF64748B),
    accent = Color(0xFF0284C7),
    onAccent = Color(0xFFFFFFFF),
    positive = Color(0xFF059669),
    warning = Color(0xFFD97706),
    critical = Color(0xFFE11D48),
    glassTint = Color(0xB8FFFFFF),       // translucent frost tint
    glassFallback = Color(0xEBFFFFFF),   // opaque-leaning frost on API 26-30
    specularTop = Color(0xB3FFFFFF),     // neutral white top highlight
    specularBottom = Color(0x2E0F172A)   // subtle neutral lower rim
)

val DarkSnowdropPalette = SnowdropPalette(
    isDark = true,
    background = Color(0xFF0E1116),
    surface = Color(0xFF161B22),
    surfaceElevated = Color(0xFF1F2630),
    hairline = Color(0x14FFFFFF),       // 8% white
    textPrimary = Color(0xFFF1F5F9),
    textSecondary = Color(0xFF94A3B8),
    textMuted = Color(0xFF64748B),
    accent = Color(0xFF38BDF8),
    onAccent = Color(0xFF090D16),
    positive = Color(0xFF10B981),
    warning = Color(0xFFF59E0B),
    critical = Color(0xFFF43F5E),
    glassTint = Color(0xA6161B22),       // translucent dark glass tint
    glassFallback = Color(0xEB161B22),   // API 26-30 frosted dark scrim
    specularTop = Color(0x38FFFFFF),     // neutral white top specular rim
    specularBottom = Color(0x0FFFFFFF)   // subtle neutral bottom rim
)

val LocalSnowdropPalette = staticCompositionLocalOf { DarkSnowdropPalette }

private val DarkColorScheme = darkColorScheme(
    primary = DarkSnowdropPalette.accent,
    onPrimary = DarkSnowdropPalette.onAccent,
    background = DarkSnowdropPalette.background,
    surface = DarkSnowdropPalette.surface,
    surfaceVariant = DarkSnowdropPalette.surfaceElevated,
    onBackground = DarkSnowdropPalette.textPrimary,
    onSurface = DarkSnowdropPalette.textPrimary,
    onSurfaceVariant = DarkSnowdropPalette.textSecondary,
    error = DarkSnowdropPalette.critical
)

private val LightColorScheme = lightColorScheme(
    primary = LightSnowdropPalette.accent,
    onPrimary = LightSnowdropPalette.onAccent,
    background = LightSnowdropPalette.background,
    surface = LightSnowdropPalette.surface,
    surfaceVariant = LightSnowdropPalette.surfaceElevated,
    onBackground = LightSnowdropPalette.textPrimary,
    onSurface = LightSnowdropPalette.textPrimary,
    onSurfaceVariant = LightSnowdropPalette.textSecondary,
    error = LightSnowdropPalette.critical
)

private val SnowdropTypography = Typography(
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 26.sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp),
    titleSmall = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, lineHeight = 20.sp),
    bodyLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Normal, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Normal, lineHeight = 20.sp),
    bodySmall = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Normal, lineHeight = 16.sp),
    labelMedium = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, lineHeight = 18.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, lineHeight = 16.sp)
)

@Composable
fun SnowdropTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val palette = if (darkTheme) DarkSnowdropPalette else LightSnowdropPalette
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    CompositionLocalProvider(LocalSnowdropPalette provides palette) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = SnowdropTypography,
            content = content
        )
    }
}

object SnowdropThemeTokens {
    val palette: SnowdropPalette
        @Composable get() = LocalSnowdropPalette.current
}

fun TextStyle.tabular(): TextStyle = copy(fontFeatureSettings = "tnum")
