log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}
log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}
log_error() {
    echo -e "${RED}❌ $1${NC}"
}
install_hyde() {
    sudo pacman -S --needed git base-devel
    cd ~/
    git clone --depth 1 https://github.com/HyDE-Project/HyDE ~/HyDE
    cd ~/HyDE/Scripts
    ./install.sh
    sed -i 's/# kb_layout = us$/kb_layout = fr/' ~/.config/hpr/userprefs.conf
    sed -i 's/ForceHideCompletePassword="false"$/ForceHideCompletePassword="true"/' /usr/share/sddm/themes/Candy/theme.conf
    sed -i 's/exec-once = uwsm app -t service -s s -- $start\.BAR || $start\.BAR # waybar\.py --watch (daemon)$/exec-once = sleep 1 \&\& (uwsm app -t service -s s -- $start.BAR || $start.BAR) # waybar.py --watch (daemon)/' ~/.local/share/hyde/hyprland.conf
    
    # Commenter tout le bloc listener qui contient systemctl suspend
    sed -i '/listener {/{
        :a
        N
        /}/!ba
        /systemctl suspend/s/^/# /mg
    }' ~/.config/hypr/hypridle.conf
    
    # Inverser format et format-alt dans clock.jsonc
    sed -i '/"format": "{:%I:%M %p}",/{
        N
        N
        s/"format": "{:%I:%M %p}",\n    "rotate": 0,\n    "format-alt": "{:%R \\udb80\\udced %d\\u00b7%m\\u00b7%y}",/"format": "{:%R \\udb80\\udced %d\\u00b7%m\\u00b7%y}",\n    "rotate": 0,\n    "format-alt": "{:%I:%M %p}",/
    }' ~/.local/share/waybar/modules/clock.jsonc
}
create_windows_config() {
    local alias_name title_name disk_path
    local config_dir="/boot/loader/entries"
    local config_file
    # Demander l'alias à l'utilisateur
    while true; do
        read -rp "Entrez l'alias pour la configuration Windows (ex: windows, win10, windows11): " alias_name
        if [[ -n "$alias_name" && "$alias_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            log_error "Alias invalide. Utilisez uniquement lettres, chiffres, tirets ou underscores."
        fi
    done
    # Convertir l'alias en Title lisible (ex: windows11 → Windows 11)
    title_name=$(echo "$alias_name" | sed -E 's/([a-zA-Z]+)([0-9]*)/\u\1 \2/')
    # Demander le chemin EFI Shell (ex: HD0d)
    while true; do
        read -rp "Entrez le chemin de démarrage EFI depuis le Shell (ex: HD0d) : " disk_path
        if [[ "$disk_path" =~ ^HD[0-9]+[a-zA-Z]?$ ]]; then
            break
        else
            log_error "Format incorrect. Exemple attendu : HD0d"
        fi
    done
    config_file="${config_dir}/${alias_name}.conf"
    # Créer le répertoire si nécessaire
    if [[ ! -d "$config_dir" ]]; then
        log_info "Création du répertoire $config_dir"
        sudo mkdir -p "$config_dir"
    fi
    # Créer le fichier de configuration
    log_info "Création du fichier de configuration $config_file"
    sudo tee "$config_file" > /dev/null << EOF
title   $title_name
efi     /shellx64.efi
options -nointerrupt -nomap -noversion ${disk_path}:EFI\\Microsoft\\Boot\\Bootmgfw.efi
EOF
    if [[ $? -eq 0 ]]; then
        log_success "Fichier de configuration créé : $config_file"
        log_info "Contenu du fichier :"
        cat "$config_file"
    else
        log_error "Erreur lors de la création du fichier"
        return 1
    fi
}
main() {
    # connect_wifi "TonSSID"   # ← décommente si besoin de Wi-Fi
   install_hyde
   create_windows_config
   yay -Sy --needed brave-browser
}
main "$@"
