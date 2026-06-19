package com.sukisu.ultra.ui.screen.kpm

import androidx.compose.runtime.Immutable
import com.sukisu.ultra.ui.component.SearchStatus
import com.sukisu.ultra.ui.viewmodel.KpmViewModel

@Immutable
data class KpmUiState(
    val isRefreshing: Boolean = false,
    val moduleList: List<KpmViewModel.ModuleInfo> = emptyList(),
    val searchStatus: SearchStatus = SearchStatus(""),
    val searchResults: List<KpmViewModel.ModuleInfo> = emptyList(),
    val error: Throwable? = null,
    val showInstallModeDialog: Boolean = false,
    val tempModuleName: String? = null,
    val inputDialogState: InputDialogState = InputDialogState(),
)

@Immutable
data class InputDialogState(
    val visible: Boolean = false,
    val moduleId: String? = null,
    val args: String = "",
)

@Immutable
data class KpmActions(
    val onRefresh: () -> Unit,
    val onSearchStatusChange: (SearchStatus) -> Unit,
    val onSearchTextChange: (String) -> Unit,
    val onRequestInstall: () -> Unit,
    val onConfirmInstall: (String, Boolean) -> Unit,
    val onDismissInstallDialog: () -> Unit,
    val onRequestUninstall: (String) -> Unit,
    val onConfirmUninstall: (String) -> Unit,
    val onDismissUninstallDialog: () -> Unit,
    val onShowInputDialog: (String) -> Unit,
    val onHideInputDialog: () -> Unit,
    val onInputArgsChange: (String) -> Unit,
    val onExecuteControl: () -> Unit,
)