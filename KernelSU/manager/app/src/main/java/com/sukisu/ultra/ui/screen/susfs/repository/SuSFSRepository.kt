package com.sukisu.ultra.ui.screen.susfs.repository

import android.content.Context
import com.sukisu.ultra.ui.screen.susfs.util.SuSFSManager

interface SuSFSRepository {
    suspend fun loadInitialConfig(context: Context): Result<SuSFSManager.ModuleConfig>

    suspend fun getEnabledFeatures(context: Context): Result<List<SuSFSManager.EnabledFeature>>

    suspend fun getInstalledApps(): Result<List<SuSFSManager.AppInfo>>

    suspend fun getSlotInfo(context: Context): Result<Pair<List<SuSFSManager.SlotInfo>, String>>
}

