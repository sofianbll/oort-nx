---
title: Ajouter une recompilation
system: linux
topic: add-recompilation
order: 4
version: 0.1.0-alpha.2
minutes: 5
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04), avec des jeux inventés et un faux Steam. Jamais sur l’ordinateur d’un joueur.
captures: folder-picker, needs-files, file-chosen, prepare
---

## Choisis le dossier
<!-- step folder checked f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Manifest.swift -->
Tuile **+** › **Un dossier de jeux**. Chaque jeu y est un dossier avec son fichier `recomplauncher.json`.

![Le choix d’un dossier (capturé sous Windows)](../../media/windows/folder-picker.fr.webp)

## Regarde ce qui manque
<!-- step needs checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/walk.js -->
Si un jeu demande des fichiers, son bouton devient **Choisir des fichiers**.

![Un jeu inventé qui demande un fichier (capturé sous Windows)](../../media/windows/needs-files.fr.webp)

## Donne ta copie
<!-- step files checked f18e2119:Sources/OortCompanion/Companion.swift f18e2119:desktop/tests/play.js -->
Sur sa page, choisis ton propre fichier. Oort retient seulement où il est, sans le copier.

![La fiche, fichier choisi (capturé sous Windows)](../../media/windows/file-chosen.fr.webp)

## Prépare-le si besoin
<!-- step prepare checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/play.js -->
**Préparation** lance l’étape que le projet a prévue. Si elle demande de copier ou de télécharger des fichiers, il faut la faire dans le projet.

![L’étape Préparation (capturé sous Windows)](../../media/windows/prepare.fr.webp)
