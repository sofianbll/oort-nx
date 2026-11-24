# Confirmations des réglages importants — 24 novembre 2026

Les choix qui modifient l’accès aux jeux, le prochain lancement ou les prochaines compilations utilisent le dialogue Selene des sauvegardes cloud. Les assistants et éditeurs qui ont déjà un bouton de validation restent en place. L’apparence, le son et la navigation restent immédiats.

| Réglage | Portée | Avant → après |
|---|---|---|
| Bibliothèque cloud marche/arrêt | Accès cloud du lanceur sur ce Mac ; ni déplacement de fichiers ni modification des sauvegardes | Immédiat → confirmation |
| Déconnexion | Supprime uniquement la connexion rclone locale, éventuellement partagée avec d’autres outils | Confirmation conservée |
| Dossier de bibliothèque et dossier des fichiers du jeu | Change la destination cloud de la bibliothèque ou des fichiers ; le déplacement facultatif a sa propre confirmation | Assistant conservé : Activer, Enregistrer ou Déplacer |
| Suivre ou modifier une référence | Accès en lecture seule à un dossier Drive partagé et import des fiches correspondantes | Éditeur avec Enregistrer conservé |
| Ne plus suivre une référence | Retire les fiches disponibles uniquement depuis cette référence ; conserve les fichiers | Immédiat → confirmation |
| Dossier du dépôt moteur | Checkout utilisé pour les contrôles et les compilations | Sélecteur natif avec validation conservé |
| Épingle testée / commit actuel | Révision fournie avec le lanceur / état observé du checkout | Lecture seule ; le bouton de Setup lance explicitement l’installation de la révision testée |
| Dernier moteur, Mise à jour, Retour au moteur testé | Change le checkout des futures compilations, pas les jeux installés | Action directe dans Réglages → confirmation ; assistant Setup distinct inchangé |
| Dérogation aux outils testés | Autorise ou bloque les prochaines compilations non certifiées | Confirmation à l’activation conservée ; ajout à la désactivation |
| VPN, défaut des jeux, mode local, adaptateur | Modes appliqués aux prochains lancements compatibles ; le VPN réinitialise aussi le choix d’adaptateur | Valeurs immédiates → proposition et confirmation |
| ID client Nextendo | ID OAuth public pour la connexion, le jeu en ligne et les compilations compatibles | Éditeur avec Enregistrer conservé |
| Réinitialiser le groupe réseau | Réinitialise les quatre réglages réseau et laisse l’ID client et les choix par jeu en place | Immédiat → confirmation |

Hors changement : contrôle du moteur au démarrage et commandes de contrôle/d’ouverture, import cloud à la demande, outils et identifiants de connexion, apparence et son. Le choix manuel de rclone conserve son sélecteur natif ; le retour à Automatique reste immédiat.

## Vérification

- Suite Swift : aucune erreur ; contrôles de publication, localisations (sept langues) et sonde de routage d’avis réussis.
- `run_settings_confirmations.py` a son propre processus, ses préférences et sa bibliothèque synthétiques. Il exécute le vrai routage d’avis et change de commit dans un dépôt Git jetable. Le résultat du sélecteur natif et l’appel de déconnexion rclone sont remplacés ; le sélecteur natif n’a pas de capture.
- Le premier essai partagé a révélé un vrai défaut de réouverture. Une bascule réussie vers le dernier moteur ou sa mise à jour persiste `NewestEngineChoice` ; annuler ne déclenche pas de bascule. La lecture du choix lors de l’initialisation faisait passer par le `didSet`, qui rappelait `app.setup` via `refreshInstalledEngineVersions`, alors que `setup` était encore en construction. Le réglage est maintenant chargé dans le stockage `@Published` sans appeler ce setter. La sonde recrée un modèle après refus et après les trois bascules pour vérifier la valeur restaurée.
- Les huit messages anglais du premier essai étaient déjà traduits et empruntaient la locale de l’app : bibliothèque marche, arrêt, déconnexion, ne plus suivre, VPN, défaut des jeux, mode local et adaptateur. Les actions de ligne appelées hors d’une vue montée lisaient la valeur de repli anglaise de `nxAppLocale`. La sonde donne à ce repli sa locale française et vérifie les huit messages avant de les rendre.
- Aucune preuve d’interaction avec la manette physique, de transaction Drive ni de jeu compilé ou installé.
