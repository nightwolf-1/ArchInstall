#!/usr/bin/env bash
# Script ISO Arch Linux Secure Boot - VERSION MICROSOFT KEYS
set -euo pipefail

# Configuration
ISO_DIR="$HOME/secureboot-iso"
ARCHISO_PROFILE="releng"
TMP_MOUNT="$ISO_DIR/tmpmnt"
SCRIPT_MODE=""  # Variable pour stocker le mode du script

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}==> $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Fonction pour détecter les fichiers OVMF
detect_ovmf_files() {
    local ovmf_dir="/usr/share/edk2-ovmf/x64"
    local ovmf_code="" ovmf_vars=""
    
    if [[ "$SCRIPT_MODE" == "sign" ]]; then
        # Pour les ISOs signées, chercher les fichiers Secure Boot
        if [ -f "$ovmf_dir/OVMF_CODE.secboot.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.secboot.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.fd"
        elif [ -f "$ovmf_dir/OVMF_CODE.secboot.4m.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.secboot.4m.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.4m.fd"
        fi
    else
        # Pour les ISOs non signées, chercher les fichiers standard
        if [ -f "$ovmf_dir/OVMF_CODE.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.fd"
        elif [ -f "$ovmf_dir/OVMF_CODE.4m.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.4m.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.4m.fd"
        fi
    fi
    
    # Si les fichiers spécifiques ne sont pas trouvés, essayer les alternatives
    if [ -z "$ovmf_code" ] || [ -z "$ovmf_vars" ]; then
        print_warning "Fichiers OVMF préférés non trouvés, recherche d'alternatives..."
        
        # Chercher n'importe quel fichier CODE disponible
        if [ -f "$ovmf_dir/OVMF_CODE.4m.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.4m.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.4m.fd"
        elif [ -f "$ovmf_dir/OVMF_CODE.secboot.4m.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.secboot.4m.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.4m.fd"
        elif [ -f "$ovmf_dir/OVMF_CODE.fd" ]; then
            ovmf_code="$ovmf_dir/OVMF_CODE.fd"
            ovmf_vars="$ovmf_dir/OVMF_VARS.fd"
        fi
    fi
    
    # Vérifier que les fichiers existent
    if [ ! -f "$ovmf_code" ] || [ ! -f "$ovmf_vars" ]; then
        print_error "Impossible de trouver les fichiers OVMF dans $ovmf_dir"
        print_info "Fichiers disponibles :"
        ls -la "$ovmf_dir" 2>/dev/null || print_error "Répertoire OVMF introuvable"
        return 1
    fi
    
    echo "$ovmf_code:$ovmf_vars"
}

install_missing_packages() {
    local missing_packages=("$@")
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        return 0
    fi
    
    print_warning "Paquets manquants détectés: ${missing_packages[*]}"
    
    if ask_yes_no "Veux-tu installer automatiquement les paquets manquants ?"; then
        print_info "Installation des paquets manquants..."
        
        if sudo pacman -S --needed "${missing_packages[@]}"; then
            print_success "Paquets installés avec succès"
            return 0
        else
            print_error "Échec de l'installation des paquets"
            return 1
        fi
    else
        print_error "Impossible de continuer sans les paquets requis"
        echo "Installe-les manuellement avec: sudo pacman -S ${missing_packages[*]}"
        return 1
    fi
}

check_dependencies() {
    print_info "Vérification des dépendances..."

    local deps=("archiso" "sbctl" "xorriso" "mtools" "dosfstools" "edk2-ovmf")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! pacman -Q "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        if ! install_missing_packages "${missing[@]}"; then
            exit 1
        fi
    else
        print_success "Toutes les dépendances sont installées"
    fi
}

check_secure_boot_tools() {
    print_info "Vérification des outils Secure Boot..."

    if ! command -v sbctl &> /dev/null; then
        print_error "sbctl n'est pas installé"
        if ask_yes_no "Veux-tu installer sbctl ?"; then
            if ! install_missing_packages "sbctl"; then
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

check_packages() {
    print_info "Vérification du fichier packages.x86_64..."

    local packages_file="$ISO_DIR/$ARCHISO_PROFILE/packages.x86_64"

    if [ ! -f "$packages_file" ]; then
        print_error "Fichier packages.x86_64 non trouvé: $packages_file"
        exit 1
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
        for pkg in "${missing_packages[@]}"; do
            echo "$pkg" >> "$packages_file"
        done
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
            for pkg in "${missing_optional[@]}"; do
                echo "$pkg" >> "$packages_file"
            done
            print_success "Packages optionnels ajoutés"
        fi
    fi
}

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

        if [[ -z "$response" ]]; then
            response="$default"
        fi

        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Réponse invalide. Utilise y/yes ou n/no." ;;
        esac
    done
}

copy_to_iso() {
    local src="$1"
    local iso_root="airootfs"

    if [[ ! -f "$src" ]]; then
        echo "❌ Fichier introuvable : $src"
        return 1
    fi

    local dest="$iso_root/usr/local/bin/$(basename "$src")"
    echo "📁 Copie de $src vers $dest"

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    chmod +x "$dest"
}

setup_iso_environment() {
    print_info "Configuration de l'environnement ISO..."

    mkdir -p "$ISO_DIR"
    cd "$ISO_DIR"

    # Copier le profil releng
    if [ ! -d "$ISO_DIR/$ARCHISO_PROFILE" ]; then
        cp -r /usr/share/archiso/configs/$ARCHISO_PROFILE "$ISO_DIR"
    fi

    cd "$ISO_DIR/$ARCHISO_PROFILE"

    # Vérifier et ajouter les packages
    check_packages

    # Créer le répertoire pour les scripts
    mkdir -p airootfs/usr/local/bin

    # Marquer le type de clés utilisées
    mkdir -p airootfs/usr/share/secureboot/
    echo "microsoft" > airootfs/usr/share/secureboot/key_type

    # Copier le script de configuration principal
    if [ -d "../../ArchInstall/scripts" ]; then
        for file in ../../ArchInstall/scripts/*.sh; do
            if [ -f "$file" ]; then
                copy_to_iso "$file"
            fi
        done
    else
        print_warning "Répertoire ../../ArchInstall/scripts non trouvé"
    fi

    print_success "Environnement ISO configuré avec support Microsoft"
}

build_iso() {
    print_info "Construction de l'ISO..."

    pwd
    iso_version=$(bash ../../ArchInstall/utils/extract.sh ./profiledef.sh get iso_version 2>/dev/null || echo "latest")
    iso_name=$(bash ../../ArchInstall/utils/extract.sh ./profiledef.sh get iso_name 2>/dev/null || echo "archlinux")
    arch=$(bash ../../ArchInstall/utils/extract.sh ./profiledef.sh get arch 2>/dev/null || echo "x86_64")

    ISO_NAME="${iso_name}-${iso_version}-${arch}.iso"
    
    # Définir le nom final selon le mode
    if [[ "$SCRIPT_MODE" == "sign" ]]; then
        FINAL_ISO="${ISO_NAME/.iso/-SecureBoot-MS-Signed.iso}"
        FINAL_ISO_PATH="$ISO_DIR/$FINAL_ISO"
    else
        # En mode build, l'ISO finale est dans out/
        FINAL_ISO="$ISO_NAME"
        FINAL_ISO_PATH="$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME"
    fi

    # Vérifier si l'ISO finale existe
    if [ -f "$FINAL_ISO_PATH" ]; then
        print_warning "L'ISO finale existe déjà : $FINAL_ISO"
        if ask_yes_no "Veux-tu la supprimer et la recréer ?"; then
            sudo rm -f "$FINAL_ISO_PATH"
        else
            print_info "Utilisation de l'ISO existante"
            return 0
        fi
    fi

    # Forcer la reconstruction pour prendre en compte les scripts modifiés
    if [ -f "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" ]; then
        print_info "Suppression de l'ancienne ISO pour prendre en compte les modifications..."
        rm -f "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME"
    fi
    
    sudo mkarchiso -vr ./
    print_success "ISO de base construite"
}

extract_and_sign_files() {
    print_info "Extraction et signature avec clés Microsoft..."

    mkdir -p "$ISO_DIR/extract"
    cd "$ISO_DIR/extract"
    rm -rf ./*

    # Extraire les fichiers selon la documentation Arch
    sudo osirrox -indev "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" \
        -extract_boot_images ./ \
        -cpx /arch/boot/x86_64/vmlinuz-linux \
        /EFI/BOOT/BOOTx64.EFI \
        /EFI/BOOT/BOOTIA32.EFI \
        /shellx64.efi \
        /shellia32.efi ./

    # Rendre les fichiers modifiables (selon la doc Arch)
    sudo chmod +w BOOTx64.EFI BOOTIA32.EFI shellx64.efi shellia32.efi vmlinuz-linux

    # Signer avec les clés Microsoft via sbctl
    local files_to_sign=("BOOTx64.EFI" "BOOTIA32.EFI" "shellx64.efi" "shellia32.efi" "vmlinuz-linux")

    sudo sbctl create-keys
    if ! sudo sbctl list-enrolled-keys | grep -q "Platform Key"; then
        sudo sbctl enroll-keys -m
    fi
    for file in "${files_to_sign[@]}"; do
        if [ -f "$file" ]; then
            print_info "Signature Microsoft de $file..."
            # Utiliser sbctl avec les clés Microsoft
            sudo sbctl sign -s "$file"
            print_success "$file signé"
        else
            print_warning "Fichier $file non trouvé"
        fi
    done

    print_success "Tous les fichiers signés avec les clés Microsoft"
}

rebuild_iso() {
    print_info "Reconstruction de l'ISO..."

    # Trouver l'image El Torito UEFI
    local eltorito_img=$(find . -name "*eltorito_img*uefi*" | head -n1)
    if [ -z "$eltorito_img" ]; then
        eltorito_img=$(find . -name "*_eltorito.img" | head -n1)
    fi

    if [ -z "$eltorito_img" ]; then
        print_error "Image UEFI El Torito introuvable"
        exit 1
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

write_to_usb() {
    print_info "Écriture sur clé USB..."

    print_info "Périphériques disponibles :"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "(disk|usb)"

    echo ""
    echo -n "Entre le nom du périphérique (ex: sdb): "
    read -r device

    if [ ! -b "/dev/$device" ]; then
        print_error "Périphérique /dev/$device non trouvé"
        return 1
    fi

    if [[ "$device" == "sda" ]] || [[ "$device" == "nvme0n1" ]]; then
        print_warning "ATTENTION: $device semble être ton disque principal !"
        if ! ask_yes_no "Es-tu sûr de vouloir continuer ?"; then
            return 1
        fi
    fi

    print_info "Périphérique sélectionné: /dev/$device"
    lsblk "/dev/$device"

    print_warning "ATTENTION: Toutes les données sur /dev/$device seront EFFACÉES !"
    if ! ask_yes_no "Continuer ?"; then
        return 1
    fi

    sudo umount "/dev/${device}"* 2>/dev/null || true

    print_info "Écriture en cours..."
    
    # Utiliser l'ISO appropriée selon le mode
    if [ ! -f "$FINAL_ISO_PATH" ]; then
        print_error "ISO non trouvée: $FINAL_ISO_PATH"
        return 1
    fi
    
    print_info "ISO utilisée: $FINAL_ISO_PATH"
    sudo dd if="$FINAL_ISO_PATH" of="/dev/$device" bs=4M status=progress oflag=sync

    print_success "ISO écrite sur /dev/$device"
}

test_with_qemu() {
    print_info "Test avec QEMU..."
    
    # Détecter les fichiers OVMF
    local ovmf_files
    if ! ovmf_files=$(detect_ovmf_files); then
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
    if [ ! -f "$FINAL_ISO_PATH" ]; then
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
    if [ -c /dev/kvm ]; then
        qemu_params+=(-enable-kvm)
    fi

    qemu-system-x86_64 "${qemu_params[@]}"

    rm -f "$test_vars"
    print_success "Test QEMU terminé"
}

print_postinstall_message(){
    echo ""
    print_info "Instructions d'installation:"
    print_info "1. Démarre sur l'ISO (Secure Boot activé)"
    print_info "2. Installe Arch Linux normalement"
    print_info "3. Récupère le PARTUUID de la partition EFI de Microsoft: blkid | grep vfat (prendre en photo)"
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

ask_test_qemu(){
    if ask_yes_no "Veux-tu tester l'ISO avec QEMU ?"; then
        test_with_qemu
    fi
}

ask_write_to_usb(){
    if ask_yes_no "Veux-tu écrire l'ISO sur une clé USB ?"; then
        write_to_usb
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -b, --build-iso    Build ISO en ajoutant les scripts dans l'ISO"
    echo "  -bs, --build-sign  Build ISO et signer (ATTENTION: il faut être en setup mode)"
    echo "  -h, --help         Afficher cette aide"
    echo
    echo "Fonctionnalités :"
    echo "  - Installation automatique des paquets manquants"
    echo "  - Test QEMU adapté selon le mode (avec/sans Secure Boot)"
    echo "  - Reconstruction forcée pour prendre en compte les scripts modifiés"
    echo "  - Détection automatique des fichiers OVMF"
    echo
    echo "Détection automatique :"
    echo "  - Chemins EFI : /boot/efi, /boot, /efi, /boot/esp"
    echo "  - Fichiers EFI : recherche récursive dans le chemin EFI"
    echo "  - Noyaux : vmlinuz-*, bzImage-* dans /boot et chemins EFI"
    echo "  - Initramfs : initramfs-*.img, initrd.img-* dans /boot et chemins EFI"
    echo "  - Fichiers OVMF : détection automatique (.fd, .4m.fd, .secboot.fd)"
    echo
}

main() {
    echo "=== ISO Arch Linux Secure Boot - CLÉS MICROSOFT ==="
    echo ""

    case "${1:-}" in
        -b|--build-iso)
            SCRIPT_MODE="build"
            check_dependencies
            setup_iso_environment
            build_iso
            ask_test_qemu
            ask_write_to_usb
            echo ""
            print_success "ISO créée avec succès !"
            print_info "Fichier: $FINAL_ISO_PATH"
            print_info "Type: Non signée (compatible avec Secure Boot désactivé)"
            print_postinstall_message
            echo ""
            print_success "Terminé !"
            ;;
        -bs|--build-sign)
            SCRIPT_MODE="sign"
            check_dependencies
            check_secure_boot_tools
            setup_iso_environment
            build_iso
            extract_and_sign_files
            rebuild_iso
            ask_test_qemu
            ask_write_to_usb
            echo ""
            print_success "ISO créée avec succès !"
            print_info "Fichier: $FINAL_ISO_PATH"
            print_info "Type: Signée avec clés Microsoft (compatible partout)"
            print_postinstall_message
            echo ""
            print_success "Terminé !"
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
}

# Vérification des privilèges
if [[ $EUID -eq 0 ]]; then
    print_error "Ne pas exécuter ce script en tant que root"
    exit 1
fi

main "$@"
