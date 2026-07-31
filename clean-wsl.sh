#!/usr/bin/env bash

# -------------------------------------------------------------------
# Clean‑WSL : a TUI system cleaner for Ubuntu (WSL 24/26)
# Version   : 2.1 – with previews, recommended mode, and space stats
# Author    : assistant
# Usage     : bash clean-wsl.sh   (or make executable & run)
# Dependencies: whiptail (preferred) or dialog, fallback text menu
# -------------------------------------------------------------------

set -o pipefail

# ----- colour definitions -------------------------------------------
if [[ -t 1 ]]; then
    BOLD="\e[1m" RED="\e[31m" GREEN="\e[32m" YELLOW="\e[33m" BLUE="\e[34m" RESET="\e[0m"
else
    BOLD="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

# ----- sanity checks -------------------------------------------------
if ! command -v sudo &>/dev/null; then
    echo -e "${RED}Error: 'sudo' is not installed or not in PATH.${RESET}" >&2
    exit 1
fi

if ! sudo -n true 2>/dev/null; then
    echo -e "${YELLOW}WARNING: You may be prompted for your sudo password.${RESET}"
fi

# ----- helper: run whiptail checklist, fallback to text menu -------
menu_choice() {
    local title="$1" text="$2" height="$3" width="$4" list_height="$5"
    shift 5
    local options=("$@")

    if command -v whiptail &>/dev/null; then
        whiptail --title "$title" --checklist "$text" "$height" "$width" "$list_height" "${options[@]}" 3>&1 1>&2 2>&3
    elif command -v dialog &>/dev/null; then
        dialog --title "$title" --checklist "$text" "$height" "$width" "$list_height" "${options[@]}" 3>&1 1>&2 2>&3
    else
        # ----- improved text fallback (supports toggling) -----
        echo -e "${BOLD}${title}${RESET}"
        echo "$text"
        echo
        local tags=() items=() statuses=()
        local idx=1
        while [[ $# -gt 0 ]]; do
            local tag="$1" item="$2" status="$3"
            shift 3
            tags+=("$tag")
            items+=("$item")
            statuses+=("$status")
            ((idx++))
        done

        while true; do
            echo "Current selections:"
            for i in "${!tags[@]}"; do
                local mark=" "
                [[ "${statuses[$i]}" == "ON" ]] && mark="X"
                echo "  $((i+1))) [$mark] ${items[$i]}"
            done
            echo "  0) Done"
            read -rp "Enter numbers to toggle (e.g., 1,3,5 or 1 3 5): " input

            input="${input//,/ }"
            local numbers=($input)
            if [[ " ${numbers[*]} " == *" 0 "* ]]; then
                break
            fi

            for num in "${numbers[@]}"; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#tags[@]} )); then
                    local idx=$((num-1))
                    if [[ "${statuses[$idx]}" == "ON" ]]; then
                        statuses[$idx]="OFF"
                    else
                        statuses[$idx]="ON"
                    fi
                else
                    echo -e "${YELLOW}Invalid number: $num${RESET}" >&2
                fi
            done
            echo
        done

        local selected=""
        for i in "${!tags[@]}"; do
            if [[ "${statuses[$i]}" == "ON" ]]; then
                selected+="${tags[$i]} "
            fi
        done
        echo "$selected" | xargs
    fi
}

# ----- confirmation helper ------------------------------------------
confirm() {
    local msg="$1"
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" 12 70 3>&1 1>&2 2>&3
    elif command -v dialog &>/dev/null; then
        dialog --yesno "$msg" 12 70 3>&1 1>&2 2>&3
    else
        read -rp "$msg (y/N): " yn
        [[ "$yn" =~ ^[Yy] ]]
    fi
}

# ----- helper: check if a path is "dangerous" -----------------------
is_dangerous_path() {
    local path="$1"
    local dangerous=("/" "/bin" "/boot" "/dev" "/etc" "/lib" "/lib64" "/opt" "/proc" "/root" "/sbin" "/sys" "/usr" "/var")
    for d in "${dangerous[@]}"; do
        if [[ "$(realpath "$path" 2>/dev/null)" == "$(realpath "$d" 2>/dev/null)" ]]; then
            return 0
        fi
    done
    return 1
}

# ----- functions to get sizes for preview ---------------------------
get_size_human() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sh "$path" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

get_size_bytes() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sb "$path" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# ----- cleanup functions (with preview support) ---------------------
declare -A TASK_LOCATIONS
declare -A TASK_SIZE_FUNC

# APT
clean_apt() {
    echo -e "${GREEN}Cleaning APT cache and old packages...${RESET}"
    sudo apt-get clean
    sudo apt-get autoclean
    sudo apt-get autoremove --purge -y
}
TASK_LOCATIONS["APT"]="/var/cache/apt/archives"
TASK_SIZE_FUNC["APT"]="get_size_bytes /var/cache/apt/archives"

# JOURNAL
clean_journal() {
    if command -v journalctl &>/dev/null && systemctl is-active --quiet systemd-journald 2>/dev/null; then
        echo -e "${GREEN}Rotating and vacuuming systemd journals...${RESET}"
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=3d
    else
        echo -e "${YELLOW}Systemd journal not active; skipping journal cleanup.${RESET}"
    fi
}
TASK_LOCATIONS["JOURNAL"]="systemd journals (kept last 3 days)"
TASK_SIZE_FUNC["JOURNAL"]="journalctl --disk-usage 2>/dev/null | awk '{print \$1}' || echo 0"

# TMP
clean_temp() {
    echo -e "${GREEN}Removing old temporary files...${RESET}"
    sudo find /tmp -mindepth 1 -mtime +1 -delete 2>/dev/null || true
    sudo find /var/tmp -mindepth 1 -mtime +7 -delete 2>/dev/null || true
}
TASK_LOCATIONS["TMP"]="/tmp (1d) & /var/tmp (7d)"
TASK_SIZE_FUNC["TMP"]="echo \$(( $(get_size_bytes /tmp 2>/dev/null) + $(get_size_bytes /var/tmp 2>/dev/null) ))"

# THUMBNAILS
clean_thumbnails() {
    echo -e "${GREEN}Deleting thumbnail cache...${RESET}"
    if [[ -d "${HOME}/.cache/thumbnails" ]]; then
        find "${HOME}/.cache/thumbnails" -mindepth 1 -delete 2>/dev/null || true
    fi
}
TASK_LOCATIONS["THUMBNAILS"]="${HOME}/.cache/thumbnails"
TASK_SIZE_FUNC["THUMBNAILS"]="get_size_bytes ${HOME}/.cache/thumbnails"

# PIP
clean_pip_cache() {
    if command -v pip &>/dev/null || command -v pip3 &>/dev/null; then
        echo -e "${GREEN}Purging pip cache...${RESET}"
        pip cache purge 2>/dev/null || pip3 cache purge 2>/dev/null || true
    fi
}
TASK_LOCATIONS["PIP"]="pip cache (~/.cache/pip)"
TASK_SIZE_FUNC["PIP"]="get_size_bytes ${HOME}/.cache/pip"

# NPM
clean_npm_cache() {
    if command -v npm &>/dev/null; then
        echo -e "${GREEN}Clearing npm cache...${RESET}"
        npm cache clean --force 2>/dev/null || true
    fi
}
TASK_LOCATIONS["NPM"]="npm cache (~/.npm)"
TASK_SIZE_FUNC["NPM"]="get_size_bytes ${HOME}/.npm"

# YARN
clean_yarn_cache() {
    if command -v yarn &>/dev/null; then
        echo -e "${GREEN}Clearing yarn cache...${RESET}"
        yarn cache clean 2>/dev/null || true
    fi
}
TASK_LOCATIONS["YARN"]="yarn cache (~/.cache/yarn)"
TASK_SIZE_FUNC["YARN"]="get_size_bytes ${HOME}/.cache/yarn"

# ALL_CACHE
clean_all_user_cache() {
    if [[ ! -d "${HOME}/.cache" ]]; then
        echo -e "${YELLOW}No ~/.cache directory found.${RESET}"
        return
    fi
    echo -e "${RED}WARNING: This will DELETE ALL CONTENTS of ${HOME}/.cache.${RESET}"
    echo -e "${YELLOW}This may cause loss of saved sessions, cookies, and temporary data for applications.${RESET}"
    if confirm "Are you absolutely sure you want to empty ~/.cache?"; then
        echo -e "${YELLOW}Removing all user cache files...${RESET}"
        find "${HOME}/.cache" -mindepth 1 -delete 2>/dev/null || true
    else
        echo "Skipped."
    fi
}
TASK_LOCATIONS["ALL_CACHE"]="${HOME}/.cache (all contents)"
TASK_SIZE_FUNC["ALL_CACHE"]="get_size_bytes ${HOME}/.cache"

# TRASH
clean_trash() {
    echo -e "${GREEN}Emptying user trash...${RESET}"
    if [[ -d "${HOME}/.local/share/Trash" ]]; then
        find "${HOME}/.local/share/Trash" -mindepth 1 -delete 2>/dev/null || true
    fi
}
TASK_LOCATIONS["TRASH"]="${HOME}/.local/share/Trash"
TASK_SIZE_FUNC["TRASH"]="get_size_bytes ${HOME}/.local/share/Trash"

# SNAP
clean_snap() {
    if command -v snap &>/dev/null; then
        echo -e "${GREEN}Removing old snap revisions...${RESET}"
        LANG=C snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r name rev; do
            sudo snap remove "$name" --revision="$rev" 2>/dev/null || true
        done
    else
        echo "Snap is not installed, skipping."
    fi
}
TASK_LOCATIONS["SNAP"]="old snap revisions"
TASK_SIZE_FUNC["SNAP"]="echo 'N/A (varies)'"

# DOCKER
clean_docker() {
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null; then
            echo -e "${GREEN}Pruning unused Docker objects...${RESET}"
            docker system prune -a -f
        elif sudo -n true 2>/dev/null && sudo docker info &>/dev/null; then
            echo -e "${GREEN}Pruning unused Docker objects (with sudo)...${RESET}"
            sudo docker system prune -a -f
        else
            echo -e "${YELLOW}Docker installed but not accessible; skipping.${RESET}"
        fi
    else
        echo "Docker is not installed, skipping."
    fi
}
TASK_LOCATIONS["DOCKER"]="Docker images, containers, volumes"
TASK_SIZE_FUNC["DOCKER"]="echo 'N/A (varies)'"

# NODE_MOD (interactive)
clean_node_modules() {
    local base_dir
    if command -v whiptail &>/dev/null; then
        base_dir=$(whiptail --inputbox "Enter base directory to search for node_modules:" 8 60 "$HOME" --title "Node Modules Cleanup" 3>&1 1>&2 2>&3) || return
    else
        read -rp "Base directory to search (default $HOME): " base_dir
        base_dir="${base_dir:-$HOME}"
    fi

    [[ -d "$base_dir" ]] || { echo -e "${RED}Invalid directory: $base_dir${RESET}"; return; }

    if is_dangerous_path "$base_dir"; then
        echo -e "${RED}WARNING: '$base_dir' is a system‑critical directory.${RESET}"
        if ! confirm "Are you sure you want to search for node_modules under $base_dir? This may delete system‑wide node modules!"; then
            echo "Aborted."
            return
        fi
    fi

    local count
    count=$(find "$base_dir" -name "node_modules" -type d -prune 2>/dev/null | wc -l)
    if [[ $count -eq 0 ]]; then
        echo "No node_modules directories found."
        return
    fi
    if confirm "Found $count node_modules directories. Delete them all?"; then
        find "$base_dir" -name "node_modules" -type d -prune -exec rm -rf {} + 2>/dev/null || true
        echo "Done."
    else
        echo "Skipped."
    fi
}
TASK_LOCATIONS["NODE_MOD"]="node_modules directories (interactive)"
TASK_SIZE_FUNC["NODE_MOD"]="echo 'Interactive scan'"

# EMPTY_DIR (interactive)
clean_empty_dirs() {
    local base_dir
    if command -v whiptail &>/dev/null; then
        base_dir=$(whiptail --inputbox "Enter directory to scan for empty directories:" 8 60 "$HOME" --title "Empty Directories" 3>&1 1>&2 2>&3) || return
    else
        read -rp "Directory to scan (default $HOME): " base_dir
        base_dir="${base_dir:-$HOME}"
    fi

    [[ -d "$base_dir" ]] || { echo -e "${RED}Invalid directory: $base_dir${RESET}"; return; }

    if is_dangerous_path "$base_dir"; then
        echo -e "${RED}WARNING: '$base_dir' is a system‑critical directory.${RESET}"
        if ! confirm "Are you sure you want to search for empty directories under $base_dir? This may remove important system placeholders!"; then
            echo "Aborted."
            return
        fi
    fi

    local count
    count=$(find "$base_dir" -type d -empty 2>/dev/null | wc -l)
    if [[ $count -eq 0 ]]; then
        echo "No empty directories found."
        return
    fi
    if confirm "Found $count empty directories. Delete them?"; then
        find "$base_dir" -type d -empty -delete 2>/dev/null || true
        echo "Done."
    else
        echo "Skipped."
    fi
}
TASK_LOCATIONS["EMPTY_DIR"]="empty directories (interactive)"
TASK_SIZE_FUNC["EMPTY_DIR"]="echo 'Interactive scan'"

# BROKEN_LNK (interactive)
clean_broken_links() {
    local base_dir
    if command -v whiptail &>/dev/null; then
        base_dir=$(whiptail --inputbox "Enter directory to scan for broken symlinks:" 8 60 "$HOME" --title "Broken Symlinks" 3>&1 1>&2 2>&3) || return
    else
        read -rp "Directory to scan (default $HOME): " base_dir
        base_dir="${base_dir:-$HOME}"
    fi

    [[ -d "$base_dir" ]] || { echo -e "${RED}Invalid directory: $base_dir${RESET}"; return; }

    if is_dangerous_path "$base_dir"; then
        echo -e "${RED}WARNING: '$base_dir' is a system‑critical directory.${RESET}"
        if ! confirm "Are you sure you want to search for broken symlinks under $base_dir? This may remove important system links!"; then
            echo "Aborted."
            return
        fi
    fi

    local count
    count=$(find "$base_dir" -xtype l 2>/dev/null | wc -l)
    if [[ $count -eq 0 ]]; then
        echo "No broken symlinks found."
        return
    fi
    if confirm "Found $count broken symlinks. Delete them?"; then
        find "$base_dir" -xtype l -delete 2>/dev/null || true
        echo "Done."
    else
        echo "Skipped."
    fi
}
TASK_LOCATIONS["BROKEN_LNK"]="broken symlinks (interactive)"
TASK_SIZE_FUNC["BROKEN_LNK"]="echo 'Interactive scan'"

# ----- preview functions --------------------------------------------
show_disk_usage() {
    echo -e "\n${BOLD}Current disk usage on /:${RESET}"
    df -h / | awk 'NR==1 || NR==2'
    echo
}

get_task_size() {
    local tag="$1"
    local size_cmd="${TASK_SIZE_FUNC[$tag]}"
    if [[ -z "$size_cmd" ]]; then
        echo "N/A"
        return
    fi
    # Execute the command stored (evaluate as string)
    eval "$size_cmd" 2>/dev/null || echo "0"
}

preview_tasks() {
    local tags=("$@")
    echo -e "\n${BOLD}📋 Selected tasks and what they will clean:${RESET}"
    local any_data=false
    for tag in "${tags[@]}"; do
        local location="${TASK_LOCATIONS[$tag]}"
        local size
        size=$(get_task_size "$tag")
        if [[ "$size" != "0" && "$size" != "N/A" && "$size" != "Interactive scan" ]]; then
            any_data=true
        fi
        echo -e "  ${BLUE}• $tag${RESET} → $location"
        if [[ "$size" == "Interactive scan" ]]; then
            echo "      (will scan and delete accordingly)"
        elif [[ "$size" == "N/A" ]]; then
            echo "      (size cannot be predicted)"
        else
            # Try to convert bytes to human if numeric
            if [[ "$size" =~ ^[0-9]+$ ]]; then
                local human=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "$size bytes")
                echo "      Current size: $human"
            else
                echo "      Current size: $size"
            fi
        fi
    done
    # If any_data is still false, it means all selected tasks have zero data or are interactive
    # But we treat interactive as "not clean" because they may still delete something.
    if [[ "$any_data" == "false" ]]; then
        # Check if all selected are interactive or N/A
        local all_interactive_or_na=true
        for tag in "${tags[@]}"; do
            local size
            size=$(get_task_size "$tag")
            if [[ "$size" != "Interactive scan" && "$size" != "N/A" && "$size" != "0" ]]; then
                all_interactive_or_na=false
                break
            fi
        done
        if [[ "$all_interactive_or_na" == "true" ]]; then
            echo -e "\n${YELLOW}⚠️  None of the selected tasks have any reclaimable data (or they are interactive).${RESET}"
            echo -e "${YELLOW}If you proceed, you may not free any disk space.${RESET}"
            return 1
        fi
    fi
    return 0
}

# ----- main TUI -----------------------------------------------------
main_menu() {
    # ---- choose mode: Recommended or Custom ----
    local mode
    if command -v whiptail &>/dev/null; then
        mode=$(whiptail --title "Clean‑WSL" --menu "Choose cleaning mode:" 12 50 2 \
            "Recommended" "Safe set of tasks for most users" \
            "Custom" "Select tasks manually" 3>&1 1>&2 2>&3)
    elif command -v dialog &>/dev/null; then
        mode=$(dialog --title "Clean‑WSL" --menu "Choose cleaning mode:" 12 50 2 \
            "Recommended" "Safe set of tasks for most users" \
            "Custom" "Select tasks manually" 3>&1 1>&2 2>&3)
    else
        echo "Choose mode:"
        echo "  1) Recommended (safe tasks)"
        echo "  2) Custom (select manually)"
        read -rp "Enter 1 or 2: " mode_choice
        case $mode_choice in
            1) mode="Recommended" ;;
            2) mode="Custom" ;;
            *) mode="Recommended" ;;
        esac
    fi

    local selected_tags=()
    if [[ "$mode" == "Recommended" ]]; then
        # Safe set: exclude risky ones (ALL_CACHE, NODE_MOD, EMPTY_DIR, BROKEN_LNK)
        local recommended=("APT" "JOURNAL" "TMP" "THUMBNAILS" "PIP" "NPM" "YARN" "TRASH" "SNAP" "DOCKER")
        # Filter out those not installed
        for tag in "${recommended[@]}"; do
            case $tag in
                PIP)   if ! command -v pip &>/dev/null && ! command -v pip3 &>/dev/null; then continue; fi ;;
                NPM)   if ! command -v npm &>/dev/null; then continue; fi ;;
                YARN)  if ! command -v yarn &>/dev/null; then continue; fi ;;
                SNAP)  if ! command -v snap &>/dev/null; then continue; fi ;;
                DOCKER) if ! command -v docker &>/dev/null; then continue; fi ;;
                JOURNAL) if ! command -v journalctl &>/dev/null; then continue; fi ;;
            esac
            selected_tags+=("$tag")
        done
        # If nothing is selected (e.g., none installed), fallback to APT
        if [[ ${#selected_tags[@]} -eq 0 ]]; then
            selected_tags=("APT")
        fi
        echo -e "${GREEN}Recommended tasks selected:${RESET} ${selected_tags[*]}"
        if ! confirm "Do you want to proceed with these tasks? (You can still add/remove in custom mode)"; then
            # Option to go to custom
            mode="Custom"
        fi
    fi

    if [[ "$mode" == "Custom" ]]; then
        # Show checklist
        local selected
        selected=$(menu_choice "🧹 WSL Ubuntu Cleaner" \
            "Select cleanup tasks (SPACE to toggle, ENTER to confirm):" \
            22 70 16 \
            "APT"        "APT cache, autoclean, autoremove"                    OFF \
            "JOURNAL"    "Systemd journal logs (keep last 3 days)"             OFF \
            "TMP"        "Temporary files older than 1 day (/tmp, /var/tmp)"   OFF \
            "THUMBNAILS" "Thumbnail cache (~/.cache/thumbnails)"               OFF \
            "PIP"        "Pip cache"                                           OFF \
            "NPM"        "Npm cache"                                           OFF \
            "YARN"       "Yarn cache"                                          OFF \
            "ALL_CACHE"  "⚠️  Delete ALL contents of user cache (~/.cache)"    OFF \
            "TRASH"      "Empty user trash"                                    OFF \
            "NODE_MOD"   "Find & delete node_modules (interactive)"            OFF \
            "EMPTY_DIR"  "Find & delete empty directories (interactive)"       OFF \
            "BROKEN_LNK" "Find & delete broken symlinks (interactive)"         OFF \
            "SNAP"       "Remove old snap revisions"                           OFF \
            "DOCKER"     "Docker system prune"                                 OFF \
            )
        [[ -z "$selected" ]] && { echo "Nothing selected, exiting."; exit 0; }
        selected_tags=($selected)
    fi

    # ---- Show disk usage before ----
    show_disk_usage

    # ---- Preview tasks ----
    if ! preview_tasks "${selected_tags[@]}"; then
        echo -e "\n${YELLOW}No reclaimable data found for the selected tasks.${RESET}"
        if confirm "Do you want to exit without cleaning?"; then
            echo "Exiting."
            exit 0
        else
            echo "Proceeding anyway (may still clean interactive items)."
        fi
    fi

    # ---- Final confirmation ----
    echo -e "\n${BOLD}You are about to run the following cleanup tasks:${RESET}"
    for tag in "${selected_tags[@]}"; do
        echo "  - $tag"
    done
    if ! confirm "Do you want to proceed with these cleanup tasks?"; then
        echo "Aborted by user."
        exit 0
    fi

    echo -e "\n${BOLD}Starting cleanup...${RESET}\n"

    for tag in "${selected_tags[@]}"; do
        echo -e "${BLUE}---[$tag]---${RESET}"
        case $tag in
            APT)        clean_apt ;;
            JOURNAL)    clean_journal ;;
            TMP)        clean_temp ;;
            THUMBNAILS) clean_thumbnails ;;
            PIP)        clean_pip_cache ;;
            NPM)        clean_npm_cache ;;
            YARN)       clean_yarn_cache ;;
            ALL_CACHE)  clean_all_user_cache ;;
            TRASH)      clean_trash ;;
            NODE_MOD)   clean_node_modules ;;
            EMPTY_DIR)  clean_empty_dirs ;;
            BROKEN_LNK) clean_broken_links ;;
            SNAP)       clean_snap ;;
            DOCKER)     clean_docker ;;
        esac
        echo
    done

    echo -e "${GREEN}Cleanup finished.${RESET}"
    echo -e "\n${BOLD}Disk usage after cleanup:${RESET}"
    df -h /
    echo
}

# ----- entry point ---------------------------------------------------
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
    echo -e "${GREEN}WSL environment detected.${RESET}"
else
    echo -e "${YELLOW}Note: This script is designed for WSL Ubuntu, but can run on standard Ubuntu.${RESET}"
fi

main_menu
