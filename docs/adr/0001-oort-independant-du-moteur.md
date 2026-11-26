# Oort indépendant du moteur : nxnative et Ryujinx derrière la même interface

**Statut : brouillon.** Direction décidée ; forme de l’interface et transition non décidées.

Oort est historiquement construit autour de nxnative : le geste « Jouer » a déjà un point commun avec d’autres intégrations, mais l’installation, la préparation et la vie du jeu restent liées à nxnative. Dans A1 (un dépôt Oort, une ligne d’intégration, une tranche à la fois), la première tranche rend Oort indépendant du moteur : les fonctions moteur actuellement rendues avec nxnative sont reprises dans la démarche, et nxnative et Ryujinx-Nextendo sont deux adapters de la même interface. Les gestes, écrans et données du joueur restent inchangés.

Le chemin le plus court aurait été d’ajouter Ryujinx à côté de nxnative et de garder nxnative en dur, ou de ne partager que « Jouer ». Cela laisserait deux chemins pour les règles du lanceur et ferait de nxnative une exception durable. Nous acceptons le coût d’isoler les particularités de deux moteurs différents pour qu’Oort ne dépende d’aucun des deux ; nous ne leur demandons ni d’avoir les mêmes capacités, ni de partager leurs fichiers ou leur cycle de vie.

Changer cette décision ensuite toucherait les appelants de plusieurs plateformes et les preuves de non-régression des jeux existants. Cette note n’autorise ni l’activation ou la distribution d’un moteur, ni un changement d’accès aux clés ou aux sauvegardes, ni une publication. La forme de la seam, le découpage et le dessin de l’interface restent à étudier.

Vocabulaire : [glossaire](../../GLOSSARY.md).
