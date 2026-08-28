# Import_Library

Script d'import en masse d'une bibliothèque de vidéos avec création de dossiers aux standards de Emby/Jellyfin

## Principe et fonctionalités
Migration interactive d'une bibliothèque de films vers une nouvelle
bibliothèque organisée au format Emby/Jellyfin, avec :
  - Analyse récursive des fichiers vidéo
  - Si plusieurs vidéos sont présentes dans un dossier : sélection de la plus grosse
  - Analyse du nom de release via scene-release-parser (https://github.com/pr0pz/scene-release-parser)
  - Recherche TMDB
  - Sélection interactive dans fzf
  - Saisie manuelle possible d'un ID TMDB
  - Possibilité d'ignorer un film
  - Vérification du hardlink (ne pas en créer un nouveau si le fichier est déjà présent)
  - Création d'un hardlink

## Dépendances
  - bash >= 4
  - curl
  - jq
  - fzf
  - Implementation de scene-release-parser (autre dépôt bientôt en ligne)

## Configuration
  - S'assurer que les dépendances sont installées
  - Copier l'exemple de fichier d'environnement et le remplir
  - Rendre le script exécutable (chmod +x Import_Library.sh)
  - Et voila!

## Utilisation
Les chemins source et destination sont TOUJOURS passés en arguments.

Exemple :
```
./Import_Library.sh \
    --from /data/Media_1/Film \
    --destination /data/medias_2/Film
```
Naviguer dans l'interface du terminal pour valider les films détectés ou entrer les ID TMDB à la main sinon.

## TODO
  - Prise en compte des séries
  - Intégration de Release Parser Web dans le script avec option lancer ou non
  - Choix de langue pour le titre du film
  - Choix du format de nom de dossier avec options simples:
    - Langue du titre (FR, US, original)
    - Année ou non
    - ID TMDB, ID IMDB (TVDB pour les séries)
  - Interface en Anglais en plus du Français

## Informations
Projet purement personnel, réalisé pour mon besoin propre. Partagé uniquement par amour du partage!
Codé avec l'aide de LLM, surtout ChatGPT mais aussi Mistral et Qwen sur une instance locale d'Ollama.
Cependant, RIEN n'est automatisé dans l'IDE, CHAQUE LIGNE est relue et CONTRÔLÉE avant d'être copiée.
Ce code peut être librement repris, utilisé et modifié conformément aux termes de la licence GPL 3.0.
