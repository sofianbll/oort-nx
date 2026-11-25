# Guide joueur Oort NX

[Accueil](README.fr.md) · [English player guide](PLAYER-GUIDE.md)

## Installer

Sur un Mac Apple silicon avec macOS 26 ou plus récent, ouvre le DMG de la [dernière version](https://github.com/sofianbll/oort-nx/releases) et glisse **Oort NX** dans Applications. Cette alpha n’est pas notariée : ouvre-la une fois, puis choisis **Ouvrir quand même** dans **Réglages Système → Confidentialité et sécurité**. Ne désactive pas les protections de macOS. Depuis la 0.3.0, installe ce DMG une fois : ta bibliothèque est copiée et l’ancienne reste intacte.

## Retrouver et lancer un jeu

1. Au premier lancement, choisis les sources à afficher, puis ouvre la bibliothèque. Tu peux remettre la configuration du moteur à plus tard.
2. Pour Steam, active la source dans **Réglages → Intégrations** et actualise la liste. Oort NX passe par Steam pour lancer les jeux Mac installés.
3. Pour une app de jeu nxnative, choisis son dossier dans **Réglages → Switch**, puis lance la recherche des apps. Changer de dossier ne déplace pas les apps déjà installées.
4. Pour un raccourci Mac, utilise **Ajouter une app…** ou dépose un fichier `.app` dans la bibliothèque. Oort NX ne modifie pas l’app et ne compte pas son temps de jeu.
5. Sélectionne un jeu, puis **Jouer**. À la manette, déplace-toi avec la croix ou le stick gauche. Au clavier, utilise les flèches, Entrée pour valider et Échap pour revenir.

## Intégrations

**Intégrations** affiche l’état des services et ouvre leurs réglages sans les activer. Les packs de sons sont facultatifs. Dans **Réglages → Son**, **Pack de sons** propose aussi trois ambiances fabriquées par l’app : Givre (vive et claquante), Brume (ample et douce) et Noyau (grave et nette). La bibliothèque cloud peut afficher les jeux qui n’ont que des fichiers source en ligne, sans les télécharger à l’ajout.

## Compiler ou reconstruire un jeu

Ouvre **Réglages → Switch → Moteur**. Vérifie l’état de compatibilité : une app existante peut rester jouable même si une nouvelle compilation est bloquée. Les builds demandent Xcode 27.2 ou plus récent, le compilateur Metal attendu et un moteur compatible. Aucun jeu, clé ni firmware n’est fourni. Utilise uniquement les fichiers pour lesquels tu as les droits nécessaires.

Dans **Ajouter un jeu**, choisis tes fichiers, vérifie le jeu, la mise à jour, les DLC et la destination, puis choisis de compiler ou d’ajouter uniquement l’entrée à la bibliothèque. Les fichiers restent à leur place lors de l’ajout. Pour reconstruire, conserve les fichiers d’origine et rattache-les depuis les options du jeu si tu les as déplacés.

## Protéger une sauvegarde

Ferme le jeu, puis ouvre **Options du jeu → Sauvegardes**. Crée une copie datée avant une manipulation. Pour restaurer, choisis le dossier de la copie avec **Importer une sauvegarde…** et relis l’aperçu avant de confirmer. L’import demande de couper la synchronisation de sauvegardes utilisée par le jeu. Une archive cloud d’app ou de cache ne remplace pas une sauvegarde.

## Signaler un problème

Indique la version d’Oort NX, de macOS et du moteur si utile, les étapes, le résultat attendu et celui obtenu. Ne joins ni jeu, ni sauvegarde, ni clé, ni chemin privé, ni journal brut. Consulte [les règles de contribution](CONTRIBUTING.md), ou [le canal privé](SECURITY.md) pour une faille.
