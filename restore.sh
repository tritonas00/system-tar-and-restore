#!/bin/bash

BR_VERSION="System Tar & Restore 5.1"

BR_EFI_DETECT_DIR="/sys/firmware/efi"
BR_SEP="::"

color_variables() {
  BR_NORM='\e[00m'
  BR_RED='\e[00;31m'
  BR_GREEN='\e[00;32m'
  BR_YELLOW='\e[00;33m'
  BR_MAGENTA='\e[00;35m'
  BR_CYAN='\e[00;36m'
  BR_BOLD='\033[1m'
}

BR_HIDE='\033[?25l'
BR_SHOW='\033[?25h'

info_screen() {
  echo -e "\n${BR_YELLOW}This script will restore a backup image or transfer this system in user\ndefined partitions. In the first case, you should run it from a LiveCD\nof the target (backed up) distro."
  echo -e "\n==>Make sure you have created one target root (/) partition. Optionally\n   you can create or use any other partition (/boot /home /var etc)."
  echo -e "\n==>Make sure that target LVM volume groups are activated, target RAID arrays\n   are properly assembled and target encrypted partitions are opened."
  echo -e "\n==>If you plan to transfer in lvm/mdadm/dm-crypt, make sure that\n   this system is capable to boot from those configurations."
  echo -e "\n${BR_CYAN}Press ENTER to continue.${BR_NORM}"
}

clean_files() {
  if [ -f /tmp/filelist ]; then rm /tmp/filelist; fi
  if [ -f /tmp/bl_error ]; then rm /tmp/bl_error; fi
  if [ -f /tmp/r_errs ]; then rm /tmp/r_errs; fi
 }

exit_screen() {
  if [ -f /tmp/bl_error ]; then
    echo -e "\n${BR_RED}Error installing $BRbootloader. Check /tmp/restore.log for details.\n\n${BR_CYAN}Press ENTER to unmount all remaining (engaged) devices.${BR_NORM}"
  elif [ -n "$BRbootloader" ]; then
    echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log\n\nPress ENTER to unmount all remaining (engaged) devices, then reboot your system.${BR_NORM}"
  else
    echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log"
    echo -e "\n${BR_YELLOW}You didn't choose a bootloader, so this is the right time to install and\nupdate one. To do so:"
    echo -e "\n==>For internet connection to work, on a new terminal with root\n   access enter: cp -L /etc/resolv.conf /mnt/target/etc/resolv.conf"
    echo -e "\n==>Then chroot into the target system: chroot /mnt/target"
    echo -e "\n==>Install and update a bootloader"
    echo -e "\n==>When done, leave chroot: exit"
    echo -e "\n==>Finally, return to this window and press ENTER to unmount\n   all remaining (engaged) devices.${BR_NORM}"
  fi
}

exit_screen_quiet() {
  if [ -f /tmp/bl_error ]; then
    echo -e "\n${BR_RED}Error installing $BRbootloader.\nCheck /tmp/restore.log for details.${BR_NORM}"
  else
    echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log${BR_NORM}"
  fi
}

ok_status() {
  echo -e "\r[${BR_GREEN}SUCCESS${BR_NORM}]"
  custom_ok="y"
}

error_status() {
  echo -e "\r[${BR_RED}FAILURE${BR_NORM}]\n$OUTPUT"
  BRSTOP="y"
}

item_type() {
  if [ -d "$BRpath/$f" ]; then
    echo dir
  else
    echo -
  fi
}

file_list() {
  DEFAULTIFS=$IFS
  IFS=$'\n'
  for f in $(ls --group-directories-first "$BRpath"); do echo "${f// /\\}" $(item_type); done
  IFS=$DEFAULTIFS
}

show_path() {
  if [ "$BRpath" = "/" ]; then
    BRcurrentpath="/"
  else
    BRcurrentpath="${BRpath#*/}/"
  fi
}

detect_root_fs_size() {
  BRfsystem=$(blkid -s TYPE -o value $BRroot)
  BRfsize=$(lsblk -d -n -o size 2>/dev/null $BRroot | sed -e 's/ *//')
  if [ -z "$BRfsystem" ]; then
    if [ -z "$BRnocolor" ]; then color_variables; fi
    echo -e "[${BR_RED}ERROR${BR_NORM}] Unknown root file system" >&2
    set_wrapper_error
    exit
  fi
}

detect_encryption() {
  if [ "$(file -b "$BRsource")" = "data" ]; then
    BRencmethod="openssl"
  elif file -b "$BRsource" | grep -qw GPG; then
    BRencmethod="gpg"
  else
    unset BRencmethod
  fi
}

ask_passphrase() {
  detect_encryption
  if [ -n "$BRencmethod" ] && [ -z "$BRencpass" ]; then
    if [ "$BRinterface" = "cli" ]; then
      echo -e "\n${BR_CYAN}Enter passphrase to decrypt archive${BR_NORM}"
      read -p "Passphrase: " BRencpass
    elif [ "$BRinterface" = "dialog" ]; then
      BRencpass=$(dialog --no-cancel --insecure --passwordbox "Enter passphrase to decrypt archive." 8 50 2>&1 1>&3)
    fi
  fi
}

detect_filetype() {
  echo "Checking archive type..."
  if [ -n "$BRwrap" ]; then echo "Checking archive type..." > /tmp/wr_proc; fi
  if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
    BRtype=$(openssl aes-256-cbc -d -salt -in "$BRsource" -k "$BRencpass" 2>/dev/null | file -b -)
  elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
    BRtype=$(gpg -d --batch --passphrase "$BRencpass" "$BRsource" 2>/dev/null | file -b -)
  else
    BRtype=$(file -b "$BRsource")
  fi

  if echo "$BRtype" | grep -q -w gzip; then
    BRfiletype="gzip compressed"
    BRreadopts="tfz"
    BR_MAINOPTS="xvpfz"
  elif echo "$BRtype" | grep -q -w bzip2; then
    BRfiletype="bzip2 compressed"
    BRreadopts="tfj"
    BR_MAINOPTS="xvpfj"
  elif echo "$BRtype" | grep -q -w XZ; then
    BRfiletype="xz compressed"
    BRreadopts="tfJ"
    BR_MAINOPTS="xvpfJ"
  elif echo "$BRtype" | grep -q -w POSIX; then
    BRfiletype="uncompressed"
    BRreadopts="tf"
    BR_MAINOPTS="xvpf"
  else
     BRfiletype="wrong"
  fi
}

check_wget() {
  if [ -f /tmp/wget_error ]; then
    rm /tmp/wget_error
    unset BRsource BRencpass BRusername BRpassword
    if [ "$BRinterface" = "cli" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Error downloading file. Wrong URL, wrong authentication, network is down or package wget is not installed." >&2
      if [ -n "$BRwrap" ]; then clean_unmount_in; fi
    elif [ "$BRinterface" = "dialog" ]; then
      dialog --title "Error" --msgbox "Error downloading file. Wrong URL, wrong authentication, network is down or package wget is not installed." 6 60
    fi
  else
    ask_passphrase
    detect_filetype
    if [ "$BRfiletype" = "wrong" ]; then
      unset BRsource BRencpass
      if [ "$BRinterface" = "cli" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type or wrong passphrase" >&2
        if [ -n "$BRwrap" ]; then clean_unmount_in; fi
      elif [ "$BRinterface" = "dialog" ]; then
        dialog --title "Error" --msgbox "Invalid file type or wrong passphrase." 5 42
      fi
    fi
  fi
}

detect_distro() {
  if [ "$BRmode" = "Restore" ]; then
    if grep -Fxq "etc/yum.conf" /tmp/filelist || grep -Fxq "etc/dnf/dnf.conf" /tmp/filelist; then
      BRdistro="Fedora"
      USER_OPTS+=(--selinux --acls "--xattrs-include='*'")
    elif grep -Fxq "etc/pacman.conf" /tmp/filelist; then
      BRdistro="Arch"
    elif grep -Fxq "etc/apt/sources.list" /tmp/filelist; then
      BRdistro="Debian"
    elif grep -Fxq "etc/zypp/zypp.conf" /tmp/filelist; then
      BRdistro="Suse"
    elif grep -Fxq "etc/urpmi/urpmi.cfg" /tmp/filelist; then
      BRdistro="Mandriva"
    elif grep -Fxq "etc/portage/make.conf" /tmp/filelist || grep -Fxq "etc/make.conf" /tmp/filelist; then
      BRdistro="Gentoo"
    else
      BRdistro="Unsupported"
    fi

  elif [ "$BRmode" = "Transfer" ]; then
    if [ -f /etc/yum.conf ] || [ -f /etc/dnf/dnf.conf ]; then
      BRdistro="Fedora"
    elif [ -f /etc/pacman.conf ]; then
      BRdistro="Arch"
    elif [ -f /etc/apt/sources.list ]; then
      BRdistro="Debian"
    elif [ -f /etc/zypp/zypp.conf ]; then
      BRdistro="Suse"
    elif [ -f /etc/urpmi/urpmi.cfg ]; then
      BRdistro="Mandriva"
    elif [ -f /etc/portage/make.conf ] || [ -f /etc/make.conf ]; then
      BRdistro="Gentoo"
    else
      BRdistro="Unsupported"
    fi
   fi
}

detect_bl_root() {
  if [[ "$BRroot" == *mapper* ]]; then
    echo "root=$BRroot"
  else
    echo "root=UUID=$(blkid -s UUID -o value $BRroot)"
  fi
}

detect_fstab_root() {
  if [[ "$BRroot" == *dev/md* ]]; then
    echo "$BRroot"
  else
    echo "UUID=$(blkid -s UUID -o value $BRroot)"
  fi
}

detect_partition_table_syslinux() {
  if [[ "$BRsyslinux" == *md* ]]; then
    BRsyslinuxdisk="$BRdev"
  else
    BRsyslinuxdisk="$BRsyslinux"
  fi
  if dd if="$BRsyslinuxdisk" skip=64 bs=8 count=1 2>/dev/null | grep -qw "EFI PART"; then
    BRpartitiontable="gpt"
  else
    BRpartitiontable="mbr"
  fi
}

set_syslinux_flags_and_paths() {
  if [ "$BRpartitiontable" = "gpt" ]; then
    echo "Setting legacy_boot flag on partition $BRpart of $BRdev"
    sgdisk $BRdev --attributes=$BRpart:set:2 &>> /tmp/restore.log || touch /tmp/bl_error
    BRsyslinuxmbr="gptmbr.bin"
  else
    echo "Setting boot flag on partition $BRpart of $BRdev"
    sfdisk $BRdev -A $BRpart &>> /tmp/restore.log || touch /tmp/bl_error
    BRsyslinuxmbr="mbr.bin"
  fi

  for BIN in /mnt/target/usr/lib/syslinux/$BRsyslinuxmbr \
    /mnt/target/usr/lib/syslinux/mbr/$BRsyslinuxmbr \
    /mnt/target/usr/share/syslinux/$BRsyslinuxmbr; do
    if [ -f "$BIN" ]; then
      BRsyslinuxmbrpath=$(dirname "$BIN")
    fi
  done

  for COM32 in /mnt/target/usr/lib/syslinux/menu.c32 \
    /mnt/target/usr/lib/syslinux/modules/bios/menu.c32 \
    /mnt/target/usr/share/syslinux/menu.c32; do
    if [ -f "$COM32" ]; then
      BRsyslinuxcompath=$(dirname "$COM32")
    fi
  done
}

generate_syslinux_cfg() {
  echo -e "UI menu.c32\nPROMPT 0\nMENU TITLE Boot Menu\nTIMEOUT 50"

  for FILE in /mnt/target/boot/*; do
    if file -b -k "$FILE" | grep -qw "bzImage"; then
      cn=$(echo "$FILE" | sed -n 's/[^-]*-//p')
      kn=$(basename "$FILE")

      if [ "$BRdistro" = "Arch" ]; then
        echo -e "LABEL arch\n\tMENU LABEL $BRdistro $cn\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn-$cn.img"
        echo -e "LABEL archfallback\n\tMENU LABEL $BRdistro $cn fallback\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn-$cn-fallback.img"
      elif [ "$BRdistro" = "Debian" ]; then
        echo -e "LABEL debian\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn.img-$cn"
      elif [ "$BRdistro" = "Fedora" ]; then
        echo -e "LABEL fedora\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn-$cn.img"
      elif [ "$BRdistro" = "Suse" ]; then
        echo -e "LABEL suse\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn-$cn"
      elif [ "$BRdistro" = "Mandriva" ]; then
        echo -e "LABEL suse\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn-$cn.img"
      elif [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ]; then
        echo -e "LABEL gentoo\n\tMENU LABEL $BRdistro-$kn\n\tLINUX ../$kn\n\tAPPEND $(detect_bl_root) $BR_KERNEL_OPTS\n\tINITRD ../$ipn-$cn"
      elif [ "$BRdistro" = "Gentoo" ]; then
        echo -e "LABEL gentoo\n\tMENU LABEL $BRdistro-$kn\n\tLINUX ../$kn\n\tAPPEND root=$BRroot $BR_KERNEL_OPTS"
      fi
    fi
  done
}

set_user_options() {
  IFS=$DEFAULTIFS
  for i in ${BR_USER_OPTS[@]}; do USER_OPTS+=("${i///\//\ }"); done
  IFS=$'\n'
}

run_tar() {
  IFS=$DEFAULTIFS
  if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
    openssl aes-256-cbc -d -salt -in "$BRsource" -k "$BRencpass" 2>> /tmp/restore.log | tar ${BR_MAINOPTS} - "${USER_OPTS[@]}" -C /mnt/target && (echo "System extracted successfully" >> /tmp/restore.log)
  elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
    gpg -d --batch --passphrase "$BRencpass" "$BRsource" 2>> /tmp/restore.log | tar ${BR_MAINOPTS} - "${USER_OPTS[@]}" -C /mnt/target && (echo "System extracted successfully" >> /tmp/restore.log)
  else
    tar ${BR_MAINOPTS} "$BRsource" "${USER_OPTS[@]}" -C /mnt/target && (echo "System extracted successfully" >> /tmp/restore.log)
  fi
}

set_rsync_opts() {
  if [ -z "$BRoverride" ]; then
    BR_RSYNCOPTS=(--exclude=/run/* --exclude=/dev/* --exclude=/sys/* --exclude=/tmp/* --exclude=/mnt/* --exclude=/proc/* --exclude=/media/* --exclude=/var/run/* --exclude=/var/lock/* --exclude=/home/*/.gvfs --exclude=lost+found)
  fi
  if [ "$BRhidden" = "y" ]; then
    BR_RSYNCOPTS+=(--exclude=/home/*/[^.]*)
  fi
  BR_RSYNCOPTS+=("${USER_OPTS[@]}")
}

run_calc() {
  IFS=$DEFAULTIFS
  rsync -av / /mnt/target "${BR_RSYNCOPTS[@]}" --dry-run 2>/dev/null | tee /tmp/filelist
}

run_rsync() {
  IFS=$DEFAULTIFS
  rsync -aAXv / /mnt/target "${BR_RSYNCOPTS[@]}" && (echo "System transferred successfully" >> /tmp/restore.log)
}

count_gauge() {
  while read ln; do
    b=$((b + 1))
    per=$(($b*100/$total))
    if [[ $per -gt $lastper ]] && [[ $per -le 100 ]]; then
      lastper=$per
      echo $lastper
    fi
  done
}

count_gauge_wget() {
  while read ln; do
    if [[ $ln -gt $lastln ]]; then
      lastln=$ln
      echo $lastln
    fi
  done
}

hide_used_parts() {
  grep -vw -e "/${BRroot#*/}" -e "/${BRswap#*/}" -e "/${BRhome#*/}" -e "/${BRboot#*/}" -e "/${BResp#*/}"
}

scan_parts() {
  for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f"; done | sort
  for f in $(find /dev/mapper/ -maxdepth 1 -mindepth 1 ! -name "control"); do echo "$f"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f"; done
}

scan_disks() {
  for f in /dev/[vhs]d[a-z]; do echo "$f"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f"; done
}

part_sel_dialog() {
  dialog --column-separator "|" --cancel-label Back --menu "Target $1 partition:" 0 0 0 `echo "${list[@]}"` 2>&1 1>&3
}

set_custom() {
  BRcustompartslist=$(dialog --no-cancel --inputbox "Set partitions: mountpoint=device e.g /usr=/dev/sda3 /var/cache=/dev/sda4\n\n(If you want spaces in mountpoints replace them with //)" 10 80 "$BRcustomold" 2>&1 1>&3)
  BRcustomold="$BRcustompartslist"
}

no_parts() {
  dialog --title "Error" --msgbox "No partitions left. Unset a partition and try again." 5 56
}

check_input() {
  if [ -n "$BRsource" ] && [ ! -f "$BRsource" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] File not found: $BRsource"
    BRSTOP="y"
  elif [ -n "$BRsource" ] && [ -f "$BRsource" ] && [ -z "$BRfiletype" ]; then
    detect_encryption
    detect_filetype
    if [ "$BRfiletype" = "wrong" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type or wrong passphrase"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRuri" ] && [ -n "$BRtfr" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use local file / url and transfer mode at the same time"
    BRSTOP="y"
  fi

  if [ "$BRmode" = "Transfer" ]; then
    if [ -z $(which rsync 2>/dev/null) ];then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package rsync is not installed. Install the package and re-run the script"
      BRSTOP="y"
    fi
    if [ -f /etc/portage/make.conf ] || [ -f /etc/make.conf ] && [ -z "$BRgenkernel" ] && [ -z $(which genkernel 2>/dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package genkernel is not installed. Install the package and re-run the script. (you can disable this check with -D)"
      BRSTOP="y"
    fi
    if [ -n "$BRgrub" ] && [ -z $(which grub-mkconfig 2>/dev/null) ] && [ -z $(which grub2-mkconfig 2>/dev/null) ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Grub not found. Install it and re-run the script."
        BRSTOP="y"
    elif [ -n "$BRsyslinux" ]; then
      if [ -z $(which extlinux 2>/dev/null) ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Extlinux not found. Install it and re-run the script"
        BRSTOP="y"
      fi
      if [ -z $(which syslinux 2>/dev/null) ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Syslinux not found. Install it and re-run the script"
        BRSTOP="y"
      fi
    fi
    if [ -n "$BRbootctl" ] || [ -n "$BRefistub" ] || [ -n "$BRgrub" ] && [ -d "$BR_EFI_DETECT_DIR" ] && [ -z $(which mkfs.vfat 2>/dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package dosfstools is not installed. Install the package and re-run the script"
      BRSTOP="y"
    fi
    if [ -n "$BRefistub" ] || [ -n "$BRgrub" ] && [ -d "$BR_EFI_DETECT_DIR" ] && [ -z $(which efibootmgr 2>/dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package efibootmgr is not installed. Install the package and re-run the script"
      BRSTOP="y"
    fi
    if [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DETECT_DIR" ] && [ -z $(which bootctl 2>/dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Bootctl not found"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRsyslinux" ] || [ -n "$BRgrub" ] || [ -n "$BRswap" ] || [ -n "$BRhome" ] || [ -n "$BRboot" ] || [ -n "$BRcustompartslist" ] || [ -n "$BRrootsubvolname" ] || [ -n "$BRsubvols" ] && [ -z "$BRroot" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] You must specify a target root partition."
    BRSTOP="y"
  fi

  if [ -n "$BRroot" ]; then
    for i in $(scan_parts); do if [ "$i" = "$BRroot" ]; then BRrootcheck="true"; fi; done
    if [ ! "$BRrootcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong root partition: $BRroot"
      BRSTOP="y"
    elif [ ! -z $(lsblk -d -n -o mountpoint 2>/dev/null $BRroot) ]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRroot is already mounted as $(lsblk -d -n -o mountpoint 2>/dev/null $BRroot), refusing to use it"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRswap" ]; then
    for i in $(scan_parts); do if [ "$i" = "$BRswap" ]; then BRswapcheck="true"; fi; done
    if [ ! "$BRswapcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong swap partition: $BRswap"
      BRSTOP="y"
    fi
    if [ "$BRswap" = "$BRroot" ]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRswap already used"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRcustomparts" ]; then
    BRdevused=(`for i in ${BRcustomparts[@]}; do BRdevice=$(echo $i | cut -f2 -d"=") && echo $BRdevice; done | sort | uniq -d`)
    BRmpointused=(`for i in ${BRcustomparts[@]}; do BRmpoint=$(echo $i | cut -f1 -d"=") && echo $BRmpoint; done | sort | uniq -d`)
    if [ -n "$BRdevused" ]; then
      for a in ${BRdevused[@]}; do
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $a already used"
        BRSTOP="y"
      done
    fi
    if [ -n "$BRmpointused" ]; then
      for a in ${BRmpointused[@]}; do
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Duplicate mountpoint: $a"
        BRSTOP="y"
      done
    fi

    for k in ${BRcustomparts[@]}; do
      BRmpoint=$(echo $k | cut -f1 -d"=")
      BRdevice=$(echo $k | cut -f2 -d"=")

      for i in $(scan_parts); do if [ "$i" = "$BRdevice" ]; then BRcustomcheck="true"; fi; done
      if [ ! "$BRcustomcheck" = "true" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong $BRmpoint partition: $BRdevice"
        BRSTOP="y"
      elif [ ! -z $(lsblk -d -n -o mountpoint 2>/dev/null $BRdevice) ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice is already mounted as $(lsblk -d -n -o mountpoint 2>/dev/null $BRdevice), refusing to use it"
        BRSTOP="y"
      fi
      if [ "$BRdevice" = "$BRroot" ] || [ "$BRdevice" = "$BRswap" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice already used"
        BRSTOP="y"
      fi
      if [ "$BRmpoint" = "/" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont assign root partition as custom"
        BRSTOP="y"
      fi
      if [[ ! "$BRmpoint" == /* ]]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong mountpoint syntax: $BRmpoint"
        BRSTOP="y"
      fi
      unset BRcustomcheck
    done
  fi

  if [ -n "$BRsubvols" ] && [ -z "$BRrootsubvolname" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify a root subvolume name"
    BRSTOP="y"
  fi

  if [ -n "$BRsubvols" ]; then
    BRsubvolused=(`for i in ${BRsubvols[@]}; do echo $i; done | sort | uniq -d`)
    if [ -n "$BRsubvolused" ]; then
      for a in ${BRsubvolused[@]}; do
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Duplicate subvolume: $a"
        BRSTOP="y"
      done
    fi

    for k in ${BRsubvols[@]}; do
      if [[ ! "$k" == /* ]]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong subvolume syntax: $k"
        BRSTOP="y"
      fi
      if [ "$k" = "/" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Use -R to assign root subvolume"
        BRSTOP="y"
      fi
    done
  fi

  if [ -n "$BRgrub" ] && [ ! "$BRgrub" = "auto" ]; then
    for i in $(scan_disks); do if [ "$i" = "$BRgrub" ]; then BRgrubcheck="true"; fi; done
    if [ ! "$BRgrubcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong disk for grub: $BRgrub"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRgrub" ] && [ "$BRgrub" = "auto" ] && [ ! -d "$BR_EFI_DETECT_DIR" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Use 'auto' in UEFI environment only"
    BRSTOP="y"
  fi

  if [ -n "$BRgrub" ] && [ ! "$BRgrub" = "auto" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] In UEFI environment use 'auto' for grub location"
    BRSTOP="y"
  fi

  if [ -n "$BRsyslinux" ]; then
    for i in $(scan_disks); do if [ "$i" = "$BRsyslinux" ]; then BRsyslinuxcheck="true"; fi; done
    if [ ! "$BRsyslinuxcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong disk for syslinux: $BRsyslinux"
      BRSTOP="y"
    fi
    if [ -d "$BR_EFI_DETECT_DIR" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] The script does not support Syslinux as UEFI bootloader"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRgrub" ] && [ -n "$BRsyslinux" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use multiple bootloaders"
    BRSTOP="y"
  elif [ -n "$BRgrub" ] && [ -n "$BRefistub" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use multiple bootloaders"
    BRSTOP="y"
  elif [ -n "$BRgrub" ] && [ -n "$BRbootctl" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use multiple bootloaders"
    BRSTOP="y"
  elif [ -n "$BRefistub" ] && [ -n "$BRbootctl" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use multiple bootloaders"
    BRSTOP="y"
  fi

  if [ -n "$BRinterface" ] && [ ! "$BRinterface" = "cli" ] && [ ! "$BRinterface" = "dialog" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong interface name: $BRinterface. Available options: cli dialog"
    BRSTOP="y"
  fi

  if [ ! -d "$BR_EFI_DETECT_DIR" ] && [ -n "$BResp" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use EFI system partition in bios mode"
    BRSTOP="y"
  fi

  if [ -n "$BRgrub" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DETECT_DIR" ] && [ -n "$BRroot" ] && [ -z "$BResp" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] You must specify a target EFI system partition"
    BRSTOP="y"
  fi

  if [ -n "$BRefistub" ] && [ ! -d "$BR_EFI_DETECT_DIR" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] EFISTUB is available in UEFI environment only"
    BRSTOP="y"
  fi

  if [ -n "$BRbootctl" ] && [ ! -d "$BR_EFI_DETECT_DIR" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Bootctl is available in UEFI environment only"
    BRSTOP="y"
  fi

  if [ -n "$BResp" ] && [ -z "$BRespmpoint" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify mount point for ESP ($BResp)"
    BRSTOP="y"
  elif [ -n "$BResp" ] && [ ! "$BRespmpoint" = "/boot/efi" ] && [ ! "$BRespmpoint" = "/boot" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Wrong ESP mount point: $BRespmpoint. Available options: /boot/efi /boot"
    BRSTOP="y"
  fi

  if [ -n "$BRSTOP" ]; then
    set_wrapper_error
    exit
  fi
}

mount_all() {
  if [ -n "$BRwrap" ]; then echo "Mounting..." > /tmp/wr_proc; fi
  echo -e "\n${BR_SEP}MOUNTING"
  echo -ne "${BR_WRK}Making working directory"
  OUTPUT=$(mkdir /mnt/target 2>&1) && ok_status || error_status

  echo -ne "${BR_WRK}Mounting $BRroot"
  OUTPUT=$(mount -o $BR_MOUNT_OPTS $BRroot /mnt/target 2>&1) && ok_status || error_status
  BRsizes+=(`lsblk -n -b -o size "$BRroot" 2>/dev/null`=/mnt/target)
  if [ -n "$BRSTOP" ]; then
    echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions" >&2
    clean_files
    rm -r /mnt/target
    set_wrapper_error
    exit
  fi

  if [ "$(ls -A /mnt/target | grep -vw "lost+found")" ]; then
    if [ -z "$BRdontckroot" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Root partition not empty, refusing to use it" >&2
      echo -e "[${BR_CYAN}INFO${BR_NORM}] Root partition must be formatted and cleaned" >&2
      echo -ne "${BR_WRK}Unmounting $BRroot"
      sleep 1
      OUTPUT=$(umount $BRroot 2>&1) && (ok_status && rm_work_dir) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
      set_wrapper_error
      exit
    else
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Root partition not empty"
    fi
  fi

  if [ "$BRfsystem" = "btrfs" ] && [ -n "$BRrootsubvolname" ]; then
    echo -ne "${BR_WRK}Creating $BRrootsubvolname"
    OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname 2>&1 1>/dev/null) && ok_status || error_status

    if [ -n "$BRsubvols" ]; then
      while read ln; do
        echo -ne "${BR_WRK}Creating $BRrootsubvolname$ln"
        OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname$ln 2>&1 1>/dev/null) && ok_status || error_status
      done< <(for a in "${BRsubvols[@]}"; do echo "$a"; done | sort)
    fi

    echo -ne "${BR_WRK}Unmounting $BRroot"
    OUTPUT=$(umount $BRroot 2>&1) && ok_status || error_status

    echo -ne "${BR_WRK}Mounting $BRrootsubvolname"
    OUTPUT=$(mount -t btrfs -o $BR_MOUNT_OPTS,subvol=$BRrootsubvolname $BRroot /mnt/target 2>&1) && ok_status || error_status
    if [ -n "$BRSTOP" ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while making subvolumes" >&2
      unset BRSTOP
      clean_unmount_in
    fi
  fi

  if [ -n "$BRcustomparts" ]; then
    BRsorted=(`for i in ${BRcustomparts[@]}; do echo $i; done | sort -k 1,1 -t =`)
    unset custom_ok
    for i in ${BRsorted[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRmpoint="${BRmpoint///\//\ }"
      echo -ne "${BR_WRK}Mounting $BRdevice"
      mkdir -p /mnt/target$BRmpoint
      OUTPUT=$(mount $BRdevice /mnt/target$BRmpoint 2>&1) && ok_status || error_status
      BRsizes+=(`lsblk -n -b -o size "$BRdevice" 2>/dev/null`=/mnt/target$BRmpoint)
      if [ -n "$custom_ok" ]; then
        unset custom_ok
        BRumountparts+=($BRmpoint=$BRdevice)
        if [ "$(ls -A /mnt/target$BRmpoint | grep -vw "lost+found")" ]; then
          echo -e "[${BR_CYAN}INFO${BR_NORM}] $BRmpoint partition not empty"
        fi
      fi
    done
    if [ -n "$BRSTOP" ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions" >&2
      unset BRSTOP
      clean_unmount_in
    fi
  fi
  BRmaxsize=$(for i in ${BRsizes[@]}; do echo $i; done | sort -nr -k 1,1 -t = | head -n1 | cut -f2 -d"=")
}

show_summary() {
  echo "TARGET PARTITION SCHEME:"
  BRpartitions="Partition|Mountpoint|Filesystem|Size|Options"
  BRpartitions="$BRpartitions\n$BRroot $BRmap|/|$BRfsystem|$BRfsize|$BR_MOUNT_OPTS"
  if [ -n "$BRcustomparts" ]; then
    for i in ${BRsorted[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRmpoint="${BRmpoint///\//\ }"
      BRcustomfs=$(blkid -s TYPE -o value $BRdevice)
      BRcustomsize=$(lsblk -d -n -o size 2>/dev/null $BRdevice | sed -e 's/ *//')
      BRpartitions="$BRpartitions\n$BRdevice|$BRmpoint|$BRcustomfs|$BRcustomsize"
    done
  fi
  if [ -n "$BRswap" ]; then
    BRpartitions="$BRpartitions\n$BRswap|swap"
  fi
  echo -e "$BRpartitions" | column -t -s '|'

  if [ "$BRfsystem" = "btrfs" ] && [ -n "$BRrootsubvolname" ]; then
    echo -e "\nSUBVOLUMES:"
    echo "$BRrootsubvolname"
    if [ -n "$BRsubvols" ]; then
      for k in "${BRsubvols[@]}"; do
        echo "$BRrootsubvolname$k"
      done | sort
    fi
  fi

  echo -e "\nBOOTLOADER:"
  if [ -n "$BRgrub" ]; then
    if [ -d "$BR_EFI_DETECT_DIR" ]; then
      echo "$BRbootloader ($BRgrubefiarch)"
    else
      echo "$BRbootloader (i386-pc)"
    fi
    if [[ "$BRgrub" == *md* ]]; then
      echo Locations: $(grep -w "${BRgrub##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]')
    else
      echo "Location: $BRgrub"
    fi
  elif [ -n "$BRsyslinux" ]; then
    echo "$BRbootloader ($BRpartitiontable)"
    if [[ "$BRsyslinux" == *md* ]]; then
      echo Locations: $(grep -w "${BRsyslinux##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]')
    else
      echo "Location: $BRsyslinux"
    fi
  elif [ -n "$BRefistub" ] || [ -n "$BRbootctl" ]; then
    echo "$BRbootloader"
  else
    echo "None (WARNING)"
  fi

  if [ -n "$BRbootloader" ] && [ -n "$BR_KERNEL_OPTS" ]; then
    echo "Kernel Options: $BR_KERNEL_OPTS"
  fi

  echo -e "\nPROCESS:"
  echo "Mode:     $BRmode"
  if [ -n "$BRencpass" ] && [ -n "$BRencmethod" ]; then
    enc_info="$BRencmethod encrypted"
  fi

  if [ "$BRmode" = "Restore" ]; then
    echo "Archive:  $BRfiletype $enc_info"
  elif [ "$BRmode" = "Transfer" ] && [ "$BRhidden" = "n" ]; then
    echo "Home:     Include"
  elif [ "$BRmode" = "Transfer" ] && [ "$BRhidden" = "y" ]; then
    echo "Home:     Only hidden files and folders"
  fi

  if [ "$BRdistro" = "Unsupported" ]; then
    echo "System:   $BRdistro (WARNING)"
  elif [ "$BRmode" = "Restore" ]; then
    echo "System:   $BRdistro based $target_arch"
  elif [ "$BRmode" = "Transfer" ]; then
    echo "System:   $BRdistro based $(uname -m)"
  fi

  if [ "$BRdistro" = "Gentoo" ] && [ -n "$BRgenkernel" ]; then
    echo "Info:     Skip initramfs building"
  fi

  if [ "$BRmode" = "Transfer" ] && [ -n "$BR_RSYNCOPTS" ]; then
    echo -e "\nRSYNC OPTIONS:"
    for i in "${BR_RSYNCOPTS[@]}"; do echo "$i"; done
  elif [ "$BRmode" = "Restore" ] && [ -n "$USER_OPTS" ]; then
    echo -e "\nARCHIVER OPTIONS:"
    for i in "${USER_OPTS[@]}"; do echo "$i"; done
  fi
}

prepare_chroot() {
  echo -e "\n${BR_SEP}PREPARING CHROOT ENVIRONMENT"
  echo "Binding /run"
  mount --bind /run /mnt/target/run
  echo "Binding /dev"
  mount --bind /dev /mnt/target/dev
  echo "Binding /dev/pts"
  mount --bind /dev/pts /mnt/target/dev/pts
  echo "Binding /proc"
  mount --bind /proc /mnt/target/proc
  echo "Binding /sys"
  mount --bind /sys /mnt/target/sys
  if [ -d "$BR_EFI_DETECT_DIR" ]; then
    echo "Binding /sys/firmware/efi/efivars"
    mount --bind /sys/firmware/efi/efivars /mnt/target/sys/firmware/efi/efivars
  fi
}

generate_fstab() {
  if [ "$BRfsystem" = "btrfs" ] && [ -n "$BRrootsubvolname" ] && [ ! "$BRdistro" = "Suse" ]; then
    echo -e "# $BRroot\n$(detect_fstab_root)  /  btrfs  $BR_MOUNT_OPTS,subvol=$BRrootsubvolname  0  0"
  elif [ "$BRfsystem" = "btrfs" ]; then
    echo -e "# $BRroot\n$(detect_fstab_root)  /  btrfs  $BR_MOUNT_OPTS  0  0"
  else
    echo -e "# $BRroot\n$(detect_fstab_root)  /  $BRfsystem  $BR_MOUNT_OPTS  0  1"
  fi

  if [ -n "$BRcustomparts" ]; then
    for i in ${BRsorted[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRmpoint="${BRmpoint///\//\\040}"
      BRcustomfs=$(blkid -s TYPE -o value $BRdevice)
      echo -e "\n# $BRdevice"
      if [[ "$BRdevice" == *dev/md* ]]; then
        echo "$BRdevice  $BRmpoint  $BRcustomfs  defaults  0  2"
      else
        echo "UUID=$(blkid -s UUID -o value $BRdevice)  $BRmpoint  $BRcustomfs  defaults  0  2"
      fi
    done
  fi

  if [ -n "$BRswap" ]; then
    if [[ "$BRswap" == *dev/md* ]]; then
      echo -e "\n# $BRswap\n$BRswap  none  swap  defaults  0  0"
    else
      echo -e "\n# $BRswap\nUUID=$(blkid -s UUID -o value $BRswap)  none  swap  defaults  0  0"
    fi
  fi
  echo -e "\n${BR_SEP}GENERATED FSTAB" >> /tmp/restore.log
  cat /mnt/target/etc/fstab >> /tmp/restore.log
}

build_initramfs() {
  echo -e "\n${BR_SEP}REBUILDING INITRAMFS IMAGES"
  if grep -q dev/md /mnt/target/etc/fstab || [[ "$BRmap" == *raid* ]]; then
    echo "Generating mdadm.conf..."
    if [ "$BRdistro" = "Debian" ]; then
      BR_MDADM_PATH="/mnt/target/etc/mdadm"
    else
      BR_MDADM_PATH="/mnt/target/etc"
    fi
    if [ -f "$BR_MDADM_PATH/mdadm.conf" ]; then
      mv "$BR_MDADM_PATH/mdadm.conf" "$BR_MDADM_PATH/mdadm.conf-old"
    fi
    mdadm --examine --scan > "$BR_MDADM_PATH/mdadm.conf"
    cat "$BR_MDADM_PATH/mdadm.conf"
    echo " "
  fi

  if [ -n "$BRencdev" ] && [ ! "$BRdistro" = "Arch" ] && [ ! "$BRdistro" = "Gentoo" ]; then
    if [ -f  /mnt/target/etc/crypttab ]; then
      mv /mnt/target/etc/crypttab /mnt/target/etc/crypttab-old
    fi
    echo "Generating basic crypttab..."
    echo "$crypttab_root UUID=$(blkid -s UUID -o value $BRencdev) none luks" > /mnt/target/etc/crypttab
    cat /mnt/target/etc/crypttab
    echo " "
  fi

  for FILE in /mnt/target/boot/*; do
    if file -b -k "$FILE" | grep -qw "bzImage"; then
      cn=$(echo "$FILE" | sed -n 's/[^-]*-//p')
      if [ -n "$BRwrap" ] && [ ! "$BRdistro" = "Gentoo" ] && [ ! "$BRdistro" = "Unsupported" ]; then
        echo "Building initramfs image for $cn..." > /tmp/wr_proc
      fi

      if [ "$BRdistro" = "Arch" ]; then
        chroot /mnt/target mkinitcpio -p $cn
      elif [ "$BRdistro" = "Debian" ]; then
        chroot /mnt/target update-initramfs -u -k $cn
      elif [ "$BRdistro" = "Suse" ]; then
        chroot /mnt/target mkinitrd -k vmlinuz-$cn -i $ipn-$cn
      elif [ "$BRdistro" = "Mandriva" ] || [ "$BRdistro" = "Fedora" ]; then
        chroot /mnt/target dracut -f -v /boot/$ipn-$cn.img $cn
      fi
    fi
  done

  if [ "$BRdistro" = "Gentoo" ]; then
    if [ -n "$BRgenkernel" ]; then
      echo "Skipping..."
    else
      if [ -n "$BRwrap" ]; then echo "Building initramfs images..." > /tmp/wr_proc; fi
      chroot /mnt/target genkernel --no-color --install initramfs
    fi
  fi
}

detect_initramfs_prefix() {
  if ls /mnt/target/boot/ | grep -q "initramfs-"; then
    ipn="initramfs"
  else
    ipn="initrd"
  fi
}

cp_grub_efi() {
  if [ ! -d /mnt/target$BRespmpoint/EFI/boot ]; then
    mkdir /mnt/target$BRespmpoint/EFI/boot
  fi

  BR_GRUBX64_EFI="$(find /mnt/target$BRespmpoint/EFI ! -path "*/EFI/boot/*" ! -path "*/EFI/BOOT/*" -name "grubx64.efi" 2>/dev/null)"
  BR_GRUBIA32_EFI="$(find /mnt/target$BRespmpoint/EFI ! -path "*/EFI/boot/*" ! -path "*/EFI/BOOT/*" -name "grubia32.efi" 2>/dev/null)"

  if [ -f "$BR_GRUBX64_EFI" ]; then
    echo "Copying "$BR_GRUBX64_EFI" as /mnt/target$BRespmpoint/EFI/boot/bootx64.efi..."
    cp "$BR_GRUBX64_EFI" /mnt/target$BRespmpoint/EFI/boot/bootx64.efi
  elif [ -f "$BR_GRUBIA32_EFI" ]; then
    echo "Copying "$BR_GRUBIA32_EFI" as /mnt/target$BRespmpoint/EFI/boot/bootx32.efi..."
    cp "$BR_GRUBIA32_EFI" /mnt/target$BRespmpoint/EFI/boot/bootx32.efi
  fi
}

cp_kernels() {
  for FILE in /mnt/target/boot/*; do
    if file -b -k "$FILE" | grep -qw "bzImage"; then
      echo "Copying $FILE in /mnt/target/boot/efi/"
      cp "$FILE" /mnt/target/boot/efi/
    fi
  done

  for FILE in /mnt/target/boot/*; do
    if [[ "$FILE" == *initramfs* ]] || [[ "$FILE" == *initrd* ]]; then
      echo "Copying $FILE in /mnt/target/boot/efi/"
      cp "$FILE" /mnt/target/boot/efi/
    fi
  done
}

detect_root_map() {
  if [[ "$BRroot" == *mapper* ]] && cryptsetup status "$BRroot" &>/dev/null; then
    BRencdev=$(cryptsetup status $BRroot 2>/dev/null | grep device | sed -e "s/ *device:[ \t]*//")

    if [[ "$BRencdev" == *mapper* ]] && lvdisplay "$BRencdev" &>/dev/null; then
      BRphysical=$(lvdisplay --maps $BRencdev 2>/dev/null | grep "Physical volume" | sed -e "s/ *Physical volume[ \t]*//")
      if [[ "$BRphysical" == *dev/md* ]]; then
        BRmap="luks->lvm->raid"
      else
        BRmap="luks->lvm"
      fi
    elif [[ "$BRencdev" == *dev/md* ]]; then
      BRmap="luks->raid"
    else
      BRmap="luks"
    fi

  elif [[ "$BRroot" == *mapper* ]] && lvdisplay "$BRroot" &>/dev/null; then
    BRphysical=$(lvdisplay --maps $BRroot 2>/dev/null | grep "Physical volume" | sed -e "s/ *Physical volume[ \t]*//")
    BRvgname=$(lvdisplay $BRroot 2>/dev/null | grep "VG Name" | sed -e "s/ *VG Name[ \t]*//")

    if [[ "$BRphysical" == *mapper* ]] && cryptsetup status "$BRphysical" &>/dev/null; then
      BRencdev=$(cryptsetup status $BRphysical 2>/dev/null | grep device | sed -e "s/ *device:[ \t]*//")
      if [[ "$BRencdev" == *dev/md* ]]; then
        BRmap="lvm->luks->raid"
      else
        BRmap="lvm->luks"
      fi
    elif [[ "$BRphysical" == *dev/md* ]]; then
      BRmap="lvm->raid"
    else
      BRmap="lvm"
    fi
  elif [[ "$BRroot" == *dev/md* ]]; then
    BRmap="raid"
  fi
}

set_kern_opts() {
  if [ -n "$BRsyslinux" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ]; then
    if [ "$BRdistro" = "Arch" ]; then
      BR_KERNEL_OPTS="rw ${BR_KERNEL_OPTS}"
    else
      BR_KERNEL_OPTS="ro quiet ${BR_KERNEL_OPTS}"
    fi
    if [ "$BRfsystem" = "btrfs" ] && [ -n "$BRrootsubvolname" ]; then
      BR_KERNEL_OPTS="rootflags=subvol=$BRrootsubvolname ${BR_KERNEL_OPTS}"
    fi
  elif [ -n "$BRgrub" ] && [ "$BRdistro" = "Fedora" ]; then
    BR_KERNEL_OPTS="quiet rhgb ${BR_KERNEL_OPTS}"
  fi

  if [ "$BRdistro" = "Gentoo" ] && [[ "$BRmap" == *lvm* ]]; then
    BR_KERNEL_OPTS="dolvm ${BR_KERNEL_OPTS}"
  fi
  if [ "$BRdistro" = "Gentoo" ] && [[ "$BRmap" == *raid* ]]; then
    BR_KERNEL_OPTS="domdadm ${BR_KERNEL_OPTS}"
  fi

  if [ "$BRmap" = "luks" ] || [ "$BRmap" = "luks->lvm" ] || [ "$BRmap" = "luks->raid" ] || [ "$BRmap" = "luks->lvm->raid" ]; then
    if [ -n "$BRencdev" ] && [ "$BRdistro" = "Gentoo" ]; then
      BR_KERNEL_OPTS="crypt_root=UUID=$(blkid -s UUID -o value $BRencdev) ${BR_KERNEL_OPTS}"
    elif [ -n "$BRencdev" ]; then
      BR_KERNEL_OPTS="cryptdevice=UUID=$(blkid -s UUID -o value $BRencdev):${BRroot##*/} ${BR_KERNEL_OPTS}"
      crypttab_root="${BRroot##*/}"
    fi
  elif [ "$BRmap" = "lvm->luks" ] || [ "$BRmap" = "lvm->luks->raid" ]; then
    if [ -n "$BRencdev" ] && [ "$BRdistro" = "Gentoo" ]; then
      BR_KERNEL_OPTS="crypt_root=UUID=$(blkid -s UUID -o value $BRencdev) ${BR_KERNEL_OPTS}"
    elif [ -n "$BRencdev" ]; then
      BR_KERNEL_OPTS="cryptdevice=UUID=$(blkid -s UUID -o value $BRencdev):$BRvgname ${BR_KERNEL_OPTS}"
      crypttab_root="${BRphysical##*/}"
    fi
  fi
}

install_bootloader() {
  if [ -n "$BRgrub" ]; then
    if [ -n "$BRwrap" ]; then echo "Installing Grub in $BRgrub..." > /tmp/wr_proc; fi
    echo -e "\n${BR_SEP}INSTALLING AND UPDATING GRUB2 IN $BRgrub"
    if [ -d "$BR_EFI_DETECT_DIR" ] && [ "$BRespmpoint" = "/boot" ] && [ -d /mnt/target/boot/efi ]; then
     if [ -d /mnt/target/boot/efi-old ]; then rm -r /mnt/target/boot/efi-old; fi
      mv /mnt/target/boot/efi /mnt/target/boot/efi-old
    fi

    if [[ "$BRgrub" == *md* ]]; then
      for f in `grep -w "${BRgrub##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]'`; do
        if [ "$BRdistro" = "Arch" ]; then
          chroot /mnt/target grub-install --target=i386-pc --recheck /dev/$f || touch /tmp/bl_error
        elif [ "$BRdistro" = "Debian" ]; then
          chroot /mnt/target grub-install --recheck /dev/$f || touch /tmp/bl_error
        else
          chroot /mnt/target grub2-install --recheck /dev/$f || touch /tmp/bl_error
        fi
      done
    elif [ "$BRdistro" = "Arch" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
      chroot /mnt/target grub-install --target=$BRgrubefiarch --efi-directory=$BRgrub --bootloader-id=grub --recheck || touch /tmp/bl_error
    elif [ "$BRdistro" = "Arch" ]; then
      chroot /mnt/target grub-install --target=i386-pc --recheck $BRgrub || touch /tmp/bl_error
    elif [ "$BRdistro" = "Debian" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
      chroot /mnt/target grub-install --efi-directory=$BRgrub --recheck
    elif [ "$BRdistro" = "Debian" ]; then
      chroot /mnt/target grub-install --recheck $BRgrub || touch /tmp/bl_error
    elif [ -d "$BR_EFI_DETECT_DIR" ]; then
      chroot /mnt/target grub2-install --efi-directory=$BRgrub --recheck
    else
      chroot /mnt/target grub2-install --recheck $BRgrub || touch /tmp/bl_error
    fi

    if [ ! "$BRdistro" = "Fedora" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then cp_grub_efi; fi
    if [ "$BRdistro" = "Fedora" ] && [ -d "$BR_EFI_DETECT_DIR" ] && [ "$BRespmpoint" = "/boot" ]; then cp_grub_efi; fi

    if [ -n "$BR_KERNEL_OPTS" ]; then
      if [ -f /mnt/target/etc/default/grub ]; then
        cp /mnt/target/etc/default/grub /mnt/target/etc/default/grub-old
      fi

      if grep -q "^GRUB_CMDLINE_LINUX=" /mnt/target/etc/default/grub; then
        sed -i 's\GRUB_CMDLINE_LINUX=.*\GRUB_CMDLINE_LINUX="'"$BR_KERNEL_OPTS"'"\' /mnt/target/etc/default/grub
      else
        echo GRUB_CMDLINE_LINUX='"'$BR_KERNEL_OPTS'"' >> /mnt/target/etc/default/grub
      fi

      echo -e "\nModified grub config" >> /tmp/restore.log
      cat /mnt/target/etc/default/grub >> /tmp/restore.log
      echo " " >> /tmp/restore.log
    fi

    if [ "$BRdistro" = "Gentoo" ]; then
      chroot /mnt/target grub2-mkconfig -o /boot/grub/grub.cfg
    elif [ "$BRdistro" = "Arch" ] || [ "$BRdistro" = "Debian" ]; then
      chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg
    else
      chroot /mnt/target grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

  elif [ -n "$BRsyslinux" ]; then
   if [ -n "$BRwrap" ]; then echo "Installing Syslinux in $BRsyslinux..." > /tmp/wr_proc; fi
    echo -e "\n${BR_SEP}INSTALLING AND CONFIGURING Syslinux IN $BRsyslinux"
    if [ -d /mnt/target/boot/syslinux ]; then
      mv /mnt/target/boot/syslinux/syslinux.cfg /mnt/target/boot/syslinux.cfg-old
      chattr -i /mnt/target/boot/syslinux/* 2>/dev/null
      rm -r /mnt/target/boot/syslinux/* 2>/dev/null
    else
      mkdir -p /mnt/target/boot/syslinux
    fi
    touch /mnt/target/boot/syslinux/syslinux.cfg

    if [ "$BRdistro" = "Arch" ]; then
      chroot /mnt/target syslinux-install_update -i -a -m || touch /tmp/bl_error
    else
      if [[ "$BRsyslinux" == *md* ]]; then
        chroot /mnt/target extlinux --raid -i /boot/syslinux || touch /tmp/bl_error
        for f in `grep -w "${BRsyslinux##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z][0-9]'`; do
          BRdev=`echo /dev/$f | cut -c -8`
          BRpart=`echo /dev/$f | cut -c 9-`
          detect_partition_table_syslinux
          set_syslinux_flags_and_paths
          echo "Installing $BRsyslinuxmbr in $BRdev ($BRpartitiontable)"
          dd bs=440 count=1 conv=notrunc if=$BRsyslinuxmbrpath/$BRsyslinuxmbr of=$BRdev &>> /tmp/restore.log || touch /tmp/bl_error
        done
      else
        chroot /mnt/target extlinux -i /boot/syslinux || touch /tmp/bl_error
        BRdev="$BRsyslinux"
        if [ -n "$BRboot" ]; then
          BRpart="${BRboot##*[[:alpha:]]}"
        else
          BRpart="${BRroot##*[[:alpha:]]}"
        fi
        detect_partition_table_syslinux
        set_syslinux_flags_and_paths
        echo "Installing $BRsyslinuxmbr in $BRsyslinux ($BRpartitiontable)"
        dd bs=440 count=1 conv=notrunc if=$BRsyslinuxmbrpath/$BRsyslinuxmbr of=$BRsyslinux &>> /tmp/restore.log || touch /tmp/bl_error
      fi
      echo "Copying com32 modules"
      cp "$BRsyslinuxcompath"/*.c32 /mnt/target/boot/syslinux/
    fi
    echo "Generating syslinux.cfg"
    generate_syslinux_cfg >> /mnt/target/boot/syslinux/syslinux.cfg
    echo -e "\n${BR_SEP}GENERATED SYSLINUX CONFIG" >> /tmp/restore.log
    cat /mnt/target/boot/syslinux/syslinux.cfg >> /tmp/restore.log

  elif [ -n "$BRefistub" ]; then
    if [ -n "$BRwrap" ]; then echo "Setting boot entries using efibootmgr..." > /tmp/wr_proc; fi
    echo -e "\n${BR_SEP}SETTING BOOT ENTRIES"
    if [[ "$BResp" == *mmcblk* ]]; then
      BRespdev="${BResp%[[:alpha:]]*}"
    else
      BRespdev="${BResp%%[[:digit:]]*}"
    fi
    BRespart="${BResp##*[[:alpha:]]}"

    if [ "$BRespmpoint" = "/boot/efi" ]; then cp_kernels; fi

    for FILE in /mnt/target$BRespmpoint/*; do
      if file -b -k "$FILE" | grep -qw "bzImage"; then
        cn=$(echo "$FILE" | sed -n 's/[^-]*-//p')
        kn=$(basename "$FILE")

        if [ "$BRdistro" = "Arch" ]; then
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro $cn fallback" -l /$kn -u "$(detect_bl_root) $BR_KERNEL_OPTS initrd=/$ipn-$cn-fallback.img" || touch /tmp/bl_error
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro $cn" -l /$kn -u "$(detect_bl_root) $BR_KERNEL_OPTS initrd=/$ipn-$cn.img" || touch /tmp/bl_error
        elif [ "$BRdistro" = "Debian" ]; then
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro-$cn" -l /$kn -u "$(detect_bl_root) $BR_KERNEL_OPTS initrd=/$ipn.img-$cn" || touch /tmp/bl_error
        elif [ "$BRdistro" = "Fedora" ] || [ "$BRdistro" = "Mandriva" ]; then
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro-$cn" -l /$kn -u "$(detect_bl_root) $BR_KERNEL_OPTS initrd=/$ipn-$cn.img" || touch /tmp/bl_error
        elif [ "$BRdistro" = "Suse" ]; then
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro-$cn" -l /$kn -u "$(detect_bl_root) $BR_KERNEL_OPTS initrd=/$ipn-$cn" || touch /tmp/bl_error
        elif [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ]; then
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro-$kn" -l /$kn -u "$(detect_bl_root) $BR_KERNEL_OPTS initrd=/$ipn-$cn" || touch /tmp/bl_error
        elif [ "$BRdistro" = "Gentoo" ]; then
          chroot /mnt/target efibootmgr -d $BRespdev -p $BRespart -c -L "$BRdistro-$kn" -l /$kn -u "root=$BRroot $BR_KERNEL_OPTS" || touch /tmp/bl_error
        fi
      fi
    done
    chroot /mnt/target efibootmgr -v

  elif [ -n "$BRbootctl" ]; then
    if [ -n "$BRwrap" ]; then echo "Installing Bootctl in $BRespmpoint..." > /tmp/wr_proc; fi
    echo -e "\n${BR_SEP}INSTALLING Bootctl IN $BRespmpoint"
    if [ -d /mnt/target$BRespmpoint/loader/entries ]; then
      for CONF in /mnt/target$BRespmpoint/loader/entries/*; do
        mv "$CONF" "$CONF"-old
      done
    fi
    if [ "$BRespmpoint" = "/boot/efi" ]; then cp_kernels; fi

    chroot /mnt/target bootctl --path=$BRespmpoint install || touch /tmp/bl_error

    if [ -f /mnt/target$BRespmpoint/loader/loader.conf ]; then
      mv /mnt/target$BRespmpoint/loader/loader.conf /mnt/target$BRespmpoint/loader/loader.conf-old
    fi
    echo "timeout  5" > /mnt/target$BRespmpoint/loader/loader.conf
    echo "Generating configuration entries"

    for FILE in /mnt/target$BRespmpoint/*; do
      if file -b -k "$FILE" | grep -qw "bzImage"; then
        cn=$(echo "$FILE" | sed -n 's/[^-]*-//p')
        kn=$(basename "$FILE")

        if [ "$BRdistro" = "Arch" ]; then
          echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn.img\noptions $(detect_bl_root) $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf
          echo -e "title $BRdistro $cn fallback\nlinux /$kn\ninitrd /$ipn-$cn-fallback.img\noptions $(detect_bl_root) $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn-fallback.conf
        elif [ "$BRdistro" = "Debian" ]; then
          echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn.img-$cn\noptions $(detect_bl_root) $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf
        elif [ "$BRdistro" = "Fedora" ] || [ "$BRdistro" = "Mandriva" ]; then
          echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn.img\noptions $(detect_bl_root) $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf
        elif [ "$BRdistro" = "Suse" ]; then
          echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn\noptions $(detect_bl_root) $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf
        elif [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ]; then
          echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn\noptions $(detect_bl_root) $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf
        elif [ "$BRdistro" = "Gentoo" ]; then
          echo -e "title $BRdistro $cn\nlinux /$kn\noptions root=$BRroot $BR_KERNEL_OPTS" > /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf
        fi
        echo -e "\n${BR_SEP}GENERATED $BRdistro-$cn.conf" >> /tmp/restore.log
        cat /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn.conf >> /tmp/restore.log
        if [ "$BRdistro" = "Arch" ]; then
          echo -e "\n${BR_SEP}GENERATED $BRdistro-$cn-fallback.conf" >> /tmp/restore.log
          cat /mnt/target$BRespmpoint/loader/entries/$BRdistro-$cn-fallback.conf >> /tmp/restore.log
        fi
      fi
    done
  fi
}

set_bootloader() {
  if [ -n "$BRgrub" ]; then
    BRbootloader="Grub"
  elif [ -n "$BRsyslinux" ]; then
    BRbootloader="Syslinux"
  elif [ -n "$BRefistub" ]; then
    BRbootloader="EFISTUB/efibootmgr"
  elif [ -n "$BRbootctl" ]; then
    BRbootloader="Systemd/bootctl"
  fi

  if [ -n "$BRsyslinux" ]; then
    if [[ "$BRsyslinux" == *md* ]]; then
      for f in `grep -w "${BRsyslinux##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]'`; do
        BRdev="/dev/$f"
      done
    fi
    detect_partition_table_syslinux
    if [ ! "$BRdistro" = "Arch" ] && [ "$BRpartitiontable" = "gpt" ] && [ -z $(which sgdisk 2>/dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package gptfdisk/gdisk is not installed. Install the package and re-run the script" >&2
      BRabort="y"
    elif [ "$BRdistro" = "Arch" ] && [ "$BRpartitiontable" = "gpt" ] && [ "$BRmode" = "Transfer" ] && [ -z $(which sgdisk 2>/dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package gptfdisk/gdisk is not installed. Install the package and re-run the script" >&2
      BRabort="y"
    elif [ "$BRdistro" = "Arch" ] && [ "$BRpartitiontable" = "gpt" ] && [ "$BRmode" = "Restore" ] && ! grep -Fq "bin/sgdisk" /tmp/filelist; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] sgdisk not found in the archived system" >&2
      BRabort="y"
    fi
  fi

  if [ "$BRmode" = "Restore" ]; then
    if [ -n "$BRgrub" ] && ! grep -Fq "bin/grub-mkconfig" /tmp/filelist && ! grep -Fq "bin/grub2-mkconfig" /tmp/filelist; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Grub not found in the archived system" >&2
      BRabort="y"
    elif [ -n "$BRsyslinux" ]; then
      if ! grep -Fq "bin/extlinux" /tmp/filelist; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Extlinux not found in the archived system" >&2
        BRabort="y"
      fi
      if ! grep -Fq "bin/syslinux" /tmp/filelist; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Syslinux not found in the archived system" >&2
        BRabort="y"
      fi
    fi

    if [ -n "$BRgrub" ] || [ -n "$BRefistub" ] && [ -d "$BR_EFI_DETECT_DIR" ] && ! grep -Fq "bin/efibootmgr" /tmp/filelist; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] efibootmgr not found in the archived system" >&2
      BRabort="y"
    fi
    if [ -n "$BRgrub" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DETECT_DIR" ] && ! grep -Fq "bin/mkfs.vfat" /tmp/filelist; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] dosfstools not found in the archived system" >&2
      BRabort="y"
    fi
    if [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DETECT_DIR" ] && ! grep -Fq "bin/bootctl" /tmp/filelist; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Bootctl not found in the archived system" >&2
      BRabort="y"
    fi
    if [ "$target_arch" = "x86_64" ]; then
      BRgrubefiarch="x86_64-efi"
    elif [ "$target_arch" = "i686" ]; then
      BRgrubefiarch="i386-efi"
    fi
  fi

  if [ -n "$BRgrub" ] && [ "$BRmode" = "Transfer" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
    if [ "$(uname -m)" = "x86_64" ]; then
      BRgrubefiarch="x86_64-efi"
    elif [ "$(uname -m)" = "i686" ]; then
      BRgrubefiarch="i386-efi"
    fi
  fi

  if [ -n "$BRgrub" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
    BRgrub="$BRespmpoint"
  fi

  if [ -n "$BRabort" ]; then
    clean_unmount_in
  fi
}

check_archive() {
  if [ -n "$BRhide" ]; then echo -en "${BR_SHOW}"; fi
  if [ "$BRinterface" = "cli" ]; then echo " "; fi
  if [ -f /tmp/tar_error ]; then
    rm /tmp/tar_error
    unset BRsource BRencpass
    if [ "$BRinterface" = "cli" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Error reading archive" >&2
      if [ -n "$BRwrap" ]; then clean_unmount_in; fi
    elif [ "$BRinterface" = "dialog" ]; then
      dialog --cr-wrap --title "Error" --msgbox "Error reading archive.\n\n$(cat /tmp/r_errs)" 0 0
    fi
  else
    target_arch=$(grep -F 'target_architecture.' /tmp/filelist | cut -f2 -d".")
    if [ -z "$target_arch" ]; then
      target_arch="unknown"
    fi
    if [ ! "$(uname -m)" = "$target_arch" ]; then
      unset BRsource BRencpass
      if [ "$BRinterface" = "cli" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Running and target system architecture mismatch or invalid archive" >&2
        echo -e "[${BR_CYAN}INFO${BR_NORM}] Target  system: $target_arch" >&2
        echo -e "[${BR_CYAN}INFO${BR_NORM}] Running system: $(uname -m)" >&2
        if [ -n "$BRwrap" ]; then clean_unmount_in; fi
      elif [ "$BRinterface" = "dialog" ]; then
        dialog --title "Error" --msgbox "Running and target system architecture mismatch or invalid archive.\n\nTarget  system: $target_arch\nRunning system: $(uname -m)" 8 71
      fi
    fi
  fi
}

generate_locales() {
  if [ "$BRdistro" = "Arch" ] || [ "$BRdistro" = "Debian" ] || [ "$BRdistro" = "Gentoo" ]; then
    if [ -n "$BRwrap" ]; then echo "Generating locales..." > /tmp/wr_proc; fi
    echo -e "\n${BR_SEP}GENERATING LOCALES"
    chroot /mnt/target locale-gen
  fi
}

rm_work_dir() {
  sleep 1
  rm -r /mnt/target
}

clean_unmount_in() {
  if [ -n "$BRwrap" ]; then echo "Unmounting..." > /tmp/wr_proc; fi
  if [ -z "$BRnocolor" ]; then color_variables; fi
  echo -e "\n${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  rm "$BRmaxsize/downloaded_backup" 2>/dev/null
  if [ -n "$BRcustomparts" ]; then
    while read ln; do
      sleep 1
      echo -ne "${BR_WRK}Unmounting $ln"
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done < <(for i in ${BRumountparts[@]}; do BRdevice=$(echo $i | cut -f2 -d"="); echo $BRdevice; done | tac)
  fi

  if [ "$BRfsystem" = "btrfs" ] && [ -n "$BRrootsubvolname" ]; then
    echo -ne "${BR_WRK}Unmounting $BRrootsubvolname"
    OUTPUT=$(umount $BRroot 2>&1) && ok_status || error_status
    sleep 1
    echo -ne "${BR_WRK}Mounting $BRroot"
    OUTPUT=$(mount $BRroot /mnt/target 2>&1) && ok_status || error_status

    if [ -n "$BRsubvols" ]; then
      while read ln; do
        sleep 1
        echo -ne "${BR_WRK}Deleting $BRrootsubvolname$ln"
        OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname$ln 2>&1 1>/dev/null) && ok_status || error_status
      done < <(for i in ${BRsubvols[@]}; do echo $i; done | sort -r)
    fi

    echo -ne "${BR_WRK}Deleting $BRrootsubvolname"
    OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname 2>&1 1>/dev/null) && ok_status || error_status
  fi

  if [ -z "$BRSTOP" ]; then
    if [ -z "$BRdontckroot" ]; then
      rm -r /mnt/target/* 2>/dev/null
    fi
  fi
  clean_files

  echo -ne "${BR_WRK}Unmounting $BRroot"
  sleep 1
  OUTPUT=$(umount $BRroot 2>&1) && (ok_status && rm_work_dir) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
  set_wrapper_error
  exit
}

clean_unmount_out() {
  if [ -n "$BRwrap" ]; then echo "Unmounting..." > /tmp/wr_proc; fi
  if [ -z "$BRnocolor" ]; then color_variables; fi
  echo -e "\n${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  rm "$BRmaxsize/downloaded_backup" 2>/dev/null
  umount /mnt/target/dev/pts
  umount /mnt/target/proc
  umount /mnt/target/dev
  if [ -d "$BR_EFI_DETECT_DIR" ]; then
    umount /mnt/target/sys/firmware/efi/efivars
  fi
  umount /mnt/target/sys
  umount /mnt/target/run

  if [ -n "$BRcustomparts" ]; then
    while read ln; do
      sleep 1
      echo -ne "${BR_WRK}Unmounting $ln"
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done < <(for i in ${BRsorted[@]}; do BRdevice=$(echo $i | cut -f2 -d"="); echo $BRdevice; done | tac)
  fi

  echo -ne "${BR_WRK}Unmounting $BRroot"
  if [ -f /mnt/target/target_architecture.$(uname -m) ]; then rm /mnt/target/target_architecture.$(uname -m); fi
  sleep 1
  OUTPUT=$(umount $BRroot 2>&1) && (ok_status && rm_work_dir) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")

  if [ -f /tmp/bl_error ]; then set_wrapper_error; fi
  if [ -n "$BRwrap" ]; then cat /tmp/restore.log > /tmp/wr_log; fi
  clean_files
  exit
}

unset_vars() {
  if [ "$BResp" = "-1" ]; then unset BResp; fi
  if [ "$BRswap" = "-1" ]; then unset BRswap; fi
  if [ "$BRboot" = "-1" ]; then unset BRboot; fi
  if [ "$BRhome" = "-1" ]; then unset BRhome; fi
  if [ "$BRgrub" = "-1" ]; then unset BRgrub; fi
  if [ "$BRsyslinux" = "-1" ]; then unset BRsyslinux; fi
  if [ "$BRefistub" = "-1" ]; then unset BRefistub; fi
  if [ "$BRbootctl" = "-1" ]; then unset BRbootctl; fi
  if [ "$BRsubvols" = "-1" ]; then unset BRsubvols; fi
  if [ "$BRrootsubvolname" = "-1" ]; then unset BRrootsubvolname; fi
  if [ "$BR_USER_OPTS" = "-1" ]; then unset BR_USER_OPTS; fi
}

tar_pgrs_cli() {
  lastper=-1
  while read ln; do
    a=$((a + 1))
    per=$(($a*100/$total))
    if [ -n "$BRverb" ] && [[ $per -le 100 ]]; then
      echo -e "${BR_YELLOW}[$per%] ${BR_GREEN}$ln${BR_NORM}"
    elif [[ $per -gt $lastper ]] && [[ $per -le 100 ]]; then
      lastper=$per
      if [ -n "$BRwrap" ]; then
        echo "Extracting $total Files: $per%" > /tmp/wr_proc
      else
        echo -ne "\rExtracting: [${pstr:0:$(($a*24/$total))}${dstr:0:24-$(($a*24/$total))}] $per%"
      fi
    fi
  done
}

rsync_pgrs_cli() {
  lastper=-1
  while read ln; do
    b=$((b + 1))
    per=$(($b*100/$total))
    if [ -n "$BRverb" ] && [[ $per -le 100 ]]; then
      echo -e "${BR_YELLOW}[$per%] ${BR_GREEN}$ln${BR_NORM}"
    elif [[ $per -gt $lastper ]] && [[ $per -le 100 ]]; then
      lastper=$per
      if [ -n "$BRwrap" ]; then
        echo "Transferring $total Files: $per%" > /tmp/wr_proc
      else
        echo -ne "\rTransferring: [${pstr:0:$(($b*24/$total))}${dstr:0:24-$(($b*24/$total))}] $per%"
      fi
    fi
  done
}

options_info() {
  if [ "$BRmode" = "Restore" ]; then
    BRoptinfo="see tar --help"
    BRtbr="tar"
  elif [ "$BRmode" = "Transfer" ]; then
    BRoptinfo="see rsync --help"
    BRtbr="rsync"
  fi
}

read_archive() {
  if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
    openssl aes-256-cbc -d -salt -in "$BRsource" -k "$BRencpass" 2>/dev/null | tar "$BRreadopts" - "${USER_OPTS[@]}" || touch /tmp/tar_error
  elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
    gpg -d --batch --passphrase "$BRencpass" "$BRsource" 2>/dev/null | tar "$BRreadopts" - "${USER_OPTS[@]}" || touch /tmp/tar_error
  else
    tar tf "$BRsource" "${USER_OPTS[@]}" || touch /tmp/tar_error
  fi
}

run_wget() {
  if [ -n "$BRusername" ] || [ -n "$BRpassword" ]; then
    wget --user="$BRusername" --password="$BRpassword" -O "$BRsource" "$BRurl" --tries=2 || touch /tmp/wget_error
  else
    wget -O "$BRsource" "$BRurl" --tries=2 || touch /tmp/wget_error
  fi
}

start_log() {
  echo -e "====================$BR_VERSION {$(date +%Y-%m-%d-%T)}====================\n"
  echo "${BR_SEP}SUMMARY"
  show_summary
  echo -e "\n${BR_SEP}TAR/RSYNC STATUS"
}

set_wrapper_error() {
  if [ -n "$BRwrap" ]; then
    echo false > /tmp/wr_proc
  fi
}

BRargs=`getopt -o "i:r:e:l:s:b:h:g:S:f:n:p:R:qtou:Nm:k:c:O:vdDHP:BxwEL" -l "interface:,root:,esp:,esp-mpoint:,swap:,boot:,home:,grub:,syslinux:,file:,username:,password:,help,quiet,rootsubvolname:,transfer,only-hidden,user-options:,no-color,mount-options:,kernel-options:,custom-partitions:,other-subvolumes:,verbose,dont-check-root,disable-genkernel,hide-cursor,passphrase:,bios,override,wrapper,efistub,bootctl" -n "$1" -- "$@"`

if [ "$?" -ne "0" ];
then
  echo "See $0 --help"
  exit
fi

eval set -- "$BRargs";

while true; do
  case "$1" in
    -i|--interface)
      BRinterface=$2
      shift 2
    ;;
    -r|--root)
      BRroot=$2
      shift 2
    ;;
    -e|--esp)
      BResp=$2
      shift 2
    ;;
    -l|--esp-mpoint)
      BRespmpoint=$2
      shift 2
    ;;
    -s|--swap)
      BRswap=$2
      shift 2
    ;;
    -b|--boot)
      BRboot=$2
      shift 2
    ;;
    -h|--home)
      BRhome=$2
      shift 2
    ;;
    -g|--grub)
      BRgrub=$2
      shift 2
    ;;
    -S|--syslinux)
      BRsyslinux=$2
      shift 2
    ;;
    -f|--file)
      BRmode="Restore"
      BRuri=$2
      shift 2
    ;;
    -n|--username)
      BRusername=$2
      shift 2
    ;;
    -p|--password)
      BRpassword=$2
      shift 2
    ;;
    -q|--quiet)
      BRcontinue="y"
      BRedit="n"
      BRquiet="y"
      shift
    ;;
    -R|--rootsubvolname)
      BRrootsubvolname=$2
      shift 2
    ;;
    -t|--transfer)
      BRmode="Transfer"
      BRtfr="y"
      shift
    ;;
    -o|--only-hidden)
      BRhidden="y"
      shift
    ;;
    -u|--user-options)
      BR_USER_OPTS=$2
      shift 2
    ;;
    -N|--no-color)
      BRnocolor="y"
      shift
    ;;
    -m|--mount-options)
      BR_MOUNT_OPTS=$2
      shift 2
    ;;
    -k|--kernel-options)
      BR_KERNEL_OPTS=$2
      shift 2
    ;;
    -c|--custom-partitions)
      BRcustompartslist=$2
      BRcustomparts=($2)
      shift 2
    ;;
    -O|--other-subvolumes)
      BRsubvols=($2)
      shift 2
    ;;
    -v|--verbose)
      BRverb="y"
      shift
    ;;
    -d|--dont-check-root)
      BRdontckroot="y"
      shift
    ;;
    -D|--disable-genkernel)
      BRgenkernel="n"
      shift
    ;;
    -H|--hide-cursor)
      BRhide="y"
      shift
    ;;
    -P|--passphrase)
      BRencpass=$2
      shift 2
    ;;
    -B|--bios)
      unset BR_EFI_DETECT_DIR
      shift
    ;;
    -x|--override)
      BRoverride="y"
      shift
    ;;
    -w|--wrapper)
      BRwrap="y"
      shift
    ;;
    -E|--efistub)
      BRefistub="y"
      shift
    ;;
    -L|--bootctl)
      BRbootctl="y"
      shift
    ;;
    --help)
    echo -e "$BR_VERSION\nUsage: restore.sh [options]
\nGeneral:
  -i,  --interface          interface to use: cli dialog
  -N,  --no-color           disable colors
  -q,  --quiet              dont ask, just run
  -v,  --verbose            enable verbose tar/rsync output (cli interface only)
  -u,  --user-options       additional tar/rsync options (see tar --help or rsync --help)
  -H,  --hide-cursor        hide cursor when running tar/rsync (useful for some terminal emulators)
\nRestore Mode:
  -f,  --file               backup file path or url
  -n,  --username           ftp/http username
  -p,  --password           ftp/http password
  -P,  --passphrase         passphrase for decryption
\nTransfer Mode:
  -t,  --transfer           activate transfer mode
  -o,  --only-hidden        transfer /home's hidden files and folders only
  -x,  --override           override the default rsync options with user options (use with -u)
\nPartitions:
  -r,  --root               target root partition
  -e,  --esp                target EFI system partition
  -l,  --esp-mpoint         mount point for ESP: /boot/efi /boot
  -b,  --boot               target /boot partition
  -h,  --home               target /home partition
  -s,  --swap               swap partition
  -c,  --custom-partitions  specify custom partitions (mountpoint=device e.g /var=/dev/sda3)
  -m,  --mount-options      comma-separated list of mount options (root partition only)
  -d,  --dont-check-root    dont check if root partition is empty (dangerous)
\nBootloaders:
  -g,  --grub               target disk for grub
  -S,  --syslinux           target disk for syslinux
  -E,  --efistub            enable EFISTUB/efibootmgr
  -L,  --bootctl            enable Systemd/bootctl
  -k,  --kernel-options     additional kernel options
\nBtrfs Subvolumes:
  -R,  --rootsubvolname     subvolume name for /
  -O,  --other-subvolumes   specify other subvolumes (subvolume path e.g /home /var /usr ...)
\nMisc Options:
  -D,  --disable-genkernel  disable genkernel check and initramfs building in gentoo
  -B,  --bios               ignore UEFI environment
  -w,  --wrapper            make the script wrapper-friendly (cli interface only)
       --help               print this page"
      exit
      shift
    ;;
    --)
      shift
      break
    ;;
  esac
done

if [ -n "$BRwrap" ]; then
  echo $$ > /tmp/wr_pid
fi

if [[ "$BRuri" == /* ]]; then
  BRsource="$BRuri"
else
  BRurl="$BRuri"
fi

if [ -z "$BRnocolor" ]; then
  color_variables
fi

BR_WRK="[${BR_CYAN}WORKING${BR_NORM}] "
DEFAULTIFS=$IFS
IFS=$'\n'

if [ -n "$BResp" ] && [ -n "$BRespmpoint" ]; then
  BRcustomparts+=("$BRespmpoint"="$BResp")
fi

if [ -n "$BRhome" ]; then
  BRcustomparts+=(/home="$BRhome")
fi

if [ -n "$BRboot" ]; then
  BRcustomparts+=(/boot="$BRboot")
fi

check_input >&2

if [ -n "$BRroot" ]; then
  if [ -z "$BRrootsubvolname" ]; then
    BRrootsubvolname="-1"
  fi

  if [ -z "$BResp" ]; then
    BResp="-1"
  fi

  if [ -z "$BRcustompartslist" ]; then
    BRcustompartslist="-1"
  fi

  if [ -z "$BR_MOUNT_OPTS" ]; then
    BR_MOUNT_OPTS="defaults,noatime"
  fi

  if [ -z "$BR_USER_OPTS" ]; then
    BR_USER_OPTS="-1"
  fi

  if [ -z "$BRswap" ]; then
    BRswap="-1"
  fi

  if [ -z "$BRboot" ]; then
    BRboot="-1"
  fi

  if [ -z "$BRhome" ]; then
    BRhome="-1"
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -z "$BRefistub" ] && [ -z "$BRbootctl" ]; then
    BRgrub="-1"
    BRsyslinux="-1"
    BRefistub="-1"
    BRbootctl="-1"
  fi

  if [ -z "$BRuri" ] && [ ! "$BRmode" = "Transfer" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify a backup file or enable transfer mode" >&2
    set_wrapper_error
    exit
  fi
fi

if [ "$BRmode" = "Transfer" ] && [ -z "$BRhidden" ]; then
  BRhidden="n"
fi

if [ -n "$BRrootsubvolname" ] && [ -z "$BRsubvols" ]; then
  BRsubvols="-1"
fi

if [ $(id -u) -gt 0 ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Script must run as root" >&2
  set_wrapper_error
  exit
fi

if [ -z "$(scan_parts 2>/dev/null)" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] No partitions found" >&2
  set_wrapper_error
  exit
fi

if [ -d /mnt/target ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] /mnt/target exists, aborting" >&2
  set_wrapper_error
  exit
fi

clean_files

PATH="$PATH:/usr/sbin:/bin:/sbin"
PS3="Enter number or Q to quit: "

echo -e "\n${BR_BOLD}$BR_VERSION${BR_NORM}"

if [ -d "$BR_EFI_DETECT_DIR" ]; then
  echo -e "[${BR_CYAN}INFO${BR_NORM}] UEFI environment detected. (use -B to ignore)"
fi

if [ -z "$BRinterface" ]; then
  echo -e "\n${BR_CYAN}Select interface:${BR_NORM}"
  select c in "CLI" "Dialog"; do
    if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
      echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
      exit
    elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
      BRinterface="cli"
      break
    elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
      BRinterface="dialog"
      break
    else
      echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
    fi
  done
fi

if [ "$BRinterface" = "cli" ]; then
  pstr="########################"
  dstr="------------------------"

  if [ ! "$BRmode" = "Transfer" ] && [ -z "$BRuri" ]; then
    info_screen; read -s
  fi

  echo "Probing hardware..."
  partition_list=(`for i in $(scan_parts); do echo "$i $(lsblk -d -n -o size $i) $(blkid -s TYPE -o value $i)"; done`)
  disk_list=(`for i in $(scan_disks); do echo "$i $(lsblk -d -n -o size $i)"; done`)
  list=(`echo "${partition_list[*]}" | hide_used_parts | column -t`)
  COLUMNS=1

  if [ -z "$BRroot" ]; then
    echo -e "\n${BR_CYAN}Select target root partition:${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRroot=$(echo $c | awk '{ print $1 }')
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ -z "$BR_MOUNT_OPTS" ]; then
    echo -e "\n${BR_CYAN}Enter alternative mount options\n${BR_MAGENTA}(Leave blank for: <defaults,noatime>)${BR_NORM}"
    read -p "Options (comma-separated list): " BR_MOUNT_OPTS
    if [ -z "$BR_MOUNT_OPTS" ]; then
      BR_MOUNT_OPTS="defaults,noatime"
    fi
  fi

  detect_root_fs_size

  if [ -n "$BRrootsubvolname" ] && [ ! "$BRrootsubvolname" = "-1" ] && [ ! "$BRfsystem" = "btrfs" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Not a btrfs root filesystem, proceeding without subvolumes..."
  fi

  if [ "$BRfsystem" = "btrfs" ]; then
    if [ -z "$BRrootsubvolname" ]; then
      echo -e "\n${BR_CYAN}Set btrfs root subvolume name\n${BR_MAGENTA}(Leave blank for no subvolumes)${BR_NORM}"
      read -p "Name: " BRrootsubvolname
    fi

    if [ -n "$BRrootsubvolname" ] && [ -z "$BRsubvols" ]; then
      echo -e "\n${BR_CYAN}Set other subvolumes\n${BR_MAGENTA}(Leave blank for none)${BR_NORM}"
      read -p "Paths (e.g /home /var /usr ...): " BRsubvolslist
      if [ -n "$BRsubvolslist" ]; then
        IFS=$DEFAULTIFS
        BRsubvols+=($BRsubvolslist)
        IFS=$'\n'
      fi
    fi
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts | column -t`)

  if [ -d "$BR_EFI_DETECT_DIR" ] && [ -z "$BResp" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select target EFI system partition:\n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BResp=$(echo $c | awk '{ print $1 }')
        echo -e "\n${BR_CYAN}Mount it as:${BR_NORM}"
        select c in "/boot/efi (Suitable for Grub)" "/boot     (Suitable for EFISTUB/Bootctl)"; do
          if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
            echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
            exit
          elif [ "$REPLY" = "1" ] || [ "$REPLY" = "2" ]; then
            BRespmpoint=$(echo $c | awk '{ print $1 }')
            BRcustomparts+=("$BRespmpoint"="$BResp")
            if [ "$BRespmpoint" = "/boot" ]; then BRboot="-1"; fi
            break
          else
            echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
          fi
        done
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "\n[${BR_YELLOW}WARNING${BR_NORM}] Since you didn't choose ESP, bootloaders will be disabled"
        BRgrub="-1"
        BRefistub="-1"
        BRbootctl="-1"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts | column -t`)

  if [ -z "$BRboot" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select target /boot partition:\n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRboot=$(echo $c | awk '{ print $1 }')
        BRcustomparts+=(/boot="$BRboot")
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts | column -t`)

  if [ -z "$BRhome" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select target /home partition:\n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRhome=$(echo $c | awk '{ print $1 }')
        BRcustomparts+=(/home="$BRhome")
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts | column -t`)

  if [ -z "$BRswap" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select swap partition:\n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRswap=$(echo $c | awk '{ print $1 }')
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts | column -t`)

  if [ -z "$BRcustompartslist" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Specify custom partitions: mountpoint=device e.g /var=/dev/sda3\n${BR_MAGENTA}(If you want spaces in mountpoints replace them with //)\n(Leave blank for none)${BR_NORM}"
    read -p "Partitions: " BRcustompartslist
    if [ -n "$BRcustompartslist" ]; then
      IFS=$DEFAULTIFS
      BRcustomparts+=($BRcustompartslist)
      IFS=$'\n'
    fi
  fi

  if [ -d "$BR_EFI_DETECT_DIR" ]; then
    bootloader_list=(Grub "EFISTUB/efibootmgr" "Systemd/bootctl")
  else
    bootloader_list=(Grub Syslinux)
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -z "$BRefistub" ] && [ -z "$BRbootctl" ]; then
    echo -e "\n${BR_CYAN}Select bootloader:\n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${bootloader_list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
       	exit
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "\n[${BR_YELLOW}WARNING${BR_NORM}] NO BOOTLOADER SELECTED"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ] && [ "$REPLY" -le ${#bootloader_list[@]} ]; then
        if [ -d "$BR_EFI_DETECT_DIR" ]; then
          BRgrub="auto"
        else
          echo -e "\n${BR_CYAN}Select target disk for Grub:${BR_NORM}"
	  select c in $(echo "${disk_list[*]}" | column -t); do
	    if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
              echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
	      exit
	    elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#disk_list[@]} ]; then
	      BRgrub=$(echo $c | awk '{ print $1 }')
	      break
	    else
              echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
	    fi
          done
          fi
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ] && [ "$REPLY" -le ${#bootloader_list[@]} ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
        BRefistub="y"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 3 ] && [ "$REPLY" -le ${#bootloader_list[@]} ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
        BRbootctl="y"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ] && [ "$REPLY" -le ${#bootloader_list[@]} ]; then
        echo -e "\n${BR_CYAN}Select target disk Syslinux:${BR_NORM}"
	select c in $(echo "${disk_list[*]}" | column -t); do
	  if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
            echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
	    exit
	  elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#disk_list[@]} ]; then
	    BRsyslinux=$(echo $c | awk '{ print $1 }')
            break
	  else
            echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
	  fi
        done
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
    if [ -n "$BRgrub" ] || [ -n "$BRsyslinux" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -z "$BR_KERNEL_OPTS" ]; then
      echo -e "\n${BR_CYAN}Enter additional kernel options\n${BR_MAGENTA}(Leave blank for defaults)${BR_NORM}"
      read -p "Options: " BR_KERNEL_OPTS
    fi
  fi

  if [ -z "$BRmode" ]; then
    echo -e "\n${BR_CYAN}Select Mode:${BR_NORM}"
    select c in "Restore system from backup file" "Transfer this system with rsync"; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        BRmode="Restore"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        BRmode="Transfer"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ "$BRmode" = "Transfer" ]; then
    while [ -z "$BRhidden" ]; do
      echo -e "\n${BR_CYAN}Transfer entire /home directory?\n${BR_MAGENTA}(If no, only hidden files and folders will be transferred)${BR_NORM}"
      read -p "(Y/n):" an

      if [ -n "$an" ]; then def=$an; else def="y"; fi

      if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
        BRhidden="n"
      elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
        BRhidden="y"
      else
        echo -e "${BR_RED}Please select a valid option${BR_NORM}"
      fi
    done
  fi

  options_info

  if [ -z "$BR_USER_OPTS" ]; then
    echo -e "\n${BR_CYAN}Enter additional $BRtbr options\n${BR_MAGENTA}(If you want spaces in names replace them with //)\n(Leave blank for defaults)${BR_NORM}"
    read -p "Options ($BRoptinfo): " BR_USER_OPTS
  fi

  unset_vars
  check_input >&2
  mount_all
  set_user_options

  if [ "$BRmode" = "Restore" ]; then
    echo -e "\n${BR_SEP}GETTING TAR IMAGE"

    if [ -n "$BRurl" ]; then
      BRsource="$BRmaxsize/downloaded_backup"
      if [ -n "$BRwrap" ]; then
        run_wget 2>&1 | while read ln; do if [ -n "$ln" ]; then echo "Downloading: ${ln//.....}" > /tmp/wr_proc; fi; done
      else
        run_wget
      fi
      check_wget
    fi

    if [ -n "$BRsource" ]; then
      IFS=$DEFAULTIFS
      if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
      if [ -n "$BRwrap" ]; then echo "Please wait while checking and reading archive..." > /tmp/wr_proc; fi
      read_archive | tee /tmp/filelist | while read ln; do a=$((a + 1)) && echo -en "\rChecking and reading archive ($a Files) "; done

      IFS=$'\n'
      check_archive
    fi

    while [ -z "$BRsource" ]; do
      echo -e "\n${BR_CYAN}Select backup file. Choose an option:${BR_NORM}"
      select c in "Local File" "URL" "Protected URL"; do
        if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
          echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
          clean_unmount_in
        elif [ "$REPLY" = "1" ]; then
          unset BRurl
          echo -e "\n${BR_CYAN}Enter the path of the backup file${BR_NORM}"
          IFS=$DEFAULTIFS
          read -e -p "Path: " BRsource
          IFS=$'\n'
          if [ ! -f "$BRsource" ]; then
            echo -e "[${BR_RED}ERROR${BR_NORM}] File not found"
            unset BRsource
          else
            ask_passphrase
            detect_filetype
            if [ "$BRfiletype" = "wrong" ]; then
              unset BRsource BRencpass
              echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type or wrong passphrase"
            fi
	  fi
          break

        elif [ "$REPLY" = "2" ] || [ "$REPLY" = "3" ]; then
          echo -e "\n${BR_CYAN}Enter the URL for the backup file${BR_NORM}"
          read -p "URL: " BRurl
          BRsource="$BRmaxsize/downloaded_backup"
          echo " "
          if [ "$REPLY" = "3" ]; then
	    read -p "USERNAME: " BRusername
            read -p "PASSWORD: " BRpassword
          fi
	  run_wget
          check_wget
          break
        else
          echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
        fi
      done

      if [ -n "$BRsource" ]; then
        IFS=$DEFAULTIFS
        if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
        read_archive | tee /tmp/filelist | while read ln; do a=$((a + 1)) && echo -en "\rChecking and reading archive ($a Files) "; done
        IFS=$'\n'
        check_archive
      fi
    done
  fi

  detect_distro
  set_bootloader

  if [ "$BRmode" = "Restore" ] && [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ] && ! grep -Fq "bin/genkernel" /tmp/filelist; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Genkernel not found in the archived system. (you can disable this check with -D)" >&2
    if [ -n "$BRwrap" ]; then clean_unmount_in; fi
    while [ -z "$BRgenkernel" ]; do
      echo -e "\n${BR_CYAN}Disable initramfs building?${BR_NORM}"
      read -p "(Y/n, abort):" an

      if [ -n "$an" ]; then def=$an; else def="y"; fi

      if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
        BRgenkernel="n"
      elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
        clean_unmount_in
      else
        echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
      fi
    done
  fi

  detect_root_map
  if [ "$BRmode" = "Transfer" ]; then set_rsync_opts; fi
  if [ -n "$BRbootloader" ]; then set_kern_opts; fi

  echo -e "\n${BR_SEP}SUMMARY${BR_YELLOW}"
  show_summary
  echo -ne "${BR_NORM}"

  while [ -z "$BRcontinue" ]; do
    echo -e "\n${BR_CYAN}Continue?${BR_NORM}"
    read -p "(Y/n):" an

    if [ -n "$an" ]; then def=$an; else def="y"; fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRcontinue="y"
    elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
      echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
      BRcontinue="n"
      clean_unmount_in
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  start_log > /tmp/restore.log
  if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
  echo -e "\n${BR_SEP}PROCESSING"

  if [ "$BRmode" = "Restore" ]; then
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    run_tar 2>>/tmp/restore.log | tar_pgrs_cli
    echo " "

  elif [ "$BRmode" = "Transfer" ]; then
    if [ -n "$BRwrap" ]; then echo "Please wait while calculating files..." > /tmp/wr_proc; fi
    run_calc | while read ln; do a=$((a + 1)) && echo -en "\rCalculating: $a Files"; done

    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    echo " "
    run_rsync 2>>/tmp/restore.log | rsync_pgrs_cli
    echo " "
  fi

  if [ -n "$BRhide" ]; then echo -en "${BR_SHOW}"; fi

  echo -e "\n${BR_SEP}GENERATING FSTAB"
  cp /mnt/target/etc/fstab /mnt/target/etc/fstab-old
  generate_fstab > /mnt/target/etc/fstab
  cat /mnt/target/etc/fstab
  detect_initramfs_prefix

  while [ -z "$BRedit" ]; do
    echo -e "\n${BR_CYAN}Edit fstab?${BR_NORM}"
    read -p "(y/N):" an

    if [ -n "$an" ]; then def=$an; else def="n"; fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRedit="y"
    elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
      BRedit="n"
    else
      echo -e "${BR_RED}Please select a valid option${BR_NORM}"
    fi
  done

  if [ "$BRedit" = "y" ]; then
    PS3="Enter number: "
    echo -e "\n${BR_CYAN}Select editor${BR_NORM}"
    select BReditor in "nano" "vi"; do
      if [[ "$REPLY" = [1-2] ]]; then
        $BReditor /mnt/target/etc/fstab
        echo -e "\n${BR_SEP}EDITED FSTAB" >> /tmp/restore.log
        cat /mnt/target/etc/fstab >> /tmp/restore.log
        break
      else
        echo -e "${BR_RED}Please select a valid option${BR_NORM}"
      fi
    done
  fi

  (prepare_chroot
   build_initramfs
   generate_locales
   install_bootloader
   sleep 1) 1> >(tee -a /tmp/restore.log) 2>&1

  if [ -z "$BRquiet" ]; then
    exit_screen; read -s
  else
    exit_screen_quiet
  fi
  sleep 1
  clean_unmount_out

elif [ "$BRinterface" = "dialog" ]; then
  echo "Probing hardware..."
  partition_list=(`for i in $(scan_parts); do echo "$i $(lsblk -d -n -o size $i)|$(blkid -s TYPE -o value $i)"; done`)

  IFS=$DEFAULTIFS

  if [ -z $(which dialog 2>/dev/null) ];then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package dialog is not installed. Install the package and re-run the script"
    exit
  fi

  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_MAGENTA BR_CYAN BR_BOLD

  if [ ! "$BRmode" = "Transfer" ] && [ -z "$BRuri" ]; then
    dialog --yes-label "Continue" --title "$BR_VERSION" --msgbox "$(info_screen)" 19 80
  fi

  exec 3>&1

  update_list() {
    IFS=$'\n'
    list=(`echo "${partition_list[*]}" | hide_used_parts`)
    IFS=$DEFAULTIFS
  }

  update_list

  update_options() {
    options=("Root partition" "$BRroot")
    if [ -d "$BR_EFI_DETECT_DIR" ]; then
      options+=("(Optional) EFI system partition" "$BResp$sbl$BRespmpoint")
    fi
    if [ ! "$BRespmpoint" = "/boot" ]; then
      options+=("(Optional) Boot partition" "$BRboot")
    fi
    options+=("(Optional) Home partition" "$BRhome" \
    "(Optional) Swap partition" "$BRswap" \
    "(Optional) Custom partitions" "$BRempty" \
    "Done with partitions" "$BRempty")
  }

  update_options

  while [ -z "$BRroot" ]; do
    BRassign="y"
    while opt=$(dialog --ok-label Select --cancel-label Quit --extra-button --extra-label Unset --menu "Set target partitions:" 0 0 0 "${options[@]}" 2>&1 1>&3); rtn="$?"; do
      if [ "$rtn" = "1" ]; then exit; fi
      BRrootold="$BRroot" BRhomeold="$BRhome" BRbootold="$BRboot" BRespold="$BResp" BRswapold="$BRswap"
      case "$opt" in
        "Root partition" )
            if [ "$rtn" = "3" ]; then unset BRroot; elif [ -z "${list[*]}" ]; then no_parts; else BRroot=$(part_sel_dialog root); if [ "$?" = "1" ]; then BRroot="$BRrootold"; fi; fi
            update_list
            update_options;;
        "(Optional) Home partition" )
            if [ "$rtn" = "3" ]; then unset BRhome; elif [ -z "${list[*]}" ]; then no_parts; else BRhome=$(part_sel_dialog /home); if [ "$?" = "1" ]; then BRhome="$BRhomeold"; fi; fi
            update_list
            update_options;;
        "(Optional) Boot partition" )
            if [ "$rtn" = "3" ]; then unset BRboot; elif [ -z "${list[*]}" ]; then no_parts; else BRboot=$(part_sel_dialog /boot); if [ "$?" = "1" ]; then BRboot="$BRbootold"; fi; fi
            update_list
            update_options;;
        "(Optional) Swap partition" )
            if [ "$rtn" = "3" ]; then unset BRswap; elif [ -z "${list[*]}" ]; then no_parts; else BRswap=$(part_sel_dialog swap); if [ "$?" = "1" ]; then BRswap="$BRswapold"; fi; fi
            update_list
            update_options;;
        "(Optional) Custom partitions" )
            if [ "$rtn" = "3" ]; then unset BRcustompartslist BRcustomold; elif [ -z "${list[*]}" ]; then no_parts; else set_custom; fi
            update_options;;
        "(Optional) EFI system partition" )
            if [ "$rtn" = "3" ]; then unset BResp BRespmpoint sbl; elif [ -z "${list[*]}" ]; then no_parts; else BResp=$(part_sel_dialog "ESP"); if [ "$?" = "1" ]; then BResp="$BRespold"; else
            BRespmpoint=$(dialog --no-cancel --menu "Mount it as:" 0 0 0 /boot/efi "Suitable for Grub" /boot "Suitable for EFISTUB/Bootctl" 2>&1 1>&3); fi; fi
            if [ -n "$BRespmpoint" ]; then sbl="->"; fi
            update_list
            update_options;;
        "Done with partitions" )
            if [ ! "$rtn" = "3" ]; then break; fi
            ;;
        esac
    done

    if [ -z "$BRroot" ]; then
      dialog --title "Error" --msgbox "You must specify a target root partition." 5 45
    fi
    if [ -d "$BR_EFI_DETECT_DIR" ] && [ -z "$BResp" ] && [ -n "$BRroot" ]; then
      dialog --title "Warning" --msgbox "Since you didn't choose ESP, bootloaders will be disabled." 5 62
      BRgrub="-1"
      BRefistub="-1"
      BRbootctl="-1"
    fi
  done

  if [ -n "$BRassign" ]; then
    if [ -n "$BRhome" ]; then
      BRcustomparts+=(/home="$BRhome")
    fi

    if [ -n "$BRboot" ]; then
      BRcustomparts+=(/boot="$BRboot")
    fi

    if [ -n "$BResp" ] && [ -n "$BRespmpoint" ]; then
      BRcustomparts+=("$BRespmpoint"="$BResp")
    fi

    if [ -n "$BRcustompartslist" ]; then
      BRcustomparts+=($BRcustompartslist)
    fi
  fi

  if [ -z "$BR_MOUNT_OPTS" ]; then
    BR_MOUNT_OPTS=$(dialog --no-cancel --inputbox "Specify alternative mount options for the root partition.\nLeave empty for: <defaults,noatime>.\n\n(comma-separated list)" 11 70 2>&1 1>&3)
    if [ -z "$BR_MOUNT_OPTS" ]; then
      BR_MOUNT_OPTS="defaults,noatime"
    fi
  fi

  detect_root_fs_size

  if [ -n "$BRrootsubvolname" ] && [ ! "$BRrootsubvolname" = "-1" ] && [ ! "$BRfsystem" = "btrfs" ]; then
    dialog --title "Warning" --msgbox "Not a btrfs root filesystem, press ok to proceed without subvolumes." 5 72
  fi

  if [ "$BRfsystem" = "btrfs" ]; then
    if [ -z "$BRrootsubvolname" ]; then
      BRrootsubvolname=$(dialog --no-cancel --inputbox "Set btrfs root subvolume name. Leave empty for no subvolumes." 8 65 2>&1 1>&3)
    fi

    if [ -n "$BRrootsubvolname" ] && [ -z "$BRsubvols" ]; then
      BRsubvolslist=$(dialog --no-cancel --inputbox "Specify other subvolumes. Leave empty for none.\n\n(subvolume path e.g /home /var /usr ...)" 9 70 2>&1 1>&3)
      if [ -n "$BRsubvolslist" ]; then
        BRsubvols+=($BRsubvolslist)
      fi
    fi
  fi

  if [ -d "$BR_EFI_DETECT_DIR" ]; then
    bootloader_list=(1 Grub 2 "EFISTUB/efibootmgr" 3 "Systemd/bootctl")
  else
    bootloader_list=(1 Grub 2 Syslinux)
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -z "$BRefistub" ] && [ -z "$BRbootctl" ]; then
    REPLY=$(dialog --cancel-label Skip --extra-button --extra-label Quit --menu "Select bootloader:" 10 0 10 "${bootloader_list[@]}" 2>&1 1>&3)
    if [ "$?" = "3" ]; then exit; fi

    if [ "$REPLY" = "1" ]; then
      if [ -d "$BR_EFI_DETECT_DIR" ]; then
        BRgrub="auto"
      else
        BRgrub=$(dialog --column-separator "|" --cancel-label Quit --menu "Set target disk for Grub:" 0 0 0 $(for i in $(scan_disks); do echo "$i $(lsblk -d -n -o size $i)|$BRempty"; done) 2>&1 1>&3)
      fi
      if [ "$?" = "1" ]; then exit; fi
    elif [ "$REPLY" = "2" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
      BRefistub="y"
    elif [ "$REPLY" = "3" ] && [ -d "$BR_EFI_DETECT_DIR" ]; then
      BRbootctl="y"
    elif [ "$REPLY" = "2" ]; then
      BRsyslinux=$(dialog --column-separator "|" --cancel-label Quit --menu "Set target disk for Syslinux:" 0 35 0 $(for i in $(scan_disks); do echo "$i $(lsblk -d -n -o size $i)|$BRempty"; done) 2>&1 1>&3)
      if [ "$?" = "1" ]; then exit;fi
    fi
    if [ -n "$BRgrub" ] || [ -n "$BRsyslinux" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -z "$BR_KERNEL_OPTS" ]; then
      BR_KERNEL_OPTS=$(dialog --no-cancel --inputbox "Specify additional kernel options. Leave empty for defaults." 8 70 2>&1 1>&3)
    fi
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -z "$BRefistub" ] && [ -z "$BRbootctl" ]; then
    dialog --title "Warning" --msgbox "No bootloader selected, press ok to continue." 5 49
  fi

  if [ -z "$BRmode" ]; then
    BRmode=$(dialog --cancel-label Quit --menu "Select Mode:" 12 50 12 Restore "system from backup file" Transfer "this system with rsync" 2>&1 1>&3)
    if [ "$?" = "1" ]; then exit; fi
  fi

  if [ "$BRmode" = "Transfer" ] && [ -z "$BRhidden" ]; then
    dialog --yesno "Transfer entire /home directory?\n\nIf No, only hidden files and folders will be transferred" 8 50
    if [ "$?" = "0" ]; then
      BRhidden="n"
    else
      BRhidden="y"
    fi
  fi

  options_info

  if [ -z "$BR_USER_OPTS" ]; then
    BR_USER_OPTS=$(dialog --no-cancel --inputbox "Enter additional $BRtbr options. Leave empty for defaults.\n\n(If you want spaces in names replace them with //)\n($BRoptinfo)" 11 74 2>&1 1>&3)
  fi

  IFS=$'\n'
  if [ -z "$BRnocolor" ]; then color_variables; fi
  unset_vars
  check_input >&2
  mount_all
  set_user_options

  if [ "$BRmode" = "Restore" ]; then

    if [ -n "$BRurl" ]; then
      BRurlold="$BRurl"
      BRsource="$BRmaxsize/downloaded_backup"
      run_wget 2>&1 | sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | count_gauge_wget | dialog --gauge "Downloading in "$BRsource"..." 0 62
      check_wget
    fi

    if [ -n "$BRsource" ]; then
      IFS=$DEFAULTIFS
      if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
      (echo "Checking and reading archive (Wait...)"
       read_archive 2>/tmp/r_errs | tee /tmp/filelist | while read ln; do a=$((a + 1)) && echo "Checking and reading archive ($a Files) "; done) | dialog --progressbox 3 55
      IFS=$'\n'
      sleep 1
      check_archive
    fi

    while [ -z "$BRsource" ]; do
      REPLY=$(dialog --cancel-label Quit --menu "Select backup file. Choose an option:" 13 50 13 File "local file" URL "remote file" "Protected URL" "protected remote file" 2>&1 1>&3)
      if [ "$?" = "1" ]; then
        clean_unmount_in

      elif [ "$REPLY" = "File" ]; then
        unset BRurl BRselect
        BRpath=/
        IFS=$DEFAULTIFS
        while [ -z "$BRsource" ]; do
          show_path
          BRselect=$(dialog --title "$BRcurrentpath" --menu "Select backup archive:" 30 90 30 "<--UP" .. $(file_list) 2>&1 1>&3)
          if [ "$?" = "1" ]; then
            break
          fi
          BRselect="/$BRselect"
          if [ -f "$BRpath${BRselect//\\/ }" ]; then
            BRsource="$BRpath${BRselect//\\/ }"
            BRsource="${BRsource#*/}"
            ask_passphrase
            detect_filetype
            if [ "$BRfiletype" = "wrong" ]; then
              dialog --title "Error" --msgbox "Invalid file type or wrong passphrase." 5 42
              unset BRsource BRselect BRencpass
            fi
          fi
          if [ "$BRselect" = "/<--UP" ]; then
            BRpath=$(dirname "$BRpath")
          else
            BRpath="$BRpath$BRselect"
            BRpath="${BRpath//\\/ }"
          fi
        done

      elif [ "$REPLY" = "URL" ] || [ "$REPLY" = "Protected URL" ]; then
        BRurl=$(dialog --no-cancel --inputbox "Enter the URL for the backup file:" 8 50 "$BRurlold" 2>&1 1>&3)
        BRurlold="$BRurl"
        BRsource="$BRmaxsize/downloaded_backup"
        if [ "$REPLY" = "Protected URL" ]; then
          BRusername=$(dialog --no-cancel --inputbox "Username:" 8 50 2>&1 1>&3)
          BRpassword=$(dialog --no-cancel --insecure --passwordbox "Password:" 8 50 2>&1 1>&3)
        fi
        run_wget 2>&1 | sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | count_gauge_wget | dialog --gauge "Downloading in "$BRsource"..." 0 62
        check_wget
      fi

      if [ -n "$BRsource" ]; then
        IFS=$DEFAULTIFS
        if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
        (echo "Checking and reading archive (Wait...)"
         read_archive 2>/tmp/r_errs | tee /tmp/filelist | while read ln; do a=$((a + 1)) && echo "Checking and reading archive ($a Files) "; done) | dialog --progressbox 3 55
        IFS=$'\n'
        sleep 1
        check_archive
      fi
    done
  fi

  detect_distro
  set_bootloader
  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_MAGENTA BR_CYAN BR_BOLD

  if [ "$BRmode" = "Restore" ] && [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ] && ! grep -Fq "bin/genkernel" /tmp/filelist; then
    dialog --yes-label "Disable initramfs building" --no-label "Abort" --title Warning --yesno "Genkernel not found in the archived system. (you can disable this check with -D)" 5 85
    if [ "$?" = "1" ]; then
      clean_unmount_in
    else
      BRgenkernel="n"
    fi
  fi

  detect_root_map
  if [ "$BRmode" = "Transfer" ]; then set_rsync_opts; fi
  if [ -n "$BRbootloader" ]; then set_kern_opts; fi

  if [ -z "$BRcontinue" ]; then
    dialog --no-collapse --title "Summary (PgUp/PgDn:Scroll)" --yes-label "OK" --no-label "Quit" --yesno "$(show_summary) $(echo -e "\n\nPress OK to continue, or Quit to abort.")" 0 0
    if [ "$?" = "1" ]; then
      clean_unmount_in
    fi
  fi

  start_log > /tmp/restore.log

  if [ "$BRmode" = "Restore" ]; then
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    run_tar 2>>/tmp/restore.log | count_gauge | dialog --gauge "Extracting $total Files..." 0 50

  elif [ "$BRmode" = "Transfer" ]; then
    if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
    run_calc | while read ln; do a=$((a + 1)) && echo "Calculating: $a Files"; done | dialog --progressbox 3 40
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    if [ -n "$BRhide" ]; then echo -en "${BR_SHOW}"; fi
    run_rsync 2>>/tmp/restore.log | count_gauge | dialog --gauge "Transferring $total Files..." 0 50
  fi

  cp /mnt/target/etc/fstab /mnt/target/etc/fstab-old
  generate_fstab > /mnt/target/etc/fstab
  detect_initramfs_prefix

  if [ -z "$BRedit" ]; then
    dialog --cr-wrap --title "GENERATING FSTAB" --yesno "Edit fstab? Generated fstab:\n\n$(cat /mnt/target/etc/fstab)" 20 100
    if [ "$?" = "0" ]; then
      REPLY=$(dialog --no-cancel --menu "Select editor:" 10 25 10 1 nano 2 vi 2>&1 1>&3)
      if [ "$REPLY" = "1" ]; then
        BReditor="nano"
      elif [ "$REPLY" = "2" ]; then
        BReditor="vi"
      fi
      $BReditor /mnt/target/etc/fstab
      echo -e "\n${BR_SEP}EDITED FSTAB" >> /tmp/restore.log
      cat /mnt/target/etc/fstab >> /tmp/restore.log
    fi
  fi

  (prepare_chroot
   build_initramfs
   generate_locales
   install_bootloader
   sleep 2) 1> >(tee -a /tmp/restore.log) 2>&1 | dialog --title "PROCESSING" --progressbox 30 100

  if [ -f /tmp/bl_error ]; then diag_tl="Error"; else diag_tl="Info"; fi

  if [ -z "$BRquiet" ]; then
    dialog --yes-label "OK" --no-label "View Log" --title "$diag_tl" --yesno "$(exit_screen)" 0 0
    if [ "$?" = "1" ]; then dialog --title "Log (Up/Dn:Scroll)" --textbox /tmp/restore.log 0 0; fi
  else
    dialog --title "$diag_tl" --infobox "$(exit_screen_quiet)" 0 0
  fi

  sleep 1
  clean_unmount_out
fi
