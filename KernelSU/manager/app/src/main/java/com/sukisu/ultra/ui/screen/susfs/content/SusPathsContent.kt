package com.sukisu.ultra.ui.screen.susfs.content

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.screen.susfs.content.miuix.SusPathsContentMiuix
import com.sukisu.ultra.ui.screen.susfs.content.material.SusPathsContentMaterial

@Composable
fun SusPathsContent(
    susPaths: Set<String>,
    isLoading: Boolean,
    onAddPath: () -> Unit,
    onAddAppPath: () -> Unit,
    onRemovePath: (String) -> Unit,
    onEditPath: ((String) -> Unit)? = null,
    forceRefreshApps: Boolean = false,
    onReset: (() -> Unit)? = null
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> SusPathsContentMiuix(
            susPaths = susPaths,
            isLoading = isLoading,
            onAddPath = onAddPath,
            onAddAppPath = onAddAppPath,
            onRemovePath = onRemovePath,
            onEditPath = onEditPath,
            forceRefreshApps = forceRefreshApps,
            onReset = onReset
        )
        UiMode.Material -> SusPathsContentMaterial(
            susPaths = susPaths,
            isLoading = isLoading,
            onAddPath = onAddPath,
            onAddAppPath = onAddAppPath,
            onRemovePath = onRemovePath,
            onEditPath = { onEditPath?.invoke(it) },
            onReset = { onReset?.invoke() }
        )
    }
}
