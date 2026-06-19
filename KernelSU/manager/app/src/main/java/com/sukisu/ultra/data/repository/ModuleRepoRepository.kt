package com.sukisu.ultra.data.repository

import com.sukisu.ultra.data.model.RepoModule

interface ModuleRepoRepository {
    suspend fun fetchModules(): Result<List<RepoModule>>
}
