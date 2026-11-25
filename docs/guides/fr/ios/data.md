---
title: Ce qu’Oort lit, écrit et envoie
system: ios
topic: data
order: 13
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé seulement sur simulateur (iPhone et iPad, iOS 27.2) avec des jeux inventés. Jamais sur un vrai appareil.
captures: picker, settings, settings
---

## Lit
<!-- step reads code e3cd6df1:mobile/Sources/OortMobile/FrameworkImport.swift e3cd6df1:mobile/PROVENANCE.md -->
Les jeux que tu ajoutes, et les dossiers de Fichiers que tu choisis.

![Fichiers, d’Apple](../../media/ios/picker.fr.webp)

## Écrit
<!-- step writes code e3cd6df1:mobile/Sources/OortMobile/FrameworkImport.swift e3cd6df1:mobile/Sources/ShellHost/PlayHistoryStore.swift -->
Son propre dossier, visible dans Fichiers : jeux, sauvegardes, réglages et temps de jeu. Plus le dossier de sauvegardes que tu as choisi.

![La page Réglages](../../media/ios/settings.fr.webp)

## Envoie
<!-- step sends code e3cd6df1:mobile/PROVENANCE.md e3cd6df1:mobile/Sources/OortMobile/Resources/Localizable.xcstrings -->
Rien : aucune requête réseau, aucun compte. L’outil qui signe l’app, lui, parle à Apple avec ton compte.

![La page Réglages](../../media/ios/settings.fr.webp)
