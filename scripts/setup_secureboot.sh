#!/usr/bin/env bash
set -euo pipefail

# Connexion Wi-Fi (si nécessaire)
connect_wifi() {
    echo "🔌 Connexion au Wi-Fi..."
    nmcli device wifi connect "$1" --ask
}

# Installation des outils requis
install_dependencies() {
    echo "📦 Installation des dépendances : sbctl, edk2-shell..."
    sudo pacman -Sy --needed --noconfirm sbctl edk2-shell
}

# Copie du shell UEFI dans /boot
install_uefi_shell() {
    echo "📁 Copie du shell UEFI dans /boot..."
    sudo cp /usr/share/edk2-shell/x64/Shell.efi /boot/shellx64.efi
}

# Création des clés Secure Boot
create_secureboot_keys() {
    sudo sbctl create-key
}

# Vérifie et enrôle les clés si nécessaire
enroll_keys_if_needed() {
    if ! sudo sbctl list-enrolled-keys | grep -q "Platform Key"; then
        echo "📥 Enrôlement des clés avec conservation des clés Microsoft..."
        sudo sbctl enroll-keys -m
    else
        echo "✅ Clés déjà enrôlées dans le firmware."
    fi
}

# Signature automatique des binaires EFI et noyaux
sign_boot_components() {
    echo "🔐 Signature des fichiers EFI et des noyaux..."

    # EFI Bootloaders communs
    efis=(
        /boot/EFI/BOOT/BOOTX64.EFI
        /boot/EFI/systemd/systemd-bootx64.efi
        /boot/shellx64.efi
    )

    for file in "${efis[@]}"; do
        if [ -f "$file" ]; then
            echo "📄 Signature de $file"
            sudo sbctl sign "$file"
        fi
    done

    # Tous les noyaux
    echo "🧠 Recherche de tous les noyaux dans /boot/"
    for kernel in /boot/vmlinuz-*; do
        [ -f "$kernel" ] || continue
        echo "📄 Signature de $kernel"
        sudo sbctl sign "$kernel"
    done
}

# ---------------------
# Point d’entrée
# ---------------------
main() {
    # connect_wifi "TonSSID"   # ← décommente si besoin de Wi-Fi

    install_dependencies
    install_uefi_shell
    create_secureboot_keys
    enroll_keys_if_needed
    sign_boot_components
}

main "$@"
