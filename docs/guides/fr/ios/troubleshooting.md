---
title: Dépannage
system: ios
topic: troubleshooting
order: 12
version: 0.1.0-alpha.1
minutes: 3
tried: Essayé seulement sur simulateur (iPhone et iPad, iOS 27.2) avec des jeux inventés. Jamais sur un vrai appareil.
captures: settings-end, code-refused, damaged, settings-end
---

## L’app ne s’ouvre plus
<!-- step expired code e3cd6df1:mobile/Sources/OortMobile/SettingsScreens.swift e3cd6df1:mobile/Sources/ShellHost/ProvisioningProfile.swift -->
Sa signature a sans doute expiré. Rafraîchis-la avec le même compte ; tes jeux et sauvegardes doivent rester. Pas essayé.

![Le bas des Réglages](../../media/ios/settings-end.fr.webp)

## Le code du jeu est refusé
<!-- step code checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Il n’est pas signé comme l’app, ou il est abîmé.

![Le message d’un code refusé](../../media/ios/code-refused.fr.webp)

## Un jeu porte un point d’exclamation
<!-- step damaged checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Sa fiche dit ce qui manque. Ajoute-le à nouveau.

![Un jeu inventé abîmé](../../media/ios/damaged.fr.webp)

## Raconte le problème
<!-- step report code e3cd6df1:SECURITY.md e3cd6df1:CONTRIBUTING.md -->
[Ouvre un signalement](https://github.com/sofianbll/oort-nx/issues) avec ton appareil, ta version d’iOS et celle d’Oort. Ni jeu, ni clé, ni sauvegarde.

![Le bas des Réglages](../../media/ios/settings-end.fr.webp)
