package com.sukisu.ultra.ui.screen.kpm

import android.util.Log
import androidx.compose.foundation.lazy.LazyListState
import com.sukisu.ultra.ui.util.getRootShell
import java.io.File
import java.io.FileInputStream

fun extractModuleName(file: File): String? {
    return try {
        val shell = getRootShell()
        val command = "strings ${file.absolutePath} | grep 'name='"
        val result = shell.newJob().add(command).to(ArrayList(), null).exec()
        if (result.isSuccess) {
            result.out.firstOrNull { it.startsWith("name=") }
                ?.substringAfter("name=")
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } else null
    } catch (e: Exception) {
        Log.e("KsuCli", "Failed to extract module name: ${e.message}", e)
        null
    }
}

fun isValidKpmFile(file: File, mimeType: String?): Boolean {
    val isCorrectMimeType = mimeType == null || mimeType.contains("application/octet-stream")
    if (isCorrectMimeType) return true

    return try {
        checkStringsCommand(file) >= 1 || isElfFile(file)
    } catch (e: Exception) {
        Log.e("KsuCli", "Failed to validate file: ${e.message}", e)
        false
    }
}

fun checkStringsCommand(tempFile: File): Int {
    val shell = getRootShell()
    val command = "strings ${tempFile.absolutePath} | grep -E 'name=|version=|license=|author='"
    val result = shell.newJob().add(command).to(ArrayList(), null).exec()

    if (!result.isSuccess) return 0

    val keywords = listOf("name=", "version=", "license=", "author=")
    var nameExists = false
    var matchCount = 0

    for (line in result.out) {
        when {
            !nameExists && line.startsWith("name=") -> {
                nameExists = true
                matchCount++
            }
            nameExists && keywords.any { line.startsWith(it) } -> {
                matchCount++
            }
        }
    }

    return if (nameExists) matchCount else 0
}

fun isElfFile(tempFile: File): Boolean {
    val elfMagic = byteArrayOf(0x7F, 0x45, 0x4C, 0x46) // "\u007FELF"
    return try {
        FileInputStream(tempFile).use { input ->
            val bytes = ByteArray(4)
            input.read(bytes) == 4 && bytes.contentEquals(elfMagic)
        }
    } catch (e: Exception) {
        Log.e("KsuCli", "Failed to check ELF file: ${e.message}", e)
        false
    }
}

fun isScrolledToEnd(listState: LazyListState): Boolean {
    val layoutInfo = listState.layoutInfo
    val lastItem = layoutInfo.visibleItemsInfo.lastOrNull() ?: return false
    return lastItem.index == layoutInfo.totalItemsCount - 1 &&
            lastItem.size < layoutInfo.viewportEndOffset
}