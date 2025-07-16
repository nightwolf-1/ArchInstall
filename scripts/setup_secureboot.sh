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
    sudo sbctl create-keys
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

find_boot_files() {
    echo "🔎 Recherche de fichiers EFI, noyaux, initramfs et images... \n"

    local dirs=("$@")
    BOOT_FILES=()  # Variable globale nettoyée à chaque appel

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            echo "📂 Recherche dans $dir"
            mapfile -d '' -t found < <(find "$dir" -type f \( \
                -iname '*.efi' \
                -o -iname 'vmlinuz-*' \
                -o -iname 'initramfs*' \
                -o -iname 'initrd*' \
                -o -iname '*.img' \
            \) -print0)
            BOOT_FILES+=("${found[@]}")
        else
            echo "⚠️  Répertoire introuvable : $dir" >&2
        fi
    done

    if [ "${#BOOT_FILES[@]}" -eq 0 ]; then
        echo "❌ Aucun fichier trouvé."
    else
        echo "✅ Fichiers trouvés :"
        for file in "${BOOT_FILES[@]}"; do
            echo "  - $file"
        done
    fi
}


# Signature automatique des binaires EFI et noyaux
sign_boot_components() {
    echo "🔐 Signature des fichiers EFI et des noyaux..."

    boot_dirs=("/boot" "/efi" "/mnt/esp" "/EFI")
    find_boot_files "${boot_dirs[@]}"

     for file in "${BOOT_FILES[@]}"; do
        echo "📄 Signature de $file"
        udo sbctl sign "$file"
    done
}
# ---------------------
# Point d’entrée
# ---------------------
main() {
    sed -i 's/# kb_layout = us$/kb_layout = fr/' ~/.config/hpr/hyprland.conf
    connect_wifi "Livebox-8450"

    install_dependencies
    install_uefi_shell
    create_secureboot_keys
    enroll_keys_if_needed
    sign_boot_components
}

main "$@"
