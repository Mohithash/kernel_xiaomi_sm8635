package com.sukisu.ultra.ui.screen.susfs

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun SuSFSScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> SuSFSMiuix()
        UiMode.Material -> SuSFSMaterial()
    }
}
