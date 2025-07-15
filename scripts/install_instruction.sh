print_info() { echo -e "${BLUE}==> $1${NC}"; }
print_info "Instructions d'installation:"
print_info "1. Démarre sur l'ISO (Secure Boot activé)"
print_info "2. Installe Arch Linux normalement"
    print_info "3. Récupère le PARTUUID de la partion EFI de mircosoft blkid | grep vfat prendre en photo"
    print_info "4. Lance systemctl reboot --firmware-setup et met secure boot en mode setup"
    print_info "5. Redémarre avec Secure Boot activé sur l'Iso"
    print_info "6. nmcli device wlan0 connect SSID --ask "
    print_info "7. sudo pacman -Sy --needed sbctl edk2-shell"
    print_info "8. sudo cp /usr/share/edk2-shell/x64/Shell.efi /boot/shellx64.efi"
    print_info "9. sudo sbctl create-keys"
    print_info "10. sudo sbctl enroll-keys -m pour garder les clés Microsoft"
    print_info "11. sudo sbctl sign /boot/EFI/BOOT/BOOX64.EFI"
    print_info "12. sudo sbctl sign /boot/EFI/systemd/systemd-bootx64.efi"
    print_info "13. sudo sbctl sign /boot/sellx64.efi"
    print_info "14. sudo sbctl sign /boot/vmlinuz-linux-lts" #Signature des noyaux
    print_info "15. sudo sbctl sign /boot/vmlinuz-linux-zen"
    print_info "16. Reboot sur le shell efi et récupérer l'alias ex: HD0d ou BLk7"
    print_info "Reboot après avoir trouver l'alias et créer un fichier avec ce contenue ou HD0d est l'alias
    esp/loader/entries/windows.conf
                    title   Windows
                    efi     /shellx64.efi
                    options -nointerrupt -nomap -noversion HD0d:EFI\Microsoft\Boot\Bootmgfw.efi"