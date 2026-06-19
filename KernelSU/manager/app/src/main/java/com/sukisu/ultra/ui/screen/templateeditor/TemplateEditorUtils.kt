package com.sukisu.ultra.ui.screen.templateeditor

import com.sukisu.ultra.Natives
import com.sukisu.ultra.data.model.TemplateInfo
import com.sukisu.ultra.ui.util.getAppProfileTemplate
import com.sukisu.ultra.ui.util.setAppProfileTemplate

fun toNativeProfile(templateInfo: TemplateInfo): Natives.Profile {
    return Natives.Profile().copy(
        rootTemplate = templateInfo.id,
        uid = templateInfo.uid,
        gid = templateInfo.gid,
        groups = templateInfo.groups,
        capabilities = templateInfo.capabilities,
        context = templateInfo.context,
        namespace = templateInfo.namespace,
        rules = templateInfo.rules.joinToString("\n").ifBlank { "" }
    )
}

fun isTemplateValid(template: TemplateInfo): Boolean {
    if (template.id.isBlank()) {
        return false
    }
    if (!isValidTemplateId(template.id)) {
        return false
    }
    return true
}

fun idCheck(value: String): Int {
    return if (value.isEmpty()) 0 else if (isTemplateExist(value)) 1 else if (!isValidTemplateId(value)) 2 else 0
}

fun saveTemplate(template: TemplateInfo, isCreation: Boolean = false): Boolean {
    if (!isTemplateValid(template)) {
        return false
    }
    if (isCreation && isTemplateExist(template.id)) {
        return false
    }
    val json = template.toJSON()
    json.put("local", true)
    return setAppProfileTemplate(template.id, json.toString())
}

fun isValidTemplateId(id: String): Boolean {
    return Regex("""^([A-Za-z][A-Za-z\d_]*\.)*[A-Za-z][A-Za-z\d_]*$""").matches(id)
}

fun isTemplateExist(id: String): Boolean {
    return getAppProfileTemplate(id).isNotBlank()
}
