package com.sukisu.ultra.ui.component.uninstalldialog

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun UninstallDialog(
    show: Boolean,
    onDismissRequest: () -> Unit
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> UninstallDialogMiuix(show, onDismissRequest)
        UiMode.Material -> UninstallDialogMaterial(show, onDismissRequest)
    }
}
