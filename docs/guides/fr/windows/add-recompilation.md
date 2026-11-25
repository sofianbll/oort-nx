---
title: Ajouter une recompilation
system: windows
topic: add-recompilation
order: 4
version: 0.1.0-alpha.1
minutes: 5
tried: Essayé sur une machine neuve de GitHub avec des jeux inventés, et par un joueur sur son PC (un jeu lancé, le 25 novembre 2026).
captures: folder-picker, needs-files, file-chosen, prepare
---

## Choisis le dossier
<!-- step folder checked cc9db84a:desktop/ui/app.js cc9db84a:Sources/OortCompanion/Manifest.swift -->
Tuile **+** › **Un dossier de jeux**. Chaque jeu y est un dossier avec son fichier `recomplauncher.json`.

![Le choix d’un dossier](../../media/windows/folder-picker.fr.webp)

## Regarde ce qui manque
<!-- step needs checked cc9db84a:desktop/ui/app.js cc9db84a:desktop/tests/walk.js -->
Si un jeu demande des fichiers, son bouton devient **Choisir des fichiers**.

![Un jeu inventé qui demande un fichier](../../media/windows/needs-files.fr.webp)

## Donne ta copie
<!-- step files checked cc9db84a:Sources/OortCompanion/Companion.swift cc9db84a:desktop/tests/play.js -->
Sur sa page, choisis ton propre fichier. Oort retient seulement où il est, sans le copier.

![La fiche, fichier choisi](../../media/windows/file-chosen.fr.webp)

## Prépare-le si besoin
<!-- step prepare checked cc9db84a:desktop/ui/app.js cc9db84a:desktop/tests/play.js -->
**Préparation** lance l’étape que le projet a prévue. Si elle demande de copier ou de télécharger des fichiers, il faut la faire dans le projet.

![L’étape Préparation](../../media/windows/prepare.fr.webp)
