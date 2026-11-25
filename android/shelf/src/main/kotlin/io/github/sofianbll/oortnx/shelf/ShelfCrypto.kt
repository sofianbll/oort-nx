package io.github.sofianbll.oortnx.shelf

import java.math.BigInteger
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec

fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

/** SHA-256, and the player's own Mac as the only signer (P-256, DER), known from the code the phone scanned. */
class ShelfCrypto(signer: ByteArray) {
    private val key: ECPublicKey = publicKey(signer) ?: throw IllegalArgumentException("not a P-256 key")

    fun digest(data: ByteArray): String = sha256().digest(data).hex()

    fun isSigned(message: ByteArray, signature: ByteArray): Boolean = try {
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(key)
            update(message)
            verify(signature)
        }
    } catch (_: GeneralSecurityException) {
        false
    }

    companion object {
        private val P256_ORDER = BigInteger("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)

        fun sha256(): MessageDigest = MessageDigest.getInstance("SHA-256")

        fun publicKey(der: ByteArray): ECPublicKey? = try {
            (KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(der)) as? ECPublicKey)?.takeIf { it.params.order == P256_ORDER }
        } catch (_: GeneralSecurityException) {
            null
        }
    }
}
