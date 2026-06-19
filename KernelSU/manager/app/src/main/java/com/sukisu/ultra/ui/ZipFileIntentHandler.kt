package com.sukisu.ultra.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sukisu.ultra.Natives
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.component.dialog.ConfirmResult
import com.sukisu.ultra.ui.component.dialog.rememberConfirmDialog
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.navigation3.Navigator
import com.sukisu.ultra.ui.navigation3.Route
import com.sukisu.ultra.ui.screen.flash.FlashIt
import com.sukisu.ultra.ui.util.getFileName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.util.zip.ZipInputStream

@Composable
fun HandleZipFileIntent(
    intentState: MutableStateFlow<Int>,
) {
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val confirmDialog = rememberConfirmDialog()
    var processed by remember { mutableStateOf(false) }

    val strings = Strings(
        safeMode = stringResource(R.string.safe_mode_module_disabled),
        zipTypeModule = stringResource(R.string.zip_type_module),
        zipTypeKernel = stringResource(R.string.zip_type_kernel),
        zipFileUnknown = stringResource(R.string.zip_file_unknown),
        mixedInstallPrompt = stringResource(R.string.mixed_install_prompt_with_name),
        kernelInstallPrompt = stringResource(R.string.kernel_install_prompt_with_name),
        moduleInstallPrompt = stringResource(R.string.module_install_prompt_with_name),
        horizonKernel = stringResource(R.string.horizon_kernel),
        module = stringResource(R.string.module),
    )

    val intentStateValue by intentState.collectAsStateWithLifecycle()
    val activity = LocalActivity.current ?: return

    LaunchedEffect(intentStateValue) {
        if (processed) return@LaunchedEffect

        val zipUris = extractZipUris(activity.intent)
        if (zipUris.isEmpty()) return@LaunchedEffect

        processed = true
        activity.intent.data = null
        activity.intent.type = null

        val zipTypes = withContext(Dispatchers.IO) {
            zipUris.map { uri -> detectZipType(context, uri) }
        }

        val (moduleUris, kernelUris, unknownUris) = categorizeUris(zipUris, zipTypes)
        val finalModuleUris = moduleUris + unknownUris

        val fileNames = buildFileNames(zipUris, zipTypes, context, strings)
        val (confirmTitle, confirmContent) = buildConfirmInfo(
            moduleUris, kernelUris, fileNames, strings
        )

        if (confirmDialog.awaitConfirm(title = confirmTitle, content = confirmContent) != ConfirmResult.Confirmed) {
            return@LaunchedEffect
        }

        handleConfirmed(finalModuleUris, kernelUris, context, navigator, strings)
    }
}

private data class Strings(
    val safeMode: String,
    val zipTypeModule: String,
    val zipTypeKernel: String,
    val zipFileUnknown: String,
    val mixedInstallPrompt: String,
    val kernelInstallPrompt: String,
    val moduleInstallPrompt: String,
    val horizonKernel: String,
    val module: String,
)

private fun extractZipUris(intent: Intent): List<Uri> {
    val uris = mutableSetOf<Uri>()

    fun isZipFile(uri: Uri?): Boolean {
        if (uri == null) return false
        val uriString = uri.toString()
        return uriString.endsWith(".zip", ignoreCase = true) ||
               uriString.endsWith(".apk", ignoreCase = true)
    }

    when (intent.action) {
        Intent.ACTION_VIEW, Intent.ACTION_SEND -> {
            val data = intent.data
            val stream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (isZipFile(data)) uris.add(data!!)
            if (isZipFile(stream)) uris.add(stream!!)
        }
        Intent.ACTION_SEND_MULTIPLE -> {
            val streamList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            streamList?.filter { isZipFile(it) }?.let { uris.addAll(it) }
        }
    }

    intent.clipData?.let { clipData ->
        for (i in 0 until clipData.itemCount) {
            clipData.getItemAt(i)?.uri?.let { if (isZipFile(it)) uris.add(it) }
        }
    }

    return uris.toList()
}

private fun categorizeUris(uris: List<Uri>, types: List<ZipType>): Triple<List<Uri>, List<Uri>, List<Uri>> {
    val moduleUris = mutableListOf<Uri>()
    val kernelUris = mutableListOf<Uri>()
    val unknownUris = mutableListOf<Uri>()

    uris.forEachIndexed { index, uri ->
        when (types[index]) {
            ZipType.MODULE -> moduleUris.add(uri)
            ZipType.KERNEL -> kernelUris.add(uri)
            ZipType.UNKNOWN -> unknownUris.add(uri)
        }
    }
    return Triple(moduleUris, kernelUris, unknownUris)
}

private fun buildFileNames(
    uris: List<Uri>,
    types: List<ZipType>,
    context: Context,
    strings: Strings
): String {
    return uris.mapIndexed { index, uri ->
        val fileName = uri.getFileName(context) ?: strings.zipFileUnknown
        val typeStr = when (types[index]) {
            ZipType.MODULE -> strings.zipTypeModule
            ZipType.KERNEL -> strings.zipTypeKernel
            ZipType.UNKNOWN -> strings.zipFileUnknown
        }
        "\n${index + 1}. $fileName$typeStr"
    }.joinToString("")
}

private fun buildConfirmInfo(
    moduleUris: List<Uri>,
    kernelUris: List<Uri>,
    fileNames: String,
    strings: Strings
): Pair<String, String> {
    val title = if (kernelUris.isNotEmpty() && moduleUris.isEmpty()) {
        strings.horizonKernel
    } else {
        strings.module
    }

    val content = when {
        moduleUris.isNotEmpty() && kernelUris.isNotEmpty() -> strings.mixedInstallPrompt.format(fileNames)
        kernelUris.isNotEmpty() -> strings.kernelInstallPrompt.format(fileNames)
        else -> strings.moduleInstallPrompt.format(fileNames)
    }

    return title to content
}

private suspend fun handleConfirmed(
    moduleUris: List<Uri>,
    kernelUris: List<Uri>,
    context: Context,
    navigator: Navigator,
    strings: Strings
) {
    if (moduleUris.isNotEmpty()) {
        if (Natives.isSafeMode) {
            Toast.makeText(context, strings.safeMode, Toast.LENGTH_SHORT).show()
        } else {
            val cachedUris = withContext(Dispatchers.IO) {
                moduleUris.mapNotNull { copyUriToCache(context, it) }
            }

            if (cachedUris.isNotEmpty()) {
                navigator.push(Route.Flash(FlashIt.FlashModules(cachedUris)))
            } else {
                Toast.makeText(context, R.string.zip_file_unknown, Toast.LENGTH_SHORT).show()
            }
        }
    }

    if (kernelUris.isNotEmpty()) {
        navigator.push(Route.Install(preselectedKernelUri = kernelUris.first()))
    }
}

private fun copyUriToCache(context: Context, uri: Uri): Uri? {
    return try {
        val fileName = uri.getFileName(context) ?: "module_${System.currentTimeMillis()}.zip"
        val destFile = File(context.cacheDir, fileName)

        context.contentResolver.openInputStream(uri)?.use { input ->
            destFile.outputStream().use { output -> input.copyTo(output) }
        }

        Uri.fromFile(destFile)
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

enum class ZipType {
    MODULE,
    KERNEL,
    UNKNOWN
}

private fun detectZipType(context: Context, uri: Uri): ZipType {
    val isApk = uri.toString().lowercase().endsWith(".apk", ignoreCase = true)

    return try {
        context.contentResolver.openInputStream(uri)?.use { inputStream ->
            ZipInputStream(inputStream).use { zipStream ->
                detectFromZipStream(zipStream, isApk)
            }
        } ?: defaultType(isApk)
    } catch (e: Exception) {
        e.printStackTrace()
        defaultType(isApk)
    }
}

private fun detectFromZipStream(zipStream: ZipInputStream, isApk: Boolean): ZipType {
    var hasModuleProp = false
    var hasToolsFolder = false
    var hasAnykernelSh = false

    var entry = zipStream.nextEntry
    while (entry != null) {
        val entryName = entry.name.lowercase()
        when {
            entryName == "module.prop" || entryName.endsWith("/module.prop") -> hasModuleProp = true
            entryName.startsWith("tools/") || entryName == "tools" -> hasToolsFolder = true
            entryName == "anykernel.sh" || entryName.endsWith("/anykernel.sh") -> hasAnykernelSh = true
        }
        zipStream.closeEntry()
        entry = zipStream.nextEntry
    }

    return when {
        hasModuleProp -> ZipType.MODULE
        hasToolsFolder && hasAnykernelSh -> ZipType.KERNEL
        isApk -> ZipType.MODULE
        else -> ZipType.UNKNOWN
    }
}

private fun defaultType(isApk: Boolean) = if (isApk) ZipType.MODULE else ZipType.UNKNOWN
