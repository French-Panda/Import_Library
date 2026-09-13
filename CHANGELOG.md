# Change Log
Tous les changements notables du projet seront indiqués dans ce fichier.

## [v1.1] - 13/09/2026
### Ajouts
- Création de releases via actions Gitea et publication sur Gitea et Github

### Changements

### Corrections

## [v1.1-rc] - 11/09/2026
### Ajouts
- Choix du niveau de LOG entre les 5 niveaux standards (CRITICAL, ERROR, WARN, INFO et DEBUG), INFO par défaut
- Choix de la langue des recherches sur TMDB et pour les dossiers des films
- Système de template pour le nommage des dossiers supportant les titres dans la langue souhaitée, l'année, les ID TMDB, IMDB, TVDB

### Changements
- Ajout du numéro de version dans l'entête des menus

### Corrections
- Petits corrections typo

## [v1.0] - 06/09/2026
### Ajouts
- Image animée du traitement d'un dossier de films

### Changements
- Git pull de RPW quand nécessaire

### Corrections
- Petits corrections typo

## [v1.0-rc] - 30/08/2026
Finalisation et test des différentes fonctionalités

### Ajouts
- Fichiers de dépôt (.gitignore, écriture README, CHANGELOG)
- Lancement de RPW via Docker possible (mettre l'URL à "LOCAL" dans le fichier .env)

### Changements

### Corrections
- Remplacement des espaces par des points dans la recherche sur RPW
- Choix SKIP inaccessible dans le TUI fzf
- Proposition d'entrée manuelle quand TMDB ne trouve pas (avant il passait avec erreur)
- Nommage correct du nom de dossier quand l'ID est entré à la main

## [v0.1] - 25/08/2026
Première version fonctionnelle
