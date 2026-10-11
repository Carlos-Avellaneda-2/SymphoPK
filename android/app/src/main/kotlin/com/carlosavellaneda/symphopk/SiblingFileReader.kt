package com.carlosavellaneda.symphopk

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import java.io.File

/**
 * Lee archivos que no son multimedia (los `.lrc` de las letras).
 *
 * Desde Android 11 el permiso de audio solo cubre archivos de audio: un
 * `.lrc` junto a la canción no se puede abrir por su ruta. Aquí se intenta
 * primero la lectura directa (funciona hasta Android 10) y después a través
 * de las carpetas que el usuario haya concedido con el selector del sistema.
 */
object SiblingFileReader {
    private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"

    // Una letra ocupa unos pocos KB; el límite evita cargar por error un
    // archivo enorme con extensión .lrc.
    private const val MAX_BYTES = 1024 * 1024

    /** Contenido del archivo, o `null` si no existe o no hay acceso. */
    fun read(context: Context, path: String): ByteArray? =
        readDirectly(path) ?: readThroughGrantedFolder(context, path)

    private fun readDirectly(path: String): ByteArray? = try {
        val file = File(path)
        if (file.isFile && file.canRead() && file.length() <= MAX_BYTES) file.readBytes() else null
    } catch (e: Exception) {
        null
    }

    private fun readThroughGrantedFolder(context: Context, path: String): ByteArray? {
        for (folder in grantedFolders(context)) {
            if (path != folder.path && !path.startsWith(folder.path + "/")) continue
            val relative = path.removePrefix(folder.path).trimStart('/')
            val treeId = DocumentsContract.getTreeDocumentId(folder.uri)
            val documentId = when {
                relative.isEmpty() -> treeId
                treeId.endsWith(":") -> treeId + relative
                else -> "$treeId/$relative"
            }
            val document = DocumentsContract.buildDocumentUriUsingTree(folder.uri, documentId)
            try {
                context.contentResolver.openInputStream(document)?.use { stream ->
                    val bytes = stream.readBytes()
                    if (bytes.size <= MAX_BYTES) return bytes
                }
            } catch (e: Exception) {
                // El archivo no existe en esta carpeta: se prueba la siguiente.
            }
        }
        return null
    }

    data class GrantedFolder(val uri: Uri, val path: String)

    /** Carpetas con permiso de lectura persistente, con su ruta equivalente. */
    fun grantedFolders(context: Context): List<GrantedFolder> =
        context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission && it.uri.authority == EXTERNAL_STORAGE_AUTHORITY }
            .mapNotNull { permission ->
                pathOf(permission.uri)?.let { GrantedFolder(permission.uri, it) }
            }

    /**
     * Convierte el identificador de un árbol de documentos en ruta:
     * `primary:Music` -> `/storage/emulated/0/Music` y
     * `1A2B-3C4D:Music` -> `/storage/1A2B-3C4D/Music`.
     */
    private fun pathOf(treeUri: Uri): String? = try {
        val treeId = DocumentsContract.getTreeDocumentId(treeUri)
        val volume = treeId.substringBefore(':')
        val relative = treeId.substringAfter(':', "").trimEnd('/')
        val root = if (volume == "primary") {
            Environment.getExternalStorageDirectory().absolutePath
        } else {
            "/storage/$volume"
        }
        if (relative.isEmpty()) root else "$root/$relative"
    } catch (e: Exception) {
        null
    }

    fun persist(context: Context, treeUri: Uri) {
        context.contentResolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
    }

    fun release(context: Context, treeUri: Uri) {
        try {
            context.contentResolver.releasePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            // El permiso ya no estaba concedido.
        }
    }
}
