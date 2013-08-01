#!/bin/bash

BR_VERSION="System Tar & Restore 3.6"
BR_SEP="::"

clear

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
  echo -e "This script will restore a backup image of your system or transfer this\nsystem in user defined partitions."
  echo -e "\n==>Make sure you have created and formatted at least one partition\n   for root (/) and optionally partitions for /home and /boot."
  echo -e "\n==>Make sure that target LVM volume groups are activated and target\n   RAID arrays are properly assembled."
  echo -e "\n==>If you didn't include /home directory in the backup\n   and you already have a seperate /home partition,\n   simply enter it when prompted."
  echo -e "\n==>Also make sure that this system and the system you want\n   to restore have the same architecture (for chroot to work)."
  echo -e "\n==>Fedora backups can only be restored from a Fedora enviroment,\n   due to extra tar options."
  echo -e "\n${BR_CYAN}Press ENTER to continue.${BR_NORM}"
}

instruct_screen(){
  echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log"
  echo -e "\n${BR_YELLOW}No bootloader found, so this is the right time to install and\nupdate one. To do so:"
  echo -e "\n==>For internet connection to work, on a new terminal with root\n   access enter: cp -L /etc/resolv.conf /mnt/target/etc/resolv.conf"
  echo -e "\n==>Then chroot into the restored system: chroot /mnt/target"
  echo -e "\n==>Install and update a bootloader"
  echo -e "\n==>When done, leave chroot: exit"
  echo -e "\n==>Finally, return to this window and press ENTER to unmount\n   all remaining (engaged) devices.${BR_NORM}"
}

ok_status() {
  echo -e "[${BR_GREEN}OK${BR_NORM}]"
}

error_status() {
  echo -e "[${BR_RED}FAILED${BR_NORM}]\n$OUTPUT"
  BRSTOP=y
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
    BRcurrentpath=/
  else
    BRcurrentpath="${BRpath#*/}/"
  fi
}

detect_parts_fs_size() {
  BRfsystem=$(df -T | grep $BRroot | awk '{print $2}')
  BRfsize=$(lsblk -d -n -o size 2> /dev/null $BRroot)

  if [ -n "$BRhome" ]; then
    BRhomefsystem=$(df -T | grep $BRhome | awk '{print $2}')
    BRhomefsize=$(lsblk -d -n -o size 2> /dev/null $BRhome)
  fi

  if [ -n "$BRboot" ]; then
    BRbootfsystem=$(df -T | grep $BRboot | awk '{print $2}')
    BRbootfsize=$(lsblk -d -n -o size 2> /dev/null $BRboot)
  fi
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

detect_filetype_url() {
  if file /mnt/target/fullbackup | grep -w gzip > /dev/null; then
    BRfiletype="gz"
  elif file /mnt/target/fullbackup | grep -w XZ > /dev/null; then
    BRfiletype="xz"
  else
    BRfiletype="wrong"
  fi
}

detect_distro() {
  if [ -f /mnt/target/etc/yum.conf ]; then
    BRdistro="Fedora"
  elif [ -f /mnt/target/etc/pacman.conf ]; then
    BRdistro="Arch"
  elif [ -f /mnt/target/etc/apt/sources.list ]; then
    BRdistro="Debian"
  fi
}

detect_syslinux_root() {
  if [[ "$BRroot" == *mapper* ]]; then
    echo "root=$BRroot"
  else
    echo "root=UUID=$(lsblk -d -n -o uuid $BRroot)"
  fi
}

detect_fstab_root() {
  if [[ "$BRroot" == *dev/md* ]]; then
    echo "$BRroot"
  else
    echo "UUID=$(lsblk -d -n -o uuid $BRroot)"
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
  if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
    syslinuxrootsubvol="rootflags=subvol=$BRrootsubvolname"
  fi
  for BRinitrd in `find /mnt/target/boot -name vmlinuz* | sed 's_/mnt/target/boot/vmlinuz-*__'` ; do
    if [ $BRdistro = Arch ]; then
      echo -e "LABEL arch\n\tMENU LABEL Arch $BRinitrd\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS ro\n\tINITRD ../initramfs-$BRinitrd.img" >> /mnt/target/boot/syslinux/syslinux.cfg
      echo -e "LABEL archfallback\n\tMENU LABEL Arch $BRinitrd fallback\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS ro\n\tINITRD ../initramfs-$BRinitrd-fallback.img" >> /mnt/target/boot/syslinux/syslinux.cfg
    elif [ $BRdistro = Debian ]; then
      echo -e "LABEL debian\n\tMENU LABEL Debian-$BRinitrd\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS ro quiet\n\tINITRD ../initrd.img-$BRinitrd" >> /mnt/target/boot/syslinux/syslinux.cfg
    elif [ $BRdistro = Fedora ]; then
      echo -e "LABEL fedora\n\tMENU LABEL Fedora-$BRinitrd\n\tLINUX ../vmlinuz-$BRinitrd\n\tAPPEND $(detect_syslinux_root) $syslinuxrootsubvol $BR_KERNEL_OPTS ro quiet\n\tINITRD ../initramfs-$BRinitrd.img" >> /mnt/target/boot/syslinux/syslinux.cfg
    fi
  done
}

set_archiver() {
  if [ "$BRarchiver" = "TAR" ]; then
BR_ARC="tar"
  elif [ "$BRarchiver" = "BSDTAR" ]; then
BR_ARC="bsdtar"
  fi
}

run_tar() {
  if [ "$BRarchiver" = "TAR" ]; then
    if [ "$BRfiletype" = "gz" ]; then
      $BR_ARC xvpfz /mnt/target/fullbackup -C /mnt/target && (echo "System decompressed successfully" >> /tmp/restore.log)
    elif [ "$BRfiletype" = "xz" ]; then
      $BR_ARC xvpfJ /mnt/target/fullbackup -C /mnt/target && (echo "System decompressed successfully" >> /tmp/restore.log)
    fi
  elif [ "$BRarchiver" = "BSDTAR" ]; then
    if [ "$BRfiletype" = "gz" ]; then
      $BR_ARC xvpfz /mnt/target/fullbackup -C /mnt/target 2>&1 && (echo "System decompressed successfully" >> /tmp/restore.log) || touch /tmp/r_error
    elif [ "$BRfiletype" = "xz" ]; then
      $BR_ARC xvpfJ /mnt/target/fullbackup -C /mnt/target 2>&1 && (echo "System decompressed successfully" >> /tmp/restore.log) || touch /tmp/r_error
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

part_list_dialog() {
  for f in /dev/[hs]d[a-z][0-9]; do echo -e "$f $(lsblk -d -n -o size $f)\r"; done | grep -vw -e `echo /dev/"${BRroot##*/}"` -e `echo /dev/"${BRswap##*/}"` -e `echo /dev/"${BRhome##*/}"` -e `echo /dev/"${BRboot##*/}"`
  for f in $(find /dev/mapper/ | grep '-'); do echo -e "$f $(lsblk -d -n -o size $f)\r"; done | grep -vw -e `echo /dev/mapper/"${BRroot##*/}"` -e `echo /dev/mapper/"${BRswap##*/}"` -e `echo /dev/mapper/"${BRhome##*/}"` -e `echo /dev/mapper/"${BRboot##*/}"`
  for f in $(find /dev -regex "/dev/md[0-9].*"); do echo -e "$f $(lsblk -d -n -o size $f)\r"; done | grep -vw -e `echo /dev/"${BRroot##*/}"` -e `echo /dev/"${BRswap##*/}"` -e `echo /dev/"${BRhome##*/}"` -e `echo /dev/"${BRboot##*/}"`
}

disk_list_dialog() {
  for f in /dev/[hs]d[a-z]; do echo -e "$f $(lsblk -d -n -o size $f)\r"; done
  for f in $(find /dev -regex "/dev/md[0-9]+"); do echo -e "$f $(lsblk -d -n -o size $f)\r"; done
}

update_part_list() {
  list=(`for f in /dev/[hs]d[a-z][0-9]; do echo -e "$f $(lsblk -d -n -o size $f)\r"; done | grep -vw -e $(echo /dev/"${BRroot##*/}") -e $(echo /dev/"${BRswap##*/}") -e $(echo /dev/"${BRhome##*/}") -e $(echo /dev/"${BRboot##*/}")
         for f in $(find /dev/mapper/ | grep '-'); do echo -e "$f $(lsblk -d -n -o size $f)\r"; done | grep -vw -e $(echo /dev/mapper/"${BRroot##*/}") -e $(echo /dev/mapper/"${BRswap##*/}") -e $(echo /dev/mapper/"${BRhome##*/}") -e $(echo /dev/mapper/"${BRboot##*/}")
         for f in $(find /dev -regex "/dev/md[0-9].*"); do echo -e "$f $(lsblk -d -n -o size $f)\r"; done | grep -vw -e $(echo /dev/"${BRroot##*/}") -e $(echo /dev/"${BRswap##*/}") -e $(echo /dev/"${BRhome##*/}") -e $(echo /dev/"${BRboot##*/}")` )
}

check_input() {
  if [ -n "$BRfile" ] && [ ! -f "$BRfile" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] File not found: $BRfile"
    BRSTOP=y
  elif [ -n "$BRfile" ]; then
    detect_filetype
    if [ "$BRfiletype" = "wrong" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type. File must be a gzip or xz compressed archive"
      BRSTOP=y
    fi
  fi

  if [ -n "$BRfile" ] && [ -n "$BRurl" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use both local file and url at the same time"
    BRSTOP=y
  fi

  if [ -n "$BRfile" ] && [ -z "$BRarchiver" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify archiver"
    BRSTOP=y
  fi

  if [ -n "$BRfile" ] || [ -n "$BRurl" ] && [ -n "$BRrestore" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use local file / url and transfer mode at the same time"
    BRSTOP=y
  fi

  if [ "x$BRmode" = "xTransfer" ]; then
    if [ -z $(which rsync 2> /dev/null) ];then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package rsync is not installed. Install the package and re-run the script"
      BRSTOP=y
    fi
    if [ -n "$BRgrub" ] && [ ! -d /usr/lib/grub/i386-pc ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Grub not found"
      BRSTOP=y
    elif [ -n "$BRsyslinux" ] && [ -z $(which extlinux 2> /dev/null) ];then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Syslinux not found"
      BRSTOP=y
    fi
  fi

  if [ -n "$BRroot" ]; then
    for i in /dev/[hs]d[a-z][0-9]; do if [[ $i == ${BRroot} ]] ; then BRrootcheck="true" ; fi; done
    for i in $(find /dev/mapper/ | grep '-'); do if [[ $i == ${BRroot} ]] ; then BRrootcheck="true" ; fi; done
    for i in $(find /dev -regex "/dev/md[0-9].*"); do if [[ $i == ${BRroot} ]] ; then BRrootcheck="true" ; fi; done
    if [ ! "$BRrootcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong root partition: $BRroot"
      BRSTOP=y
    elif pvdisplay 2>&1 | grep -w $BRroot > /dev/null; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRroot contains lvm physical volume, refusing to use it. Use a logical volume instead"
      BRSTOP=y
    elif [[ ! -z `lsblk -d -n -o mountpoint 2> /dev/null $BRroot` ]]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRroot is already mounted as $(lsblk -d -n -o mountpoint 2> /dev/null $BRroot), refusing to use it"
      BRSTOP=y
    fi
  fi

  if [ -n "$BRswap" ]; then
    for i in /dev/[hs]d[a-z][0-9]; do if [[ $i == ${BRswap} ]] ; then BRswapcheck="true" ; fi; done
    for i in $(find /dev/mapper/ | grep '-'); do if [[ $i == ${BRswap} ]] ; then BRswapcheck="true" ; fi; done
    for i in $(find /dev -regex "/dev/md[0-9].*"); do if [[ $i == ${BRswap} ]] ; then BRswapcheck="true" ; fi; done
    if [ ! "$BRswapcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong swap partition: $BRswap"
      BRSTOP=y
    elif pvdisplay 2>&1 | grep -w $BRswap > /dev/null; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRswap contains lvm physical volume, refusing to use it. Use a logical volume instead"
      BRSTOP=y
    fi
    if [ "$BRswap" == "$BRroot" ]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRswap already used"
      BRSTOP=y
    fi
  fi

  if [ -n "$BRhome" ]; then
    for i in /dev/[hs]d[a-z][0-9]; do if [[ $i == ${BRhome} ]] ; then BRhomecheck="true" ; fi; done
    for i in $(find /dev/mapper/ | grep '-'); do if [[ $i == ${BRhome} ]] ; then BRhomecheck="true" ; fi; done
    for i in $(find /dev -regex "/dev/md[0-9].*"); do if [[ $i == ${BRhome} ]] ; then BRhomecheck="true" ; fi; done
    if [ ! "$BRhomecheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong home partition: $BRhome"
      BRSTOP=y
    elif pvdisplay 2>&1 | grep -w $BRhome > /dev/null; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRhome contains lvm physical volume, refusing to use it. Use a logical volume instead"
      BRSTOP=y
    elif [[ ! -z `lsblk -d -n -o mountpoint 2> /dev/null $BRhome` ]]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRhome is already mounted as $(lsblk -d -n -o mountpoint 2> /dev/null $BRhome), refusing to use it"
      BRSTOP=y
    fi
    if [ "$BRhome" == "$BRroot" ] || [ "$BRhome" == "$BRswap" ]; then
     echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRhome already used"
     BRSTOP=y
    fi
     if [ "x$BRhomesubvol" = "xy" ]; then
     echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use partitions inside btrfs subvolumes"
     BRSTOP=y
    fi
  fi

  if [ -n "$BRboot" ]; then
    for i in /dev/[hs]d[a-z][0-9]; do if [[ $i == ${BRboot} ]] ; then BRbootcheck="true" ; fi; done
    for i in $(find /dev/mapper/ | grep '-'); do if [[ $i == ${BRboot} ]] ; then BRbootcheck="true" ; fi; done
    for i in $(find /dev -regex "/dev/md[0-9].*"); do if [[ $i == ${BRboot} ]] ; then BRbootcheck="true" ; fi; done
    if [ ! "$BRbootcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong boot partition: $BRboot"
      BRSTOP=y
    elif pvdisplay 2>&1 | grep -w $BRboot > /dev/null; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRboot contains lvm physical volume, refusing to use it. Use a logical volume instead"
      BRSTOP=y
    elif [[ ! -z `lsblk -d -n -o mountpoint 2> /dev/null $BRboot` ]]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRboot is already mounted as $(lsblk -d -n -o mountpoint 2> /dev/null $BRboot), refusing to use it"
      BRSTOP=y
    fi
    if [ "$BRboot" == "$BRroot" ] || [ "$BRboot" == "$BRswap" ] || [ "$BRboot" == "$BRhome" ]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRboot already used"
      BRSTOP=y
    fi
  fi

  if [ "$BRcustom" = "y" ]; then
    if [[ -n $(for i in ${BRcustomparts[@]}; do BRdevice=$(echo $i | cut -f2 -d"=") && echo $BRdevice; done | sort  | uniq -d) ]]; then
      for a in ${BRcustomparts[@]}; do BRdevice=$(echo $a | cut -f2 -d"="); done
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice already used"
      touch /tmp/abort
    fi

    for a in ${BRcustomparts[@]}; do
      BRmpoint=$(echo $a | cut -f1 -d"=")
      BRdevice=$(echo $a | cut -f2 -d"=")
      echo "$BRmpoint=$BRdevice"
    done |

    while read ln; do
      BRmpoint=$(echo $ln | cut -f1 -d"=")
      BRdevice=$(echo $ln | cut -f2 -d"=")

      for i in /dev/[hs]d[a-z][0-9]; do if [[ $i == ${BRdevice} ]] ; then BRcustomcheck="true" ; fi; done
      for i in $(find /dev/mapper/ | grep '-'); do if [[ $i == ${BRdevice} ]] ; then BRcustomcheck="true" ; fi; done
      for i in $(find /dev -regex "/dev/md[0-9].*"); do if [[ $i == ${BRdevice} ]] ; then BRcustomcheck="true" ; fi; done
      if [ ! "$BRcustomcheck" = "true" ]; then
        echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong $BRmpoint partition: $BRdevice"
        touch /tmp/abort
      elif pvdisplay 2>&1 | grep -w $BRdevice > /dev/null; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice contains lvm physical volume, refusing to use it. Use a logical volume instead"
        touch /tmp/abort
      elif [[ ! -z `lsblk -d -n -o mountpoint 2> /dev/null $BRdevice` ]]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice is already mounted as $(lsblk -d -n -o mountpoint 2> /dev/null $BRdevice), refusing to use it"
        touch /tmp/abort
      fi
      if [ "$BRdevice" == "$BRroot" ] || [ "$BRdevice" == "$BRswap" ] || [ "$BRdevice" == "$BRhome" ] || [ "$BRdevice" == "$BRboot" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] $BRdevice already used"
        touch /tmp/abort
      fi
      if [[ "$BRmpoint" == *var* ]] && [ "x$BRvarsubvol" = "xy" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use partitions inside btrfs subvolumes"
        touch /tmp/abort
      elif [[ "$BRmpoint" == *var* ]]; then
        touch /tmp/BRvarsubvol
      fi
      if [[ "$BRmpoint" == *usr* ]] && [ "x$BRusrsubvol" = "xy" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use partitions inside btrfs subvolumes"
        touch /tmp/abort
      elif [[ "$BRmpoint" == *usr* ]]; then
        touch /tmp/BRusrsubvol
      fi
      if [[ "$BRmpoint" == *home* ]] && [ "x$BRhomesubvol" = "xy" ]; then
        echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use partitions inside btrfs subvolumes"
        touch /tmp/abort
      elif [[ "$BRmpoint" == *home* ]]; then
        touch /tmp/BRhomesubvol
      fi
      unset BRcustomcheck
    done
  fi

  if [ -n "$BRgrub" ]; then
    for i in /dev/[hs]d[a-z]; do if [[ $i == ${BRgrub} ]] ; then BRgrubcheck="true" ; fi; done
    for i in $(find /dev -regex "/dev/md[0-9]+"); do if [[ $i == ${BRgrub} ]] ; then BRgrubcheck="true" ; fi; done
    if [ ! "$BRgrubcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong disk for grub: $BRgrub"
      BRSTOP=y
    fi
  fi

  if [ -n "$BRsyslinux" ]; then
    for i in /dev/[hs]d[a-z]; do if [[ $i == ${BRsyslinux} ]] ; then BRsyslinuxcheck="true" ; fi; done
    for i in $(find /dev -regex "/dev/md[0-9]+"); do if [[ $i == ${BRsyslinux} ]] ; then BRsyslinuxcheck="true" ; fi; done
    if [ ! "$BRsyslinuxcheck" = "true" ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong disk for syslinux: $BRsyslinux"
      BRSTOP=y
    fi
    if [[ "$BRsyslinux" == *md* ]]; then
      for f in `cat /proc/mdstat | grep $(echo "$BRsyslinux" | cut -c 6-) | grep -oP '[hs]d[a-z][0-9]'` ; do
        BRdev=`echo /dev/$f | cut -c -8`
      done
    fi
    detect_partition_table
    if [ "$BRpartitiontable" = "gpt" ] && [ -z $(which sgdisk 2> /dev/null) ]; then
      echo -e "[${BR_RED}ERROR${BR_NORM}] Package gptfdisk/gdisk is not installed. Install the package and re-run the script"
      BRSTOP=y
    fi
  fi

  if [ -n "$BRgrub" ] && [ -n "$BRsyslinux" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Dont use both bootloaders at the same time"
    BRSTOP=y
  fi

  if [ -n "$BRinterface" ] && [ ! "$BRinterface" = "CLI" ] && [ ! "$BRinterface" = "Dialog" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong interface name: $BRinterface. Available options: CLI Dialog"
    BRSTOP=y
  fi

  if [ -n "$BRarchiver" ] && [ ! "$BRarchiver" = "TAR" ] && [ ! "$BRarchiver" = "BSDTAR" ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong archiver: $BRarchiver. Available options: TAR BSDTAR"
    BRSTOP=y
  fi

  if [ "$BRarchiver" = "BSDTAR" ] && [ -z $(which bsdtar 2> /dev/null) ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
    BRSTOP=y
  fi

  if [ -f /tmp/BRvarsubvol ]; then BRvarsubvol="n" && rm /tmp/BRvarsubvol ; fi
  if [ -f /tmp/BRusrsubvol ]; then BRusrsubvol="n" && rm /tmp/BRusrsubvol ; fi
  if [ -f /tmp/BRhomesubvol ]; then BRhomesubvol="n" && rm /tmp/BRhomesubvol ; fi

  if [ -n "$BRSTOP" ]; then
    exit
  fi

  if [ -f /tmp/abort ]; then
    rm /tmp/abort
    exit
  fi
}

mount_all() {
  echo -e "\n${BR_SEP}MOUNTING"
  echo -n "Making working directory "
  OUTPUT=$(mkdir /mnt/target 2>&1) && ok_status || error_status

  echo -n "Mounting $BRroot "
  OUTPUT=$(mount -o $BR_MOUNT_OPTS $BRroot /mnt/target 2>&1) && ok_status || error_status
  if [ -n "$BRSTOP" ]; then
    echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions"
    clean_files
    rm -r /mnt/target
    exit
  fi

  if [ "$(ls -A /mnt/target | grep -vw "lost+found")" ]; then
    echo -e "\n[${BR_RED}ERROR${BR_NORM}] Root partition not empty, refusing to use it"
    echo -e "[${BR_CYAN}INFO${BR_NORM}] Root partition must be formatted and cleaned\n"
    echo -n "Unmounting $BRroot "
    sleep 1
    OUTPUT=$(umount $BRroot 2>&1) && (ok_status && clean_root) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
    exit
  fi

  if [ -n "$BRhome" ]; then
    echo -n "Mounting $BRhome "
    mkdir /mnt/target/home
    OUTPUT=$(mount $BRhome /mnt/target/home 2>&1) && ok_status || error_status
    if [ -n "$BRSTOP" ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions"
      unset BRhome BRboot BRSTOP
      clean_unmount_in
    elif [ "$(ls -A /mnt/target/home | grep -vw "lost+found")" ]; then
      echo -e "[${BR_CYAN}INFO${BR_NORM}] /home partition not empty"
    fi
  fi

  if [ -n "$BRboot" ]; then
    echo -n "Mounting $BRboot "
    mkdir /mnt/target/boot
    OUTPUT=$(mount $BRboot /mnt/target/boot 2>&1) && ok_status || error_status
    if [ -n "$BRSTOP" ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error while mounting partitions"
      unset BRboot BRSTOP
      clean_unmount_in
    elif [ "$(ls -A /mnt/target/boot | grep -vw "lost+found")" ]; then
      echo -e "[${BR_CYAN}INFO${BR_NORM}] /boot partition not empty"
    fi
  fi

  if [ "$BRcustom" = "y" ]; then
    for i in ${BRcustomparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      echo -n "Mounting $BRdevice "
      mkdir -p /mnt/target$BRmpoint
      OUTPUT=$(mount $BRdevice /mnt/target$BRmpoint 2>&1) && (ok_status && touch /tmp/custom_ok) || error_status
      if [ -f /tmp/custom_ok ]; then
        rm -r /tmp/custom_ok
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
  echo -e "Root Partition: $BRroot $BRfsystem $BRfsize $BR_MOUNT_OPTS"

  if [ -n "$BRboot" ]; then
    echo "Boot Partition: $BRboot $BRbootfsystem $BRbootfsize"
  fi

  if [ -n "$BRhome" ]; then
    echo "Home Partition: $BRhome $BRhomefsystem $BRhomefsize"
  fi

  if [ -n "$BRswap" ]; then
    echo "Swap Partition: $BRswap"
  fi

  if [ "$BRcustom" = "y" ]; then
    for i in ${BRcustomparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRcustomfs=$(df -T | grep $BRdevice | awk '{print $2}')
      BRcustomsize=$(lsblk -d -n -o size 2> /dev/null $BRdevice)
      echo "$BRmpoint Partition: $BRdevice $BRcustomfs $BRcustomsize"
    done
  fi

  if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
    echo -e "\nSUBVOLUMES:"
    echo "Root Subvolume: $BRrootsubvolname"

    if [ "x$BRhomesubvol" = "xy" ]; then
      echo "Home Subvolume: Yes"
    fi

    if [ "x$BRvarsubvol" = "xy" ]; then
      echo "Var  Subvolume: Yes"
    fi

    if [ "x$BRusrsubvol" = "xy" ]; then
      echo "Usr  Subvolume: Yes"
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
    echo "File: $BRfiletype compressed archive"
    echo "Archiver: $BRarchiver"
  elif [ "$BRmode" = "Transfer" ] && [ "$BRhidden" = "n" ]; then
    echo "Mode: $BRmode"
    echo "Home: Include"
  elif [ "$BRmode" = "Transfer" ] && [ "$BRhidden" = "y" ]; then
    echo "Mode: $BRmode"
    echo "Home: Only hidden files and folders"
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
  if [ $BRdistro = Arch ]; then
    echo "tmpfs  /tmp  tmpfs  nodev,nosuid  0  0" >> /mnt/target/etc/fstab
  fi

  if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
    echo "$(detect_fstab_root)  /  btrfs  $BR_MOUNT_OPTS,subvol=$BRrootsubvolname,noatime  0  0" >> /mnt/target/etc/fstab
  elif [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xn" ]; then
    echo "$(detect_fstab_root)  /  btrfs  $BR_MOUNT_OPTS,noatime  0  0" >> /mnt/target/etc/fstab
  else
    echo "$(detect_fstab_root)  /  $BRfsystem  $BR_MOUNT_OPTS,noatime  0  1" >> /mnt/target/etc/fstab
  fi

  if [ -n "$BRhome" ]; then
    if [[ "$BRhome" == *dev/md* ]]; then
      echo "$BRhome  /home  $BRhomefsystem  defaults,noatime  0  2" >> /mnt/target/etc/fstab
    else
      echo "UUID=$(lsblk -d -n -o uuid $BRhome)  /home  $BRhomefsystem  defaults,noatime  0  2" >> /mnt/target/etc/fstab
    fi
  fi

  if [ -n "$BRboot" ]; then
    if [[ "$BRboot" == *dev/md* ]]; then
      echo "$BRboot  /boot  $BRbootfsystem  defaults  0  1" >> /mnt/target/etc/fstab
    else
      echo "UUID=$(lsblk -d -n -o uuid $BRboot)  /boot  $BRbootfsystem  defaults  0  1" >> /mnt/target/etc/fstab
    fi
  fi

  if [ "$BRcustom" = "y" ]; then
    for i in ${BRcustomparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      BRmpoint=$(echo $i | cut -f1 -d"=")
      BRcustomfs=$(df -T | grep $BRdevice | awk '{print $2}')
      if [[ "$BRdevice" == *dev/md* ]]; then
        echo "$BRdevice  $BRmpoint  $BRcustomfs  defaults  0  2" >> /mnt/target/etc/fstab
      else
        echo "UUID=$(lsblk -d -n -o uuid $BRdevice)  $BRmpoint  $BRcustomfs  defaults  0  2" >> /mnt/target/etc/fstab
      fi
    done
  fi

  if [ -n "$BRswap" ]; then
    if [[ "$BRswap" == *dev/md* ]]; then
      echo "$BRswap  swap  swap  defaults  0  0" >> /mnt/target/etc/fstab
    else
      echo "UUID=$(lsblk -d -n -o uuid $BRswap)  swap  swap  defaults  0  0" >> /mnt/target/etc/fstab
    fi
  fi
  echo -e "\n${BR_SEP}GENERATED FSTAB" >> /tmp/restore.log
  cat /mnt/target/etc/fstab >> /tmp/restore.log
}

build_initramfs() {
  echo -e "\n${BR_SEP}REBUILDING INITRAMFS IMAGE"
  if grep -q dev/md /mnt/target/etc/fstab; then
    echo "Generating mdadm.conf..."
    if [ $BRdistro = Debian ]; then
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
        mv /mnt/target/etc/default/grub /mnt/target/etc/default/grub-old
      fi
      echo 'GRUB_TIMEOUT=5' > /mnt/target/etc/default/grub
      echo 'GRUB_DEFAULT=saved' >> /mnt/target/etc/default/grub
      echo 'GRUB_CMDLINE_LINUX="vconsole.keymap=us quiet"' >> /mnt/target/etc/default/grub
      echo 'GRUB_DISABLE_RECOVERY="true"' >> /mnt/target/etc/default/grub
      echo -e "\n${BR_SEP}Generated grub2 config" >> /tmp/restore.log
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

generate_locales() {
  if [ "$BRdistro" = "Arch" ] || [ "$BRdistro" = "Debian" ]; then
    echo -e "\n${BR_SEP}GENERATING LOCALES"
    chroot /mnt/target locale-gen
  fi
}

clean_root() {
  sleep 1
  rm -r /mnt/target
}

clean_files() {
  if [ -f /mnt/target/fullbackup ]; then rm /mnt/target/fullbackup; fi
  if [ -f /tmp/filelist ]; then rm /tmp/filelist; fi
  if [ -f /tmp/bl_error ]; then rm /tmp/bl_error; fi
  if [ -f /tmp/r_error ]; then rm /tmp/r_error; fi
  if [ -f /tmp/bsdtar_out ]; then rm /tmp/bsdtar_out; fi
 }

clean_unmount_when_subvols() {
  echo "${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  if [ "$BRcustom" = "y" ]; then
    for i in ${BRcustomparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      echo $BRdevice
    done | tac |

    while read ln; do
      sleep 1
      echo -n "Unmounting $ln "
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done
  fi

  if [ -n "$BRhome" ]; then
    echo -n "Unmounting $BRhome "
    OUTPUT=$(umount $BRhome 2>&1) && ok_status || error_status
  fi

  if [ -n "$BRboot" ]; then
    echo -n "Unmounting $BRboot "
    OUTPUT=$(umount $BRboot 2>&1) && ok_status || error_status
  fi

  echo -n "Unmounting $BRrootsubvolname "
  OUTPUT=$(umount $BRroot 2>&1) && ok_status || error_status

  if [ -z "$BRSTOP" ]; then
    echo -n "Mounting $BRroot "
    OUTPUT=$(mount $BRroot /mnt/target 2>&1) && ok_status || error_status

    if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRhomesubvol" = "xy" ]; then
      echo -n "Deleting $BRrootsubvolname/home "
      OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname/home  2>&1 1> /dev/null) && ok_status || error_status
    fi
    if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRvarsubvol" = "xy" ]; then
      echo -n "Deleting $BRrootsubvolname/var "
      OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname/var  2>&1 1> /dev/null) && ok_status || error_status
    fi
    if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRusrsubvol" = "xy" ]; then
      echo -n "Deleting $BRrootsubvolname/usr "
      OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname/usr 2>&1 1> /dev/null) && ok_status || error_status
    fi
    if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
      echo -n "Deleting $BRrootsubvolname "
      OUTPUT=$(btrfs subvolume delete /mnt/target/$BRrootsubvolname 2>&1 1> /dev/null) && ok_status || error_status
    fi

    rm -r /mnt/target/* 2>/dev/null
    echo -n "Unmounting $BRroot "
    sleep 1
    OUTPUT=$(umount $BRroot 2>&1) && (ok_status && clean_root) || error_status
  else
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained"
  fi
  clean_files
  exit
}

clean_unmount_in() {
  echo "${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  if [ "$BRcustom" = "y" ]; then
    for i in ${BRumountparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      echo $BRdevice
    done | tac |

    while read ln; do
      sleep 1
      echo -n "Unmounting $ln "
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done
  fi

  if [ -n "$BRhome" ]; then
    echo -n "Unmounting $BRhome "
    OUTPUT=$(umount $BRhome 2>&1) && ok_status || error_status
  fi

  if [ -n "$BRboot" ]; then
    echo -n "Unmounting $BRboot "
    OUTPUT=$(umount $BRboot 2>&1) && ok_status || error_status
  fi

  if [ -z "$BRSTOP" ]; then
    rm -r /mnt/target/* 2>/dev/null
  fi
  clean_files

  echo -n "Unmounting $BRroot "
  sleep 1
  OUTPUT=$(umount $BRroot 2>&1) && (ok_status && clean_root) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
  exit
}

clean_unmount_out() {
  echo -e "\n${BR_SEP}CLEANING AND UNMOUNTING"
  cd ~
  umount /mnt/target/dev/pts
  umount /mnt/target/proc
  umount /mnt/target/dev
  umount /mnt/target/sys
  umount /mnt/target/run

  if [ "$BRcustom" = "y" ]; then
    for i in ${BRcustomparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      echo $BRdevice
    done | tac |

    while read ln; do
      sleep 1
      echo -n "Unmounting $ln "
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done
  fi

  if [ -n "$BRhome" ]; then
    echo -n "Unmounting $BRhome "
    OUTPUT=$(umount $BRhome 2>&1) && ok_status || error_status
  fi
  if [ -n "$BRboot" ]; then
    echo -n "Unmounting $BRboot "
    OUTPUT=$(umount $BRboot 2>&1) && ok_status || error_status
  fi
  clean_files

  echo -n "Unmounting $BRroot "
  sleep 1
  OUTPUT=$(umount $BRroot 2>&1) && (ok_status && clean_root) || (error_status && echo -e "[${BR_YELLOW}WARNING${BR_NORM}] /mnt/target remained")
  exit
}

create_subvols() {
  echo -e "\n${BR_SEP}CREATING SUBVOLUMES"
  cd ~
  if [ "$BRcustom" = "y" ]; then
    for i in ${BRcustomparts[@]}; do
      BRdevice=$(echo $i | cut -f2 -d"=")
      echo $BRdevice
    done | tac |

    while read ln; do
      sleep 1
      echo -n "Unmounting $ln "
      OUTPUT=$(umount $ln 2>&1) && ok_status || error_status
    done
  fi

  if [ -n "$BRhome" ]; then
    echo -n "Unmounting $BRhome "
    OUTPUT=$(umount $BRhome 2>&1) && ok_status || error_status
  fi

  if [ -n "$BRboot" ]; then
    echo -n "Unmounting $BRboot "
    OUTPUT=$(umount $BRboot 2>&1) && ok_status || error_status
  fi

  if [ -z "$BRSTOP" ]; then
    rm -r /mnt/target/* 2>/dev/null
    echo -n "Creating $BRrootsubvolname "
    OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname 2>&1 1> /dev/null) && ok_status || error_status

    if [ "x$BRhomesubvol" = "xy" ]; then
      echo -n "Creating $BRrootsubvolname/home "
      OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname/home 2>&1 1> /dev/null) && ok_status || error_status
    fi
    if [ "x$BRvarsubvol" = "xy" ]; then
      echo -n "Creating $BRrootsubvolname/var "
      OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname/var 2>&1 1> /dev/null) && ok_status || error_status
    fi
    if [ "x$BRusrsubvol" = "xy" ]; then
      echo -n "Creating $BRrootsubvolname/usr "
      OUTPUT=$(btrfs subvolume create /mnt/target/$BRrootsubvolname/usr 2>&1 1> /dev/null) && ok_status || error_status
    fi

    echo -n "Unmounting $BRroot "
    OUTPUT=$(umount $BRroot 2>&1) && ok_status || error_status

    echo -n "Mounting $BRrootsubvolname "
    OUTPUT=$(mount -t btrfs -o $BR_MOUNT_OPTS,subvol=$BRrootsubvolname $BRroot /mnt/target 2>&1) && ok_status || error_status

    if [ -n "$BRhome" ]; then
      echo -n "Mounting $BRhome "
      mkdir /mnt/target/home
      OUTPUT=$(mount $BRhome /mnt/target/home 2>&1) && ok_status || error_status
    fi

    if [   -n "$BRboot" ]; then
      echo -n "Mounting $BRboot "
      mkdir /mnt/target/boot
      OUTPUT=$(mount $BRboot /mnt/target/boot 2>&1) && ok_status || error_status
    fi

    if [ "$BRcustom" = "y" ]; then
      for i in ${BRcustomparts[@]}; do
        BRdevice=$(echo $i | cut -f2 -d"=")
        BRmpoint=$(echo $i | cut -f1 -d"=")
        echo -n "Mounting $BRdevice "
        mkdir -p /mnt/target$BRmpoint
        OUTPUT=$(mount $BRdevice /mnt/target$BRmpoint 2>&1) && ok_status || error_status
      done
    fi
  fi
}

BRargs=`getopt -o "i:r:s:b:h:g:S:f:u:n:p:R:HVUqtoNm:k:c:a:" -l "interface:,root:,swap:,boot:,home:,grub:,syslinux:,file:,url:,username:,password:,help,quiet,rootsubvolname:,homesubvol,varsubvol,usrsubvol,transfer,only-hidden,no-color,mount-options:,kernel-options:,custom-partitions:archiver:" -n "$1" -- "$@"`

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
      BRfile=$2
      shift 2
    ;;
    -u|--url)
      BRmode="Restore"
      BRurl=$2
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
      shift
    ;;
    -R|--rootsubvolname)
      BRrootsubvol="y"
      BRrootsubvolname=$2
      shift 2
    ;;
    -H|--homesubvol)
      BRhomesubvol="y"
      shift
    ;;
    -V|--varsubvol)
      BRvarsubvol="y"
      shift
    ;;
    -U|--usrsubvol)
      BRusrsubvol="y"
      shift
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
      BRcustomparts=($2)
      shift 2
    ;;
    -a|--archiver)
      BRarchiver=$2
      shift 2
    ;;
    --help)
    BR_BOLD='\033[1m'
    BR_NORM='\e[00m'
    echo -e "
${BR_BOLD}$BR_VERSION

Interface:${BR_NORM}
  -i,  --interface          interface to use (CLI Dialog)
  -N,  --no-color           disable colors
  -q,  --quiet              dont ask, just run

${BR_BOLD}Restore Mode:${BR_NORM}
  -f,  --file               backup file path
  -u,  --url                url
  -n,  --username           username
  -p,  --password           password
  -a,  --archiver           select archiver (TAR BSDTAR)

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
  -H,  --homesubvol         make subvolume for /home
  -V,  --varsubvol          make subvolume for /var
  -U,  --usrsubvol          make subvolume for /usr

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

if [ -z "$BRnocolor" ]; then
  color_variables
fi

DEFAULTIFS=$IFS
IFS=$'\n'

check_input

if [ -n "$BRroot" ]; then
  if [ -z "$BRrootsubvolname" ]; then
    BRrootsubvol="n"
  fi

  if [ -z "$BRcustom" ]; then
    BRcustom="n"
  fi

  if [ -z "$BRmountoptions" ]; then
    BRmountoptions="No"
    BR_MOUNT_OPTS="defaults"
  fi

  if [ -z "$BRswap" ]; then
    BRswap=-1
  fi

  if [ -z "$BRboot" ]; then
    BRboot=-1
  fi

  if [ -z "$BRhome" ]; then
    BRhome=-1
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    BRgrub=-1
    BRsyslinux=-1
    if [ -n "$BR_KERNEL_OPTS" ]; then
      echo -e "[${BR_YELLOW}WARNING${BR_NORM}] No bootloader selected, skipping kernel options"
      sleep 1
    fi
  fi

  if [ -n "$BRgrub" ] && [ -z "$BRsyslinux" ] && [ -n "$BR_KERNEL_OPTS" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Grub selected, skipping kernel options"
    sleep 1
  fi

  if [ -z "$BRfile" ] && [ -z "$BRurl" ] && [ -z "$BRrestore" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] You must specify a backup file or enable transfer mode"
    exit
  fi
fi

if [ "x$BRmode" = "xTransfer" ] && [ -z "$BRhidden" ]; then
  BRhidden="n"
fi

if [ -n "$BRrootsubvol" ]; then
  if [ -z "$BRvarsubvol" ]; then
    BRvarsubvol=-1
  fi

  if [ -z "$BRusrsubvol" ]; then
    BRusrsubvol=-1
  fi

  if [ -z "$BRhomesubvol" ]; then
    BRhomesubvol=-1
  fi
fi

if [ $(id -u) -gt 0 ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Script must run as root"
  exit
fi

if [ -d /mnt/target ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] /mnt/target exists, aborting"
  exit
fi

if [ -f /etc/pacman.conf ]; then
  PATH="$PATH:/usr/sbin:/bin"
fi

PS3="Choice: "

interfaces=(CLI Dialog)

while [ -z "$BRinterface" ]; do
  echo -e "\n${BR_CYAN}Select interface or enter Q to quit${BR_NORM}"
  select c in ${interfaces[@]}; do
    if [ $REPLY = "q" ] || [ $REPLY = "Q" ]; then
      echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
      exit
    elif [[ $REPLY = [0-9]* ]] && [ $REPLY -gt 0 ] && [ $REPLY -le ${#interfaces[@]} ]; then
      BRinterface=$c
      break
    else
      echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
    fi
  done
done

if [ "$BRinterface" = "CLI" ]; then
  clear
  echo -e "${BR_BOLD}$BR_VERSION${BR_NORM}"
  echo " "

  if [ -z "$BRrestore" ] && [ -z "$BRfile" ] && [ -z "$BRurl" ]; then
    info_screen
    read -s a
    clear
  fi

  disk_list=(`for f in /dev/[hs]d[a-z]; do echo -e "$f"; done; for f in $(find /dev -regex "/dev/md[0-9]+"); do echo -e "$f"; done`)
  editorlist=(nano vi)
  update_part_list

  while [ -z "$BRroot" ]; do
    echo -e "\n${BR_CYAN}Select target root partition or enter Q to quit${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRroot=(`echo $c | awk '{ print $1 }'`)
        echo -e "${BR_GREEN}You selected $BRroot as your root partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
      fi
    done
  done

  while [ -z "$BRmountoptions" ]; do
    echo -e "\n${BR_CYAN}Enter additional mount options?${BR_NORM}"
    read -p "(y/N):" an

    if [ -n "$an" ]; then
      def=$an
    else
      def="n"
    fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRmountoptions="Yes"
      echo -e "\n${BR_CYAN}Enter options (comma-separated list of mount options)${BR_NORM}"
      read -p "Options: " BR_MOUNT_OPTS
    elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
      BRmountoptions="No"
      BR_MOUNT_OPTS="defaults"
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  update_part_list

  if [ -z "$BRhome" ]; then
    echo -e "\n${BR_CYAN}Select target home partition or enter Q to quit \n${BR_MAGENTA}(Optional - Press C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRhome=(`echo $c | awk '{ print $1 }'`)
        echo -e "${BR_GREEN}You selected $BRhome as your home partition${BR_NORM}"
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "${BR_GREEN}No seperate home partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
      fi
    done
  fi

  update_part_list

  if [ -z "$BRboot" ]; then
    echo -e "\n${BR_CYAN}Select target boot partition or enter Q to quit \n${BR_MAGENTA}(Optional - Press C to skip)${BR_NORM}"
    select c in ${list[@]}; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#list[@]} ]; then
        BRboot=(`echo $c | awk '{ print $1 }'`)
        echo -e "${BR_GREEN}You selected $BRboot as your boot partition${BR_NORM}"
        break
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "${BR_GREEN}No seperate boot partition${BR_NORM}"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
      fi
    done
  fi

  update_part_list

  if [ -z "$BRswap" ]; then
    echo -e "\n${BR_CYAN}Select swap partition or enter Q to quit \n${BR_MAGENTA}(Optional - Press C to skip)${BR_NORM}"
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
        echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
      fi
    done
  fi

  while [ -z "$BRcustom" ]; do
    echo -e "\n${BR_CYAN}Specify custom partitions?${BR_NORM}"
    read -p "(y/N):" an

    if [ -n "$an" ]; then
      def=$an
    else
      def="n"
    fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRcustom="y"
      IFS=$DEFAULTIFS
      echo -e "\n${BR_CYAN}Set partitions (mountpoint=device e.g /usr=/dev/sda3 /var/cache=/dev/sda4)${BR_NORM}"
      read -p "Partitions: " BRcustompartslist
      BRcustomparts=($BRcustompartslist)
      IFS=$'\n'
    elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
      BRcustom="n"
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    echo -e "\n${BR_CYAN}Select bootloader or enter Q to quit \n${BR_MAGENTA}(Optional - Press C to skip)${BR_NORM}"
    select c in Grub Syslinux; do
      if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
       	exit
      elif [ "$REPLY" = "c" ] || [ "$REPLY" = "C" ]; then
        echo -e "\n[${BR_YELLOW}WARNING${BR_NORM}] NO BOOTLOADER SELECTED"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then

        while [ -z "$BRgrub" ]; do
          echo -e "\n${BR_CYAN}Select target disk for Grub or enter Q to quit${BR_NORM}"
	  select c in ${disk_list[@]}; do
	    if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
              echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
	      exit
	    elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#disk_list[@]} ]; then
	      BRgrub=(`echo $c | awk '{ print $1 }'`)
              echo -e "${BR_GREEN}You selected $BRgrub to install Grub${BR_NORM}"
	      break
	    else
              echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
	    fi
	  done
        done
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then

        while [ -z "$BRsyslinux" ]; do
          echo -e "\n${BR_CYAN}Select target disk Syslinux or enter Q to quit${BR_NORM}"
	  select c in ${disk_list[@]}; do
	    if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
              echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
	      exit
	    elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -gt 0 ] && [ "$REPLY" -le ${#disk_list[@]} ]; then
	      BRsyslinux=(`echo $c | awk '{ print $1 }'`)
              echo -e "${BR_GREEN}You selected $BRsyslinux to install Syslinux${BR_NORM}"
	      echo -e "\n${BR_CYAN}Enter additional kernel options?${BR_NORM}"
              read -p "(y/N):" an

              if [ -n "$an" ]; then
                def=$an
              else
                def="n"
              fi

              if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
                read -p "Enter options:" BR_KERNEL_OPTS
                break
              elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
                break
              else
                echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
              fi
	    else
              echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
	    fi
	  done
        done
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
      fi
    done
  fi


  if [ "x$BRswap" = "x-1" ]; then
    unset BRswap
  fi
  if [ "x$BRboot" = "x-1" ]; then
    unset BRboot
  fi
  if [ "x$BRhome" = "x-1" ]; then
    unset BRhome
  fi
  if [ "x$BRgrub" = "x-1" ]; then
    unset BRgrub
  fi
  if [ "x$BRsyslinux" = "x-1" ]; then
    unset BRsyslinux
  fi

  while [ -z "$BRmode" ]; do
    echo -e "\n${BR_CYAN}Select Mode or enter Q to quit${BR_NORM}"
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
        echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
      fi
    done
  done

  if [ "$BRmode" = "Restore" ]; then
    while [ -z "$BRarchiver" ]; do
      echo -e "\n${BR_CYAN}Select the archiver you used to create the backup archive:${BR_NORM}"
      select c in "TAR (GNU Tar)" "BSDTAR (Libarchive Tar)"; do
        if [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
          BRarchiver="TAR"
          echo -e "${BR_GREEN}You selected $BRarchiver${BR_NORM}"
          break
        elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
          BRarchiver="BSDTAR"
          echo -e "${BR_GREEN}You selected $BRarchiver${BR_NORM}"
          break
        else
          echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
        fi
      done
    done
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
        echo -e "${BR_GREEN}Entire /home directory will be transferred${BR_NORM}"
      elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
        BRhidden="y"
         echo -e "${BR_GREEN}Only /home's hidden files and folders will be transferred${BR_NORM}"
      else
        echo -e "${BR_RED}Please select a valid option${BR_NORM}"
      fi
    done
  fi

  check_input
  mount_all
  detect_parts_fs_size

  if [ "x$BRfsystem" = "xbtrfs" ]; then
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

    if [ "x$BRrootsubvol" = "xy" ]; then
      while [ -z "$BRrootsubvolname" ]; do
        read -p "Enter subvolume name: " BRrootsubvolname
        echo "Subvolume name: $BRrootsubvolname"
        if [ -z "$BRrootsubvolname" ]; then
          echo -e "\n${BR_CYAN}Please enter a name for the subvolume.${BR_NORM}"
        fi
      done

      if [ -z "$BRhome" ]; then
        while [ -z "$BRhomesubvol" ]; do
          echo -e "\n${BR_CYAN}Create subvolume for /home inside $BRrootsubvolname?${BR_NORM}"
          read -p "(Y/n) " an

          if [ -n "$an" ]; then
            btrfsdef=$an
          else
            btrfsdef="y"
          fi

          if [ "$btrfsdef" = "y" ] || [ "$btrfsdef" = "Y" ]; then
            BRhomesubvol="y"
          elif [ "$btrfsdef" = "n" ] || [ "$btrfsdef" = "N" ]; then
            BRhomesubvol="n"
          else
            echo -e "${BR_RED}Please select a valid option${BR_NORM}"
          fi
        done
      fi

      while [ -z "$BRvarsubvol" ]; do
        echo -e "\n${BR_CYAN}Create subvolume for /var inside $BRrootsubvolname?${BR_NORM}"
        read -p "(Y/n):" an

        if [ -n "$an" ]; then
          btrfsdef=$an
        else
          btrfsdef="y"
        fi

        if [ "$btrfsdef" = "y" ] || [ "$btrfsdef" = "Y" ]; then
          BRvarsubvol="y"
        elif [ "$btrfsdef" = "n" ] || [ "$btrfsdef" = "N" ]; then
          BRvarsubvol="n"
        else
          echo -e "${BR_RED}Please select a valid option${BR_NORM}"
        fi
      done

      while [ -z "$BRusrsubvol" ]; do
        echo -e "\n${BR_CYAN}Create subvolume for /usr inside $BRrootsubvolname?${BR_NORM}"
        read -p "(Y/n):" an

        if [ -n "$an" ]; then
          btrfsdef=$an
        else
          btrfsdef="y"
        fi

        if [ "$btrfsdef" = "y" ] || [ "$btrfsdef" = "Y" ]; then
          BRusrsubvol="y"
        elif [ "$btrfsdef" = "n" ] || [ "$btrfsdef" = "N" ]; then
          BRusrsubvol="n"
        else
          echo -e "${BR_RED}Please select a valid option${BR_NORM}"
        fi
      done

      if [ "x$BRhomesubvol" = "x-1" ]; then
        unset BRhomesubvol
      fi
      if [ "x$BRusrsubvol" = "x-1" ]; then
        unset BRusrsubvol
      fi
      if [ "x$BRhome" = "x-1" ]; then
        unset BRvarsubvol
      fi
      create_subvols
    fi
  elif [ "x$BRrootsubvol" = "xy" ] || [ "x$BRhomesubvol" = "xy" ] || [ "x$BRvarsubvol" = "xy" ] || [ "x$BRusrsubvol" = "xy" ]; then
    echo -e "[${BR_YELLOW}WARNING${BR_NORM}] Not a btrfs root filesystem, proceeding without subvolumes..."
    sleep 1
  fi

  if [ "$BRmode" = "Restore" ]; then
    echo -e "\n${BR_SEP}GETTING TAR IMAGE"
    if [ -n "$BRfile" ]; then
      echo -n "Symlinking file "
      OUTPUT=$(ln -s "$BRfile" "/mnt/target/fullbackup" 2>&1) && ok_status || error_status
    fi

    if [ -n "$BRurl" ]; then
      if [ -n "$BRusername" ]; then
        wget --user=$BRusername --password=$BRpassword -O /mnt/target/fullbackup $BRurl --tries=2
        if [ "$?" -ne "0" ]; then
          echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error downloading file. Wrong URL or network is down"
          rm /mnt/target/fullbackup 2>/dev/null
        else
          detect_filetype_url
          if [ "$BRfiletype" = "wrong" ]; then
            echo -e "${BR_RED}Invalid file type${BR_NORM}"
            rm /mnt/target/fullbackup 2>/dev/null
          fi
        fi
      else
        wget -O /mnt/target/fullbackup $BRurl --tries=2
        if [ "$?" -ne "0" ]; then
          echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error downloading file. Wrong URL or network is down"
          rm /mnt/target/fullbackup 2>/dev/null
        else
        detect_filetype_url
          if [ "$BRfiletype" = "wrong" ]; then
            echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type"
            rm /mnt/target/fullbackup 2>/dev/null
          fi
        fi
      fi
    fi
    if [ -f /mnt/target/fullbackup ]; then
      set_archiver
      ($BR_ARC tf /mnt/target/fullbackup || touch /tmp/tar_error) | tee /tmp/filelist | while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done
      if [ -f /tmp/tar_error ]; then
        rm /tmp/tar_error
        echo -e "[${BR_RED}ERROR${BR_NORM}] Error reading archive"
        rm /mnt/target/fullbackup
      fi
      echo " "
    fi

    while [ ! -f /mnt/target/fullbackup ]; do
      echo -e "\n${BR_CYAN}Select backup file. Choose an option or enter Q to quit${BR_NORM}"
      select c in "Local File" "URL" "Protected URL"; do
        if [ "$REPLY" = "q" ] || [ "$REPLY" = "Q" ]; then
          echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
          if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
            clean_unmount_when_subvols
          fi
          clean_unmount_in
        elif [ "$REPLY" = "1" ]; then
          unset BRurl
          echo -e "\n${BR_CYAN}Enter the path of the backup file${BR_NORM}"
          read -p "Path:" BRfile
          if [ ! -f "$BRfile" ] || [ -z "$BRfile" ]; then
            echo -e "[${BR_RED}ERROR${BR_NORM}] File not found"
      	  else
            detect_filetype
            if [ "$BRfiletype" = "gz" ] || [ "$BRfiletype" = "xz" ]; then
              echo -n "Symlinking file "
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
	    wget --user=$BRusername --password=$BRpassword -O /mnt/target/fullbackup $BRurl --tries=2
            if [ "$?" -ne "0" ]; then
              echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error downloading file. Wrong URL or network is down"
	      rm /mnt/target/fullbackup 2>/dev/null
            else
              detect_filetype_url
              if [ "$BRfiletype" = "wrong" ]; then
                echo -e "${BR_RED}Invalid file type${BR_NORM}"
                rm /mnt/target/fullbackup 2>/dev/null
              fi
            fi
	    break
          fi
          wget -O /mnt/target/fullbackup $BRurl --tries=2
          if [ "$?" -ne "0" ]; then
            echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error downloading file. Wrong URL or network is down"
	    rm /mnt/target/fullbackup 2>/dev/null
          else
            detect_filetype_url
            if [ "$BRfiletype" = "wrong" ]; then
              echo -e "[${BR_RED}ERROR${BR_NORM}] Invalid file type"
              rm /mnt/target/fullbackup 2>/dev/null
            fi
          fi
          break
        else
          echo -e "${BR_RED}Please select a valid option from the list or enter Q to quit${BR_NORM}"
        fi
      done
      if [ -f /mnt/target/fullbackup ]; then
        set_archiver
        ($BR_ARC tf /mnt/target/fullbackup || touch /tmp/tar_error) | tee /tmp/filelist | while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done
        if [ -f /tmp/tar_error ]; then
          rm /tmp/tar_error
          echo -e "[${BR_RED}ERROR${BR_NORM}] Error reading archive"
          rm /mnt/target/fullbackup
        fi
        echo " "
      fi
    done
  fi

  if [ -n "$BRgrub" ]; then
    BRbootloader=Grub
  elif [ -n "$BRsyslinux" ]; then
    BRbootloader=Syslinux
  fi
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
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  if [ "x$BRcontinue" = "xn" ]; then
    if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
      clean_unmount_when_subvols
    fi
    clean_unmount_in
  elif [ "x$BRcontinue" = "xy" ]; then
    echo "--------------$(date +%d-%m-%Y-%T)--------------" >> /tmp/restore.log
    echo " " >> /tmp/restore.log
    if [ "$BRmode" = "Restore" ]; then
      echo -e "\n${BR_SEP}EXTRACTING"
      total=$(cat /tmp/filelist | wc -l)
      set_archiver
      sleep 1

      if [ "$BRarchiver" = "TAR" ]; then
        run_tar 2>>/tmp/restore.log
      elif [ "$BRarchiver" = "BSDTAR" ]; then
        run_tar | tee /tmp/bsdtar_out 
      fi | while read ln; do a=$(( a + 1 )) && echo -en "\rDecompressing: $(($a*100/$total))%"; done

      if [ "$BRarchiver" = "BSDTAR" ] && [ -f /tmp/r_error ]; then
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

    detect_distro

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
      while [ -z "$BReditor" ]; do
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
      done
    fi

    ( prepare_chroot
      build_initramfs
      generate_locales
      sleep 1 ) 1> >(tee -a /tmp/restore.log) 2>&1

    if [ "$BRmode" = "Restore" ] && [ -n "$BRgrub" ] && [ ! -d /mnt/target/usr/lib/grub/i386-pc ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Grub not found, proceeding without bootloader"
      unset BRgrub
    elif [ "$BRmode" = "Restore" ] && [ -n "$BRsyslinux" ] && [ -z $(chroot /mnt/target which extlinux 2> /dev/null) ];then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Syslinux not found, proceeding without bootloader"
      unset BRsyslinux
    fi

    install_bootloader 1> >(tee -a /tmp/restore.log) 2>&1
    sleep 1

    if [ -f /tmp/bl_error ]; then
      echo -e "\n[${BR_RED}ERROR${BR_NORM}] Error installing $BRbootloader. Check /tmp/restore.log for details.\n${BR_CYAN}Press ENTER to unmount all remaining (engaged) devices.${BR_NORM}"
    elif [ -n "$BRgrub" ] || [ -n "$BRsyslinux" ]; then
      echo -e "\n${BR_CYAN}Completed. Log: /tmp/restore.log\nPress ENTER to unmount all remaining (engaged) devices, then reboot your system.${BR_NORM}"
    else
      instruct_screen
    fi
    read -s a

    sleep 1
    clean_unmount_out
  fi

elif [ "$BRinterface" = "Dialog" ]; then
  clear
  IFS=$DEFAULTIFS

  if [ -z $(which dialog 2> /dev/null) ];then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package dialog is not installed. Install the package and re-run the script"
    exit
  fi

  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD

  if [ -z "$BRrestore" ] && [ -z "$BRfile" ] && [ -z "$BRurl" ]; then
    dialog --title "$BR_VERSION" --msgbox "$(info_screen)" 25 80
  fi

  exec 3>&1

  while [ -z "$BRroot" ]; do
    BRroot=$(dialog --cancel-label Quit --menu "Set target root partition:" 0 0 0 `part_list_dialog` 2>&1 1>&3)
    if [ "$?" = "1" ]; then
      BRroot=" "
      exit
    fi
  done

  while [ -z "$BRmountoptions" ]; do
     dialog --yesno "Specify additional mount options?" 6 40
     if [ "$?" = "0" ]; then
       BRmountoptions="Yes"
       BR_MOUNT_OPTS=$(dialog --no-cancel --inputbox "Enter options: (comma-separated list of mount options)" 8 70 2>&1 1>&3)
     else
       BRmountoptions="No"
       BR_MOUNT_OPTS="defaults"
     fi
   done

  if [ -z "$BRhome" ]; then
    BRhome=$(dialog --cancel-label Skip --extra-button --extra-label Quit --menu "Set target home partition:" 0 0 0 `part_list_dialog` 2>&1 1>&3)
    if [ "$?" = "3" ]; then
      BRhome=" "
      exit
    fi
  fi

  if [ -z "$BRboot" ]; then
    BRboot=$(dialog --cancel-label Skip --extra-button --extra-label Quit --menu "Set target boot partition:" 0 0 0 `part_list_dialog` 2>&1 1>&3)
    if [ "$?" = "3" ]; then
      BRboot=" "
      exit
    fi
  fi

  if [ -z "$BRswap" ]; then
    BRswap=$(dialog --cancel-label Skip --extra-button --extra-label Quit --menu "Set swap partition:" 0 0 0 `part_list_dialog` 2>&1 1>&3)
    if [ "$?" = "3" ]; then
      BRswap=" "
      exit
    fi
  fi

  if [ -z "$BRcustom" ]; then
    dialog --yesno "Specify custom partitions?" 6 30
    if [ "$?" = "0" ]; then
      BRcustom="y"
      BRcustompartslist=$(dialog --no-cancel --inputbox "Set partitions: (mountpoint=device e.g /usr=/dev/sda3 /var/cache=/dev/sda4)" 8 80 2>&1 1>&3)
      BRcustomparts=($BRcustompartslist)
    fi
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    REPLY=$(dialog --cancel-label Skip --extra-button --extra-label Quit --menu "Select bootloader:" 10 0 10 1 Grub 2 Syslinux 2>&1 1>&3)
    if [ "$?" = "3" ]; then
      exit
    fi
    if [ "$REPLY" = "1" ]; then
      while [ -z "$BRgrub" ]; do
        BRgrub=$(dialog --cancel-label Quit --menu "Set target disk for Grub:" 0 0 0 `disk_list_dialog` 2>&1 1>&3)
        if [ "$?" = "1" ]; then
          BRgrub=" "
          exit
        fi
      done
    elif [ "$REPLY" = "2" ]; then
      while [ -z "$BRsyslinux" ]; do
        BRsyslinux=$(dialog --cancel-label Quit --menu "Set target disk for Syslinux:" 0 35 0 `disk_list_dialog` 2>&1 1>&3)
        if [ "$?" = "1" ]; then
          BRsyslinux=" "
          exit
        else
          dialog --yesno "Specify additional kernel options?" 6 40
          if [ "$?" = "0" ]; then
            BR_KERNEL_OPTS=$(dialog --no-cancel --inputbox "Enter additional kernel options:" 8 70 2>&1 1>&3)
          fi
        fi
      done
    fi
  fi

  if [ -z "$BRgrub" ] && [ -z "$BRsyslinux" ]; then
    echo "WARNING! NO BOOTLOADER SELECTED" | dialog --progressbox 3 35
    sleep 2
  fi

  if [ "x$BRswap" = "x-1" ] || [[ "x$BRswap" == *"Error"* ]]; then
    unset BRswap
  fi
  if [ "x$BRboot" = "x-1" ] || [[ "x$BRboot" == *"Error"* ]]; then
    unset BRboot
  fi
  if [ "x$BRhome" = "x-1" ] || [[ "x$BRhome" == *"Error"* ]]; then
    unset BRhome
  fi
  if [ "x$BRgrub" = "x-1" ]; then
    unset BRgrub
  fi
  if [ "x$BRsyslinux" = "x-1" ]; then
    unset BRsyslinux
  fi

  while [ -z "$BRmode" ]; do
    BRmode=$(dialog --cancel-label Quit --menu "Select Mode:" 12 50 12 Restore "system from backup file" Transfer "this system with rsync" 2>&1 1>&3)
    if [ "$?" = "1" ]; then
      BRmode=" "
      exit
    fi
  done

  if [ "$BRmode" = "Restore" ]; then
    while [ -z "$BRarchiver" ]; do
      BRarchiver=$(dialog --no-cancel --menu "Select the archiver you used to create the backup archive:" 12 45 12 TAR "GNU Tar" BSDTAR "Libarchive Tar" 2>&1 1>&3)
    done
  fi

  if [ "$BRmode" = "Transfer" ]; then
    while [ -z "$BRhidden" ]; do
      dialog --yesno "Transfer entire /home directory?\n\nIf No, only hidden files and folders will be transferred" 9 50
      if [ "$?" = "0" ]; then
        BRhidden="n"
      else
        BRhidden="y"
      fi
    done
  fi

  IFS=$'\n'
  if [ -z "$BRnocolor" ]; then
    color_variables
  fi
  check_input
  mount_all
  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD
  detect_parts_fs_size

  if [ "x$BRfsystem" = "xbtrfs" ]; then
    while [ -z "$BRrootsubvol" ]; do
      dialog --yesno "BTRFS root file system detected. Create subvolume for root?" 5 68
      if [ "$?" = "0" ]; then
        BRrootsubvol="y"
      else
        BRrootsubvol="n"
      fi
    done

    if [ "x$BRrootsubvol" = "xy" ]; then
      while [ -z "$BRrootsubvolname" ]; do
        BRrootsubvolname=$(dialog --no-cancel --inputbox "Enter subvolume name:" 8 50 2>&1 1>&3)
        if [ -z "$BRrootsubvolname" ]; then
          echo "Please enter a name for the subvolume" | dialog --title "Error" --progressbox 3 45
          sleep 2
        fi
      done

      if [ -z "$BRhome" ]; then
        while [ -z "$BRhomesubvol" ]; do
          dialog --yesno "Create subvolume for /home inside $BRrootsubvolname?" 6 50
          if [ "$?" = "0" ]; then
            BRhomesubvol="y"
          else
            BRhomesubvol="n"
          fi
        done
      fi

      while [ -z "$BRvarsubvol" ]; do
        dialog --yesno "Create subvolume for /var inside $BRrootsubvolname?" 6 50
        if [ "$?" = "0" ]; then
          BRvarsubvol="y"
        else
          BRvarsubvol="n"
        fi
      done

      while [ -z "$BRusrsubvol" ]; do
        dialog --yesno "Create subvolume for /usr inside $BRrootsubvolname?" 6 50
        if [ "$?" = "0" ]; then
          BRusrsubvol="y"
        else
          BRusrsubvol="n"
        fi
      done

      if [ "x$BRhomesubvol" = "x-1" ]; then
	unset BRhomesubvol
      fi
      if [ "x$BRusrsubvol" = "x-1" ]; then
	unset BRusrsubvol
      fi
      if [ "x$BRhome" = "x-1" ]; then
	unset BRvarsubvol
      fi
      if [ -z "$BRnocolor" ]; then
        color_variables
      fi
      create_subvols
      unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD
    fi
  elif [ "x$BRrootsubvol" = "xy" ] || [ "x$BRhomesubvol" = "xy" ] || [ "x$BRvarsubvol" = "xy" ] || [ "x$BRusrsubvol" = "xy" ]; then
    echo "Not a btrfs root filesystem, proceeding without subvolumes..." | dialog --title "Warning" --progressbox 3 70
    sleep 3
  fi

  if [ "$BRmode" = "Restore" ]; then
    if [ -n "$BRfile" ]; then
      ( ln -s "${BRfile[@]}" "/mnt/target/fullbackup" 2> /dev/null && echo "Symlinking file: Done" || echo "Symlinking file: Error" ) | dialog  --progressbox  3 30
      sleep 2
    fi

    if [ -n "$BRurl" ]; then
      if [ -n "$BRusername" ]; then
        ( wget --user=$BRusername --password=$BRpassword -O /mnt/target/fullbackup $BRurl --tries=2 || touch /tmp/wget_error ) 2>&1 |
        sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | dialog --gauge "Downloading..." 0 50
        if [ -f /tmp/wget_error ]; then
          rm /tmp/wget_error
          echo "Error downloading file. Wrong URL or network is down." | dialog --title "Error" --progressbox 3 57
          sleep 2
          rm /mnt/target/fullbackup 2>/dev/null
        else
          detect_filetype_url
          if [ "$BRfiletype" = "wrong" ]; then
            echo "Invalid file type" | dialog --title "Error" --progressbox 3 21
            sleep 2
            rm /mnt/target/fullbackup 2>/dev/null
          fi
        fi
      else
        ( wget -O /mnt/target/fullbackup $BRurl --tries=2 || touch /tmp/wget_error ) 2>&1 |
        sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | dialog --gauge "Downloading..." 0 50
        if [ -f /tmp/wget_error ]; then
          rm /tmp/wget_error
          echo "Error downloading file. Wrong URL or network is down." | dialog --title "Error" --progressbox 3 57
          sleep 2
          rm /mnt/target/fullbackup 2>/dev/null
        else
          detect_filetype_url
          if [ "$BRfiletype" = "wrong" ]; then
            echo "Invalid file type" | dialog --title "Error" --progressbox 3 21
            sleep 2
            rm /mnt/target/fullbackup 2>/dev/null
          fi
        fi
      fi
    fi
    if [ -f /mnt/target/fullbackup ]; then
      set_archiver
      ( $BR_ARC tf /mnt/target/fullbackup 2>&1 || touch /tmp/tar_error ) |
      tee /tmp/filelist | while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done | dialog --progressbox 3 40
      sleep 1
      ( if [ -f /tmp/tar_error ]; then
        rm /tmp/tar_error
        echo -e "Error reading archive"
        rm /mnt/target/fullbackup
        sleep 2
      fi ) | dialog --progressbox 3 30
    fi

    while [ ! -f /mnt/target/fullbackup ]; do
      REPLY=$(dialog --cancel-label Quit --menu "Select backup file. Choose an option:" 13 50 13 File "local file" URL "remote file" "Protected URL" "protected remote file" 2>&1 1>&3)
      if [ "$?" = "1" ]; then
        if [ -z "$BRnocolor" ]; then
          color_variables
        fi
        if [  "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
          clean_unmount_when_subvols
        fi
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
              ( ln -s "$BRfile" "/mnt/target/fullbackup" 2> /dev/null && echo "Symlinking file: Done" || (echo "Symlinking file: Error" && touch /tmp/ln_error) ) | dialog  --progressbox  3 30
              if [ -f /tmp/ln_error ]; then
                rm /tmp/ln_error
                unset BRfile BRselect
              fi
              sleep 2
            else
              echo "Invalid file type" | dialog --title "Error" --progressbox 3 21
              sleep 2
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
        BRurl=$(dialog --no-cancel --inputbox "Enter the URL for the backup file:" 8 50 2>&1 1>&3)
        if [ "$REPLY" = "Protected URL" ]; then
          BRusername=$(dialog --no-cancel --inputbox "Username:" 8 50 2>&1 1>&3)
          BRpassword=$(dialog --no-cancel --insecure --passwordbox "Password:" 8 50 2>&1 1>&3)
          ( wget --user=$BRusername --password=$BRpassword -O /mnt/target/fullbackup $BRurl --tries=2 || touch /tmp/wget_error ) 2>&1 |
          sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | dialog --gauge "Downloading..." 0 50
          if [ -f /tmp/wget_error ]; then
            rm /tmp/wget_error
            echo "Error downloading file. Wrong URL or network is down." | dialog --title "Error" --progressbox 3 57
	    sleep 2
            rm /mnt/target/fullbackup 2>/dev/null
          else
            detect_filetype_url
            if [ "$BRfiletype" = "wrong" ]; then
              echo "Invalid file type" | dialog --title "Error" --progressbox 3 21
              sleep 2
              rm /mnt/target/fullbackup 2>/dev/null
            fi
          fi

        elif [ "$REPLY" = "URL" ]; then
          ( wget -O /mnt/target/fullbackup $BRurl --tries=2 || touch /tmp/wget_error ) 2>&1 |
          sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' | dialog --gauge "Downloading..." 0 50
          if [ -f /tmp/wget_error ]; then
            rm /tmp/wget_error
            echo "Error downloading file. Wrong URL or network is down." | dialog --title "Error" --progressbox 3 57
            sleep 2
            rm /mnt/target/fullbackup 2>/dev/null
          else
            detect_filetype_url
            if [ "$BRfiletype" = "wrong" ]; then
              echo "Invalid file type" | dialog --title "Error" --progressbox 3 21
              sleep 2
              rm /mnt/target/fullbackup 2>/dev/null
            fi
          fi
        fi
      fi
      if [ -f /mnt/target/fullbackup ]; then
        set_archiver
        ( $BR_ARC tf /mnt/target/fullbackup 2>&1 || touch /tmp/tar_error ) |
        tee /tmp/filelist | while read ln; do a=$(( a + 1 )) && echo -en "\rReading archive: $a Files "; done | dialog --progressbox 3 40
        sleep 1
        ( if [ -f /tmp/tar_error ]; then
          rm /tmp/tar_error
          echo -e "Error reading archive"
          rm /mnt/target/fullbackup
          sleep 2
        fi ) | dialog --progressbox 3 30
      fi
    done
  fi

  if [ -n "$BRgrub" ]; then
    BRbootloader=Grub
  elif [ -n "$BRsyslinux" ]; then
    BRbootloader=Syslinux
  fi

  if [ -z "$BRcontinue" ]; then
    dialog --title "Summary" --yes-label "OK" --no-label "Quit" --yesno "$(show_summary) $(echo -e "\n\nPress OK to continue, or Quit to abort.")" 0 0
    if [ "$?" = "1" ]; then
      if [ -z "$BRnocolor" ]; then
        color_variables
      fi
      if [ "x$BRfsystem" = "xbtrfs" ] && [ "x$BRrootsubvol" = "xy" ]; then
        clean_unmount_when_subvols
      fi
      clean_unmount_in
    fi
  fi

  echo "--------------$(date +%d-%m-%Y-%T)--------------" >> /tmp/restore.log
  echo " " >> /tmp/restore.log
  if [ "$BRmode" = "Restore" ]; then
    total=$(cat /tmp/filelist | wc -l)
    set_archiver
    sleep 1
    
    if [ "$BRarchiver" = "TAR" ]; then
      run_tar 2>>/tmp/restore.log
    elif [ "$BRarchiver" = "BSDTAR" ]; then
      run_tar | tee /tmp/bsdtar_out 
    fi | count_gauge | dialog --gauge "Decompressing..." 0 50

    if [ "$BRarchiver" = "BSDTAR" ] && [ -f /tmp/r_error ]; then
      cat /tmp/bsdtar_out >> /tmp/restore.log
    fi

  elif [ "$BRmode" = "Transfer" ]; then
    run_calc | while read ln; do a=$(( a + 1 )) && echo -en "\rCalculating: $a Files"; done | dialog --progressbox 3 40
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    run_rsync 2>>/tmp/restore.log | count_gauge | dialog --gauge "Syncing..." 0 50
  fi

  detect_distro
  generate_fstab

  if [ -n "$BRedit" ]; then
    cat /mnt/target/etc/fstab | dialog --title "GENERATING FSTAB" --progressbox 20 100
    sleep 2
  else
    dialog --title "GENERATING FSTAB" --yesno "$(echo -e "Edit fstab? Generated fstab:\n\n`cat /mnt/target/etc/fstab`")" 13 100
    if [ "$?" = "0" ]; then
      while [ -z "$BRdeditor" ]; do
        REPLY=$(dialog --no-cancel --menu "Select editor:" 10 25 10 1 nano 2 vi 2>&1 1>&3)
        if [ "$REPLY" = "1" ]; then
          BRdeditor="nano"
        elif [ "$REPLY" = "2" ]; then
          BRdeditor="vi"
        fi
        $BRdeditor /mnt/target/etc/fstab
      done
    fi
  fi

 ( prepare_chroot
   build_initramfs
   generate_locales
   sleep 2 ) 1> >(tee -a /tmp/restore.log) 2>&1 | dialog --title "PROCESSING" --progressbox 30 100

  if [ "$BRmode" = "Restore" ] && [ -n "$BRgrub" ] && [ ! -d /mnt/target/usr/lib/grub/i386-pc ]; then
    echo -e "Grub not found! Proceeding without bootloader" | dialog --title "Warning" --progressbox 3 49
    sleep 2
    unset BRgrub
  elif [ "$BRmode" = "Restore" ] && [ -n "$BRsyslinux" ] && [ -z $(chroot /mnt/target which extlinux 2> /dev/null) ];then
    echo -e "Syslinux not found! Proceeding without bootloader" | dialog --title "Warning" --progressbox 3 53
    sleep 2
    unset BRsyslinux
  fi

  if [ -n "$BRgrub" ] || [ -n "$BRsyslinux" ]; then
    install_bootloader 1> >(tee -a /tmp/restore.log) 2>&1 | dialog --title "INSTALLING AND CONFIGURING BOOTLOADER" --progressbox 30 70
    sleep 2
  fi

  if [ -f /tmp/bl_error ]; then
    dialog --yes-label "OK" --no-label "View Log" --title "Info" --yesno "Error installing $BRbootloader. Check /tmp/restore.log for details.\n\nPress OK to unmount all remaining (engaged) devices." 8 70
  elif [ -n "$BRgrub" ] || [ -n "$BRsyslinux" ]; then
    dialog --yes-label "OK" --no-label "View Log" --title "Info" --yesno "Completed. Log: /tmp/restore.log\n\nPress OK to unmount all remaining (engaged) devices, then reboot your system." 8 90
  else
    dialog --yes-label "OK" --no-label "View Log" --title "Info" --yesno "$(instruct_screen)" 22 80
  fi

  if [ "$?" = "1" ]; then
    dialog --textbox /tmp/restore.log 0 0
  fi

  sleep 1
  if [ -z "$BRnocolor" ]; then
    color_variables
  fi
  clean_unmount_out
fi
