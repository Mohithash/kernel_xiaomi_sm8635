package com.sukisu.ultra.data.repository

import com.sukisu.ultra.data.model.TemplateInfo

interface TemplateRepository {
    suspend fun getTemplates(sync: Boolean): Result<List<TemplateInfo>>
    suspend fun importTemplates(jsonString: String): Result<Unit>
    suspend fun exportTemplates(): Result<String>
    suspend fun getTemplate(id: String): Result<TemplateInfo>
}
