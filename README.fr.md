# Oort NX

<img src="Resources/AppIcon-Light.png" alt="Icône Trame d’Oort NX" width="96" height="96">

**Tes jeux, à leur place sur Mac.** Retrouve dans une seule bibliothèque tes raccourcis Mac, tes jeux Steam installés pour Mac et les jeux compilés avec nxnative. Choisis un jeu et lance-le à la manette, au clavier ou à la souris. Tes fichiers de jeux restent à toi.

**[Le voir en mouvement](https://sofianbll.github.io/oort-nx/)** · [Guide joueur](PLAYER-GUIDE.fr.md) · [English](README.md) · [Notes de version](CHANGELOG.md)

## Commencer

- **Apple silicon · macOS 26 ou plus récent.** Steam et certains jeux peuvent demander une version plus récente.
- **Télécharge** le DMG dans [Versions](https://github.com/sofianbll/oort-nx/releases) et glisse Oort NX dans Applications. L’app n’est pas notariée : ouvre-la une fois, puis choisis **Ouvrir quand même** dans **Réglages Système → Confidentialité et sécurité**. Tu viens de la 0.3.0 ? Installe ce DMG une fois : ta bibliothèque est copiée et l’ancienne reste intacte.
- **Bêta.** Les numéros suivent le versionnage sémantique. Ni vrai transfert Drive ni vrai jeu n’ont été essayés avec cette version.
- **Tu veux compiler un jeu ?** Ouvre **Réglages → Switch → Moteur**. Il te faut des fichiers compatibles que tu as le droit d’utiliser, nxnative et les versions de Xcode et de Metal qu’il demande. Aucun jeu, clé ou firmware n’est fourni. Tu n’as pas besoin des outils de compilation pour jouer à une app de jeu déjà installée.

Pour compiler Oort NX, suis le [guide de développement](docs/working-on-it/development.md). Pour obtenir de l’aide, voir [Contribuer](CONTRIBUTING.md) ; signale les failles [en privé](SECURITY.md).

## Plateformes

L’app tourne sur macOS. **Ryujinx-Nextendo** est le moteur visé pour Windows ; aucune build ni compatibilité Windows n’est annoncée. Nextendo sur Mac reste facultatif et inchangé. Les sources de l’app iPhone et iPad sont dans `mobile/` ; aucune build n’est publiée.

## Crédits

Oort NX s’appuie sur [Arcane de Bium23](https://github.com/Bium23/NxLibrary) et le [thème Selene de Matthew Silva](https://github.com/mattxslv/Selene). Le sélecteur d’images s’inspire de [Playnite de Josef Nemec](https://github.com/JosefNemec/Playnite). La couche hôte de l’app iPhone et iPad vient de [NX2Apple de LNPANDY](https://github.com/LNPANDY/NX2Apple) (MIT). Merci aux contributeurs de [nxnative](https://github.com/seedds/nxnative) et de [Nextendo](https://github.com/eyasbzour/nxnative-online).

[Licence MIT](LICENSE) · [Licences tierces](NOTICE) · [Soutenir Bium23](https://buymeacoffee.com/bium)
