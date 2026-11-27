package com.snowdrop.app.ui.components

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.snowdrop.app.ui.theme.SnowdropThemeTokens
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeChild

/**
 * Layer 2 floating Liquid Glass container.
 * Uses real-time RenderEffect backdrop blur on API 31+ via Haze and falls back to
 * a translucent frosted scrim on API 26-30, framed by a neutral specular hairline.
 */
@Composable
fun SnowdropGlassSurface(
    hazeState: HazeState?,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(24.dp),
    content: @Composable BoxScope.() -> Unit
) {
    val palette = SnowdropThemeTokens.palette
    val borderBrush = Brush.verticalGradient(
        colors = listOf(palette.specularTop, palette.specularBottom)
    )

    val glassModifier = if (hazeState != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val style = HazeStyle(
            backgroundColor = palette.glassFallback,
            tint = HazeTint(color = palette.glassTint),
            blurRadius = 20.dp,
            noiseFactor = 0.03f
        )
        Modifier.hazeChild(state = hazeState, style = style)
    } else {
        Modifier.background(palette.glassFallback)
    }

    Box(
        modifier = modifier
            .shadow(
                elevation = if (palette.isDark) 8.dp else 12.dp,
                shape = shape,
                ambientColor = palette.textPrimary.copy(alpha = 0.08f),
                spotColor = palette.textPrimary.copy(alpha = 0.08f)
            )
            .clip(shape)
            .then(glassModifier)
            .border(width = 1.dp, brush = borderBrush, shape = shape),
        content = content
    )
}
