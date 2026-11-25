---
title: Images et informations d’un jeu
system: windows
topic: settings-pictures
order: 9
version: 0.1.0-alpha.2
minutes: 3
tried: Essayé sur une machine neuve de GitHub, avec des jeux inventés, un faux Steam et de faux services. Un joueur a lancé un jeu sur son PC avec l’alpha.1, pas encore avec celle-ci.
captures: pictures, pictures, online-asked, online-found, online-results, integrations-on
---

## Ouvre la page
<!-- step open checked f18e2119:desktop/tests/online.js f18e2119:Sources/OortCompanion/Companion+Own.swift -->
Sur un jeu : **Options › Images et informations**.

![Images et informations d’un programme inventé](../../media/windows/pictures.fr.webp)

## Choisis tes images
<!-- step own checked f18e2119:desktop/tests/steam.js f18e2119:Sources/OortCompanion/Companion+Own.swift f18e2119:Tests/OortCompanionTests/OwnTests.swift -->
Jaquette, icône, arrière-plan ou logo : un fichier PNG, JPEG ou WebP. Il est copié dans le dossier d’Oort ; l’original ne change pas.

![Images et informations d’un programme inventé](../../media/windows/pictures.fr.webp)

## Cherche en ligne, si tu dis oui
<!-- step ask checked f18e2119:desktop/tests/online.js f18e2119:Sources/OortCompanion/Online.swift -->
Oort envoie le nom du jeu ou son numéro Steam, et ta langue, au magasin Steam, à Wikidata et à Wikipédia. Vérifié avec de faux services, jamais avec les vrais.

![La question avant de chercher en ligne](../../media/windows/online-asked.fr.webp)

## Regarde ce qui est trouvé
<!-- step found checked f18e2119:desktop/tests/online.js f18e2119:Sources/OortCompanion/Online.swift -->
Jaquette, description, année et genres arrivent seuls. Wikipédia limite les demandes : c’est surtout le magasin Steam qui répond.

![Le programme inventé, avec ce qui a été trouvé](../../media/windows/online-found.fr.webp)

## Corrige
<!-- step right checked f18e2119:desktop/tests/online.js f18e2119:Sources/OortCompanion/Online.swift -->
Mauvais jeu ? **Informations en ligne**, puis le bon. **Aucun de ceux-là** efface ce qui vient d’internet pour ce jeu.

![Le choix du bon jeu](../../media/windows/online-results.fr.webp)

## Coupe ou efface
<!-- step off checked f18e2119:desktop/tests/online.js f18e2119:Sources/OortCompanion/Online.swift -->
**Réglages › Intégrations** coupe les informations en ligne et supprime tout ce qui a été trouvé. Tes images restent.

![Réglages › Intégrations, informations en ligne actives](../../media/windows/integrations-on.fr.webp)
