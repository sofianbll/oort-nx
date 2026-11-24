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
- La sonde hors écran produit 18 cartes et exécute ses assertions avant de passer aux autres écrans. Elle utilise le routage d’avis réel, un résultat synthétique du sélecteur natif et des compteurs à la place des changements Git et rclone. Le sélecteur natif n’a pas de capture. Lecture des images : boutons et focus attendus pour les nouvelles confirmations ; les messages qui dépendent de l’environnement de section sont en anglais dans la fixture non montée.
- La commande complète `run_cloud_screens.py` n’est pas verte : le réglage moteur synthétique reste dans la suite isolée entre les deux modèles de la sonde. Le modèle suivant relit cet état et boucle entre l’initialisation de `SetupModel` et `refreshInstalledEngineVersions`. Deux reprises du script ont déjà été effectuées. La sonde doit isoler ou restaurer cette valeur et fournir la locale de section avant de relancer.
- Aucune preuve d’interaction avec la manette physique, de transaction Drive ni de jeu compilé ou installé.
