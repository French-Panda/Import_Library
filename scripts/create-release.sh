#!/usr/bin/env bash

set -euo pipefail

# Configuration
TAG="${1:-}"

ARCHIVE="Import_Library_${TAG}.zip"
NOTES_FILE="release-notes.md"

# Fichiers qui doivent être présents dans l'archive.
FILES=(
    "README.md"
    "Import_Library.sh"
    "Import_Library.env.example"
)

# Vérifications générales
if [[ -z "$TAG" ]]; then
    echo "Erreur : aucun tag fourni." >&2
    echo "Usage : $0 <tag>" >&2
    exit 1
fi

# Le workflow possède déjà cette condition, mais le script la vérifie également 
# afin qu'une exécution manuelle ne puisse pas publier une version alpha/beta/rc.
if [[ "$TAG" =~ -(alpha|beta|rc)$ ]]; then
    echo "Tag '${TAG}' : version non définitive."
    echo "Aucune release ne sera créée."
    exit 0
fi

if [[ ! -f "CHANGELOG.md" ]]; then
    echo "Erreur : CHANGELOG.md introuvable." >&2
    exit 1
fi

for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "Erreur : fichier requis introuvable : ${file}" >&2
        exit 1
    fi
done

# Vérification que le tag existe
if ! git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
    echo "Erreur : le tag '${TAG}' n'existe pas." >&2
    exit 1
fi

# Recherche de la précédente version définitive
PREVIOUS_TAG=""

while IFS= read -r candidate; do

    # Le tag courant ne peut évidemment pas être sa précédente version.
    if [[ "$candidate" == "$TAG" ]]; then
        continue
    fi

    # On ignore toutes les versions non définitives.
    if [[ "$candidate" =~ -(alpha|beta|rc)$ ]]; then
        continue
    fi

    PREVIOUS_TAG="$candidate"

    # Les tags sont parcourus du plus grand au plus petit.
    break

done < <(
    git tag --sort=-version:refname
)

if [[ -n "$PREVIOUS_TAG" ]]; then
    echo "Version définitive précédente : ${PREVIOUS_TAG}"
else
    echo "Aucune version définitive précédente."
fi

# Vérification de l'existence de la section actuelle dans le CHANGELOG
if ! grep -q "^## \[${TAG}\]" CHANGELOG.md; then
    echo "Erreur : aucune section '## [${TAG}]' trouvée dans CHANGELOG.md." >&2
    exit 1
fi

# Extraction du CHANGELOG
if [[ -n "$PREVIOUS_TAG" ]]; then

    awk \
        -v current="$TAG" \
        -v previous="$PREVIOUS_TAG" '
        BEGIN {
            in_release = 0
        }

        # Début de la version courante.
        $0 ~ "^## \\[" current "\\]" {
            in_release = 1
            next
        }

        # Début de la précédente version définitive :
        # on arrête AVANT cette ligne.
        $0 ~ "^## \\[" previous "\\]" {
            if (in_release) {
                exit
            }
        }

        # Tout ce qui se trouve entre les deux versions est conservé.
        in_release {
            print
        }
    ' CHANGELOG.md > "$NOTES_FILE"

else

    # Première version définitive :
    # on prend tout le CHANGELOG à partir de la section courante.
    awk \
        -v current="$TAG" '
        BEGIN {
            in_release = 0
        }

        $0 ~ "^## \\[" current "\\]" {
            in_release = 1
            next
        }

        # Pour la toute première release, il n'y a pas de limite
        # inférieure.
        in_release {
            print
        }
    ' CHANGELOG.md > "$NOTES_FILE"

fi

# Nettoyage du fichier de notes
sed -i ':a;/^[[:space:]]*$/{$d;N;ba;}' "$NOTES_FILE"
sed -i ':a;/^[[:space:]]*$/{$d;N;ba;}' "$NOTES_FILE"
if [[ ! -s "$NOTES_FILE" ]]; then
    echo "Erreur : aucune information de release trouvée dans CHANGELOG.md." >&2
    exit 1
fi

# Création du ZIP
echo
echo "Création de l'archive : ${ARCHIVE}"
rm -f "$ARCHIVE"

zip -q "$ARCHIVE" "${FILES[@]}"

# ============================================================================
# Vérification du contenu de l'archive
# ============================================================================

echo
echo "Contenu de l'archive :"

zipinfo -1 "$ARCHIVE"

# Vérification stricte : exactement les trois fichiers attendus.
EXPECTED_CONTENT=$(printf '%s\n' "${FILES[@]}" | sort)
ACTUAL_CONTENT=$(zipinfo -1 "$ARCHIVE" | sort)

if [[ "$EXPECTED_CONTENT" != "$ACTUAL_CONTENT" ]]; then
    echo "Erreur : contenu inattendu dans l'archive." >&2
    exit 1
fi

# Résumé
echo
echo "Release préparée."
echo "================="
echo "Tag                : ${TAG}"
echo "Version précédente : ${PREVIOUS_TAG:-aucune}"
echo "Archive            : ${ARCHIVE}"
echo
echo "Notes de publication :"
echo "----------------------"
cat "$NOTES_FILE"
echo
