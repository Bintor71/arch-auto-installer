#!/bin/bash
set -e  # Stop execution if any command fails

echo "🚀 Starting Arch Linux installation!"

# Select target disk
lsblk
read -p "Enter the target disk (e.g., /dev/sda or /dev/nvme0n1): " DISK
ROOT_PART="${DISK}1"
BOOT_PART="${DISK}2"

# Ask for username
read -p "Enter your username: " USER_NAME

# Auto-detect timezone
TIMEZONE=$(curl -s https://ipapi.co/timezone)
echo "Detected timezone: $TIMEZONE"
read -p "Do you want to use it? (Y/n): " TZ_CONFIRM
if [[ "$TZ_CONFIRM" =~ ^(n|N)$ ]]; then
    read -p "Enter your timezone (e.g., Europe/Moscow): " TIMEZONE
fi

# Select language packs
echo "Select language packs (separated by space) or enter 'all' to install all:"
echo "[1] Russian (ru_RU.UTF-8)  [2] English (en_US.UTF-8)
read -p "Enter numbers (e.g., 1 2) or 'all': " LOCALE_SELECTION

# Process selected languages
if [[ "$LOCALE_SELECTION" == "all" ]]; then
    LOCALES=("ru_RU.UTF-8" "en_US.UTF-8")
else
    LOCALES=()
    [[ "$LOCALE_SELECTION" == *"1"* ]] && LOCALES+=("ru_RU.UTF-8")
    [[ "$LOCALE_SELECTION" == *"2"* ]] && LOCALES+=("en_US.UTF-8")
fi

# Select software
echo "Select basic software (separated by space) or enter 'all' to install everything:"
echo "[1] Firefox  [2] Telegram  [3] BSPWM  [4] Picom  [5] Polybar  [6] Rofi  [7] Alacritty"
read -p "Enter numbers (e.g., 1 2 3 4) or 'all': " SOFTWARE_SELECTION

# Format partitions
mkfs.ext4 "$ROOT_PART" -F
mkfs.vfat -F32 "$BOOT_PART"

# Mount partitions
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# Install base system
pacstrap /mnt base linux linux-firmware grub efibootmgr sudo nano networkmanager

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configure the system inside chroot
arch-chroot /mnt /bin/bash <<EOF
echo "🌎 Configuring system..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configure localization
echo "🗣 Setting up language packs..."
> /etc/locale.gen
for LOCALE in ${LOCALES[@]}; do
    echo "$LOCALE UTF-8" >> /etc/locale.gen
done
locale-gen
echo "LANG=${LOCALES[0]}" > /etc/locale.conf  # Set the first selected language as default

# Configure hostname and hosts
echo "arch-pc" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 arch-pc.localdomain arch-pc" >> /etc/hosts
echo "root:root" | chpasswd

# Install bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Create user
useradd -m -G wheel -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_NAME" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install selected software
echo "📦 Installing selected software..."
SOFTWARE_LIST=""
if [[ "$SOFTWARE_SELECTION" == "all" ]]; then
    SOFTWARE_LIST="firefox telegram-desktop bspwm sxhkd picom polybar rofi alacritty"
else
    [[ "$SOFTWARE_SELECTION" == *"1"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST firefox"
    [[ "$SOFTWARE_SELECTION" == *"2"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST telegram-desktop"
    [[ "$SOFTWARE_SELECTION" == *"3"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST bspwm sxhkd"
    [[ "$SOFTWARE_SELECTION" == *"4"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST picom"
    [[ "$SOFTWARE_SELECTION" == *"5"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST polybar"
    [[ "$SOFTWARE_SELECTION" == *"6"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST rofi"
    [[ "$SOFTWARE_SELECTION" == *"7"* ]] && SOFTWARE_LIST="$SOFTWARE_LIST alacritty"
fi

pacman --noconfirm -S $SOFTWARE_LIST

EOF

# Copy user configurations
if [[ -d "/home/$USER/.config" ]]; then
    echo "📂 Copying user configurations..."
    rsync -aAXv /home/$USER/.config/ /mnt/home/$USER_NAME/.config/
    rsync -aAXv /home/$USER/.bashrc /mnt/home/$USER_NAME/.bashrc
fi

echo "✅ Installation complete! Rebooting..."
umount -R /mnt
reboot
