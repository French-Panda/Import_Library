#!/usr/bin/env bash

# ==============================================================================
# Import_Library.sh
# Voir README pour explications
# ==============================================================================
set -Eeuo pipefail

# ==============================================================================
# Variables globales
# ==============================================================================
SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE=""
FROM=""
DESTINATION=""
TMDB_TOKEN=""
RELEASE_PARSER_URL=""
TMDB_MAX_RESULTS=20
LOG_FILE=""
TOTAL=0
PROCESSED=0
SUCCESS=0
ERRORS=0
SKIPPED=0
CURRENT_STEP="Initialisation"
CURRENT_FILE=""
CURRENT_RELEASE=""
CURRENT_TITLE=""
CURRENT_TMDB_ID=""

# Fichier temporaire contenant l'état courant affiché dans le TUI.
STATE_FILE=""
# Fichier temporaire contenant les candidats TMDB.
CANDIDATES_FILE=""
# Fichier temporaire contenant les résultats.
RESULTS_FILE=""
# Index des inodes déjà présents dans la bibliothèque destination.
declare -A DESTINATION_INODES=()

# ==============================================================================
# Couleurs ANSI
#
# fzf sait gérer les couleurs lui-même ; ces variables servent principalement
# aux messages de log affichés dans le TUI et sont désactivées si stdout n'est
# pas un terminal.
# ==============================================================================

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
    C_CYAN=$'\033[36m'
    C_BOLD=$'\033[1m'
else
    C_RESET=""
    C_RED=""
    C_YELLOW=""
    C_GREEN=""
    C_CYAN=""
    C_BOLD=""
fi

# ==============================================================================
# Nettoyage
# ==============================================================================
cleanup()
{
    [[ -n "${STATE_FILE:-}" && -f "$STATE_FILE" ]]           && rm -f "$STATE_FILE"
    [[ -n "${CANDIDATES_FILE:-}" && -f "$CANDIDATES_FILE" ]] && rm -f "$CANDIDATES_FILE"
    [[ -n "${RESULTS_FILE:-}" && -f "$RESULTS_FILE" ]]       && rm -f "$RESULTS_FILE"
}
trap cleanup EXIT

# ==============================================================================
# Usage / Help
# ==============================================================================
usage()
{
    cat <<EOF
Usage:
  $SCRIPT_NAME --from <folder> --destination <folder> [--config <file>]

Options:
  -f, --from <folder>        : Bibliothèque source à analyser.
  -d, --destination <folder> : Nouvelle bibliothèque.
  -c, --config <file>        : Fichier .env à utiliser.
  -h, --help                 : Affiche cette aide.

Configuration .env :
  TMDB_TOKEN="..."
  RELEASE_PARSER_URL="https://example.org/rpw"
  TMDB_MAX_RESULTS="20"

Exemple :
  $SCRIPT_NAME \\
      --from /data/medias_1/Film \\
      --destination /data/medias_2/Film \\
      --config /etc/Import_Library.env
EOF
}

# ==============================================================================
# Parsing des arguments
# ==============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--from)
            [[ $# -ge 2 ]] ||
                {
                    echo "Argument manquant pour $1" >&2
                    exit 2
                }
            FROM="${2%/}"
            shift 2
            ;;
        -d|--destination)
            [[ $# -ge 2 ]] ||
                {
                    echo "Argument manquant pour $1" >&2
                    exit 2
                }
            DESTINATION="${2%/}"
            shift 2
            ;;
        -c|--config)
            [[ $# -ge 2 ]] ||
                {
                    echo "Argument manquant pour $1" >&2
                    exit 2
                }
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Option inconnue : $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# ==============================================================================
# Chargement du fichier .env
# Si --config n'est pas fourni, recherche de :
#   1. ./Import_Library.env
#   2. ./.env
# Les variables déjà exportées dans l'environnement sont conservées sauf si
# le fichier .env les redéfinit.
# ==============================================================================
if [[ -n "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" ]] ||
        {
            echo "Fichier de configuration introuvable : $CONFIG_FILE" >&2
            exit 2
        }
elif [[ -f "./Import_Library.env" ]]; then
    CONFIG_FILE="./Import_Library.env"
elif [[ -f "./.env" ]]; then
    CONFIG_FILE="./.env"
fi

if [[ -n "$CONFIG_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
fi

# ==============================================================================
# Validation
# ==============================================================================
die()
{
    echo "ERREUR: $*" >&2
    exit 1
}

[[ -n "$FROM" ]]                   || die "Le dossier source est obligatoire : --from / -f"
[[ -n "$DESTINATION" ]]            || die "Le dossier destination est obligatoire : --destination / -d"
[[ -d "$FROM" ]]                   || die "Dossier source inexistant : $FROM"
[[ -n "${TMDB_TOKEN:-}" ]]         || die "TMDB_TOKEN n'est pas défini"
[[ -n "${RELEASE_PARSER_URL:-}" ]] || die "RELEASE_PARSER_URL n'est pas défini"

command -v curl >/dev/null || die "curl est nécessaire"
command -v jq >/dev/null   || die "jq est nécessaire"
command -v fzf >/dev/null  || die "fzf est nécessaire"

[[ "${TMDB_MAX_RESULTS:-20}" =~ ^[0-9]+$ ]] || die "TMDB_MAX_RESULTS doit être un nombre"
TMDB_MAX_RESULTS="${TMDB_MAX_RESULTS:-20}"

# ==============================================================================
# Création du répertoire destination
# ==============================================================================
mkdir -p "$DESTINATION"


# ==============================================================================
# Journal
#   YYYYMMDD_Library_migration.log
# Format :
#   HH:mm:ss - [LEVEL] - Message
# ==============================================================================
LOG_FILE="$(date '+%Y%m%d')_Library_migration.log"
log()
{
    local level="$1" && shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%H:%M:%S')"
    printf '%s - [%s] - %s\n' \
        "$timestamp" \
        "$level" \
        "$message" \
        >> "$LOG_FILE"
}

log_debug()
{
    log "DEBUG" "$@"
}

log_info()
{
    log "INFO" "$@"
}

log_warn()
{
    log "WARN" "$@"
}

log_error()
{
    log "ERROR" "$@"
}

log_critical()
{
    log "CRITICAL" "$@"
}

# ==============================================================================
# Gestion de l'état affiché dans le TUI
# Le fichier est volontairement simple :
#   CURRENT_STEP=...
#   CURRENT_FILE=...
#   ...
# fzf/les fonctions d'affichage peuvent le relire à tout moment.
# ==============================================================================
write_state()
{
    cat > "$STATE_FILE" <<EOF
CURRENT_STEP=$CURRENT_STEP
CURRENT_FILE=$CURRENT_FILE
CURRENT_RELEASE=$CURRENT_RELEASE
CURRENT_TITLE=$CURRENT_TITLE
CURRENT_TMDB_ID=$CURRENT_TMDB_ID
PROCESSED=$PROCESSED
SUCCESS=$SUCCESS
ERRORS=$ERRORS
SKIPPED=$SKIPPED
TOTAL=$TOTAL
EOF
}

# ==============================================================================
# Affichage de l'en-tête TUI
# ==============================================================================
tui_header()
{
    clear
    local current_number=$((PROCESSED + 1))
    if (( current_number > TOTAL )); then
        current_number="$TOTAL"
    fi
    printf '%s%sLIBRARY MIGRATION%s\n' \
        "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '\n'
    printf 'Film %s/%s    |    Traités : %s    |    OK : %s    |    Erreurs : %s    |    Ignorés : %s\n' \
        "$current_number" \
        "$TOTAL" \
        "$PROCESSED" \
        "$SUCCESS" \
        "$ERRORS" \
        "$SKIPPED"
    printf '%s\n' \
        '──────────────────────────────────────────────────────────────────────────────'
    printf 'Source      : %s\n' "$FROM"
    printf 'Destination : %s\n' "$DESTINATION"
    printf 'Log         : %s\n' "$LOG_FILE"
    printf '%s\n\n' \
        '──────────────────────────────────────────────────────────────────────────────'
}

# ==============================================================================
# Affichage du pied TUI
# ==============================================================================
tui_footer()
{
    printf '\n'
    printf '%s\n' \
        '──────────────────────────────────────────────────────────────────────────────'
    printf '%s%sÉtape :%s %s\n' \
        "$C_BOLD" "$C_CYAN" "$C_RESET" "$CURRENT_STEP"
    [[ -n "$CURRENT_FILE" ]] &&
        printf 'Fichier : %s\n' "$CURRENT_FILE"
    [[ -n "$CURRENT_RELEASE" ]] &&
        printf 'Release : %s\n' "$CURRENT_RELEASE"
    [[ -n "$CURRENT_TITLE" ]] &&
        printf 'Titre   : %s\n' "$CURRENT_TITLE"
    [[ -n "$CURRENT_TMDB_ID" ]] &&
        printf 'TMDB    : %s\n' "$CURRENT_TMDB_ID"
    printf '%s\n' \
        '──────────────────────────────────────────────────────────────────────────────'
}

# ==============================================================================
# Affichage TUI complet avant une sélection
# ==============================================================================
tui_prepare_selection()
{
    tui_header
    printf '%s%sSélection du film TMDB%s\n\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    tui_footer
    write_state
}

# ==============================================================================
# Encode une chaîne pour une URL
# ==============================================================================
urlencode()
{
    jq -nr --arg value "$1" '$value|@uri'
}


# ------------------------------------------------------------------------------
# Détermine le nom à utiliser pour analyser le film.
# Si la vidéo se trouve dans un dossier sous FROM, le nom de ce dossier est
# utilisé. Cela permet de privilégier un nom de release correctement tagué
# lorsque le fichier vidéo lui-même possède un nom moins exploitable.
# ------------------------------------------------------------------------------
get_source_release_name()
{
    local video="${1%/}"
    local parent

    parent="$(dirname "$video")"

    if [[ "$parent" != "$FROM" ]]; then
        basename "$parent"
    else
        basename "$video"
    fi
}

# ==============================================================================
# Appel scene-release-parser
# ==============================================================================
parse_release()
{
    local release="$1"
    curl --fail --silent --show-error --get --data-urlencode "Release=${release// /\\.}" "$RELEASE_PARSER_URL"
}

# ==============================================================================
# Recherche TMDB
# On recherche d'abord avec l'année lorsque celle-ci est connue.
# L'API TMDB recherche les titres originaux, traduits et alternatifs.
# ==============================================================================
#        --header "Authorization: Bearer $TMDB_TOKEN"
search_tmdb()
{
    local title="$1"
    local year="${2:-}"
    local args=(
        --fail
        --silent
        --show-error
        --get
        --url "https://api.themoviedb.org/3/search/movie"
        --data-urlencode "api_key=${TMDB_TOKEN}"
        --data-urlencode "query=$title"
        --data-urlencode "language=fr-FR"
        --data-urlencode "include_adult=false"
    )
    local result
    if [[ -n "$year" ]] ; then
        local args2=("${args[@]}" --data-urlencode "year=$year")
        result="$(curl "${args2[@]}")" || return 1
    fi
    # Si pas d'année ou que la recherche avec année ne donne rien, on tente sans année.
    if [[ -z "$year" ]] || [[ "$(echo "$result" | jq '.results | length')" -eq 0 ]]; then
        log_debug "TMDB: aucun résultat avec année $year, nouvelle recherche sans année"
        result="$(curl "${args[@]}")" || return 1
    fi
    echo "$result"
}

# ==============================================================================
# Nettoyage d'un nom de dossier
# ==============================================================================
sanitize_title()
{
    local value="$1"
    log_debug "Nettoyage du nom de film: ${value}"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    # Caractères problématiques pour un nom de fichier/dossier.
    # L'apostrophe n'est volontairement PAS remplacée.
    value="$(printf '%s' "$value" | sed 's#[/:*?"<>|\\]#-#g')"
    # Espaces multiples + espaces en début/fin.
    value="$(printf '%s' "$value" | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    printf '%s' "$value"
}

# ==============================================================================
# Construction des candidats TMDB
# Fichier de sortie :
#   ID<TAB>original<TAB>français<TAB>anglais
# Les titres sont ensuite affichés par fzf.
# ==============================================================================
build_candidates()
{
    local search_json="$1"
    : > "$CANDIDATES_FILE"
    echo "$search_json" |
        jq -r --argjson max "$TMDB_MAX_RESULTS" '
            .results[:$max][]
            | [
                .id,
                (.original_title // ""),
                (.title // "")
              ]
            | @tsv
        ' >> "$CANDIDATES_FILE"
}

# ==============================================================================
# Sélection TUI TMDB
# Entrées :
#   [SKIP]
#   [MANUAL]
#   résultats TMDB
# La fenêtre de sélection est au milieu de l'écran.
# Le haut contient la progression.
# Le bas contient l'état courant.
# ==============================================================================
select_tmdb()
{
    tui_prepare_selection >&2
    local selection
    selection="$(
        {
            printf '0\t[SKIP]\tPasser ce film\t\n'
            printf 'MANUAL\t[MANUAL]\tEntrer manuellement un ID TMDB\t\n'
            cat "$CANDIDATES_FILE"
        } |
        column -t -s $'\t' |
        fzf \
            --height='55%' \
            --layout=reverse \
            --border=rounded \
            --prompt='TMDB > ' \
            --header='ID TMDB | Original | Français' \
            --header-lines=1 \
            --no-multi \
            --cycle \
            --info=inline
    )" || return 2
    [[ -n "$selection" ]] || return 2

    # Film ignoré.
    if grep -q '\[SKIP\]' <<< "$selection"; then
        return 1
    fi

    # ID manuel.
    if grep -q '\[MANUAL\]' <<< "$selection"; then
        local manual_id

        while true; do
            printf '\n' >&2
            read -rp "ID TMDB (vide = annuler) : " manual_id
            [[ -z "$manual_id" ]] && return 2
            if [[ "$manual_id" =~ ^[0-9]+$ ]]; then
                printf '%s\n' "$manual_id"
                return 0
            fi
            printf '%s\n' "ID TMDB invalide." >&2
        done
    fi

    # Le premier champ est l'ID.
    awk '{print $1}' <<< "$selection"
}

# ==============================================================================
# Détermination du titre final
# Priorité : 1. Français / 2. Original
# ==============================================================================
get_final_title()
{
    local search_json="$1"
    local tmdb_id="$2"
    local fallback_title="$3"
    local french
    local original

    french="$(
        echo "$search_json" |
            jq -r --arg id "$tmdb_id" '.results[] | select((.id | tostring) == $id) | .title // "" ' |
            head -n 1)"

    original="$(
        echo "$search_json" |
            jq -r --arg id "$tmdb_id" ' .results[] | select((.id | tostring) == $id) | .original_title // "" ' |
            head -n 1)"

    if [[ -n "$french" && "$french" != "$original" ]]; then
        printf '%s\n' "$french"
        return 0
    fi

    if [[ -n "$original" ]]; then
        printf '%s\n' "$original"
        return 0
    fi

    # ID manuel ne faisant pas partie des résultats.
    printf '%s\n' "$fallback_title"
}

# ==============================================================================
# Extensions vidéo
# ==============================================================================
is_video()
{
    local file="$1"
    local extension="${file##*.}"
    extension="${extension,,}"
    case "$extension" in
        mkv|mp4|avi|m4v|mov|ts|m2ts|webm|mpg|mpeg|wmv)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# Analyse de l'arborescence source:
#   /Film.mkv -> traité
#   /Film/Film.mkv -> traité
#   /Film/
#       Film.mkv -> traité
#       Film.en.srt
#   /Film/
#       Film.mkv
#       Film2.mkv
#       -> SEULEMENT le plus gros fichier vidéo
# ==============================================================================
declare -a MOVIE_FILES=()
add_video()
{
    local file="$1"
    MOVIE_FILES+=("$file")
}

scan_source()
{
    local entry

    # Fichiers directement présents dans FROM.
    while IFS= read -r -d '' entry; do
        if is_video "$entry"; then
            add_video "$entry"
        fi
    done < <(find "$FROM" -mindepth 1 -maxdepth 1 -type f -print0)

    # Dossiers directement présents dans FROM.
    while IFS= read -r -d '' entry; do
        local largest=""
        local largest_size=0
        while IFS= read -r -d '' video; do
            local size
            size="$(stat -c '%s' "$video")"
            if (( size > largest_size )); then
                largest="$video"
                largest_size="$size"
            fi
        done < <(find "$entry" -type f -print0 |
            while IFS= read -r -d '' file; do
                if is_video "$file"; then
                    printf '%s\0' "$file"
                fi
            done
        )

        # Un dossier peut ne contenir aucune vidéo.
        if [[ -n "$largest" ]]; then
            add_video "$largest"
            local video_count
            video_count="$(find "$entry" -type f -print0 |
                while IFS= read -r -d '' file; do
                    if is_video "$file"; then
                        echo 1
                    fi
                done | wc -l)"
            if (( video_count > 1 )); then
                log_warn "Plusieurs vidéos dans '$entry' : $video_count fichiers ; utilisation du plus gros : $largest"
            fi
        else
            log_info "Aucune vidéo dans le dossier '$entry'"
        fi
    done < <(find "$FROM" -mindepth 1 -maxdepth 1 -type d -print0)
}

# ==============================================================================
# Vérification filesystem: hardlinks obligatoirement sur le même filesystem.
# ==============================================================================
check_filesystem()
{
    local source="$1"
    local source_device
    local destination_device
    source_device="$(stat -c '%d' "$source")"
    destination_device="$(stat -c '%d' "$DESTINATION")"
    [[ "$source_device" == "$destination_device" ]]
}

# ==============================================================================
# Fonction de construction d'une table inode
# Cela permet, lors d'un rejeu complet, de détecter un hardlink et échapper à des actions inutiles
# ==============================================================================
build_destination_inode_index()
{
    local file
    local inode
    DESTINATION_INODES=()
    while IFS= read -r -d '' file; do
        inode="$(stat -c '%i' "$file")"
        DESTINATION_INODES["$inode"]="$file"
    done < <(find "$DESTINATION" -type f -print0)
    log_info "Index destination : ${#DESTINATION_INODES[@]} inode(s) trouvé(s)"
}

# ==============================================================================
# Traitement d'un film
# ==============================================================================
process_movie()
{
    local video="$1"
    CURRENT_FILE="$video"
    CURRENT_RELEASE=""
    CURRENT_TITLE=""
    CURRENT_TMDB_ID=""
    # Le nom du dossier est privilégié pour l'analyse RPW/TMDB.
    CURRENT_RELEASE="$(get_source_release_name "$video")"

    # Vérification immédiate de l'inode dans la bibliothèque destination.
    local source_inode
    source_inode="$(stat -c '%i' "$video")"
    if [[ -n "${DESTINATION_INODES[$source_inode]+_}" ]]; then
        log_info "Déjà présent dans la destination : '$video' [inode $source_inode] -> '${DESTINATION_INODES[$source_inode]}'"
        (( SUCCESS+=1 ))
        return 0
    fi

    # Parser
    CURRENT_STEP="Analyse de la release"
    tui_header
    tui_footer
    write_state
    local release="${CURRENT_RELEASE%.*}"
    local parsed
    log_info "Traitement : $video"
    log_debug "Release envoyée au parser : $release"
    if ! parsed="$(parse_release "$release")"; then
        log_error "Échec du scene-release-parser pour '$release'"
        (( ERRORS+=1 ))
        return 1
    fi
    if ! echo "$parsed" | jq -e '.data' >/dev/null 2>&1; then
        log_error "Réponse JSON invalide du scene-release-parser pour '$release'"
        (( ERRORS+=1 ))
        return 1
    fi
    local title
    local year
    title="$(echo "$parsed" | jq -r '.data.title // ""')"
    year="$(echo "$parsed" | jq -r '.data.year // ""')"
    if [[ -z "$title" ]]; then
        log_error "Le parser n'a pas retourné de titre pour '$release'"
        (( ERRORS+=1 ))
        return 1
    fi
    CURRENT_TITLE="$title"
    log_info "Titre détecté : '$title'${year:+ ($year)}"

    # Recherche TMDB
    CURRENT_STEP="Recherche TMDB"
    tui_header
    tui_footer
    write_state
    local search_json
    if ! search_json="$(search_tmdb "$title" "$year")"; then
        log_error "Erreur API TMDB pour '$title'"
        (( ERRORS+=1 ))
        return 1
    fi
    local count
    count="$(jq '.results | length' <<< "$search_json")"
    if (( count == 0 )); then
        log_warn "Aucun résultat TMDB pour '$title'"
        (( ERRORS+=1 ))
        return 1
    fi
    log_info "$count résultat(s) TMDB trouvé(s) pour '$title'"

    # Construction des candidats
    CURRENT_STEP="Préparation des résultats TMDB"
    tui_header
    tui_footer
    write_state
    if ! build_candidates "$search_json"; then
        log_error "Impossible de construire les candidats TMDB"
        (( ERRORS+=1 ))
        return 1
    fi

    # Sélection utilisateur
    CURRENT_STEP="Sélection du film TMDB"
    local tmdb_id
    if tmdb_id="$(select_tmdb)"; then
        :
    else
        local selection_status=$?
        if (( selection_status == 1 )); then
            log_info "Film ignoré par l'utilisateur : $video"
            (( SKIPPED+=1 ))
        else
            log_warn "Sélection annulée : $video"
            (( SKIPPED+=1 ))
        fi
        return 0
    fi
    CURRENT_TMDB_ID="$tmdb_id"
    log_info "TMDB sélectionné : $tmdb_id"

    local tmdb_year
    tmdb_year="$(jq -r --argjson id "$tmdb_id" '.results[] | select(.id == $id) | .release_date | split("-")[0] // empty' <<< "$search_json")"

    # Récupération du titre final
    CURRENT_STEP="Récupération du titre TMDB"
    tui_header
    tui_footer
    write_state
    local movie_title
    if ! movie_title="$(get_final_title "$search_json" "$tmdb_id" "$title")"; then
        log_error "Impossible de récupérer le titre TMDB $tmdb_id"
        (( ERRORS+=1 ))
        return 1
    fi
    movie_title="$(sanitize_title "$movie_title")"
    log_info "Titre final : '$movie_title'"

    # Destination
    CURRENT_STEP="Préparation du dossier destination"
    tui_header
    tui_footer
    write_state
    local movie_directory
    if [[ -n "$tmdb_year" ]]; then
        movie_directory="${DESTINATION}/${movie_title} (${tmdb_year}) [tmdbid-${tmdb_id}]"
    else
        # Fallback si TMDB ne fournit pas de date de sortie.
        movie_directory="${DESTINATION}/${movie_title} [tmdbid-${tmdb_id}]"
    fi
    mkdir -p "$movie_directory"
    local filename
    local target
    filename="$(basename "$video")"
    target="${movie_directory}/${filename}"
    log_debug "Destination : $target"

    # Vérification filesystem
    CURRENT_STEP="Vérification du filesystem"
    tui_header
    tui_footer
    write_state
    if ! check_filesystem "$video"; then
        log_critical "Impossible de créer un hardlink : source et destination ne sont pas sur le même filesystem"
        (( ERRORS+=1 ))
        return 1
    fi

    # Si le fichier destination existe déjà.
    if [[ -e "$target" ]]; then
        # Même inode = migration déjà effectuée.
        if [[ "$(stat -c '%i' "$video")" == "$(stat -c '%i' "$target")" ]]; then
            log_info "Hardlink déjà présent : $target"
            (( SUCCESS+=1 ))
            return 0
        fi
        log_error "Le fichier destination existe déjà mais n'est pas le même inode : $target"
        (( ERRORS+=1 ))
        return 1
    fi

    # Création du hardlink
    CURRENT_STEP="Création du hardlink"
    tui_header
    tui_footer
    write_state
    if ! ln "$video" "$target"; then
        log_error "Échec de création du hardlink : $target"
        (( ERRORS+=1 ))
        return 1
    fi

    # Vérification du hardlink
    CURRENT_STEP="Vérification du hardlink"
    tui_header
    tui_footer
    write_state
    local source_inode
    local target_inode
    source_inode="$(stat -c '%i' "$video")"
    target_inode="$(stat -c '%i' "$target")"
    if [[ "$source_inode" != "$target_inode" ]]; then
        log_critical "ERREUR CRITIQUE : inode différent après création du hardlink"
        rm -f "$target"
        (( ERRORS+=1 ))
        return 1
    fi
    DESTINATION_INODES["$source_inode"]="$target"

    # Succès
    log_info "SUCCÈS : '$video' -> '$target' [inode $source_inode]"
    (( SUCCESS+=1 ))
    return 0
}

# ==============================================================================
# TUI : bilan final
# ==============================================================================
show_summary()
{
    while true; do
        clear
        printf '%s%sLIBRARY MIGRATION — BILAN%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
        printf '%-22s %s\n' "Films détectés :" "$TOTAL"
        printf '%-22s %s\n' "Films traités  :" "$PROCESSED"
        printf '%-22s %s%s%s\n' "Succès         :" "$C_GREEN" "$SUCCESS" "$C_RESET"
        printf '%-22s %s%s%s\n' "Erreurs         :" "$C_RED" "$ERRORS" "$C_RESET"
        printf '%-22s %s%s%s\n' "Ignorés         :" "$C_YELLOW" "$SKIPPED" "$C_RESET"
        printf '\n'
        printf '%s\n' \
            '──────────────────────────────────────────────────────────────────────────────'

        printf 'Source      : %s\n' "$FROM"
        printf 'Destination : %s\n' "$DESTINATION"
        printf 'Log         : %s\n' "$LOG_FILE"

        printf '%s\n\n' \
            '──────────────────────────────────────────────────────────────────────────────'
        local choice
        choice="$(
            printf '%s\n' "Ouvrir le log" "Quitter" |
            fzf --height=30% --layout=reverse --border=rounded --prompt='Action > ' --no-multi
        )" || return
        case "$choice" in
            "Ouvrir le log")
                # On utilise l'éditeur configuré. Fallback vers less.
                if [[ -n "${EDITOR:-}" ]]; then
                    "$EDITOR" "$LOG_FILE"
                else
                    less "$LOG_FILE"
                fi
                ;;

            "Quitter")
                return
                ;;
        esac
    done
}

# ==============================================================================
# Initialisation des fichiers temporaires
# ==============================================================================
STATE_FILE="$(mktemp)"
CANDIDATES_FILE="$(mktemp)"
RESULTS_FILE="$(mktemp)"

# ==============================================================================
# Scan initial
# ==============================================================================
CURRENT_STEP="Analyse de la bibliothèque source"
tui_header
tui_footer
log_info "Début de migration"
log_info "Source : $FROM"
log_info "Destination : $DESTINATION"
log_info "Configuration : ${CONFIG_FILE:-environnement}"
scan_source
build_destination_inode_index
TOTAL="${#MOVIE_FILES[@]}"
log_info "$TOTAL fichier(s) vidéo à traiter"
if (( TOTAL == 0 )); then
    log_warn "Aucun fichier vidéo trouvé dans '$FROM'"
    show_summary
    exit 0
fi

# ==============================================================================
# Boucle principale
# ==============================================================================
for video in "${MOVIE_FILES[@]}"; do
    CURRENT_STEP="Préparation"
    tui_header
    tui_footer
    process_movie "$video" || true
    (( PROCESSED+=1 ))
done

# ==============================================================================
# Bilan
# ==============================================================================
CURRENT_STEP="Migration terminée"
log_info "Migration terminée : total=$TOTAL traite=$PROCESSED succes=$SUCCESS erreurs=$ERRORS ignores=$SKIPPED"
show_summary
