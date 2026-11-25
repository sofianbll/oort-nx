package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SearchTest {
    @Test fun caseAndAccentsDoNotCount() {
        assertTrue(matches("Marée haute", "MAREE"))
        assertTrue(matches("Maree haute", "marée"))
    }

    @Test fun everyWordMustBeThereInAnyOrder() {
        assertTrue(matches("Le phare de Brume", "brume phare"))
        assertFalse(matches("Le phare de Brume", "phare rouge"))
    }

    @Test fun anEmptyOrBlankQueryKeepsEveryGame() {
        assertTrue(matches("Collines rouges", ""))
        assertTrue(matches("Collines rouges", "  "))
    }
}
