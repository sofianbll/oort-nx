---
title: Installer
system: windows
topic: install
order: 1
version: 0.1.0-alpha.1
minutes: 5
tried: Essayé sur une machine neuve de GitHub avec des jeux inventés, et par un joueur sur son PC (un jeu lancé, le 25 novembre 2026).
captures: missing:release-page, missing:checksum, missing:smartscreen, missing:installer, first-empty
---

## Télécharge
<!-- step download code cc9db84a:desktop/src-tauri/tauri.conf.json https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1 -->
Prends `Oort-NX-Windows-0.1.0-alpha.1-x64-setup.exe` et `SHA256SUMS` sur la [page de la version](https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1). Il faut Windows 10 ou 11 en 64 bits ; Windows 10 n’a pas été essayé.

<!-- missing release-page: La page de la version sur GitHub, fichiers dépliés. -->

## Compare l’empreinte
<!-- step checksum code cc9db84a:desktop/tests/windows/prove.ps1 https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1 -->
Dans PowerShell, `Get-FileHash Oort-NX-Windows-0.1.0-alpha.1-x64-setup.exe` doit donner la ligne de `SHA256SUMS`. Si elle diffère, supprime le fichier.

<!-- missing checksum: Le terminal avec l’empreinte et sa réponse. -->

## Passe l’avertissement
<!-- step warning code cc9db84a:desktop/tests/windows/prove.ps1 https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1 -->
L’installateur n’est pas signé : Windows affiche « Windows a protégé votre ordinateur ». Choisis **Informations complémentaires**, puis **Exécuter quand même**, seulement pour ce fichier vérifié.

<!-- missing smartscreen: La fenêtre SmartScreen, avant et après « Informations complémentaires ». -->

## Suis l’installation
<!-- step run checked cc9db84a:desktop/tests/windows/prove.ps1 -->
Elle se fait pour ton compte, sans droits d’administrateur. Si WebView2 manque, l’installateur prend celui de Microsoft ; ce cas n’a pas été essayé.

<!-- missing installer: Les fenêtres de l’installateur, une par une. -->

## Ouvre Oort NX
<!-- step open checked cc9db84a:desktop/tests/windows/prove.ps1 -->
Il est dans le menu Démarrer. La première page te demande où sont tes jeux.

![L’accueil vide d’Oort NX](../../media/windows/first-empty.fr.webp)
