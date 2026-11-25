package io.github.sofianbll.oortnx.drive

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** A credential. Printing or interpolating it shows nothing. */
class DriveSecret(private val value: String) {
    /** Only where it goes into a request or into the vault. */
    internal fun reveal(): String = value
    override fun toString(): String = "(hidden)"
    override fun equals(other: Any?): Boolean = other is DriveSecret && other.value == value
    override fun hashCode(): Int = value.hashCode()
}

/** Where the refresh token waits between two runs. */
interface DriveVault {
    fun read(): DriveSecret?
    fun write(secret: DriveSecret)
    fun erase()
}

/**
 * The refresh token in a file, sealed with AES-GCM. [key] comes from [DriveKeystore] on a device: it never leaves the secure hardware, so a
 * copy of the file is worth nothing elsewhere. Give it a file in `noBackupFilesDir`.
 */
class DriveSealedVault(private val file: File, private val key: () -> SecretKey, private val eraseKey: () -> Unit = {}) : DriveVault {
    override fun read(): DriveSecret? {
        if (!file.exists()) return null
        return try {
            val sealed = file.readBytes()
            if (sealed.size !in IV + 17..4096) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, IV))
            cipher.updateAAD(LABEL)
            DriveSecret(String(cipher.doFinal(sealed, IV, sealed.size - IV), Charsets.UTF_8))
        } catch (_: GeneralSecurityException) {
            // Another device's copy, a lost key, a changed file: the player signs in again.
            null
        }
    }

    override fun write(secret: DriveSecret) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(LABEL)
        val sealed = cipher.iv + cipher.doFinal(secret.reveal().toByteArray())
        check(cipher.iv.size == IV)
        Files.createDirectories(file.parentFile!!.toPath())
        val next = File(file.path + ".new")
        FileOutputStream(next).use {
            it.write(sealed)
            it.fd.sync()
        }
        Files.move(next.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE)
    }

    override fun erase() {
        Files.deleteIfExists(file.toPath())
        eraseKey()
    }

    private companion object {
        const val IV = 12
        val LABEL = "oort-drive-1".toByteArray()
    }
}

/** The device's keystore: made there, used there, never exported. No player authentication, so a download can go on with the screen off. */
object DriveKeystore {
    private const val STORE = "AndroidKeyStore"
    private const val ALIAS = "oort-drive"

    fun key(): SecretKey {
        val store = KeyStore.getInstance(STORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, STORE).run {
            init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build(),
            )
            generateKey()
        }
    }

    fun erase() {
        KeyStore.getInstance(STORE).apply { load(null) }.deleteEntry(ALIAS)
    }
}
