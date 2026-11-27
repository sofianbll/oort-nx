# Version du moteur installé — vérification du 24 novembre

Le packer nxnative inscrit son propre `HEAD` dans `DMCommit` dans le plist du
bundle. Le catalogue, lui, enregistre le commit attendu par le contrôle de
compatibilité, y compris avec l’override qui permet de compiler depuis un
autre commit. Un scan au même emplacement ou une restauration cloud peut
également conserver cet ancien enregistrement. Un hash du catalogue ne prouve
donc pas la version d’une app installée.

La sonde `apps/mac/Tests/CatalogAppChecks/run_cloud_screens.py` écrit des plists et un
historique Git synthétiques, avec un enregistrement de catalogue volontairement
en désaccord. Elle contrôle les fichiers locaux, cloud et absents, puis rend
la ligne Moteur et les couvertures dans les trois positions. Les images
montrent un seul badge par couverture, dont le transfert prioritaire dans
Spotlight. Aucun jeu n’est lancé. Les gestes, VoiceOver et un service cloud
réel ne sont pas vérifiés par cette sonde.
