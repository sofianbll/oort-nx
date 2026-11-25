---
title: Ajouter tes jeux Steam
system: windows
topic: add-steam
order: 5
version: 0.1.0-alpha.2
minutes: 2
tried: Essayé sur une machine neuve de GitHub, avec des jeux inventés, un faux Steam et de faux services. Un joueur a lancé un jeu sur son PC avec l’alpha.1, pas encore avec celle-ci.
captures: setup-games, steam-shelf, steam-waiting, steam-back
---

## Active Steam
<!-- step on checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 f18e2119:Sources/OortCompanion/SteamShelf.swift -->
Dans l’accueil guidé, la tuile **+** ou **Réglages › Intégrations › Steam**. Oort lit les jeux installés, sur tous les disques, et n’écrit rien chez Steam.

![Steam, avec cinq jeux inventés](../../media/windows/setup-games.fr.webp)

## Retrouve-les
<!-- step shelf checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 -->
Leurs images sont celles que Steam garde déjà sur ton ordinateur. Les outils et les bandes-son sont laissés de côté ; un jeu doit être entièrement téléchargé.

![Un jeu Steam inventé dans la bibliothèque](../../media/windows/steam-shelf.fr.webp)

## Joue
<!-- step play checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 f18e2119:desktop/src-tauri/src/steam.rs -->
**Jouer** demande le jeu à Steam, qui le lance. S’il le met d’abord à jour, Oort attend ; **Annuler** arrête l’attente.

![L’attente du lancement par Steam](../../media/windows/steam-waiting.fr.webp)

## Reviens
<!-- step back checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 -->
Quitte le jeu : Oort revient et compte le temps. Vérifié avec un faux Steam, jamais avec le vrai.

![Oort après la partie](../../media/windows/steam-back.fr.webp)
