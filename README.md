# Import_Library

Script d'import en masse d'une bibliothèque de vidéos avec création de dossiers aux standards de Emby/Jellyfin#!/usr/bin/env bash

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
