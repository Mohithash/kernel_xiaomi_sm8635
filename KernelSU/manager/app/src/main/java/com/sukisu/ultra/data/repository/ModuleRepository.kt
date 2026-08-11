package com.sukisu.ultra.data.repository

import com.sukisu.ultra.data.model.Module
import com.sukisu.ultra.data.model.ModuleUpdateInfo

interface ModuleRepository {
    suspend fun getModules(): Result<List<Module>>
    suspend fun checkUpdate(module: Module): Result<ModuleUpdateInfo>
}
