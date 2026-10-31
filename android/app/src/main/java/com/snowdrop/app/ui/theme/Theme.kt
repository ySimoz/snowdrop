package com.snowdrop.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Frost Sapphire & Slate Design Tokens
val FrostSlate950 = Color(0xFF090D16)
val FrostSlate900 = Color(0xFF0F172A)
val FrostSlate800 = Color(0xFF1E293B)
val FrostSlate700 = Color(0xFF334155)
val FrostSlate600 = Color(0xFF475569)
val FrostSlate400 = Color(0xFF94A3B8)
val FrostSlate100 = Color(0xFFF1F5F9)
val FrostSlate50  = Color(0xFFF8FAFC)

val FrostIceBlue  = Color(0xFF38BDF8)
val FrostSapphire = Color(0xFF2563EB)
val FrostEmerald  = Color(0xFF10B981)
val FrostAmber    = Color(0xFFF59E0B)
val FrostRose     = Color(0xFFF43F5E)

val GlassCardBg     = Color(0xBF1E293B) // 75% Slate 800
val GlassBorder     = Color(0x3338BDF8) // 20% Ice Blue
val GlassBorderMuted = Color(0x1FFFFFFF) // 12% White

private val DarkColorScheme = darkColorScheme(
    primary = FrostIceBlue,
    onPrimary = FrostSlate950,
    primaryContainer = Color(0xFF0369A1),
    onPrimaryContainer = Color(0xFFE0F2FE),
    secondary = FrostSapphire,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFF1E3A8A),
    onSecondaryContainer = Color(0xFFDBEAFE),
    tertiary = FrostEmerald,
    background = FrostSlate900,
    surface = FrostSlate800,
    surfaceVariant = FrostSlate700,
    onBackground = FrostSlate50,
    onSurface = FrostSlate100,
    onSurfaceVariant = FrostSlate400,
    error = FrostRose
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF0284C7),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFBAE6FD),
    onPrimaryContainer = Color(0xFF0369A1),
    secondary = FrostSapphire,
    onSecondary = Color.White,
    tertiary = FrostEmerald,
    background = Color(0xFFF8FAFC),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFE2E8F0),
    onBackground = Color(0xFF0F172A),
    onSurface = Color(0xFF0F172A),
    onSurfaceVariant = Color(0xFF64748B),
    error = FrostRose
)

@Composable
fun SnowdropTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
