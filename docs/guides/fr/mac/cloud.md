---
title: Bibliothèque cloud (Google Drive)
system: mac
topic: cloud
order: 10
version: 0.5.0-beta.3
minutes: 10
tried: Jamais essayée avec un vrai Google Drive dans cette version : seulement contre un faux Drive.
captures: settings-cloud, settings-cloud, cloud-account, cloud-folder, cloud-tab, settings-cloud
---

## À quoi ça sert
<!-- step what code bf0c3410:PLAYER-GUIDE.md bf0c3410:Sources/NXLibraryCore/Library/RcloneConfiguration.swift -->
Garder en ligne tes jeux compilés et les retrouver sur un autre Mac. Seul Google Drive est pris en charge, et tes sauvegardes n’y sont pas. **Garde une copie de ce qui compte.**

![Réglages › Bibliothèque cloud](../../media/mac/settings-cloud.fr.webp)

## L’outil : rclone
<!-- step tool code bf0c3410:Sources/NXLibraryCore/Library/RcloneDownload.swift bf0c3410:Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift -->
Oort utilise le rclone déjà sur ton Mac, ou demande avant de prendre celui de rclone.org. **Avancé** permet de choisir le tien.

![Réglages › Bibliothèque cloud](../../media/mac/settings-cloud.fr.webp)

## Connecte Google
<!-- step account checked bf0c3410:Sources/NXLibrary/Views/Settings/CloudSetupAssistant.swift bf0c3410:Tests/CatalogAppChecks/run_cloud_screens.py -->
Garde une connexion existante, ou **Se connecter**. Google accorde à rclone l’accès à tout ton Drive, pas à un seul dossier.

![L’assistant cloud, étape 1](../../media/mac/cloud-account.fr.webp)

## Choisis le dossier
<!-- step folder checked bf0c3410:Sources/NXLibrary/Views/Settings/CloudSetupAssistant.swift bf0c3410:Tests/CatalogAppChecks/run_cloud_screens.py -->
Oort cherche une bibliothèque dans `Games`, sinon tu donnes un chemin. Rien n’est déplacé par ce choix.

![L’assistant cloud, étape 2](../../media/mac/cloud-folder.fr.webp)

## Télécharge un jeu
<!-- step use checked bf0c3410:Tests/CatalogAppChecks/run_store_next_step.py bf0c3410:Tests/CatalogAppChecks/run_cloud_screens.py -->
L’onglet **Cloud** montre ce qui est en ligne. **Télécharger l’app** la ramène ; **Télécharger les fichiers du jeu** demande ensuite de compiler.

![L’onglet Cloud avec un jeu inventé](../../media/mac/cloud-tab.fr.webp)

## Débranche
<!-- step stop code bf0c3410:Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift bf0c3410:PLAYER-GUIDE.md -->
**Déconnecter** retire la connexion de ce Mac. Les fichiers restent dans ton Drive. La connexion rclone peut servir à d’autres outils.

![Réglages › Bibliothèque cloud](../../media/mac/settings-cloud.fr.webp)
