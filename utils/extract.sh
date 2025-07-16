#!/usr/bin/env bash

# Version sans eval - utilise un sous-shell sécurisé pour l'évaluation

# Fonction pour extraire une variable de manière sécurisée
extract_var_secure() {
    local file="$1"
    local var_name="$2"

    # Utiliser la méthode directe qui est plus sûre
    extract_var_direct "$file" "$var_name"
}

# Fonction pour sourcer seulement les variables simples (pas les tableaux)
source_simple_vars() {
    local file="$1"
    
    # Créer un fichier temporaire avec seulement les variables simples
    local temp_file=$(mktemp)
    
    # Extraire seulement les variables simples (pas les tableaux)
    grep -E '^[a-zA-Z_][a-zA-Z0-9_]*=' "$file" | \
    grep -v -E '^(buildmodes|bootmodes|file_permissions|airootfs_image_tool_options|bootstrap_tarball_compression)=' | \
    grep -v -E '\$\(' > "$temp_file"
    
    # Sourcer le fichier temporaire
    source "$temp_file"
    
    # Nettoyer
    rm -f "$temp_file"
}

# Fonction alternative : extraction directe avec parsing manuel
extract_var_direct() {
    local file="$1"
    local var_name="$2"

    # Extraire la valeur brute
    local raw_value=$(grep "^$var_name=" "$file" | head -1 | sed "s/^$var_name=\"\(.*\)\"/\1/")

    if [[ -n "$raw_value" ]]; then
        # Si c'est une commande date avec SOURCE_DATE_EPOCH
        if [[ "$raw_value" =~ \$\(date.*SOURCE_DATE_EPOCH ]]; then
            # Extraire SOURCE_DATE_EPOCH du fichier
            local source_date_epoch=$(grep "^SOURCE_DATE_EPOCH=" "$file" | head -1 | sed 's/^SOURCE_DATE_EPOCH="\?\([^"]*\)"\?/\1/')
            
            if [[ -n "$source_date_epoch" ]]; then
                # Utiliser SOURCE_DATE_EPOCH
                date --date="@$source_date_epoch" +%Y.%m.%d
            else
                # Fallback sur date actuelle
                date +%Y.%m.%d
            fi
        # Si c'est une commande date simple comme $(date +%Y.%m.%d)
        elif [[ "$raw_value" =~ \$\(date[[:space:]]+\+%Y\.%m\.%d\) ]]; then
            date +%Y.%m.%d
        # Si c'est une commande date avec autre format
        elif [[ "$raw_value" =~ \$\(date.*\+[^)]+\) ]]; then
            # Extraire le format
            local format=$(echo "$raw_value" | sed 's/.*+\([^)]*\).*/\1/')
            date +"$format"
        # Pattern plus complexe pour archlinux: ARCH_YYYYMMDD
        elif [[ "$raw_value" =~ ARCH_[0-9]{8} ]]; then
            # Extraire la date du pattern ARCH_YYYYMMDD et la convertir
            local arch_date=$(echo "$raw_value" | sed 's/.*ARCH_\([0-9]\{8\}\).*/\1/')
            if [[ -n "$arch_date" && ${#arch_date} -eq 8 ]]; then
                # Convertir YYYYMMDD en YYYY.MM.DD
                echo "${arch_date:0:4}.${arch_date:4:2}.${arch_date:6:2}"
            else
                # Fallback
                date +%Y.%m.%d
            fi
        # Si c'est une autre commande, essayer de l'exécuter directement
        elif [[ "$raw_value" =~ \$\( ]]; then
            # Créer un environnement minimal pour l'exécution
            (
                # Sourcer les variables simples nécessaires
                source_simple_vars "$file"
                # Exécuter la commande substituée
                bash -c "echo $raw_value"
            ) 2>/dev/null || echo ""
        else
            echo "$raw_value"
        fi
    else
        echo ""
    fi
}

# Fonction pour récupérer toutes les valeurs principales
get_all_values() {
    local file="$1"
    local method="${2:-secure}"  # secure ou direct

    if [[ ! -f "$file" ]]; then
        echo "Erreur: Le fichier $file n'existe pas" >&2
        return 1
    fi

    # Choisir la méthode d'extraction
    local extract_func="extract_var_secure"
    if [[ "$method" == "direct" ]]; then
        extract_func="extract_var_direct"
    fi

    # Extraire chaque variable
    local iso_name=$($extract_func "$file" "iso_name")
    local arch=$($extract_func "$file" "arch")
    local install_dir=$($extract_func "$file" "install_dir")
    local pacman_conf=$($extract_func "$file" "pacman_conf")
    local airootfs_image_type=$($extract_func "$file" "airootfs_image_type")
    local iso_publisher=$($extract_func "$file" "iso_publisher")
    local iso_application=$($extract_func "$file" "iso_application")
    local iso_label=$($extract_func "$file" "iso_label")
    local iso_version=$($extract_func "$file" "iso_version")

    # Afficher les résultats
    echo "iso_name=$iso_name"
    echo "iso_version=$iso_version"
    echo "iso_label=$iso_label"
    echo "arch=$arch"
    echo "iso_publisher=$iso_publisher"
    echo "iso_application=$iso_application"
    echo "install_dir=$install_dir"
    echo "pacman_conf=$pacman_conf"
    echo "airootfs_image_type=$airootfs_image_type"
}

# Fonction pour récupérer une valeur spécifique
get_value() {
    local file="$1"
    local var_name="$2"
    local method="${3:-secure}"

    if [[ ! -f "$file" ]]; then
        echo "Erreur: Le fichier $file n'existe pas" >&2
        return 1
    fi

    if [[ "$method" == "direct" ]]; then
        extract_var_direct "$file" "$var_name"
    else
        extract_var_secure "$file" "$var_name"
    fi
}

# Fonction pour tester les différentes méthodes
test_methods() {
    local file="$1"

    echo "=== Test des méthodes d'extraction ==="
    echo ""

    echo "Méthode 1: Extraction sécurisée (sous-shell)"
    if result=$(get_all_values "$file" "secure" 2>&1); then
        echo "✅ Succès"
        echo "$result"
    else
        echo "❌ Échec: $result"
    fi

    echo ""
    echo "Méthode 2: Extraction directe (parsing manuel)"
    if result=$(get_all_values "$file" "direct" 2>&1); then
        echo "✅ Succès"
        echo "$result"
    else
        echo "❌ Échec: $result"
    fi
}

# Fonction pour afficher les valeurs principales
show_main_values() {
    local file="$1"
    local method="${2:-secure}"

    echo "=== Valeurs principales (méthode: $method) ==="
    echo "ISO Name: $(get_value "$file" "iso_name" "$method")"
    echo "ISO Version: $(get_value "$file" "iso_version" "$method")"
    echo "Architecture: $(get_value "$file" "arch" "$method")"
    echo "ISO Label: $(get_value "$file" "iso_label" "$method")"
    echo ""
    echo "=== Nom de fichier suggéré ==="
    local name=$(get_value "$file" "iso_name" "$method")
    local version=$(get_value "$file" "iso_version" "$method")
    local arch=$(get_value "$file" "arch" "$method")
    echo "${name}-${version}-${arch}.iso"
}

# Fonction principale
main() {
    local file="$1"
    local command="${2:-show}"
    local param3="$3"
    local param4="$4"

    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <profiledef.sh> [commande] [paramètre] [méthode]"
        echo ""
        echo "Commandes:"
        echo "  show [méthode]      - Affiche les valeurs principales"
        echo "  get <variable> [méthode] - Récupère une variable spécifique"
        echo "  all [méthode]       - Affiche toutes les valeurs"
        echo "  test                - Test les différentes méthodes"
        echo ""
        echo "Méthodes:"
        echo "  secure              - Sous-shell sécurisé (défaut)"
        echo "  direct              - Parsing manuel des commandes date"
        echo ""
        echo "Exemples:"
        echo "  $0 profiledef.sh show"
        echo "  $0 profiledef.sh show direct"
        echo "  $0 profiledef.sh get iso_version"
        echo "  $0 profiledef.sh get iso_version direct"
        echo "  $0 profiledef.sh all secure"
        exit 1
    fi

    case "$command" in
        "show")
            show_main_values "$file" "$param3"
            ;;
        "get")
            if [[ -z "$param3" ]]; then
                echo "Usage: $0 $file get <variable_name> [méthode]"
                exit 1
            fi
            get_value "$file" "$param3" "$param4"
            ;;
        "all")
            get_all_values "$file" "$param3"
            ;;
        "test")
            test_methods "$file"
            ;;
        *)
            echo "Commande inconnue: $command"
            exit 1
            ;;
    esac
}

main "$@"