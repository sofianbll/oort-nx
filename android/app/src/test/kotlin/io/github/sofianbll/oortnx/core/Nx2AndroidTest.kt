package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class Nx2AndroidTest {
    @Test fun recognisesTheGamesPackages() {
        assertTrue(Nx2Android.isGamePackage("org.nx2a.supermarioodyssey"))
        assertTrue(Nx2Android.isGamePackage("org.nx2a.t0100000011d90000"))
        assertFalse(Nx2Android.isGamePackage("org.nx2a."))
        assertFalse(Nx2Android.isGamePackage("org.nx2a"))
        assertFalse(Nx2Android.isGamePackage("com.example.org.nx2a.x"))
        assertFalse(Nx2Android.isGamePackage("org.nxnative.android")) // DroidPlay: another product, launched from inside itself
    }

    @Test fun readsATitleIdOnlyWhenThePackageCarriesOne() {
        assertEquals("0100000011D90000", Nx2Android.titleId("org.nx2a.t0100000011d90000"))
        assertNull(Nx2Android.titleId("org.nx2a.supermarioodyssey"))
        assertNull(Nx2Android.titleId("org.nx2a.t0100"))
    }
}
