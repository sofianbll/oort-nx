---
title: Ajouter tes jeux Steam
system: linux
topic: add-steam
order: 5
version: 0.1.0-alpha.2
minutes: 2
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04), avec des jeux inventés et un faux Steam. Jamais sur l’ordinateur d’un joueur.
captures: setup-games, steam-shelf, steam-waiting, steam-back
---

## Active Steam
<!-- step on checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/linux/prove.sh f18e2119:Sources/OortCompanion/SteamShelf.swift -->
Dans l’accueil guidé, la tuile **+** ou **Réglages › Intégrations › Steam**. Oort lit les jeux installés, sur tous les disques, et n’écrit rien chez Steam.

![Steam, avec cinq jeux inventés](../../media/linux/setup-games.fr.webp)

## Retrouve-les
<!-- step shelf checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/linux/prove.sh -->
Leurs images sont celles que Steam garde déjà sur ton ordinateur. Les outils et les bandes-son sont laissés de côté ; un jeu doit être entièrement téléchargé.

![Un jeu Steam inventé dans la bibliothèque](../../media/linux/steam-shelf.fr.webp)

## Joue
<!-- step play checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/linux/prove.sh f18e2119:desktop/src-tauri/src/steam.rs -->
**Jouer** demande le jeu à Steam, qui le lance. S’il le met d’abord à jour, Oort attend ; **Annuler** arrête l’attente.

![L’attente du lancement par Steam (capturé sous Windows)](../../media/windows/steam-waiting.fr.webp)

## Reviens
<!-- step back checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/linux/prove.sh -->
Quitte le jeu : Oort revient et compte le temps. Vérifié avec un faux Steam, jamais avec le vrai, ni avec Proton.

![Oort après la partie](../../media/linux/steam-back.fr.webp)
