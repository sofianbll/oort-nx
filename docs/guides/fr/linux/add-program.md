---
title: Ajouter un programme ou un émulateur
system: linux
topic: add-program
order: 3
version: 0.1.0-alpha.2
minutes: 3
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04), avec des jeux inventés et un faux Steam. Jamais sur l’ordinateur d’un joueur.
captures: add, program-filled, program-icon
---

## Ouvre Ajouter un jeu
<!-- step add checked f18e2119:desktop/ui/app.js -->
Choisis la tuile **+**, puis **Un programme**.

![La page Ajouter un jeu (capturé sous Windows)](../../media/windows/add.fr.webp)

## Choisis le fichier
<!-- step program code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/ProgramFile.swift -->
**Programme** est le fichier à lancer, ou son entrée de menu. Pour un émulateur, **Fichier du jeu** est le jeu qu’il doit ouvrir.

![Un programme inventé, son nom proposé (capturé sous Windows)](../../media/windows/program-filled.fr.webp)

## Ajoute-le
<!-- step finish code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Companion+Own.swift -->
Son nom et son icône arrivent seuls, lus dans son fichier. Change le nom si tu veux, puis **Ajouter à la bibliothèque**.

![Le programme inventé dans la bibliothèque, avec son icône (capturé sous Windows)](../../media/windows/program-icon.fr.webp)
