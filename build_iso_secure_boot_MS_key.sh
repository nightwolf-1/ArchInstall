#!/usr/bin/env bash
# Script ISO Arch Linux Secure Boot - VERSION MICROSOFT KEYS (Optimisé)
set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ISO_DIR="${ISO_DIR:-$HOME/secureboot-iso}"
readonly ARCHISO_PROFILE="releng"
readonly TMP_MOUNT="$ISO_DIR/tmpmnt"
readonly OVMF_DIR="/usr/share/edk2-ovmf/x64"

# Variables globales
SCRIPT_MODE=""
FINAL_ISO_PATH=""
FINAL_ISO=""
ISO_NAME=""

# =============================================================================
# CONFIGURATION DES COULEURS ET LOGGING
# =============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_info() { echo -e "${BLUE}==> $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# =============================================================================
# UTILITAIRES
# =============================================================================

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local response

    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n "$question [Y/n] "
        else
            echo -n "$question [y/N] "
        fi

        read -r response
        [[ -z "$response" ]] && response="$default"

        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Réponse invalide. Utilise y/yes ou n/no." ;;
        esac
    done
}

cleanup_on_exit() {
    local test_vars="/tmp/OVMF_VARS_test_*.fd"
    rm -f $test_vars 2>/dev/null || true
}

trap cleanup_on_exit EXIT

# =============================================================================
# GESTION DES DÉPENDANCES
# =============================================================================

check_package_installed() {
    local package="$1"
    pacman -Q "$package" &>/dev/null
}


get_missing_packages() {
    local deps=("$@")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! check_package_installed "$dep"; then
            missing+=("$dep")
        fi
    done

    # Correction : ne pas utiliser printf si le tableau est vide
    if [ ${#missing[@]} -gt 0 ]; then
        printf '%s\n' "${missing[@]}"
    fi
}

install_packages() {
    local packages=("$@")

    # Correction : filtrer les éléments vides
    local filtered_packages=()
    for pkg in "${packages[@]}"; do
        if [[ -n "$pkg" ]]; then
            filtered_packages+=("$pkg")
        fi
    done

    if [ ${#filtered_packages[@]} -eq 0 ]; then
        return 0
    fi

    print_warning "Paquets manquants détectés: ${filtered_packages[*]}"

    if ask_yes_no "Veux-tu installer automatiquement les paquets manquants ?"; then
        print_info "Installation des paquets manquants..."

        if sudo pacman -S --needed "${filtered_packages[@]}"; then
            print_success "Paquets installés avec succès"
            return 0
        else
            print_error "Échec de l'installation des paquets"
            return 1
        fi
    else
        print_error "Impossible de continuer sans les paquets requis"
        echo "Installe-les manuellement avec: sudo pacman -S ${filtered_packages[*]}"
        return 1
    fi
}

check_dependencies() {
    print_info "Vérification des dépendances..."

    local deps=("archiso" "sbctl" "xorriso" "mtools" "dosfstools" "edk2-ovmf")
    local missing=()

    # Correction : utiliser une boucle directe pour éviter les éléments vides
    for dep in "${deps[@]}"; do
        if ! check_package_installed "$dep"; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        if ! install_packages "${missing[@]}"; then
            exit 1
        fi
    else
        print_success "Toutes les dépendances sont installées"
    fi
}

# =============================================================================
# GESTION OVMF
# =============================================================================

find_ovmf_files() {
    local mode="$1"
    local ovmf_code="" ovmf_vars=""
    
    if [[ "$mode" == "sign" ]]; then
        # Pour les ISOs signées, chercher les fichiers Secure Boot
        local secboot_files=(
            "$OVMF_DIR/OVMF_CODE.secboot.fd:$OVMF_DIR/OVMF_VARS.fd"
            "$OVMF_DIR/OVMF_CODE.secboot.4m.fd:$OVMF_DIR/OVMF_VARS.4m.fd"
        )
        
        for file_pair in "${secboot_files[@]}"; do
            local code="${file_pair%:*}"
            local vars="${file_pair#*:}"
            if [[ -f "$code" && -f "$vars" ]]; then
                ovmf_code="$code"
                ovmf_vars="$vars"
                break
            fi
        done
    else
        # Pour les ISOs non signées, chercher les fichiers standard
        local standard_files=(
            "$OVMF_DIR/OVMF_CODE.fd:$OVMF_DIR/OVMF_VARS.fd"
            "$OVMF_DIR/OVMF_CODE.4m.fd:$OVMF_DIR/OVMF_VARS.4m.fd"
        )
        
        for file_pair in "${standard_files[@]}"; do
            local code="${file_pair%:*}"
            local vars="${file_pair#*:}"
            if [[ -f "$code" && -f "$vars" ]]; then
                ovmf_code="$code"
                ovmf_vars="$vars"
                break
            fi
        done
    fi
    
    # Fallback: essayer n'importe quel fichier disponible
    if [[ -z "$ovmf_code" || -z "$ovmf_vars" ]]; then
        print_warning "Fichiers OVMF préférés non trouvés, recherche d'alternatives..."
        
        local fallback_files=(
            "$OVMF_DIR/OVMF_CODE.4m.fd:$OVMF_DIR/OVMF_VARS.4m.fd"
            "$OVMF_DIR/OVMF_CODE.secboot.4m.fd:$OVMF_DIR/OVMF_VARS.4m.fd"
            "$OVMF_DIR/OVMF_CODE.fd:$OVMF_DIR/OVMF_VARS.fd"
        )
        
        for file_pair in "${fallback_files[@]}"; do
            local code="${file_pair%:*}"
            local vars="${file_pair#*:}"
            if [[ -f "$code" && -f "$vars" ]]; then
                ovmf_code="$code"
                ovmf_vars="$vars"
                break
            fi
        done
    fi
    
    # Vérification finale
    if [[ ! -f "$ovmf_code" || ! -f "$ovmf_vars" ]]; then
        print_error "Impossible de trouver les fichiers OVMF dans $OVMF_DIR"
        print_info "Fichiers disponibles :"
        ls -la "$OVMF_DIR" 2>/dev/null || print_error "Répertoire OVMF introuvable"
        return 1
    fi
    
    echo "$ovmf_code:$ovmf_vars"
}

# =============================================================================
# GESTION SECURE BOOT
# =============================================================================

check_secure_boot_tools() {
    print_info "Vérification des outils Secure Boot..."

    if ! command -v sbctl &> /dev/null; then
        print_error "sbctl n'est pas installé"
        if ask_yes_no "Veux-tu installer sbctl ?"; then
            if ! install_packages "sbctl"; then
                exit 1
            fi
        else
            exit 1
        fi
    fi

    # Vérifier/créer les clés avec sbctl setup
    if ! sudo sbctl setup --print-state --json | grep -q '"installed": true'; then
        print_warning "Les clés Secure Boot ne sont pas configurées"
        if ask_yes_no "Veux-tu configurer les clés Secure Boot maintenant ?"; then
            sudo sbctl setup --setup
        else
            print_warning "Attention: Les clés ne sont pas configurées, la signature pourrait échouer"
        fi
    fi

    print_success "Outils Secure Boot prêts"
}

setup_secure_boot_keys() {
    print_info "Configuration des clés Secure Boot..."
    
    sudo sbctl create-keys
    if ! sudo sbctl list-enrolled-keys | grep -q "Platform Key"; then
        sudo sbctl enroll-keys -m
    fi
    
    print_success "Clés Secure Boot configurées"
}

sign_efi_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        print_warning "Fichier $file non trouvé"
        return 1
    fi
    
    print_info "Signature Microsoft de $file..."
    sudo sbctl sign -s "$file"
    print_success "$file signé"
}

# =============================================================================
# GESTION DES PACKAGES
# =============================================================================

add_packages_to_list() {
    local packages_file="$1"
    shift
    local packages=("$@")
    
    for pkg in "${packages[@]}"; do
        if ! grep -q "^$pkg$" "$packages_file"; then
            echo "$pkg" >> "$packages_file"
        fi
    done
}

check_iso_packages() {
    print_info "Vérification du fichier packages.x86_64..."

    local packages_file="$ISO_DIR/$ARCHISO_PROFILE/packages.x86_64"

    if [[ ! -f "$packages_file" ]]; then
        print_error "Fichier packages.x86_64 non trouvé: $packages_file"
        return 1
    fi

    # Packages requis pour Secure Boot
    local required_packages=("sbctl" "efibootmgr" "efitools" "edk2-shell")
    local missing_packages=()

    for pkg in "${required_packages[@]}"; do
        if ! grep -q "^$pkg$" "$packages_file"; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_warning "Ajout des packages manquants: ${missing_packages[*]}"
        add_packages_to_list "$packages_file" "${missing_packages[@]}"
        print_success "Packages ajoutés à $packages_file"
    else
        print_success "Tous les packages requis sont présents"
    fi

    # Vérifier les packages optionnels recommandés
    local optional_packages=("mokutil" "keyutils" "tpm2-tools")
    local missing_optional=()

    for pkg in "${optional_packages[@]}"; do
        if ! grep -q "^$pkg$" "$packages_file"; then
            missing_optional+=("$pkg")
        fi
    done

    if [ ${#missing_optional[@]} -gt 0 ]; then
        print_warning "Packages optionnels manquants: ${missing_optional[*]}"
        if ask_yes_no "Veux-tu les ajouter ?"; then
            add_packages_to_list "$packages_file" "${missing_optional[@]}"
            print_success "Packages optionnels ajoutés"
        fi
    fi
}

# =============================================================================
# GESTION DES FICHIERS
# =============================================================================

copy_file_to_iso() {
    local src="$1"
    local iso_root="airootfs"

    if [[ ! -f "$src" ]]; then
        print_error "Fichier introuvable : $src"
        return 1
    fi

    local dest="$iso_root/usr/local/bin/$(basename "$src")"
    print_info "Copie de $src vers $dest"

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    chmod +x "$dest"
}

copy_scripts_to_iso() {
    local scripts_dir="../../ArchInstall/scripts"
    
    if [[ ! -d "$scripts_dir" ]]; then
        print_warning "Répertoire $scripts_dir non trouvé"
        return 0
    fi
    
    for file in "$scripts_dir"/*.sh; do
        if [[ -f "$file" ]]; then
            copy_file_to_iso "$file"
        fi
    done
}

extract_iso_version_info() {
    local profiledef_file="./profiledef.sh"
    local extract_script="../../ArchInstall/utils/extract.sh"
    
    if [[ -f "$extract_script" && -f "$profiledef_file" ]]; then
        local iso_version=$(bash "$extract_script" "$profiledef_file" get iso_version 2>/dev/null || echo "latest")
        local iso_name=$(bash "$extract_script" "$profiledef_file" get iso_name 2>/dev/null || echo "archlinux")
        local arch=$(bash "$extract_script" "$profiledef_file" get arch 2>/dev/null || echo "x86_64")
        
        ISO_NAME="${iso_name}-${iso_version}-${arch}.iso"
    else
        ISO_NAME="archlinux-latest-x86_64.iso"
    fi
}

# =============================================================================
# CONSTRUCTION DE L'ISO
# =============================================================================

setup_iso_environment() {
    print_info "Configuration de l'environnement ISO..."

    mkdir -p "$ISO_DIR"
    cd "$ISO_DIR"

    # Copier le profil releng
    if [[ ! -d "$ISO_DIR/$ARCHISO_PROFILE" ]]; then
        cp -r "/usr/share/archiso/configs/$ARCHISO_PROFILE" "$ISO_DIR"
    fi

    cd "$ISO_DIR/$ARCHISO_PROFILE"

    # Vérifier et ajouter les packages
    check_iso_packages

    # Créer les répertoires nécessaires
    mkdir -p airootfs/usr/local/bin
    mkdir -p airootfs/usr/share/secureboot/

    # Marquer le type de clés utilisées
    echo "microsoft" > airootfs/usr/share/secureboot/key_type

    # Copier les scripts
    copy_scripts_to_iso

    print_success "Environnement ISO configuré avec support Microsoft"
}

build_base_iso() {
    print_info "Construction de l'ISO de base..."

    extract_iso_version_info
    
    # Définir les chemins selon le mode
    if [[ "$SCRIPT_MODE" == "sign" ]]; then
        FINAL_ISO="${ISO_NAME/.iso/-SecureBoot-MS-Signed.iso}"
        FINAL_ISO_PATH="$ISO_DIR/$FINAL_ISO"
    else
        FINAL_ISO="$ISO_NAME"
        FINAL_ISO_PATH="$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME"
    fi

    # Vérifier si l'ISO finale existe
    if [[ -f "$FINAL_ISO_PATH" ]]; then
        print_warning "L'ISO finale existe déjà : $FINAL_ISO"
        if ask_yes_no "Veux-tu la supprimer et la recréer ?"; then
            sudo rm -f "$FINAL_ISO_PATH"
        else
            print_info "Utilisation de l'ISO existante"
            return 0
        fi
    fi

    # Nettoyer l'ancienne ISO de base pour prendre en compte les modifications
    local base_iso="$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME"
    if [[ -f "$base_iso" ]]; then
        print_info "Suppression de l'ancienne ISO pour prendre en compte les modifications..."
        rm -f "$base_iso"
    fi
    
    sudo mkarchiso -vr ./
    print_success "ISO de base construite"
}

# =============================================================================
# SIGNATURE ET RECONSTRUCTION
# =============================================================================

extract_files_for_signing() {
    print_info "Extraction des fichiers pour signature..."

    local extract_dir="$ISO_DIR/extract"
    mkdir -p "$extract_dir"
    cd "$extract_dir"
    rm -rf ./*

    # Extraire les fichiers selon la documentation Arch
    sudo osirrox -indev "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" \
        -extract_boot_images ./ \
        -cpx /arch/boot/x86_64/vmlinuz-linux \
        /EFI/BOOT/BOOTx64.EFI \
        /EFI/BOOT/BOOTIA32.EFI \
        /shellx64.efi \
        /shellia32.efi ./

    # Rendre les fichiers modifiables
    sudo chmod +w BOOTx64.EFI BOOTIA32.EFI shellx64.efi shellia32.efi vmlinuz-linux

    print_success "Fichiers extraits"
}

sign_extracted_files() {
    print_info "Signature des fichiers avec clés Microsoft..."

    setup_secure_boot_keys

    local files_to_sign=("BOOTx64.EFI" "BOOTIA32.EFI" "shellx64.efi" "shellia32.efi" "vmlinuz-linux")

    for file in "${files_to_sign[@]}"; do
        sign_efi_file "$file"
    done

    print_success "Tous les fichiers signés avec les clés Microsoft"
}

find_eltorito_image() {
    local eltorito_img
    
    # Chercher l'image El Torito UEFI
    eltorito_img=$(find . -name "*eltorito_img*uefi*" | head -n1)
    if [[ -z "$eltorito_img" ]]; then
        eltorito_img=$(find . -name "*_eltorito.img" | head -n1)
    fi

    if [[ -z "$eltorito_img" ]]; then
        print_error "Image UEFI El Torito introuvable"
        return 1
    fi

    echo "$eltorito_img"
}

rebuild_signed_iso() {
    print_info "Reconstruction de l'ISO signée..."

    local eltorito_img
    if ! eltorito_img=$(find_eltorito_image); then
        return 1
    fi

    print_info "Utilisation de l'image El Torito: $eltorito_img"

    # Remplacer les fichiers selon la documentation Arch
    sudo mcopy -D oO -i "$eltorito_img" vmlinuz-linux ::/arch/boot/x86_64/vmlinuz-linux
    sudo mcopy -D oO -i "$eltorito_img" BOOTx64.EFI BOOTIA32.EFI ::/EFI/BOOT/
    sudo mcopy -D oO -i "$eltorito_img" shellx64.efi shellia32.efi ::/

    # Reconstruire l'ISO selon la documentation Arch
    sudo xorriso -indev "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" \
        -outdev "$FINAL_ISO_PATH" \
        -map vmlinuz-linux /arch/boot/x86_64/vmlinuz-linux \
        -map_l ./ /EFI/BOOT/ BOOTx64.EFI BOOTIA32.EFI -- \
        -map_l ./ / shellx64.efi shellia32.efi -- \
        -boot_image any replay \
        -append_partition 2 0xef "$eltorito_img"

    print_success "ISO finale générée : $FINAL_ISO"
}

# =============================================================================
# TESTS ET ÉCRITURE
# =============================================================================

test_iso_with_qemu() {
    print_info "Test avec QEMU..."
    
    # Détecter les fichiers OVMF
    local ovmf_files
    if ! ovmf_files=$(find_ovmf_files "$SCRIPT_MODE"); then
        print_error "Impossible de détecter les fichiers OVMF"
        return 1
    fi
    
    local ovmf_code="${ovmf_files%:*}"
    local ovmf_vars="${ovmf_files#*:}"
    
    if [[ "$SCRIPT_MODE" == "sign" ]]; then
        print_info "Mode: Test avec Secure Boot activé (ISO signée)"
    else
        print_info "Mode: Test sans Secure Boot (ISO non signée)"
    fi

    # Vérifier que l'ISO existe
    if [[ ! -f "$FINAL_ISO_PATH" ]]; then
        print_error "ISO non trouvée: $FINAL_ISO_PATH"
        return 1
    fi

    local test_vars="/tmp/OVMF_VARS_test_$(date +%s).fd"
    cp "$ovmf_vars" "$test_vars"

    print_info "Lancement de QEMU..."
    print_info "ISO testée: $FINAL_ISO_PATH"
    print_info "OVMF CODE: $ovmf_code"
    print_info "OVMF VARS: $ovmf_vars"

    # Paramètres QEMU adaptés
    local qemu_params=(
        -m 2048
        -smp 2
        -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
        -drive "if=pflash,format=raw,file=$test_vars"
        -drive "if=ide,media=cdrom,file=$FINAL_ISO_PATH"
        -net nic -net user
        -vga virtio
    )
    
    # Ajouter KVM si disponible
    if [[ -c /dev/kvm ]]; then
        qemu_params+=(-enable-kvm)
    fi

    qemu-system-x86_64 "${qemu_params[@]}"

    rm -f "$test_vars"
    print_success "Test QEMU terminé"
}

get_available_devices() {
    print_info "Périphériques disponibles :"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "(disk|usb)"
}

validate_device() {
    local device="$1"
    
    if [[ ! -b "/dev/$device" ]]; then
        print_error "Périphérique /dev/$device non trouvé"
        return 1
    fi

    if [[ "$device" == "sda" ]] || [[ "$device" == "nvme0n1" ]]; then
        print_warning "ATTENTION: $device semble être ton disque principal !"
        if ! ask_yes_no "Es-tu sûr de vouloir continuer ?"; then
            return 1
        fi
    fi
    
    return 0
}

write_iso_to_device() {
    local device="$1"
    
    print_info "Périphérique sélectionné: /dev/$device"
    lsblk "/dev/$device"

    print_warning "ATTENTION: Toutes les données sur /dev/$device seront EFFACÉES !"
    if ! ask_yes_no "Continuer ?"; then
        return 1
    fi

    # Démonter toutes les partitions
    sudo umount "/dev/${device}"* 2>/dev/null || true

    print_info "Écriture en cours..."
    print_info "ISO utilisée: $FINAL_ISO_PATH"
    
    sudo dd if="$FINAL_ISO_PATH" of="/dev/$device" bs=4M status=progress oflag=sync
    print_success "ISO écrite sur /dev/$device"
}

write_to_usb() {
    print_info "Écriture sur clé USB..."

    if [[ ! -f "$FINAL_ISO_PATH" ]]; then
        print_error "ISO non trouvée: $FINAL_ISO_PATH"
        return 1
    fi

    get_available_devices

    echo ""
    echo -n "Entre le nom du périphérique (ex: sdb): "
    read -r device

    if validate_device "$device"; then
        write_iso_to_device "$device"
    fi
}

# =============================================================================
# INTERFACE UTILISATEUR
# =============================================================================

print_postinstall_message() {
    echo ""
    print_info "Instructions d'installation:"
    print_info "1. Démarre sur l'ISO (Secure Boot activé)"
    print_info "2. Installe Arch Linux normalement"
    print_info "3. Récupère le PARTUUID de la partition EFI de Microsoft: blkid | grep vfat"
    print_info "4. Lance systemctl reboot --firmware-setup et met secure boot en mode setup"
    print_info "5. Redémarre avec Secure Boot activé sur l'ISO"
    print_info "6. nmcli device wifi connect SSID --ask"
    print_info "7. sudo pacman -Sy --needed sbctl edk2-shell"
    print_info "8. sudo cp /usr/share/edk2-shell/x64/Shell.efi /boot/shellx64.efi"
    print_info "9. sudo sbctl create-keys"
    print_info "10. sudo sbctl enroll-keys -m (pour garder les clés Microsoft)"
    print_info "11. sudo sbctl sign /boot/EFI/BOOT/BOOTx64.EFI"
    print_info "12. sudo sbctl sign /boot/EFI/systemd/systemd-bootx64.efi"
    print_info "13. sudo sbctl sign /boot/shellx64.efi"
    print_info "14. sudo sbctl sign /boot/vmlinuz-linux-lts"
    print_info "15. sudo sbctl sign /boot/vmlinuz-linux-zen"
    print_info "16. Reboot sur le shell EFI et récupérer l'alias (ex: HD0d ou BLk7)"
    print_info "17. Créer un fichier esp/loader/entries/windows.conf avec:"
    print_info "    title   Windows"
    print_info "    efi     /shellx64.efi"
    print_info "    options -nointerrupt -nomap -noversion HD0d:EFI\\Microsoft\\Boot\\Bootmgfw.efi"
    print_info "    (où HD0d est l'alias trouvé à l'étape 16)"
}

ask_test_qemu() {
    if ask_yes_no "Veux-tu tester l'ISO avec QEMU ?"; then
        test_iso_with_qemu
    fi
}

ask_write_to_usb() {
    if ask_yes_no "Veux-tu écrire l'ISO sur une clé USB ?"; then
        write_to_usb
    fi
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -b, --build-iso    Build ISO en ajoutant les scripts dans l'ISO
  -bs, --build-sign  Build ISO et signer (ATTENTION: il faut être en setup mode)
  -h, --help         Afficher cette aide

Fonctionnalités :
  - Installation automatique des paquets manquants
  - Test QEMU adapté selon le mode (avec/sans Secure Boot)
  - Reconstruction forcée pour prendre en compte les scripts modifiés
  - Détection automatique des fichiers OVMF

Détection automatique :
  - Chemins EFI : /boot/efi, /boot, /efi, /boot/esp
  - Fichiers EFI : recherche récursive dans le chemin EFI
  - Noyaux : vmlinuz-*, bzImage-* dans /boot et chemins EFI
  - Initramfs : initramfs-*.img, initrd.img-* dans /boot et chemins EFI
  - Fichiers OVMF : détection automatique (.fd, .4m.fd, .secboot.fd)
EOF
}

# =============================================================================
# MODES DE FONCTIONNEMENT
# =============================================================================

build_iso_mode() {
    SCRIPT_MODE="build"
    check_dependencies
    setup_iso_environment
    build_base_iso
    ask_test_qemu
    ask_write_to_usb
    
    echo ""
    print_success "ISO créée avec succès !"
    print_info "Fichier: $FINAL_ISO_PATH"
    print_info "Type: Non signée (compatible avec Secure Boot désactivé)"
    print_postinstall_message
}

build_and_sign_mode() {
    SCRIPT_MODE="sign"
    check_dependencies
    check_secure_boot_tools
    setup_iso_environment
    build_base_iso
    extract_files_for_signing
    sign_extracted_files
    rebuild_signed_iso
    ask_test_qemu
    ask_write_to_usb
    
    echo ""
    print_success "ISO créée avec succès !"
    print_info "Fichier: $FINAL_ISO_PATH"
    print_info "Type: Signée avec clés Microsoft (compatible partout)"
    print_postinstall_message
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    echo "=== ISO Arch Linux Secure Boot - CLÉS MICROSOFT ==="
    echo ""

    case "${1:-}" in
        -b|--build-iso)
            build_iso_mode
            ;;
        -bs|--build-sign)
            build_and_sign_mode
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Option inconnue : ${1:-<aucune>}"
            show_help
            exit 1
            ;;
    esac
    
    echo ""
    print_success "Terminé !"
}

# =============================================================================
# VÉRIFICATIONS ET LANCEMENT
# =============================================================================

# Vérification des privilèges
if [[ $EUID -eq 0 ]]; then
    print_error "Ne pas exécuter ce script en tant que root"
    exit 1
fi

main "$@"
