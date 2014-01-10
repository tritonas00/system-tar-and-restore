#!/bin/bash

BR_VERSION="System Tar & Restore 3.9"
BR_SEP="::"

color_variables() {
  BR_NORM='\e[00m'
  BR_RED='\e[00;31m'
  BR_GREEN='\e[00;32m'
  BR_YELLOW='\e[00;33m'
  BR_BLUE='\e[00;34m'
  BR_MAGENTA='\e[00;35m'
  BR_CYAN='\e[00;36m'
  BR_BOLD='\033[1m'
}

info_screen() {
  echo -e "\n${BR_YELLOW}This script will restore a backup image of your system or transfer this\nsystem in user defined partitions."
  echo -e "\n==>Make sure you have created one target root (/) partition. Optionally\n   you can create or use any other partition (/boot /home /var etc)."
  echo -e "\n==>Make sure that target LVM volume groups are activated and target\n   RAID arrays are properly assembled."
  echo -e "\n==>If the target system is Fedora (or variant), select bsdtar archiver.${BR_NORM}"
  echo -e "\n${BR_CYAN}Press ENTER to continue.${BR_NORM}"
}

exit_screen() {
  if [ -f /tmp/bl_error ]; then
    echo -e "\n${BR_RED}Error installing $BRbootloader. Check /tmp/restore.log for details.\n\n${BR_CYAN}Press ENTER to unmount all remaining (engaged) devices.${BR_NORM}"
  elif [ -n "$BRgrub" ] || [ -n "$BRsyslinux" ]; then
    echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log\n\nPress ENTER to unmount all remaining (engaged) devices, then reboot your system.${BR_NORM}"
  else
    echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log"
    echo -e "\n${BR_YELLOW}No bootloader found, so this is the right time to install and\nupdate one. To do so:"
    echo -e "\n==>For internet connection to work, on a new terminal with root\n   access enter: cp -L /etc/resolv.conf /mnt/target/etc/resolv.conf"
    echo -e "\n==>Then chroot into the restored system: chroot /mnt/target"
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
  BRfsize=$(lsblk -d -n -o size 2> /dev/null $BRroot)
}

detect_filetype() {
  if file "$BRfile" | grep -w gzip > /dev/null; then
    BRfiletype="gz"
  elif file "$BRfile" | grep -w XZ > /dev/null; then
    BRfiletype="xz"
  else
    BRfiletype="wrong"
  fi
}

check_wget() {
  if [ -f /tmp/wget_error ]; then
    rm /tmp/wget_error
    rm /mnt/target/fullbackup 2>/dev/null
    if [ "$BRinterface" = "cli" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Error downloading file. Wrong URL or network is down"
    elif [ "$BRinterface" = "dialog" ]; then
      dialog --title "Error" --msgbox "Error downloading file. Wrong URL or network is down." 5 57
    fi
  else
    if file /mnt/target/fullbackup | grep -w gzip > /dev/null; then
      BRfiletype="gz"
    elif file /mnt/target/fullbackup | grep -w XZ > /dev/null; then
      BRfiletype="xz"
    else
      rm /mnt/target/fullbackup 2>/dev/null
      if [ "$BRinterface" = "cli" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type"
      elif [ "$BRinterface" = "dialog" ]; then
        dialog --title "Error" --msgbox "Invalid file type." 5 22
      fi
    fi
  fi
}

detect_distro() {
  if [ "$BRmode" = "Restore" ]; then
    if grep -Fxq "etc/yum.conf" /tmp/filelist 2>/dev/null; then
      BRdistro="Fedora"
    elif grep -Fxq "etc/pacman.conf" /tmp/filelist 2>/dev/null; then
      BRdistro="Arch"
    elif grep -Fxq "etc/apt/sources.list" /tmp/filelist 2>/dev/null; then
      BRdistro="Debian"
    else
      BRdistro="Unsupported"
    fi

  elif [ "$BRmode" = "Transfer" ]; then
    if [ -f /etc/yum.conf ]; then
      BRdistro="Fedora"
    elif [ -f /etc/pacman.conf ]; then
      BRdistro="Arch"
    elif [ -f /etc/apt/sources.list ]; then
      BRdistro="Debian"
    else
      BRdistro="Unsupported"
    fi
   fi
}

detect_syslinux_root() {
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

detect_partition_table() {
  if [[ "$BRsyslinux" == *md* ]]; then
    BRsyslinuxdisk="$BRdev"
  else
    BRsyslinuxdisk="$BRsyslinux"
  fi
  if dd if="$BRsyslinuxdisk" skip=64 bs=8 count=1 2>/dev/null | grep -w "EFI PART" > /dev/null; then
    BRpartitiontable="gpt"
  else
    BRpartitiontable="mbr"
  fi
}

set_syslinux_flags_and_paths() {
  if [ "$BRpartitiontable" = "gpt" ]; then
    echo "Setting legacy_boot flag on $BRdev$BRpart"
    sgdisk $BRdev --attributes=$BRpart:set:2 &>> /tmp/restore.log || touch /tmp/bl_error
    BRsyslinuxmbr="gptmbr.bin"
  else
    echo "Setting boot flag on $BRdev$BRpart"
    sfdisk $BRdev -A $BRpart &>> /tmp/restore.log || touch /tmp/bl_error
    BRsyslinuxmbr="mbr.bin"
  fi
  if [ "$BRdistro" = Debian ]; then
    BRsyslinuxpath="/mnt/target/usr/lib/syslinux"
  elif [ $BRdistro = Fedora ]; then
    BRsyslinuxpath="/mnt/target/usr/share/syslinux"
  fi
}

generate_syslinux_cfg() {
  echo -e "UI menu.c32\nPROMPT 0\nMENU TITLE Boot Menu\nTIMEOUT 50" > /mnt/target/boot/syslinux/syslinux.cfg
  if [ "$BRfsystem" = "btrfs" ] && [ "$BRrootsubvol" = "y" ]; then
    syslinuxrootsubvol="rootflags=subvol=$BRrootsubvolname"
  fi
  for BRinitrd in `find /mnt/target/boot -name vmlinuz* | sed 's_/mnt/target/boot/vmlinuz-*__'` ; do
    if [ $BRdistro = Arch ]; then
      echo -e "LABEL arch\n\tMENU LABEL Arch $BRinitrd\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS rw\n\tINITRD ../initramfs-$BRinitrd.img" >> /mnt/target/boot/syslinux/syslinux.cfg
      echo -e "LABEL archfallback\n\tMENU LABEL Arch $BRinitrd fallback\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS rw\n\tINITRD ../initramfs-$BRinitrd-fallback.img" >> /mnt/target/boot/syslinux/syslinux.cfg
    elif [ $BRdistro = Debian ]; then
      echo -e "LABEL debian\n\tMENU LABEL Debian-$BRinitrd\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS ro quiet\n\tINITRD ../initrd.img-$BRinitrd" >> /mnt/target/boot/syslinux/syslinux.cfg
    elif [ $BRdistro = Fedora ]; then
      echo -e "LABEL fedora\n\tMENU LABEL Fedora-$BRinitrd\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS ro quiet\n\tINITRD ../initramfs-$BRinitrd.img" >> /mnt/target/boot/syslinux/syslinux.cfg
    fi
  done
}

run_tar() {
  if [ "$BRarchiver" = "tar" ]; then
    if [ "$BRfiletype" = "gz" ]; then
      $BRarchiver xvpfz /mnt/target/fullbackup -C /mnt/target && (echo "System decompressed successfully" >> /tmp/restore.log)
    elif [ "$BRfiletype" = "xz" ]; then
      $BRarchiver xvpfJ /mnt/target/fullbackup -C /mnt/target && (echo "System decompressed successfully" >> /tmp/restore.log)
    fi
  elif [ "$BRarchiver" = "bsdtar" ]; then
    if [ "$BRfiletype" = "gz" ]; then
      $BRarchiver xvpfz /mnt/target/fullbackup -C /mnt/target 2>&1 && (echo "System decompressed successfully" >> /tmp/restore.log) || touch /tmp/r_error
    elif [ "$BRfiletype" = "xz" ]; then
      $BRarchiver xvpfJ /mnt/target/fullbackup -C /mnt/target 2>&1 && (echo "System decompressed successfully" >> /tmp/restore.log) || touch /tmp/r_error
    fi
  fi
}

run_calc() {
  if [ "$BRhidden" = "n" ]; then
    rsync -av / /mnt/target --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,lost+found,/home/*/.gvfs} --dry-run 2> /dev/null | tee /tmp/filelist
  elif [ "$BRhidden" = "y" ]; then
    rsync -av / /mnt/target --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,lost+found,/home/*/.gvfs,/home/*/[^.]*} --dry-run 2> /dev/null | tee /tmp/filelist
  fi
}

run_rsync() {
  if [ "$BRhidden" = "n" ]; then
    rsync -aAXv / /mnt/target --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,lost+found,/home/*/.gvfs} && (echo "System transferred successfully" >> /tmp/restore.log)
  elif [ "$BRhidden" = "y" ]; then
    rsync -aAXv / /mnt/target --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,lost+found,/home/*/.gvfs,/home/*/[^.]*} && (echo "System transferred successfully" >> /tmp/restore.log)
  fi
}

count_gauge() {
  while read ln; do
    b=$(( b + 1 ))
    per=$(($b*100/$total))
    if [[ $per -gt $lastper ]]; then
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
  grep -vw -e `echo /dev/"${BRroot##*/}"` -e `echo /dev/"${BRswap##*/}"` -e `echo /dev/"${BRhome##*/}"` -e `echo /dev/"${BRboot##*/}"` -e `echo /dev/mapper/"${BRroot##*/}"` -e `echo /dev/mapper/"${BRswap##*/}"` -e `echo /dev/mapper/"${BRhome##*/}"` -e `echo /dev/mapper/"${BRboot##*/}"`
}

check_parts() {
  for f in $(find /dev -regex "/dev/[hs]d[a-z][0-9]+"); do echo -e "$f"; done
  for f in $(find /dev/mapper/ | grep '-'); do echo -e "$f"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo -e "$f"; done
}

check_disks() {
  for f in /dev/[hs]d[a-z]; do echo "$f"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f"; done
}

disk_list_dialog() {
  for f in /dev/[hs]d[a-z]; do echo -e "$f $(lsblk -d -n -o size $f)"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo -e "$f $(lsblk -d -n -o size $f)"; done
}

part_sel_dialog() {
  dialog --column-separator "|" --cancel-label Back --menu "Set target $1 partition:" 0 0 0 `echo "${list[@]}"` 2>&1 1>&3
}

set_custom() {
  BRcustompartslist=$(dialog --no-cancel --inputbox "Set partitions: (mountpoint=device e.g /usr=/dev/sda3 /var/cache=/dev/sda4)" 8 80 "$BRcustomold" 2>&1 1>&3)
  BRcustomold="$BRcustompartslist"
}

no_parts() {
  dialog --title "Error" --msgbox "No partitions left. Unset a partition and try again." 5 56
}

disk_report() {
  for i in /dev/[hs]d[a-z]; do
    echo -e "\n$i  ($(lsblk -d -n -o model $i)  $(lsblk -d -n -o size $i))"
    for f in $i[0-9]; do echo -e "\t\t$f  $(blkid -s TYPE -o value $f)  $(lsblk -d -n -o size $f)  $(lsblk -d -n -o mountpoint 2> /dev/null $f)"; done
  done
}

check_input() {
  if [ -n "$BRfile" ] && [ ! -f "$BRfile" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] File not found: $BRfile"
    BRSTOP="y"
  elif [ -n "$BRfile" ]; then
    detect_filetype
    if [ "$BRfiletype" = "wrong" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type. File must be a gzip or xz compressed archive"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRuri" ] && [ -z "$BRarchiver" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify archiver"
    BRSTOP="y"
  fi

  if [ -n "$BRuri" ] && [ -n "$BRrestore" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use local file / url and transfer mode at the same time"
    BRSTOP="y"
  fi

  if [ "$BRmode" = "Transfer" ]; then
    if [ -z $(which rsync 2> /dev/null) ];then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package rsync is not installed. Install the package and re-run the script"
      BRSTOP="y"
    fi
    if [ -n "$BRgrub" ] && [ ! -d /usr/lib/grub/i386-pc ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Grub not found"
      BRSTOP="y"
    elif [ -n "$BRsyslinux" ] && [ -z $(which extlinux 2> /dev/null) ];then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Syslinux not found"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRsyslinux" ] || [ -n "$BRgrub" ] || [ -n "$BRswap" ] || [ -n "$BRhome" ] || [ -n "$BRboot" ] || [ -n "$BRother" ] || [ -n "$BRrootsubvol" ] || [ -n "$BRsubvolother" ] && [ -z "$BRroot" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] You must specify a target root partition."
    BRSTOP="y"
  fi

  if [ -n "$BRroot" ]; then
    for i in $(check_parts); do if [[ $i == ${BRroot} ]] ; then BRrootcheck="true" ; fi; done
    if [ ! "$BRrootcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong root partition: $BRroot"
      BRSTOP="y"
    elif pvdisplay 2>&1 | grep -w $BRroot > /dev/null; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRroot contains lvm physical volume, refusing to use it. Use a logical volume instead"
      BRSTOP="y"
    elif [[ ! -z `lsblk -d -n -o mountpoint 2> /dev/null $BRroot` ]]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRroot is already mounted as $(lsblk -d -n -o mountpoint 2> /dev/null $BRroot), refusing to use it"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRswap" ]; then
    for i in $(check_parts); do if [[ $i == ${BRswap} ]] ; then BRswapcheck="true" ; fi; done
    if [ ! "$BRswapcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong swap partition: $BRswap"
      BRSTOP="y"
    elif pvdisplay 2>&1 | grep -w $BRswap > /dev/null; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRswap contains lvm physical volume, refusing to use it. Use a logical volume instead"
      BRSTOP="y"
    fi
    if [ "$BRswap" == "$BRroot" ]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRswap already used"
      BRSTOP="y"
    fi
  fi

  if [ "$BRcustom" = "y" ]; then
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

    while read ln; do
      BRmpoint=$(echo $ln | cut -f1 -d"=")
      BRdevice=$(echo $ln | cut -f2 -d"=")

      for i in $(check_parts); do if [[ $i == ${BRdevice} ]] ; then BRcustomcheck="true" ; fi; done
      if [ ! "$BRcustomcheck" = "true" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong $BRmpoint partition: $BRdevice"
        BRSTOP="y"
      elif pvdisplay 2>&1 | grep -w $BRdevice > /dev/null; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice contains lvm physical volume, refusing to use it. Use a logical volume instead"
        BRSTOP="y"
      elif [[ ! -z `lsblk -d -n -o mountpoint 2> /dev/null $BRdevice` ]]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice is already mounted as $(lsblk -d -n -o mountpoint 2> /dev/null $BRdevice), refusing to use it"
        BRSTOP="y"
      fi
      if [ "$BRdevice" == "$BRroot" ] || [ "$BRdevice" == "$BRswap" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice already used"
        BRSTOP="y"
      fi
      if [ "$BRmpoint" = "/" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont assign root partition as custom"
        BRSTOP="y"
      fi
      if [ "$BRsubvolother" = "y" ]; then
        for item in "${BRsubvols[@]}"; do
          if [[ "$BRmpoint" == *"$item"* ]] && [[ "$item" == *"$BRmpoint"* ]]; then
            echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use partitions inside btrfs subvolumes"
            BRSTOP="y"
          fi
        done
      fi
      if [[ ! "$BRmpoint" == /* ]]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Wrong mountpoint syntax: $BRmpoint"
        BRSTOP="y"
      fi
      unset BRcustomcheck
    done < <( for a in ${BRcustomparts[@]}; do BRmpoint=$(echo $a | cut -f1 -d"="); BRdevice=$(echo $a | cut -f2 -d"="); echo "$BRmpoint=$BRdevice"; done )
  fi

  if [ "$BRsubvolother" = "y" ]; then
    BRsubvolused=(`for i in ${BRsubvols[@]}; do echo $i; done | sort | uniq -d`)
    if [ -n "$BRsubvolused" ]; then
      for a in ${BRsubvolused[@]}; do
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Duplicate subvolume: $a"
        BRSTOP="y"
      done
    fi

    while read ln; do
      if [[ ! "$ln" == /* ]]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Wrong subvolume syntax: $ln"
        BRSTOP="y"
      fi
      if [ "$ln" = "/" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Use -R to assign root subvolume"
        BRSTOP="y"
      fi
    done < <( for a in ${BRsubvols[@]}; do echo $a; done )
  fi

  if [ -n "$BRgrub" ]; then
    for i in $(check_disks); do if [[ $i == ${BRgrub} ]] ; then BRgrubcheck="true" ; fi; done
    if [ ! "$BRgrubcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong disk for grub: $BRgrub"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRsyslinux" ]; then
    for i in $(check_disks); do if [[ $i == ${BRsyslinux} ]] ; then BRsyslinuxcheck="true" ; fi; done
    if [ ! "$BRsyslinuxcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong disk for syslinux: $BRsyslinux"
      BRSTOP="y"
    fi
    if [[ "$BRsyslinux" == *md* ]]; then
      for f in `cat /proc/mdstat | grep $(echo "$BRsyslinux" | cut -c 6-) | grep -oP '[hs]d[a-z][0-9]'` ; do
        BRdev=`echo /dev/$f | cut -c -8`
      done
    fi
    detect_partition_table
    if [ "$BRpartitiontable" = "gpt" ] && [ -z $(which sgdisk 2> /dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package gptfdisk/gdisk is not installed. Install the package and re-run the script"
      BRSTOP="y"
    fi
  fi

  if [ -n "$BRgrub" ] && [ -n "$BRsyslinux" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use both bootloaders at the same time"
    BRSTOP="y"
  fi

  if [ -n "$BRinterface" ] && [ ! "$BRinterface" = "cli" ] && [ ! "$BRinterface" = "dialog" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong interface name: $BRinterface. Available options: cli dialog"
    BRSTOP="y"
  fi

  if [ -n "$BRarchiver" ] && [ ! "$BRarchiver" = "tar" ] && [ ! "$BRarchiver" = "bsdtar" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong archiver: $BRarchiver. Available options: tar bsdtar"
    BRSTOP="y"
  fi

  if [ "$BRarchiver" = "bsdtar" ] && [ -z $(which bsdtar 2> /dev/null) ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
    BRSTOP="y"
  fi

  if [ -n "$BRSTOP" ]; then
    exit
  fi
}

mount_all() {
  echo -e "\n${BR_SEP}MOUNTING"
  echo -ne "${BR_WRK}Making working directory"
  OUTPUT=$(mkdir /mnt/target 2>&1) && ok_status || error_status

  echo -ne "${BR_WRK}Mounting $BRroot"
  OUTPUT=$(mount -o $BR_MOUNT_OPTS $BRroot /mnt/target 2>&1) && ok_status || error_status
  if [ -n "$BRSTOP" ]; then
    echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions"
    clean_files
    rm -r /mnt/target
    exit
  fi

  if [ "$(ls -A /mnt/target | grep -vw "lost+found")" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Root partition not empty, refusing to use it"
    echo -e "[${BR_CYAN}INFO${BR_NORM}] Root partition must be formatted and cleaned"
    echo -ne "${BR_WRK}Unmounting $BRroot"
    sleep 1
    OUTPUT=$(umount $BRroot 2>&1) && (ok_status && rm_work_dir) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
    exit
  fi

  if [ "$BRfsystem" = "btrfs" ] && [ "$BRrootsubvol" = "y" ]; then
    echo -ne "${BR_WRK}Creating $BRrootsubvolname"
    OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname 2>&1 1> /dev/null) && ok_status || error_status

    if [ "$BRsubvolother" = "y" ]; then
      while read ln; do
        echo -ne "${BR_WRK}Creating $BRrootsubvolname$ln"
        OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname$ln 2>&1 1> /dev/null) && ok_status || error_status
      done< <(for a in "${BRsubvols[@]}"; do echo "$a"; done | sort)
    fi

    echo -ne "${BR_WRK}Unmounting $BRroot"
    OUTPUT=$(umount $BRroot 2>&1) && ok_status || error_status

    echo -ne "${BR_WRK}Mounting $BRrootsubvolname"
    OUTPUT=$(mount -t btrfs -o $BR_MOUNT_OPTS,subvol=$BRrootsubvolname $BRroot /mnt/target 2>&1) && ok_status || error_status
    if [ -n "$BRSTOP" ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while making subvolumes"
      unset BRSTOP
      clean_unmount_in
    fi
  fi

  if [ "$BRcustom" = "y" ]; then
    BRsorted=(`for i in ${BRcustomparts[@]}; do echo $i; done | sort -k 1,1 -t =`)
    unset custom_ok
    for i in ${BRsorted[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      echo -ne "${BR_WRK}Mounting $BRdevice"
      mkdir -p /mnt/target$BRmpoint
      OUTPUT=$(mount $BRdevice /mnt/target$BRmpoint 2>&1) && ok_status || error_status
      if [ -n "$custom_ok" ]; then
        unset custom_ok
        BRumountparts+=($BRmpoint=$BRdevice)
        if [ "$(ls -A /mnt/target$BRmpoint | grep -vw "lost+found")" ]; then
          echo -e "[${BR_CYAN}INFO${BR_NORM}] $BRmpoint partition not empty"
        fi
      fi
    done
    if [ -n "$BRSTOP" ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions"
      unset BRSTOP
      clean_unmount_in
    fi
  fi
}

show_summary() {
  echo -e "${BR_YELLOW}PARTITIONS:"
  echo -e "root partition: $BRroot $BRfsystem $BRfsize $BR_MOUNT_OPTS"

  if [ "$BRcustom" = "y" ]; then
    for i in ${BRsorted[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRcustomfs=$(df -T | grep $BRdevice | awk '{print $2}')
      BRcustomsize=$(lsblk -d -n -o size 2> /dev/null $BRdevice)
      echo "${BRmpoint#*/} partition: $BRdevice $BRcustomfs $BRcustomsize"
    done
  fi

  if [ -n "$BRswap" ]; then
    echo "swap partition: $BRswap"
  fi

  if [ "$BRfsystem" = "btrfs" ] && [ "$BRrootsubvol" = "y" ]; then
    echo -e "\nSUBVOLUMES:"
    echo "root: $BRrootsubvolname"
    if [ "$BRsubvolother" = "y" ]; then
      while read ln; do
        echo "${ln#*/}"
      done< <(for a in "${BRsubvols[@]}"; do echo "$a"; done | sort)
    fi
  fi

  echo -e "\nBOOTLOADER:"

  if [ -n "$BRgrub" ]; then
    echo "$BRbootloader"
    if [[ "$BRgrub" == *md* ]]; then
      echo "Locations: $(echo $(cat /proc/mdstat | grep $(echo "$BRgrub" | cut -c 6-) | grep -oP '[hs]d[a-z]'))"
    else
      echo "Location: $BRgrub"
    fi
  elif [ -n "$BRsyslinux" ]; then
    echo "$BRbootloader"
    if [[ "$BRsyslinux" == *md* ]]; then
      echo "Locations: $(echo $(cat /proc/mdstat | grep $(echo "$BRsyslinux" | cut -c 6-) | grep -oP '[hs]d[a-z]'))"
    else
      echo "Location: $BRsyslinux"
    fi
    if [ -n "$BR_KERNEL_OPTS" ]; then
      echo "Kernel Options: $BR_KERNEL_OPTS"
    fi
  else
    echo "None (WARNING)"
  fi

  echo -e "\nPROCESS:"

  if [ "$BRmode" = "Restore" ]; then
    echo "Mode: $BRmode"
    echo "Archiver: $BRarchiver"
    echo "Archive: $BRfiletype compressed"
  elif [ "$BRmode" = "Transfer" ] && [ "$BRhidden" = "n" ]; then
    echo "Mode: $BRmode"
    echo "Home: Include"
  elif [ "$BRmode" = "Transfer" ] && [ "$BRhidden" = "y" ]; then
    echo "Mode: $BRmode"
    echo "Home: Only hidden files and folders"
  fi
  if [ "$BRdistro" = "Unsupported" ]; then
    echo -e "System: $BRdistro (WARNING)${BR_NORM}"
  elif [ "$BRmode" = "Restore" ]; then
    echo -e "System: $BRdistro based ${target_arch#*.}${BR_NORM}"
  elif [ "$BRmode" = "Transfer" ]; then
     echo -e "System: $BRdistro based $(uname -m)${BR_NORM}"
  fi
}

prepare_chroot() {
  echo -e "\n${BR_SEP}PREPARING CHROOT ENVIROMENT"
  echo -e "Binding /run"
  mount --bind /run /mnt/target/run
  echo -e "Binding /dev"
  mount --bind /dev /mnt/target/dev
  echo -e "Binding /dev/pts"
  mount --bind /dev/pts /mnt/target/dev/pts
  echo -e "Mounting /proc"
  mount -t proc /proc /mnt/target/proc
  echo -e "Mounting /sys"
  mount -t sysfs /sys /mnt/target/sys
}

generate_fstab() {
  mv /mnt/target/etc/fstab /mnt/target/etc/fstab-old
  if [ "$BRfsystem" = "btrfs" ] && [ "$BRrootsubvol" = "y" ]; then
    echo "$(detect_fstab_root)  /  btrfs  $BR_MOUNT_OPTS,subvol=$BRrootsubvolname,noatime  0  0" >> /mnt/target/etc/fstab
  elif [ "$BRfsystem" = "btrfs" ] && [ "$BRrootsubvol" = "n" ]; then
    echo "$(detect_fstab_root)  /  btrfs  $BR_MOUNT_OPTS,noatime  0  0" >> /mnt/target/etc/fstab
  else
    echo "$(detect_fstab_root)  /  $BRfsystem  $BR_MOUNT_OPTS,noatime  0  1" >> /mnt/target/etc/fstab
  fi

  if [ "$BRcustom" = "y" ]; then
    for i in ${BRsorted[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRcustomfs=$(df -T | grep $BRdevice | awk '{print $2}')
      if [[ "$BRdevice" == *dev/md* ]]; then
        echo "$BRdevice  $BRmpoint  $BRcustomfs  defaults  0  2" >> /mnt/target/etc/fstab
      else
        echo "UUID=$(blkid -s UUID -o value $BRdevice)  $BRmpoint  $BRcustomfs  defaults  0  2" >> /mnt/target/etc/fstab
      fi
    done
  fi

  if [ -n "$BRswap" ]; then
    if [[ "$BRswap" == *dev/md* ]]; then
      echo "$BRswap  swap  swap  defaults  0  0" >> /mnt/target/etc/fstab
    else
      echo "UUID=$(blkid -s UUID -o value $BRswap)  swap  swap  defaults  0  0" >> /mnt/target/etc/fstab
    fi
  fi
  echo -e "\n${BR_SEP}GENERATED FSTAB" >> /tmp/restore.log
  cat /mnt/target/etc/fstab >> /tmp/restore.log
}

build_initramfs() {
  echo -e "\n${BR_SEP}REBUILDING INITRAMFS IMAGES"
  if grep -q dev/md /mnt/target/etc/fstab; then
    echo "Generating mdadm.conf..."
    if [ "$BRdistro" = "Debian" ]; then
      if [ -f /mnt/target/etc/mdadm/mdadm.conf ]; then
        mv /mnt/target/etc/mdadm/mdadm.conf /mnt/target/etc/mdadm/mdadm.conf-old
      fi
      mdadm --examine --scan > /mnt/target/etc/mdadm/mdadm.conf
      cat /mnt/target/etc/mdadm/mdadm.conf
    else
      if [ -f /mnt/target/etc/mdadm.conf ]; then
        mv /mnt/target/etc/mdadm.conf /mnt/target/etc/mdadm.conf-old
      fi
      mdadm --examine --scan > /mnt/target/etc/mdadm.conf
      cat /mnt/target/etc/mdadm.conf
    fi
    echo " "
  fi

  for BRinitrd in `find /mnt/target/boot -name vmlinuz* | sed 's_/mnt/target/boot/vmlinuz-*__'` ; do
    if [ "$BRdistro" = "Arch" ]; then
      chroot /mnt/target mkinitcpio -p $BRinitrd
    elif [ "$BRdistro" = "Debian" ]; then
      chroot /mnt/target update-initramfs -u -k $BRinitrd
    elif [ "$BRdistro" = "Fedora" ]; then
      echo "Building image for $BRinitrd..."
      chroot /mnt/target dracut --force /boot/initramfs-$BRinitrd.img $BRinitrd
    fi
  done
}

install_bootloader() {
  if [ -n "$BRgrub" ]; then
    echo -e "\n${BR_SEP}INSTALLING AND UPDATING GRUB2 IN $BRgrub"
    if [[ "$BRgrub" == *md* ]]; then
      for f in `cat /proc/mdstat | grep $(echo "$BRgrub" | cut -c 6-) | grep -oP '[hs]d[a-z]'` ; do
        if [ "$BRdistro" = "Arch" ]; then
          chroot /mnt/target grub-install --target=i386-pc --recheck /dev/$f || touch /tmp/bl_error
        elif [ "$BRdistro" = "Debian" ]; then
          chroot /mnt/target grub-install --recheck /dev/$f || touch /tmp/bl_error
        elif [ "$BRdistro" = "Fedora" ]; then
          chroot /mnt/target grub2-install --recheck /dev/$f || touch /tmp/bl_error
        fi
      done
    elif [ "$BRdistro" = "Arch" ]; then
      chroot /mnt/target grub-install --target=i386-pc --recheck $BRgrub || touch /tmp/bl_error
    elif [ "$BRdistro" = "Debian" ]; then
      chroot /mnt/target grub-install --recheck $BRgrub || touch /tmp/bl_error
    elif [ "$BRdistro" = "Fedora" ]; then
      chroot /mnt/target grub2-install --recheck $BRgrub || touch /tmp/bl_error
    fi

    if [ "$BRdistro" = "Fedora" ]; then
      if [ -f /mnt/target/etc/default/grub ]; then
        cp /mnt/target/etc/default/grub /mnt/target/etc/default/grub-old
      fi
      sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="vconsole.keymap=us quiet"/' /mnt/target/etc/default/grub
      echo -e "\n${BR_SEP}Modified grub2 config" >> /tmp/restore.log
      cat /mnt/target/etc/default/grub >> /tmp/restore.log
      chroot /mnt/target grub2-mkconfig -o /boot/grub2/grub.cfg
    else
      chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg
    fi

  elif [ -n "$BRsyslinux" ]; then
    echo -e "\n${BR_SEP}INSTALLING AND CONFIGURING Syslinux IN $BRsyslinux"
    if [ -d /mnt/target/boot/syslinux ]; then
      mv /mnt/target/boot/syslinux/syslinux.cfg /mnt/target/boot/syslinux.cfg-old
      chattr -i /mnt/target/boot/syslinux/* 2> /dev/null
      rm -r /mnt/target/boot/syslinux/* 2> /dev/null
    else
      mkdir -p /mnt/target/boot/syslinux
    fi
    touch /mnt/target/boot/syslinux/syslinux.cfg

    if [ "$BRdistro" = "Arch" ]; then
      chroot /mnt/target syslinux-install_update -i -a -m || touch /tmp/bl_error
    else
      if [[ "$BRsyslinux" == *md* ]]; then
        chroot /mnt/target extlinux --raid -i /boot/syslinux || touch /tmp/bl_error
        for f in `cat /proc/mdstat | grep $(echo "$BRsyslinux" | cut -c 6-) | grep -oP '[hs]d[a-z][0-9]'` ; do
          BRdev=`echo /dev/$f | cut -c -8`
          BRpart=`echo /dev/$f | cut -c 9-`
          detect_partition_table
          set_syslinux_flags_and_paths
          echo "Installing $BRsyslinuxmbr in $BRdev ($BRpartitiontable)"
          dd bs=440 count=1 conv=notrunc if=$BRsyslinuxpath/$BRsyslinuxmbr of=$BRdev &>> /tmp/restore.log || touch /tmp/bl_error
        done
      else
        chroot /mnt/target extlinux -i /boot/syslinux || touch /tmp/bl_error
        if [ -n "$BRboot" ]; then
          BRdev=`echo $BRboot | cut -c -8`
          BRpart=`echo $BRboot | cut -c 9-`
        else
          BRdev=`echo $BRroot | cut -c -8`
          BRpart=`echo $BRroot | cut -c 9-`
        fi
        detect_partition_table
        set_syslinux_flags_and_paths
        echo "Installing $BRsyslinuxmbr in $BRsyslinux ($BRpartitiontable)"
        dd bs=440 count=1 conv=notrunc if=$BRsyslinuxpath/$BRsyslinuxmbr of=$BRsyslinux &>> /tmp/restore.log || touch /tmp/bl_error
      fi
      cp $BRsyslinuxpath/menu.c32 /mnt/target/boot/syslinux/
    fi
    generate_syslinux_cfg
    echo -e "\n${BR_SEP}GENERATED SYSLINUX CONFIG" >> /tmp/restore.log
    cat /mnt/target/boot/syslinux/syslinux.cfg >> /tmp/restore.log
  fi
}

set_bootloader() {
  if [ -n "$BRgrub" ]; then
    BRbootloader="Grub"
  elif [ -n "$BRsyslinux" ]; then
    BRbootloader="Syslinux"
  fi

  if [ "$BRmode" = "Restore" ]; then
    if [ -n "$BRgrub" ] && ! grep -Fq "usr/lib/grub/i386-pc" /tmp/filelist 2>/dev/null; then
      if [ -z "$BRnocolor" ]; then color_variables; fi
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Grub not found in the archived system\n"
      clean_unmount_in
    elif [ -n "$BRsyslinux" ] && ! grep -Fq "bin/extlinux" /tmp/filelist 2>/dev/null; then
      if [ -z "$BRnocolor" ]; then color_variables; fi
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Syslinux not found in the archived system\n"
      clean_unmount_in
    fi
  fi
}

check_archive() {
  if [ "$BRinterface" = "cli" ]; then echo " "; fi
  if [ -f /tmp/tar_error ]; then
    rm /tmp/tar_error
    rm /mnt/target/fullbackup 2>/dev/null
    if [ "$BRinterface" = "cli" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Error reading archive"
    elif [ "$BRinterface" = "dialog" ]; then
      dialog --title "Error" --msgbox "Error reading archive." 5 26
    fi
  else
    target_arch=$(grep -F 'target_architecture.' /tmp/filelist)
    if [ -z "$target_arch" ]; then
      target_arch="unknown"
    fi
    if [ ! "$(uname -m)" == "$(echo ${target_arch#*.})" ]; then
      rm /mnt/target/fullbackup 2>/dev/null
      if [ "$BRinterface" = "cli" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Running and target system architecture mismatch or invalid archive"
        echo -e "[${BR_CYAN}INFO${BR_NORM}] Target  system: ${target_arch#*.}"
        echo -e "[${BR_CYAN}INFO${BR_NORM}] Running system: $(uname -m)"
      elif [ "$BRinterface" = "dialog" ]; then
        dialog --title "Error" --msgbox "Running and target system architecture mismatch or invalid archive.\n\nTarget  system: ${target_arch#*.}\nRunning system: $(uname -m)" 8 71
      fi
    fi
  fi
}

generate_locales() {
  if [ "$BRdistro" = "Arch" ] || [ "$BRdistro" = "Debian" ]; then
    echo -e "\n${BR_SEP}GENERATING LOCALES"
    chroot /mnt/target locale-gen
  fi
}

rm_work_dir() {
  sleep 1
  rm -r /mnt/target
}

clean_files() {
  if [ -f /mnt/target/fullbackup ]; then rm /mnt/target/fullbackup; fi
  if [ -f /tmp/filelist ]; then rm /tmp/filelist; fi
  if [ -f /tmp/bl_error ]; then rm /tmp/bl_error; fi
  if [ -f /tmp/r_error ]; then rm /tmp/r_error; fi
  if [ -f /tmp/bsdtar_out ]; then rm /tmp/bsdtar_out; fi
  if [ -f /mnt/target/target_architecture.$(uname -m) ]; then rm /mnt/target/target_architecture.$(uname -m); fi
 }

clean_unmount_in() {
  if [ -z "$BRnocolor" ]; then color_variables; fi
  echo "${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  if [ "$BRcustom" = "y" ]; then
    while read ln; do
      sleep 1
      echo -ne "${BR_WRK}Unmounting $ln"
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done < <( for i in ${BRumountparts[@]}; do BRdevice=$(echo $i | cut -f2 -d"="); echo $BRdevice; done | tac )
  fi

  if [ "$BRfsystem" = "btrfs" ] && [ "$BRrootsubvol" = "y" ]; then
    echo -ne "${BR_WRK}Unmounting $BRrootsubvolname"
    OUTPUT=$(umount $BRroot 2>&1) && ok_status || error_status
    sleep 1
    echo -ne "${BR_WRK}Mounting $BRroot"
    OUTPUT=$(mount $BRroot /mnt/target 2>&1) && ok_status || error_status

    if [ "$BRsubvolother" = "y" ]; then
      while read ln; do
        sleep 1
        echo -ne "${BR_WRK}Deleting $BRrootsubvolname$ln"
        OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname$ln 2>&1 1> /dev/null) && ok_status || error_status
      done < <( for i in ${BRsubvols[@]}; do echo $i; done | sort | tac )
    fi

    echo -ne "${BR_WRK}Deleting $BRrootsubvolname"
    OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname 2>&1 1> /dev/null) && ok_status || error_status
  fi

  if [ -z "$BRSTOP" ]; then
    rm -r /mnt/target/* 2>/dev/null
  fi
  clean_files

  echo -ne "${BR_WRK}Unmounting $BRroot"
  sleep 1
  OUTPUT=$(umount $BRroot 2>&1) && (ok_status && rm_work_dir) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
  exit
}

clean_unmount_out() {
  if [ -z "$BRnocolor" ]; then color_variables; fi
  echo -e "\n${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  umount /mnt/target/dev/pts
  umount /mnt/target/proc
  umount /mnt/target/dev
  umount /mnt/target/sys
  umount /mnt/target/run

  if [ "$BRcustom" = "y" ]; then
    while read ln; do
      sleep 1
      echo -ne "${BR_WRK}Unmounting $ln"
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done < <( for i in ${BRsorted[@]}; do BRdevice=$(echo $i | cut -f2 -d"="); echo $BRdevice; done | tac )
  fi

  clean_files

  echo -ne "${BR_WRK}Unmounting $BRroot"
  sleep 1
  OUTPUT=$(umount $BRroot 2>&1) && (ok_status && rm_work_dir) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
  exit
}

unset_vars() {
  if [ "$BRswap" = "-1" ]; then unset BRswap; fi
  if [ "$BRboot" = "-1" ]; then unset BRboot; fi
  if [ "$BRhome" = "-1" ]; then unset BRhome; fi
  if [ "$BRgrub" = "-1" ]; then unset BRgrub; fi
  if [ "$BRsyslinux" = "-1" ]; then unset BRsyslinux; fi
}

BRargs=`getopt -o "i:r:s:b:h:g:S:f:u:n:p:R:qtoNm:k:c:a:O:" -l "interface:,root:,swap:,boot:,home:,grub:,syslinux:,file:,url:,username:,password:,help,quiet,rootsubvolname:,transfer,only-hidden,no-color,mount-options:,kernel-options:,custom-partitions:,archiver:,other-subvolumes:" -n "$1" -- "$@"`

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
    -u|--url)
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
      BRrootsubvol="y"
      BRrootsubvolname=$2
      shift 2
    ;;
    -t|--transfer)
      BRmode="Transfer"
      BRrestore="off"
      shift
    ;;
    -o|--only-hidden)
      BRhidden="y"
      shift
    ;;
    -N|--no-color)
      BRnocolor="y"
      shift
    ;;
    -m|--mount-options)
      BRmountoptions="Yes"
      BR_MOUNT_OPTS=$2
      shift 2
    ;;
    -k|--kernel-options)
      BR_KERNEL_OPTS=$2
      shift 2
    ;;
    -c|--custom-partitions)
      BRcustom="y"
      BRother="y"
      BRcustomparts=($2)
      BRcustomold="$2"
      shift 2
    ;;
    -a|--archiver)
      BRarchiver=$2
      shift 2
    ;;
    -O|--other-subvolumes)
      BRsubvolother="y"
      BRsubvols=($2)
      shift 2
    ;;
    --help)
    BR_BOLD='\033[1m'
    BR_NORM='\e[00m'
    echo -e "
${BR_BOLD}$BR_VERSION

Interface:${BR_NORM}
  -i,  --interface          interface to use (cli dialog)
  -N,  --no-color           disable colors
  -q,  --quiet              dont ask, just run

${BR_BOLD}Restore Mode:${BR_NORM}
  -f,  --file               backup file path or url
  -n,  --username           username
  -p,  --password           password
  -a,  --archiver           select archiver (tar bsdtar)
  -u,  --url                same as -f (for compatibility)

${BR_BOLD}Transfer Mode:${BR_NORM}
  -t,  --transfer           activate transfer mode
  -o,  --only-hidden        transfer /home's hidden files and folders only

${BR_BOLD}Partitions:${BR_NORM}
  -r,  --root               target root partition
  -h,  --home               target home partition
  -b,  --boot               target boot partition
  -s,  --swap               swap partition
  -c,  --custom-partitions  specify custom partitions (mountpoint=device)
  -m,  --mount-options      comma-separated list of mount options (root partition)

${BR_BOLD}Bootloader:${BR_NORM}
  -g,  --grub               target disk for grub
  -S,  --syslinux           target disk for syslinux
  -k,  --kernel-options     additional kernel options (syslinux)

${BR_BOLD}Btrfs Subvolumes:${BR_NORM}
  -R,  --rootsubvolname     subvolume name for /
  -O,  --other-subvolumes   specify other subvolumes (subvolume path e.g /home /var /usr ...)

--help  print this page
"
      unset BR_BOLD BR_NORM
      exit
      shift
    ;;
    --)
      shift
      break
    ;;
  esac
done

if [[ "$BRuri" == /* ]]; then
  BRfile="$BRuri"
else
  BRurl="$BRuri"
fi

if [ -z "$BRnocolor" ]; then
  color_variables
fi

BR_WRK="[${BR_CYAN}WORKING${BR_NORM}] "
DEFAULTIFS=$IFS
IFS=$'\n'

if [ -n "$BRhome" ]; then
  BRcustom="y"
  BRcustomparts+=(/home="$BRhome")
fi

if [ -n "$BRboot" ]; then
  BRcustom="y"
  BRcustomparts+=(/boot="$BRboot")
fi

check_input

if [ -n "$BRroot" ]; then
  if [ -z "$BRrootsubvolname" ]; then
    BRrootsubvol="n"
  fi

  if [ -z "$BRother" ]; then
    BRother="n"
  fi

  if [ -z "$BRmountoptions" ]; then
    BRmountoptions="No"
    BR_MOUNT_OPTS="defaults"
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

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    BRgrub="-1"
    BRsyslinux="-1"
  fi

  if [ -z "$BRuri" ] && [ -z "$BRrestore" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify a backup file or enable transfer mode"
    exit
  fi
fi

if [ "$BRmode" = "Transfer" ] && [ -z "$BRhidden" ]; then
  BRhidden="n"
fi

if [ -n "$BRrootsubvol" ]; then
  if [ -z "$BRsubvolother" ]; then
    BRsubvolother="n"
  fi
fi

if [ "$BRgrub" = "-1" ] && [ "$BRsyslinux" = "-1" ] && [ -n "$BR_KERNEL_OPTS" ]; then
  echo -e "[${BR_YELLOW}WARNING${BR_NORM}] No bootloader selected, skipping kernel options"
elif [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -n "$BR_KERNEL_OPTS" ]; then
  echo -e "[${BR_YELLOW}WARNING${BR_NORM}] No bootloader selected, skipping kernel options"
fi

if [ -n "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -n "$BR_KERNEL_OPTS" ]; then
  echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Grub selected, skipping kernel options"
fi

if [ $(id -u) -gt 0 ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Script must run as root"
  exit
fi

if [ -z "$(check_parts 2>/dev/null)" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] No partitions found"
  exit
fi

if [ -d /mnt/target ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] /mnt/target exists, aborting"
  exit
fi

if [ -f /etc/pacman.conf ]; then
  PATH="$PATH:/usr/sbin:/bin"
fi

PS3="Enter number or Q to quit: "

echo -e "\n${BR_BOLD}$BR_VERSION${BR_NORM}"

if [ -z "$BRinterface" ]; then
  echo -e "\n${BR_CYAN}Select interface:${BR_NORM}"
  select c in "CLI" "Dialog"; do
    if [ $REPLY = "q" ] || [ $REPLY = "Q" ]; then
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

  if [ -z "$BRrestore" ] && [ -z "$BRuri" ]; then
    info_screen
    read -s a
  fi

  partition_list=(
   `for f in $(find /dev -regex "/dev/[hs]d[a-z][0-9]+"); do echo -e "$f $(lsblk -d -n -o size $f)"; done | sort
    for f in $(find /dev/mapper/ | grep '-'); do echo -e "$f $(lsblk -d -n -o size $f)"; done
    for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo -e "$f $(lsblk -d -n -o size $f)"; done`
  )

  disk_list=(`disk_list_dialog`)

  editorlist=(nano vi)
  list=(`echo "${partition_list[*]}" | hide_used_parts`)

  if [ -z "$BRroot" ]; then
    echo -e "\n${BR_CYAN}Select target root partition:${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRroot=(`echo $c | awk '{ print $1 }'`)
        echo -e "${BR_GREEN}You selected $BRroot as your root partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ -z "$BRmountoptions" ]; then
    echo -e "\n${BR_CYAN}Enter additional mount options (leave blank for defaults)${BR_NORM}"
    read -p "Options (comma-separated list): " BR_MOUNT_OPTS
    if [ -z "$BR_MOUNT_OPTS" ]; then
      BRmountoptions="No"
      BR_MOUNT_OPTS="defaults"
    elif [ -n "$BR_MOUNT_OPTS" ]; then
      BRmountoptions="Yes"
    fi
  fi

  detect_root_fs_size

  if [ -z "$BRfsystem" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Unknown root file system"
    exit
  fi

  if [ "$BRfsystem" = "btrfs" ]; then
    while [ -z "$BRrootsubvol" ]; do
      echo -e "\n${BR_CYAN}BTRFS root file system detected. Create subvolume for root?${BR_NORM}"
      read -p "(Y/n):" an

      if [ -n "$an" ]; then
        btrfsdef=$an
      else
        btrfsdef="y"
      fi

      if [ "$btrfsdef" = "y" ] || [ "$btrfsdef" = "Y" ]; then
        BRrootsubvol="y"
      elif [ "$btrfsdef" = "n" ] || [ "$btrfsdef" = "N" ]; then
        BRrootsubvol="n"
      else
        echo -e "${BR_RED}Please select a valid option${BR_NORM}"
      fi
    done

    if [ "$BRrootsubvol" = "y" ]; then
      while [ -z "$BRrootsubvolname" ]; do
        read -p "Enter subvolume name: " BRrootsubvolname
        echo "Subvolume name: $BRrootsubvolname"
        if [ -z "$BRrootsubvolname" ]; then
          echo -e "\n${BR_CYAN}Please enter a name for the subvolume.${BR_NORM}"
        fi
      done

      if [ -z "$BRsubvolother" ]; then
        echo -e "\n${BR_CYAN}Set other subvolumes (leave blank for none)${BR_NORM}"
        read -p "Paths (e.g /home /var /usr ...): " BRsubvolslist
        if [ -z "$BRsubvolslist" ]; then
          BRsubvolother="n"
        elif [ -n "$BRsubvolslist" ]; then
          BRsubvolother="y"
          IFS=$DEFAULTIFS
          BRsubvols+=($BRsubvolslist)
          IFS=$'\n'
          for item in "${BRsubvols[@]}"; do
            if [[ "$item" == *"/home"* ]]; then BRhome="-1"; fi
            if [[ "$item" == *"/boot"* ]]; then BRboot="-1"; fi
          done
        fi
      fi
    fi
  elif [ "$BRrootsubvol" = "y" ] || [ "$BRsubvolother" = "y" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Not a btrfs root filesystem, proceeding without subvolumes..."
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts`)

  if [ -z "$BRhome" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select target home partition: \n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRhome=(`echo $c | awk '{ print $1 }'`)
        BRcustom="y"
        BRcustomparts+=(/home="$BRhome")
        echo -e "${BR_GREEN}You selected $BRhome as your home partition${BR_NORM}"
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "${BR_GREEN}No home partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts`)

  if [ -z "$BRboot" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select target boot partition: \n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRboot=(`echo $c | awk '{ print $1 }'`)
        BRcustom="y"
        BRcustomparts+=(/boot="$BRboot")
        echo -e "${BR_GREEN}You selected $BRboot as your boot partition${BR_NORM}"
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "${BR_GREEN}No boot partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts`)

  if [ -z "$BRswap" ] && [ -n "${list[*]}" ]; then
    echo -e "\n${BR_CYAN}Select swap partition: \n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRswap=(`echo $c | awk '{ print $1 }'`)
        echo -e "${BR_GREEN}You selected $BRswap as your swap partition${BR_NORM}"
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "${BR_GREEN}No swap partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  list=(`echo "${partition_list[*]}" | hide_used_parts`)

  if [ -n "${list[*]}" ]; then
    if [ -z "$BRother" ]; then
      echo -e "\n${BR_CYAN}Specify custom partitions: mountpoint=device e.g /var=/dev/sda3 (leave blank for none)${BR_NORM}"
      read -p "Partitions: " BRcustompartslist
      if [ -z "$BRcustompartslist" ]; then
        BRother="n"
      elif [ -n "$BRcustompartslist" ]; then
        BRcustom="y"
        BRother="y"
        IFS=$DEFAULTIFS
        BRcustomparts+=($BRcustompartslist)
        IFS=$'\n'
      fi
    fi
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    echo -e "\n${BR_CYAN}Select bootloader: \n${BR_MAGENTA}(Optional - Enter C to skip)${BR_NORM}"
    select c in Grub Syslinux; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
       	exit
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "\n[${BR_YELLOW}WARNING${BR_NORM}] NO BOOTLOADER SELECTED"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        echo -e "\n${BR_CYAN}Select target disk for Grub:${BR_NORM}"
	select c in ${disk_list[@]}; do
	  if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
            echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
	    exit
	  elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#disk_list[@]} ]; then
	    BRgrub=(`echo $c | awk '{ print $1 }'`)
            echo -e "${BR_GREEN}You selected $BRgrub to install Grub${BR_NORM}"
	    break
	  else
            echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
	  fi
	done
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        echo -e "\n${BR_CYAN}Select target disk Syslinux:${BR_NORM}"
	select c in ${disk_list[@]}; do
	if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
          echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
	  exit
	elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#disk_list[@]} ]; then
	  BRsyslinux=(`echo $c | awk '{ print $1 }'`)
          echo -e "${BR_GREEN}You selected $BRsyslinux to install Syslinux${BR_NORM}"
	  echo -e "\n${BR_CYAN}Enter additional kernel options (leave blank for defaults)${BR_NORM}"
          read -p "Options:" BR_KERNEL_OPTS
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
  fi

  unset_vars

  if [ -z "$BRmode" ]; then
    echo -e "\n${BR_CYAN}Select Mode:${BR_NORM}"
    select c in "Restore system from backup file" "Transfer this system with rsync"; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        echo -e "${BR_GREEN}You selected Restore Mode${BR_NORM}"
        BRmode="Restore"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        echo -e "${BR_GREEN}You selected Transfer Mode${BR_NORM}"
        BRmode="Transfer"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ "$BRmode" = "Restore" ]; then
    if [ -z "$BRarchiver" ]; then
      echo -e "\n${BR_CYAN}Select the archiver you used to create the backup archive:${BR_NORM}"
      select c in "tar (GNU Tar)" "bsdtar (Libarchive Tar)"; do
        if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
          echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
          exit
        elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
          BRarchiver="tar"
          echo -e "${BR_GREEN}You selected $BRarchiver${BR_NORM}"
          break
        elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
          BRarchiver="bsdtar"
          echo -e "${BR_GREEN}You selected $BRarchiver${BR_NORM}"
          break
        else
          echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
        fi
      done
    fi
  fi

  if [ "$BRmode" = "Transfer" ]; then
    while [ -z "$BRhidden" ]; do
      echo -e "\n${BR_CYAN}Transfer entire /home directory?\n(If no, only hidden files and folders will be transferred)${BR_NORM}"
      read -p "(Y/n):" an

      if [ -n "$an" ]; then
        def=$an
      else
        def="y"
      fi

      if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
        BRhidden="n"
      elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
        BRhidden="y"
      else
        echo -e "${BR_RED}Please select a valid option${BR_NORM}"
      fi
    done
  fi

  check_input
  mount_all

  if [ "$BRmode" = "Restore" ]; then
    echo -e "\n${BR_SEP}GETTING TAR IMAGE"
    if [ -n "$BRfile" ]; then
      echo -ne "${BR_WRK}Symlinking file"
      OUTPUT=$(ln -s "$BRfile" "/mnt/target/fullbackup" 2>&1) && ok_status || error_status
    fi

    if [ -n "$BRurl" ]; then
      if [ -n "$BRusername" ]; then
        wget --user="$BRusername" --password="$BRpassword" -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error
      else
        wget -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error
      fi
      check_wget
    fi

    if [ -f /mnt/target/fullbackup ]; then
      ($BRarchiver tf /mnt/target/fullbackup || touch /tmp/tar_error) | tee /tmp/filelist |
      while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done
      check_archive
    fi

    while [ ! -f /mnt/target/fullbackup ]; do
      echo -e "\n${BR_CYAN}Select backup file. Choose an option:${BR_NORM}"
      select c in "Local File" "URL" "Protected URL"; do
        if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
          echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
          clean_unmount_in
        elif [ "$REPLY" = "1" ]; then
          unset BRurl
          echo -e "\n${BR_CYAN}Enter the path of the backup file${BR_NORM}"
          IFS=$DEFAULTIFS
          read -e -p "Path:" BRfile
          IFS=$'\n'
          if [ ! -f "$BRfile" ] || [ -z "$BRfile" ]; then
            echo -e "[${BR_RED}ERROR${BR_NORM}] File not found"
          else
            detect_filetype
            if [ "$BRfiletype" = "gz" ] || [ "$BRfiletype" = "xz" ]; then
              echo -ne "${BR_WRK}Symlinking file"
              OUTPUT=$(ln -s $BRfile "/mnt/target/fullbackup" 2>&1) && ok_status || error_status
            else
              echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type"
            fi
	  fi
          break

        elif [ "$REPLY" = "2" ] || [ "$REPLY" = "3" ]; then
          unset BRfile
          echo -e "\n${BR_CYAN}Enter the URL for the backup file${BR_NORM}"
          read -p "URL:" BRurl
          echo " "
          if [ "$REPLY" = "3" ]; then
	    read -p "USERNAME: " BRusername
            read -p "PASSWORD: " BRpassword
	    wget --user="$BRusername" --password="$BRpassword" -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error
            check_wget
            break
          elif [ "$REPLY" = "2" ]; then
            wget -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error
            check_wget
            break
          fi
        else
          echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
        fi
      done

      if [ -f /mnt/target/fullbackup ]; then
        ($BRarchiver tf /mnt/target/fullbackup || touch /tmp/tar_error) | tee /tmp/filelist |
        while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done
        check_archive
      fi
    done
  fi

  detect_distro
  set_bootloader
  echo -e "\n${BR_SEP}SUMMARY"
  show_summary

  while [ -z "$BRcontinue" ]; do
    echo -e "\n${BR_CYAN}Continue?${BR_NORM}"
    read -p "(Y/n):" an

    if [ -n "$an" ]; then
      def=$an
    else
      def="y"
    fi

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

  echo "--------------$(date +%d-%m-%Y-%T)--------------" >> /tmp/restore.log
  echo " " >> /tmp/restore.log
  if [ "$BRmode" = "Restore" ]; then
    echo -e "\n${BR_SEP}EXTRACTING"
    total=$(cat /tmp/filelist | wc -l)
    sleep 1

    if [ "$BRarchiver" = "tar" ]; then
      run_tar 2>>/tmp/restore.log
    elif [ "$BRarchiver" = "bsdtar" ]; then
      run_tar | tee /tmp/bsdtar_out
    fi | while read ln; do a=$(( a + 1 )) && echo -en "\rDecompressing: $(($a*100/$total))%"; done

    if [ "$BRarchiver" = "bsdtar" ] && [ -f /tmp/r_error ]; then
      cat /tmp/bsdtar_out >> /tmp/restore.log
    fi

    echo " "
  elif [ "$BRmode" = "Transfer" ]; then
    echo -e "\n${BR_SEP}TRANSFERING"
    run_calc | while read ln; do a=$(( a + 1 )) && echo -en "\rCalculating: $a Files"; done
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    echo " "
    run_rsync 2>>/tmp/restore.log | while read ln; do b=$(( b + 1 )) && echo -en "\rSyncing: $(($b*100/$total))%"; done
    echo " "
  fi

  echo -e "\n${BR_SEP}GENERATING FSTAB"
  generate_fstab
  cat /mnt/target/etc/fstab

  while [ -z "$BRedit" ] ; do
    echo -e "\n${BR_CYAN}Edit fstab?${BR_NORM}"
    read -p "(y/N):" an

    if [ -n "$an" ]; then
      def=$an
    else
      def="n"
    fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRedit="y"
    elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
      BRedit="n"
    else
      echo -e "${BR_RED}Please select a valid option${BR_NORM}"
    fi
  done

  if [ "$BRedit" = "y" ]; then
    echo -e "\n${BR_CYAN}Select editor${BR_NORM}"
    select c in ${editorlist[@]}; do
      if [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#editorlist[@]} ]; then
        BReditor=$c
        $BReditor /mnt/target/etc/fstab
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
    exit_screen; read -s a
  else
    exit_screen_quiet
  fi
  sleep 1
  clean_unmount_out

elif [ "$BRinterface" = "dialog" ]; then
  partition_list=(
   `for f in $(find /dev -regex "/dev/[hs]d[a-z][0-9]+"); do echo -e "$f $(lsblk -d -n -o size $f)|$(blkid -s TYPE -o value $f)"; done | sort
    for f in $(find /dev/mapper/ | grep '-'); do echo -e "$f $(lsblk -d -n -o size $f)|$(blkid -s TYPE -o value $f)"; done
    for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo -e "$f $(lsblk -d -n -o size $f)|$(blkid -s TYPE -o value $f)"; done`
  )

  IFS=$DEFAULTIFS

  if [ -z $(which dialog 2> /dev/null) ];then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package dialog is not installed. Install the package and re-run the script"
    exit
  fi

  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD

  if [ -z "$BRrestore" ] && [ -z "$BRuri" ]; then
    dialog --yes-label "Continue" --no-label "View Partition Table" --title "$BR_VERSION" --yesno "$(info_screen)" 17 80
    if [ "$?" = "1" ]; then
      dialog --title "Partition Table" --msgbox "$(disk_report)" 0 0
    fi
  fi

  exec 3>&1

  update_list() {
    IFS=$'\n'
    list=(`echo "${partition_list[*]}" | hide_used_parts`)
    IFS=$DEFAULTIFS
  }

  update_list

  update_options() {
    options=("Root partition" "$BRroot" \
    "(Optional) Home partition" "$BRhome" \
    "(Optional) Boot partition" "$BRboot" \
    "(Optional) Swap partition" "$BRswap" \
    "(Optional) Custom partitions" "$BRempty" \
    "Done with partitions" "$BRempty")
  }

  update_options

  while [ -z "$BRroot" ]; do
    BRassign="y"
    while opt=$(dialog --ok-label Select --cancel-label Quit --extra-button --extra-label Unset --menu "Set target partitions:" 0 0 0 "${options[@]}" 2>&1 1>&3); rtn="$?"; do
      if [ "$rtn" = "1" ]; then exit; fi
      BRrootold="$BRroot" BRhomeold="$BRhome" BRbootold="$BRboot" BRswapold="$BRswap"
      case "$opt" in
        "${options[0]}" )
            if [ "$rtn" = "3" ]; then unset BRroot; elif [ -z "${list[*]}" ]; then no_parts; else BRroot=$(part_sel_dialog root); if [ "$?" = "1" ]; then BRroot="$BRrootold"; fi; fi
            update_list
            update_options;;
        "${options[2]}" )
            if [ "$rtn" = "3" ]; then unset BRhome; elif [ -z "${list[*]}" ]; then no_parts; else BRhome=$(part_sel_dialog home); if [ "$?" = "1" ]; then BRhome="$BRhomeold"; fi; fi
            update_list
            update_options;;
        "${options[4]}" )
            if [ "$rtn" = "3" ]; then unset BRboot; elif [ -z "${list[*]}" ]; then no_parts; else BRboot=$(part_sel_dialog boot); if [ "$?" = "1" ]; then BRboot="$BRbootold"; fi; fi
            update_list
            update_options;;
        "${options[6]}" )
            if [ "$rtn" = "3" ]; then unset BRswap; elif [ -z "${list[*]}" ]; then no_parts; else BRswap=$(part_sel_dialog swap); if [ "$?" = "1" ]; then BRswap="$BRswapold"; fi; fi
            update_list
            update_options;;
        "${options[8]}" )
            if [ "$rtn" = "3" ]; then unset BRcustompartslist BRcustomold; elif [ -z "${list[*]}" ]; then no_parts; else set_custom; fi
            update_options;;
        "${options[10]}" )
            if [ ! "$rtn" = "3" ]; then break; fi
        ;;
      esac
    done

    if [ -z "$BRroot" ]; then
      dialog --title "Error" --msgbox "You must specify a target root partition." 5 45
    fi
  done

  if [ -n "$BRassign" ]; then
    if [ -n "$BRhome" ]; then
      BRcustom="y"
      BRcustomparts+=(/home="$BRhome")
    fi

    if [ -n "$BRboot" ]; then
      BRcustom="y"
      BRcustomparts+=(/boot="$BRboot")
    fi

    if [ -n "$BRcustompartslist" ]; then
      BRcustom="y"
      BRother="y"
      BRcustomparts+=($BRcustompartslist)
    fi
  fi

  if [ -z "$BRmountoptions" ]; then
    BR_MOUNT_OPTS=$(dialog --no-cancel --inputbox "Specify additional mount options for root partition.\nLeave empty for defaults.\n\n(comma-separated list)" 10 70 2>&1 1>&3)
    if [ -z "$BR_MOUNT_OPTS" ]; then
      BRmountoptions="No"
      BR_MOUNT_OPTS="defaults"
    elif [ -n "$BR_MOUNT_OPTS" ]; then
      BRmountoptions="Yes"
    fi
  fi

  detect_root_fs_size

  if [ -z "$BRfsystem" ]; then
    if [ -z "$BRnocolor" ]; then color_variables; fi
    echo -e "[${BR_RED}ERROR${BR_NORM}] Unknown root file system"
    exit
  fi

  if [ "$BRfsystem" = "btrfs" ]; then
    if [ -z "$BRrootsubvol" ]; then
      dialog --yesno "BTRFS root file system detected. Create subvolume for root?" 5 68
      if [ "$?" = "0" ]; then
        BRrootsubvol="y"
      else
        BRrootsubvol="n"
      fi
    fi

    if [ "$BRrootsubvol" = "y" ]; then
      while [ -z "$BRrootsubvolname" ]; do
        BRrootsubvolname=$(dialog --no-cancel --inputbox "Enter subvolume name:" 8 50 2>&1 1>&3)
        if [ -z "$BRrootsubvolname" ]; then
          dialog --title "Warning" --msgbox "Please enter a name for the subvolume." 5 42
        fi
      done

      if [ -z "$BRsubvolother" ]; then
        BRsubvolslist=$(dialog --no-cancel --inputbox "Specify other subvolumes. Leave empty for none.\n\n(subvolume path e.g /home /var /usr ...)" 9 70 2>&1 1>&3)
        if [ -z "$BRsubvolslist" ]; then
          BRsubvolother="n"  
        elif [ -n "$BRsubvolslist" ]; then
          BRsubvolother="y"
          BRsubvols+=($BRsubvolslist)
          for item in "${BRsubvols[@]}"; do
            if [[ "$item" == *"/home"* ]]; then BRhome="-1"; fi
            if [[ "$item" == *"/boot"* ]]; then BRboot="-1"; fi
          done
        fi
      fi
    fi
  elif [ "$BRrootsubvol" = "y" ] || [ "$BRsubvolother" = "y" ]; then
    dialog --title "Warning" --msgbox "Not a btrfs root filesystem, press ok to proceed without subvolumes." 5 72
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    REPLY=$(dialog --cancel-label Skip --extra-button --extra-label Quit --menu "Select bootloader:" 10 0 10 1 Grub 2 Syslinux 2>&1 1>&3)
    if [ "$?" = "3" ]; then exit; fi

    if [ "$REPLY" = "1" ]; then
      BRgrub=$(dialog --cancel-label Quit --menu "Set target disk for Grub:" 0 0 0 `disk_list_dialog` 2>&1 1>&3)
      if [ "$?" = "1" ]; then exit; fi
    elif [ "$REPLY" = "2" ]; then
      BRsyslinux=$(dialog --cancel-label Quit --menu "Set target disk for Syslinux:" 0 35 0 `disk_list_dialog` 2>&1 1>&3)
      if [ "$?" = "1" ]; then
        exit
      else
         BR_KERNEL_OPTS=$(dialog --no-cancel --inputbox "Specify additional kernel options. Leave empty for defaults." 8 70 2>&1 1>&3)
       fi
    fi
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    dialog --title "Warning" --msgbox "No bootloader selected, press ok to continue." 5 49
  fi

  unset_vars

  if [ -z "$BRmode" ]; then
    BRmode=$(dialog --cancel-label Quit --menu "Select Mode:" 12 50 12 Restore "system from backup file" Transfer "this system with rsync" 2>&1 1>&3)
    if [ "$?" = "1" ]; then exit; fi
  fi

  if [ "$BRmode" = "Restore" ]; then
    if [ -z "$BRarchiver" ]; then
      BRarchiver=$(dialog --no-cancel --menu "Select the archiver you used to create the backup archive:" 12 45 12 tar "GNU Tar" bsdtar "Libarchive Tar" 2>&1 1>&3)
    fi
  fi

  if [ "$BRmode" = "Transfer" ]; then
    if [ -z "$BRhidden" ]; then
      dialog --yesno "Transfer entire /home directory?\n\nIf No, only hidden files and folders will be transferred" 9 50
      if [ "$?" = "0" ]; then
        BRhidden="n"
      else
        BRhidden="y"
      fi
    fi
  fi

  IFS=$'\n'
  if [ -z "$BRnocolor" ]; then
    color_variables
  fi

  check_input
  mount_all
  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD

  if [ "$BRmode" = "Restore" ]; then
    if [ -n "$BRfile" ]; then
      ln -s "${BRfile[@]}" "/mnt/target/fullbackup" 2> /dev/null || dialog --title "Error" --msgbox "Error symlinking file." 5 26
    fi

    if [ -n "$BRurl" ]; then
      BRurlold="$BRurl"
      if [ -n "$BRusername" ]; then
       (wget --user="$BRusername" --password="$BRpassword" -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error) 2>&1 |
        sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | count_gauge_wget | dialog --gauge "Downloading..." 0 50
      else
       (wget -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error) 2>&1 |
        sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | count_gauge_wget | dialog --gauge "Downloading..." 0 50
      fi
      check_wget
    fi

    if [ -f /mnt/target/fullbackup ]; then
      ($BRarchiver tf /mnt/target/fullbackup 2>&1 || touch /tmp/tar_error) | tee /tmp/filelist |
      while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done | dialog --progressbox 3 40
      sleep 1
      check_archive
    fi

    while [ ! -f /mnt/target/fullbackup ]; do
      REPLY=$(dialog --cancel-label Quit --menu "Select backup file. Choose an option:" 13 50 13 File "local file" URL "remote file" "Protected URL" "protected remote file" 2>&1 1>&3)
      if [ "$?" = "1" ]; then
        clean_unmount_in

      elif [ "$REPLY" = "File" ]; then
        unset BRurl BRfile BRselect
        BRpath=/
        IFS=$DEFAULTIFS
        while [ -z "$BRfile" ]; do
          show_path
          BRselect=$(dialog --title "$BRcurrentpath" --menu "Select backup archive:" 30 90 30 "<--UP" .. $(file_list) 2>&1 1>&3)
          if [ "$?" = "1" ]; then
            break
          fi
          BRselect="/$BRselect"
          if [ -f "$BRpath${BRselect//\\/ }" ]; then
            BRfile="$BRpath${BRselect//\\/ }"
            BRfile="${BRfile#*/}"
            detect_filetype
            if [ "$BRfiletype" = "gz" ] || [ "$BRfiletype" = "xz" ]; then
              ln -s "$BRfile" "/mnt/target/fullbackup" 2> /dev/null || touch /tmp/ln_error
              if [ -f /tmp/ln_error ]; then
                rm /tmp/ln_error
                unset BRfile BRselect
                dialog --title "Error" --msgbox "Error symlinking file." 5 26
              fi
            else
              dialog --title "Error" --msgbox "Invalid file type." 5 22
              unset BRfile BRselect
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
        unset BRfile
        BRurl=$(dialog --no-cancel --inputbox "Enter the URL for the backup file:" 8 50 "$BRurlold" 2>&1 1>&3)
        BRurlold="$BRurl"
        if [ "$REPLY" = "Protected URL" ]; then
          BRusername=$(dialog --no-cancel --inputbox "Username:" 8 50 2>&1 1>&3)
          BRpassword=$(dialog --no-cancel --insecure --passwordbox "Password:" 8 50 2>&1 1>&3)
         (wget --user="$BRusername" --password="$BRpassword" -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error) 2>&1 |
          sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | count_gauge_wget | dialog --gauge "Downloading..." 0 50
        elif [ "$REPLY" = "URL" ]; then
         (wget -O /mnt/target/fullbackup "$BRurl" --tries=2 || touch /tmp/wget_error) 2>&1 |
          sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | count_gauge_wget | dialog --gauge "Downloading..." 0 50
        fi
        check_wget
      fi
      if [ -f /mnt/target/fullbackup ]; then
        ($BRarchiver tf /mnt/target/fullbackup 2>&1 || touch /tmp/tar_error) | tee /tmp/filelist |
        while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done | dialog --progressbox 3 40
        sleep 1
        check_archive
      fi
    done
  fi

  detect_distro
  set_bootloader

  if [ -z "$BRcontinue" ]; then
    dialog --title "Summary" --yes-label "OK" --no-label "Quit" --yesno "$(show_summary) $(echo -e "\n\nPress OK to continue, or Quit to abort.")" 0 0
    if [ "$?" = "1" ]; then
      clean_unmount_in
    fi
  fi

  echo "--------------$(date +%d-%m-%Y-%T)--------------" >> /tmp/restore.log
  echo " " >> /tmp/restore.log
  if [ "$BRmode" = "Restore" ]; then
    total=$(cat /tmp/filelist | wc -l)
    sleep 1

    if [ "$BRarchiver" = "tar" ]; then
      run_tar 2>>/tmp/restore.log
    elif [ "$BRarchiver" = "bsdtar" ]; then
      run_tar | tee /tmp/bsdtar_out
    fi | count_gauge | dialog --gauge "Decompressing..." 0 50

    if [ "$BRarchiver" = "bsdtar" ] && [ -f /tmp/r_error ]; then
      cat /tmp/bsdtar_out >> /tmp/restore.log
    fi

  elif [ "$BRmode" = "Transfer" ]; then
    run_calc | while read ln; do a=$(( a + 1 )) && echo -en "\rCalculating: $a Files"; done | dialog --progressbox 3 40
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    run_rsync 2>>/tmp/restore.log | count_gauge | dialog --gauge "Syncing..." 0 50
  fi

  generate_fstab

  if [ -n "$BRedit" ]; then
    cat /mnt/target/etc/fstab | dialog --title "GENERATING FSTAB" --progressbox 20 100
    sleep 2
  else
    dialog --title "GENERATING FSTAB" --yesno "$(echo -e "Edit fstab? Generated fstab:\n\n`cat /mnt/target/etc/fstab`")" 13 100
    if [ "$?" = "0" ]; then
      REPLY=$(dialog --no-cancel --menu "Select editor:" 10 25 10 1 nano 2 vi 2>&1 1>&3)
      if [ "$REPLY" = "1" ]; then
        BReditor="nano"
      elif [ "$REPLY" = "2" ]; then
        BReditor="vi"
      fi
      $BReditor /mnt/target/etc/fstab
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
    if [ "$?" = "1" ]; then dialog --textbox /tmp/restore.log 0 0; fi
  else
    dialog --title "$diag_tl" --infobox "$(exit_screen_quiet)" 0 0
  fi

  sleep 1
  clean_unmount_out
fi
