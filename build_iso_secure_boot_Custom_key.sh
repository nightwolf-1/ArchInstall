#!/usr/bin/env bash

# Script ISO Arch Linux Secure Boot - VERSION CLÉS PERSONNALISÉES

set -euo pipefail

# Configuration
ISO_DIR="$HOME/secureboot-iso"
ARCHISO_PROFILE="releng"
CUSTOM_KEYS_DIR="$HOME/.secureboot-keys"
TMP_MOUNT="$ISO_DIR/tmpmnt"

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

check_dependencies() {
    print_info "Vérification des dépendances…"
    
    local deps=("archiso" "sbctl" "xorriso" "mtools" "dosfstools" "edk2-ovmf")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! pacman -Q "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Dépendances manquantes: ${missing[*]}"
        echo "Installe-les avec: sudo pacman -S ${missing[*]}"
        exit 1
    fi
    
    print_success "Toutes les dépendances sont installées"
}

check_secure_boot_tools() {
    print_info "Vérification des outils Secure Boot…"
    
    if ! command -v sbctl &> /dev/null; then
        print_error "sbctl n'est pas installé"
        exit 1
    fi
    
    # Créer le dossier pour les clés personnalisées
    mkdir -p "$CUSTOM_KEYS_DIR"
    
    # Vérifier/créer les clés personnalisées
    if ! sudo sbctl verify &>/dev/null; then
        print_info "Création des clés personnalisées..."
        sudo sbctl create-keys
        
        # Copier les clés dans le dossier personnel
        sudo cp -r /usr/share/secureboot/keys/* "$CUSTOM_KEYS_DIR/" 2>/dev/null || true
        sudo chown -R $(whoami):$(whoami) "$CUSTOM_KEYS_DIR"
    fi
    
    print_success "Clés personnalisées prêtes"
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

setup_iso_environment() {
    print_info "Configuration de l'environnement ISO…"
    
    mkdir -p "$ISO_DIR"
    cd "$ISO_DIR"
    
    # Copier le profil releng
    if [ ! -d "$ISO_DIR/$ARCHISO_PROFILE" ]; then
        cp -r /usr/share/archiso/configs/$ARCHISO_PROFILE "$ISO_DIR"
    fi
    
    cd "$ISO_DIR/$ARCHISO_PROFILE"
    
    # Ajouter les outils nécessaires
    if ! grep -q "sbctl" packages.x86_64 2>/dev/null; then
        echo "sbctl" >> packages.x86_64
        echo "efibootmgr" >> packages.x86_64
    fi
    
    mkdir -p airootfs/usr/local/bin
    cp setup-secureboot.sh airootfs/usr/local/bin
    chmod +x airootfs/usr/local/bin/setup-secureboot.sh

    # Copier les clés personnalisées dans l'ISO
    mkdir -p airootfs/usr/share/secureboot/
    if [ -d "$CUSTOM_KEYS_DIR" ]; then
        cp -r "$CUSTOM_KEYS_DIR" airootfs/usr/share/secureboot/keys
    fi
    echo "custom" > airootfs/usr/share/secureboot/key_type
    
    print_success "Environnement ISO configuré avec clés personnalisées"
}

build_iso() {
    print_info "Construction de l'ISO…"
    
    read -r iso_name iso_version arch < <(
        awk '
        /^iso_name=/     { gsub(/.*="/, "", $0); gsub(/"$/, "", $0); name = $0 }
        /^iso_version=/  { gsub(/.*="/, "", $0); gsub(/"$/, "", $0); version = $0 }
        /^arch=/         { gsub(/.*="/, "", $0); gsub(/"$/, "", $0); arch = $0 }
        END              { print name, version, arch }
        ' ./profiledef.sh
    )
    
    if [ -z "$iso_version" ]; then
        iso_version=$(date +"%Y.%m.%d")
    fi
    
    ISO_NAME="${iso_name}-${iso_version}-${arch}.iso"
    FINAL_ISO="${ISO_NAME/.iso/-SecureBoot-Custom.iso}"
    
    # Vérifier si l'ISO finale existe
    if [ -f "$ISO_DIR/$FINAL_ISO" ]; then
        print_warning "L'ISO finale existe déjà : $FINAL_ISO"
        if ask_yes_no "Veux-tu la supprimer et la recréer ?"; then
            rm -f "$ISO_DIR/$FINAL_ISO"
        else
            print_info "Utilisation de l'ISO existante"
            return 0
        fi
    fi
    
    # Construire l'ISO de base
    if [ -f "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" ]; then
        print_info "L'ISO de base existe déjà : $ISO_NAME"
        if ask_yes_no "Veux-tu la regénérer ?"; then
            sudo mkarchiso -vr ./
        fi
    else
        sudo mkarchiso -vr ./
    fi
    
    print_success "ISO de base construite"
}

extract_and_sign_files() {
    print_info "Extraction et signature avec clés personnalisées…"
    
    mkdir -p "$ISO_DIR/extract"
    cd "$ISO_DIR/extract"
    rm -rf ./*
    
    # Extraire les fichiers
    sudo osirrox -indev "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" \
        -extract_boot_images ./ \
        -cpx /arch/boot/x86_64/vmlinuz-linux \
        /EFI/BOOT/BOOTx64.EFI \
        /EFI/BOOT/BOOTIA32.EFI \
        /shellx64.efi \
        /shellia32.efi ./
    
    # Signer avec les clés personnalisées
    local files_to_sign=("BOOTx64.EFI" "BOOTIA32.EFI" "shellx64.efi" "shellia32.efi" "vmlinuz-linux")
    
    for file in "${files_to_sign[@]}"; do
        if [ -f "$file" ]; then
            print_info "Signature personnalisée de $file..."
            sudo sbctl sign "$file"
            print_success "$file signé"
        fi
    done
    
    print_success "Tous les fichiers signés avec les clés personnalisées"
}

rebuild_iso() {
    print_info "Reconstruction de l'ISO…"
    
    local eltorito_img=$(find . -name "*_eltorito.img" | head -n1)
    if [ -z "$eltorito_img" ]; then
        print_error "Image UEFI introuvable"
        exit 1
    fi
    
    # Remplacer les fichiers
    sudo mcopy -D oO -i "$eltorito_img" vmlinuz-linux ::/arch/boot/x86_64/vmlinuz-linux
    sudo mcopy -D oO -i "$eltorito_img" BOOTx64.EFI BOOTIA32.EFI ::/EFI/BOOT/
    sudo mcopy -D oO -i "$eltorito_img" shellx64.efi shellia32.efi ::/
    
    # Reconstruire l'ISO
    sudo xorriso -indev "$ISO_DIR/$ARCHISO_PROFILE/out/$ISO_NAME" \
        -outdev "$ISO_DIR/$FINAL_ISO" \
        -map vmlinuz-linux /arch/boot/x86_64/vmlinuz-linux \
        -map_l ./ /EFI/BOOT/ BOOTx64.EFI BOOTIA32.EFI -- \
        -map_l ./ / shellx64.efi shellia32.efi -- \
        -boot_image any replay \
        -append_partition 2 0xef "$eltorito_img"
    
    print_success "ISO finale générée : $FINAL_ISO"
}

write_to_usb() {
    print_info "Écriture sur clé USB…"
    
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
    sudo dd if="$ISO_DIR/$FINAL_ISO" of="/dev/$device" bs=4M status=progress oflag=sync
    
    print_success "ISO écrite sur /dev/$device"
}

test_with_qemu() {
    print_info "Test avec QEMU…"
    
    local ovmf_code="/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd"
    local ovmf_vars="/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
    
    if [ ! -f "$ovmf_code" ] || [ ! -f "$ovmf_vars" ]; then
        print_error "Fichiers OVMF manquants"
        return 1
    fi
    
    local test_vars="/tmp/OVMF_VARS_test.fd"
    cp "$ovmf_vars" "$test_vars"
    
    print_info "Lancement de QEMU avec Secure Boot..."
    
    qemu-system-x86_64 \
        -m 2048 \
        -enable-kvm \
        -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
        -drive if=pflash,format=raw,file="$test_vars" \
        -drive if=ide,media=cdrom,file="$ISO_DIR/$FINAL_ISO" \
        -net nic -net user \
        -vga virtio
    
    rm -f "$test_vars"
}

main() {
    echo "=== ISO Arch Linux Secure Boot - CLÉS PERSONNALISÉES ==="
    echo ""
    
    check_dependencies
    check_secure_boot_tools
    setup_iso_environment
    build_iso
    extract_and_sign_files
    rebuild_iso
    
    echo ""
    print_success "ISO créée avec succès !"
    print_info "Fichier: $ISO_DIR/$FINAL_ISO"
    print_info "Type: Clés personnalisées (nécessite enrollment)"
    
    echo ""
    if ask_yes_no "Veux-tu écrire l'ISO sur une clé USB ?"; then
        write_to_usb
    fi
    
    if ask_yes_no "Veux-tu tester l'ISO avec QEMU ?"; then
        test_with_qemu
    fi
    
    echo ""
    print_success "Terminé !"
    echo ""
    print_info "Instructions d'installation:"
    print_info "1. Démarre sur l'ISO (Secure Boot désactivé)"
    print_info "2. Installe Arch Linux normalement"
    print_info "3. Avant de redémarrer, exécute: setup-secureboot-after-install"
    print_info "4. Redémarre et entre dans l'UEFI"
    print_info "5. Active le mode Setup (Clear Secure Boot keys)"
    print_info "6. Redémarre sur l'ISO et exécute: enroll-custom-keys"
    print_info "7. Redémarre avec Secure Boot activé"
}

# Gestion des signaux
trap 'echo ""; print_error "Interruption par l'utilisateur"; exit 1' INT TERM

if [[ $EUID -eq 0 ]]; then
    print_error "Ne pas exécuter ce script en tant que root"
    exit 1
fi

main "$@"