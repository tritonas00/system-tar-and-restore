#!/bin/bash

BR_VERSION="System Tar & Restore 4.7"
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

BR_HIDE='\033[?25l'
BR_SHOW='\033[?25h'

info_screen() {
  echo -e "\n${BR_YELLOW}This script will make a tar backup image of this system."
  echo -e "\n==>Make sure you have enough free space."
  echo -e "\n==>If you plan to restore in btrfs/lvm/mdadm, make sure that\n   this system is capable to boot from btrfs/lvm/mdadm."
  echo -e "\n==>Make sure you have GRUB or SYSLINUX packages installed."
  echo -e "\nGRUB PACKAGES:"
  echo "->Arch/Gentoo: grub    efibootmgr* dosfstools*"
  echo "->Debian:      grub-pc grub-efi*   dosfstools*"
  echo "->Fedora/Suse: grub2   efibootmgr* dosfstools*"
  echo "->Mandriva:    grub2   grub2-efi*  dosfstools*"
  echo -e "\nSYSLINUX PACKAGES:"
  echo "->Arch/Suse/Gentoo: syslinux"
  echo "->Debian/Mandriva:  syslinux extlinux"
  echo "->Fedora:           syslinux syslinux-extlinux"
  echo -e "\n*Required for UEFI systems"
  echo -e "\n${BR_CYAN}Press ENTER to continue.${BR_NORM}"
}

clean_files() {
  if [ -f /tmp/excludelist ]; then rm /tmp/excludelist; fi
  if [ -f /tmp/b_error ]; then rm /tmp/b_error; fi
  if [ -f /tmp/b_filelist ]; then rm /tmp/b_filelist; fi
  if [ -f /target_architecture.$(uname -m) ]; then rm /target_architecture.$(uname -m); fi
}

exit_screen() {
  if [ -f /tmp/b_error ]; then
    echo -e "${BR_RED}\nAn error occurred.\n\nCheck $BRFOLDER/backup.log for details.\nElapsed time: $(($elapsed/3600)) hours $((($elapsed%3600)/60)) min $(($elapsed%60)) sec\n\n${BR_CYAN}Press ENTER to exit.${BR_NORM}"
  else
    echo -e "${BR_CYAN}\nCompleted.\n\nBackup archive and log saved in $BRFOLDER\nElapsed time: $(($elapsed/3600)) hours $((($elapsed%3600)/60)) min $(($elapsed%60)) sec\n\nPress ENTER to exit.${BR_NORM}"
  fi
}

exit_screen_quiet() {
  if [ -f /tmp/b_error ]; then
    echo -e "${BR_RED}\nAn error occurred.\n\nCheck $BRFOLDER/backup.log for details\nElapsed time: $(($elapsed/3600)) hours $((($elapsed%3600)/60)) min $(($elapsed%60)) sec${BR_NORM}"
  else
    echo -e "${BR_CYAN}\nCompleted.\n\nBackup archive and log saved in $BRFOLDER\nElapsed time: $(($elapsed/3600)) hours $((($elapsed%3600)/60)) min $(($elapsed%60)) sec${BR_NORM}"
  fi
}

show_summary() {
  echo "ARCHIVE:"
  echo "$BRFile.$BR_EXT"

  echo -e "\nARCHIVER OPTIONS:"
  for i in "${BR_TAROPTS[@]}"; do echo "$i"; done

  echo -e "\nHOME DIRECTORY:"
  if [ "$BRhome" = "Yes" ]; then
    echo "Include"
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ]; then
    echo "Only hidden files and folders"
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ]; then
    echo "Exclude"
  fi

  echo -e "\nFOUND BOOTLOADERS:"
  if which grub-mkconfig &>/dev/null || which grub2-mkconfig &>/dev/null; then
    echo "Grub"
  else
    BRgrub="n"
  fi
  if which extlinux &>/dev/null && which syslinux &>/dev/null; then
    echo "Syslinux"
  else
   BRsyslinux="n"
  fi
  if [ -n "$BRgrub" ] && [ -n "$BRsyslinux" ]; then
    echo "None or not supported"
  fi

  if [ -n "$BRoldbackups" ] && [ -n "$BRclean" ]; then
    echo -e "\nREMOVE BACKUPS:"
    for item in "${BRoldbackups[@]}"; do echo "$item"; done
  fi
}

dir_list() {
  IFS=$'\n'
  for D in "$BRpath"*; do [ -d "${D}" ] && echo "$(basename ${D// /\\}) dir"; done
  IFS=$DEFAULTIFS
}

show_path() {
  BRcurrentpath="$BRpath"
  if [[ "$BRcurrentpath" == *//* ]]; then
    BRcurrentpath="${BRcurrentpath#*/}"
  fi
}

set_tar_options() {
  if [ "$BRcompression" = "gzip" ]; then
    BR_MAINOPTS="cvpzf"
    BR_EXT="tar.gz"
  elif [ "$BRcompression" = "xz" ]; then
    BR_MAINOPTS="cvpJf"
    BR_EXT="tar.xz"
  elif [ "$BRcompression" = "bzip2" ]; then
    BR_MAINOPTS="cvpjf"
    BR_EXT="tar.bz2"
  elif [ "$BRcompression" = "none" ]; then
    BR_MAINOPTS="cvpf"
    BR_EXT="tar"
  fi

  if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
    BR_EXT="${BR_EXT}.aes"
  elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
    BR_EXT="${BR_EXT}.gpg"
  fi

  BR_TAROPTS=(--exclude=/run/* --exclude=/dev/* --exclude=/sys/* --exclude=/tmp/* --exclude=/mnt/* --exclude=/proc/* --exclude=/media/* --exclude=/var/run/* --exclude=/var/lock/* --exclude=.gvfs --exclude=lost+found --exclude="$BRFOLDER" --sparse)
  if [ -n "$BRoverride" ]; then
    BR_TAROPTS=(--exclude="$BRFOLDER" --sparse)
  fi
  if [ -f /etc/yum.conf ]; then
    BR_TAROPTS+=(--acls --xattrs --selinux)
  fi
  if [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ]; then
    BR_TAROPTS+=(--exclude=/home/*)
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ]; then
    find /home/*/* -maxdepth 0 -iname ".*" -prune -o -print > /tmp/excludelist
    BR_TAROPTS+=(--exclude-from=/tmp/excludelist)
  fi

  for i in ${BR_USER_OPTS[@]}; do BR_TAROPTS+=("${i///\//\ }"); done
}

run_calc() {
  tar cvf /dev/null "${BR_TAROPTS[@]}" / 2>/dev/null | tee /tmp/b_filelist
}

run_tar() {
  if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
    tar ${BR_MAINOPTS} >(openssl aes-256-cbc -salt -k "$BRencpass" -out "$BRFile".${BR_EXT} 2>> "$BRFOLDER"/backup.log) "${BR_TAROPTS[@]}" / 2>> "$BRFOLDER"/backup.log || touch /tmp/b_error
  elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
    tar ${BR_MAINOPTS} >(gpg -c --batch --yes --passphrase "$BRencpass" -z 0 -o "$BRFile".${BR_EXT} 2>> "$BRFOLDER"/backup.log) "${BR_TAROPTS[@]}" / 2>> "$BRFOLDER"/backup.log || touch /tmp/b_error
  else
    tar ${BR_MAINOPTS} "$BRFile".${BR_EXT} "${BR_TAROPTS[@]}" / 2>> "$BRFOLDER"/backup.log || touch /tmp/b_error
  fi
}

find_old_backups() {
  IFS=$'\n'
  for i in $(find $(dirname "$BRFOLDER") -mindepth 1 -maxdepth 1 -type d -iname "Backup-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]"); do
    if [ ! "$i" == "$BRFOLDER" ]; then
      BRoldbackups+=("$i")
    fi
  done
  IFS=$DEFAULTIFS
}

set_path() {
  BRFOLDER=$(echo "$BRFOLDER"/Backup-$(date +%d-%m-%Y) | sed 's://*:/:g')
}

set_names() {
  if [ -n "$BRNAME" ]; then
    BRFile="$BRFOLDER"/"$BRNAME"
  else
    BRFile="$BRFOLDER"/Backup-$(hostname)-$(date +%d-%m-%Y-%T)
  fi
  BRfiledefault="$BRFOLDER"/Backup-$(hostname)-$(date +%d-%m-%Y-%T)
}

prepare() {
  touch /target_architecture.$(uname -m)
  if [ "$BRinterface" = "cli" ]; then echo -e "\n${BR_SEP}PROCESSING"; fi
  mkdir -p "$BRFOLDER"
  sleep 1
  if [ -n "$BRhide" ]; then echo -en "${BR_HIDE}"; fi
  echo -e "====================$BR_VERSION {$(date +%d-%m-%Y-%T)}====================\n" >> "$BRFOLDER"/backup.log
  echo "${BR_SEP}SUMMARY" >> "$BRFOLDER"/backup.log
  start=$(date +%s)
}

out_pgrs_cli() {
  lastper=-1
  while read ln; do
    b=$((b + 1))
    if [ -n "$BRverb" ]; then
      echo -e "${BR_YELLOW}[$(($b*100/$total))%] ${BR_GREEN}$ln${BR_NORM}"
    else
      per=$(($b*100/$total))
      if [[ $per -gt $lastper ]]; then
        lastper=$per
        echo -ne "\rArchiving: [${pstr:0:$(($b*24/$total))}${dstr:0:24-$(($b*24/$total))}] $per%"
      fi
    fi
  done
}

BRargs=`getopt -o "i:d:f:c:u:hnNqvgDHP:E:orC:" -l "interface:,directory:,filename:,compression:,user-options:,exclude-home,no-hidden,no-color,quiet,verbose,generate,disable-genkernel,hide-cursor,passphrase:,encryption-method:,override,remove,conf:,help" -n "$1" -- "$@"`

if [ "$?" -ne "0" ]; then
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
    -u|--user-options)
      BR_USER_OPTS=$2
      shift 2
    ;;
    -d|--directory)
      BRFOLDER=$2
      shift 2
    ;;
    -f|--filename)
      BRNAME=$2
      shift 2
    ;;
    -c|--compression)
      BRcompression=$2
      shift 2
    ;;
    -h|--exclude-home)
      BRhome="No"
      shift
    ;;
    -n|--no-hidden)
      BRhidden="No"
      shift
    ;;
    -N|--no-color)
      BRnocolor="y"
      shift
    ;;
    -q|--quiet)
      BRquiet="y"
      shift
    ;;
    -v|--verbose)
      BRverb="y"
      shift
    ;;
    -g|--generate)
      BRgen="y"
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
    -E|--encryption-method)
      BRencmethod=$2
      shift 2
    ;;
    -o|--override)
      BRoverride="y"
      shift
    ;;
    -r|--remove)
      BRclean="y"
      shift
    ;;
    -C|--conf)
      BRconf=$2
      shift 2
    ;;
    --help)
      echo -e "$BR_VERSION\nUsage: backup.sh [options]
\nGeneral:
  -i, --interface          interface to use: cli dialog
  -N, --no-color           disable colors
  -q, --quiet              dont ask, just run
  -v, --verbose            enable verbose archiver output (cli interface only)
  -g, --generate           generate configuration file (in case of successful backup)
  -H, --hide-cursor        hide cursor when running archiver (useful for some terminal emulators)
  -r, --remove             remove older backups in the destination directory
\nDestination:
  -d, --directory          backup destination path
  -f, --filename           backup file name (without extension)
\nHome Directory:
  -h, --exclude-home	   exclude /home directory (keep hidden files and folders)
  -n, --no-hidden          dont keep home's hidden files and folders (use with -h)
\nArchiver Options:
  -c, --compression        compression type: gzip bzip2 xz none
  -u, --user-options       additional tar options (see tar --help)
  -o, --override           override the default tar options with user options (use with -u)
  -E, --encryption-method  encryption method: openssl gpg
  -P, --passphrase         passphrase for encryption
\nMisc Options:
  -D, --disable-genkernel  disable genkernel check in gentoo
  -C, --conf               alternative configuration file path
      --help	           print this page"
      exit
      shift
    ;;
    --)
      shift
      break
    ;;
  esac
done

if [ -z "$BRconf" ]; then
  BRconf="/etc/backup.conf"
elif [ -n "$BRconf" ] && [ ! -f "$BRconf" ]; then
  BRconferror="y"
fi

if [ -f "$BRconf" ]; then
  source "$BRconf"
fi

if [ -z "$BRnocolor" ]; then
  color_variables
fi

if [ $(id -u) -gt 0 ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Script must run as root"
  exit
fi

clean_files

if [ -n "$BRconferror" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] File does not exist: $BRconf"
  BRSTOP="y"
fi

if [ ! -d "$BRFOLDER" ] && [ -n "$BRFOLDER" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Directory does not exist: $BRFOLDER"
  BRSTOP="y"
fi

if [ -n "$BRcompression" ] && [ ! "$BRcompression" = "gzip" ] && [ ! "$BRcompression" = "xz" ] && [ ! "$BRcompression" = "bzip2" ] && [ ! "$BRcompression" = "none" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong compression type: $BRcompression. Available options: gzip bzip2 xz none"
  BRSTOP="y"
fi

if [ -n "$BRinterface" ] && [ ! "$BRinterface" = "cli" ] && [ ! "$BRinterface" = "dialog" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong interface name: $BRinterface. Available options: cli dialog"
  BRSTOP="y"
fi

if [ -f /etc/portage/make.conf ] || [ -f /etc/make.conf ] && [ -z "$BRgenkernel" ] && [ -z $(which genkernel 2>/dev/null) ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Package genkernel is not installed. Install the package and re-run the script. (you can disable this check with -D)"
  BRSTOP="y"
fi

if [ -n "$BRencpass" ] && [ -z "$BRencmethod" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] You must specify an encryption method"
  BRSTOP="y"
fi

if [ -z "$BRencpass" ] && [ -n "$BRencmethod" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] You must specify a passphrase"
  BRSTOP="y"
fi

if [ -n "$BRencmethod" ] && [ ! "$BRencmethod" = "openssl" ] && [ ! "$BRencmethod" = "gpg" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong encryption method: $BRencmethod. Available options: openssl gpg"
  BRSTOP="y"
fi

if [ -n "$BRSTOP" ]; then
  exit
fi

if [ -n "$BRquiet" ]; then
  BRcontinue="y"
fi

if [ -z "$BRhidden" ]; then
  BRhidden="Yes"
fi

if [ -n "$BRFOLDER" ]; then
  if [ -z "$BRhome" ]; then
    BRhome="Yes"
  fi
  if [ -z "$BR_USER_OPTS" ]; then
    BR_USER_OPTS=" "
  fi
  if [ -z "$BRNAME" ]; then
    BRNAME="Backup-$(hostname)-$(date +%d-%m-%Y-%T)"
  fi
  if [ -z "$BRcompression" ]; then
    BRcompression="none"
  fi
  if [ -z "$BRencmethod" ]; then
    BRencmethod="none"
  fi
fi

PS3="Enter number or Q to quit: "
DEFAULTIFS=$IFS

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
  IFS=$'\n'
  pstr="########################"
  dstr="------------------------"

  if [ -z "$BRFOLDER" ]; then
    info_screen
    read -s a
  fi

  while [ -z "$BRFOLDER" ] || [ ! -d "$BRFOLDER" ]; do
    echo -e "\n${BR_CYAN}Enter path to save the backup archive\n${BR_MAGENTA}(Leave blank for default: </>)${BR_NORM}"
    read -e -p "Path: " BRFOLDER
    if [ -z "$BRFOLDER" ]; then
      BRFOLDER="/"
    elif [ ! -d "$BRFOLDER" ]; then
      echo -e "${BR_RED}Directory does not exist${BR_NORM}"
    fi
  done

  if [ -z "$BRNAME" ]; then
    echo -e "\n${BR_CYAN}Enter archive name\n${BR_MAGENTA}(Leave blank for default: <Backup-$(hostname)-$(date +%d-%m-%Y-%T)>)${BR_NORM}"
    read -e -p "Name (without extension): " BRNAME
  fi
  COLUMNS=1

  if [ -z "$BRhome" ]; then
    echo -e "\n${BR_CYAN}Home (/home) directory options:${BR_NORM}"
    select c in "Include" "Only hidden files and folders" "Exclude"; do
      if [ $REPLY = "q" ] || [ $REPLY = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [ "$REPLY" = "1" ]; then
        BRhome="Yes"
        break
      elif [ "$REPLY" = "2" ]; then
        BRhome="No"
        BRhidden="Yes"
        break
      elif [ "$REPLY" = "3" ]; then
        BRhome="No"
        BRhidden="No"
        break
      else
        echo -e "${BR_RED}Please select a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ -z "$BRcompression" ]; then
    echo -e "\n${BR_CYAN}Select the type of compression:${BR_NORM}"
    select c in "gzip  (Fast, big file)" "bzip2 (Slow, smaller file)" "xz    (Slow, smallest file)" "none  (No compression)"; do
      if [ $REPLY = "q" ] || [ $REPLY = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        BRcompression="gzip"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        BRcompression="bzip2"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 3 ]; then
        BRcompression="xz"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 4 ]; then
        BRcompression="none"
        break
      else
        echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ -z "$BR_USER_OPTS" ]; then
    echo -e "\n${BR_CYAN}Enter additional tar options\n${BR_MAGENTA}(If you want spaces in names replace them with //)\n(Leave blank for defaults)${BR_NORM}"
    read -p "Options (see tar --help): " BR_USER_OPTS
  fi

  if which openssl &>/dev/null || which gpg &>/dev/null; then
    while  [ -z "$BRencmethod" ]; do
      echo -e "\n${BR_CYAN}Enter passphrase to encrypt archive\n${BR_MAGENTA}(Leave blank for no encryption)${BR_NORM}"
      read -p "Passphrase: " BRencpass
      if [ -n "$BRencpass" ]; then
        echo -e "\n${BR_CYAN}Select encryption method:${BR_NORM}"
        select c in openssl gpg; do
          if [ $REPLY = "q" ] || [ $REPLY = "Q" ]; then
            echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
            exit
          elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
            BRencmethod="openssl"
            break
          elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
            BRencmethod="gpg"
            break
          else
            echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
          fi
        done
      else
        BRencmethod="none"
      fi
      break
    done
  fi

  IFS=$DEFAULTIFS
  set_path
  set_tar_options
  set_names
  find_old_backups

  if [ -z "$BRquiet" ]; then
    while [ -f "$BRFile.$BR_EXT" ]; do
      echo -e "\n${BR_CYAN}Destination ($BRNAME.$BR_EXT) already exists.\nOverwrite?${BR_NORM}"
      read -p "(y/N):" an

      if [ -n "$an" ]; then def=$an; else def="n"; fi

      if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
        break
      elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
        echo -e "\n${BR_CYAN}Enter archive name\n${BR_MAGENTA}(Leave blank for default 'Backup-$(hostname)-$(date +%d-%m-%Y-%T)')${BR_NORM}"
        read -e -p "Name (without extension): " BRNAME
        set_names
      else
        echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
      fi
    done
  fi

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
      BRcontinue="n"
      echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
      exit
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  if [ -n "$BRoldbackups" ] && [ -n "$BRclean" ]; then
    for item in "${BRoldbackups[@]}"; do rm -r "$item"; done
  fi

  prepare
  show_summary >> "$BRFOLDER"/backup.log
  echo -e "\n${BR_SEP}ARCHIVER STATUS" >> "$BRFOLDER"/backup.log
  run_calc | while read ln; do a=$((a + 1)) && echo -en "\rCalculating: $a Files"; done
  total=$(cat /tmp/b_filelist | wc -l)
  sleep 1
  echo " "

  run_tar | out_pgrs_cli

  OUTPUT=$(chmod ugo+rw -R "$BRFOLDER" 2>&1) && echo -ne "\nSetting permissions: Done\n" || echo -ne "\nSetting permissions: Failed\n$OUTPUT\n"
  if [ ! -f /tmp/b_error ]; then echo "System archived successfully" >> "$BRFOLDER"/backup.log; fi

  elapsed=$(($(date +%s)-$start))
  echo "Elapsed time: $(($elapsed/3600)) hours $((($elapsed%3600)/60)) min $(($elapsed%60)) sec" >> "$BRFOLDER"/backup.log

  if [ -z "$BRquiet" ]; then
    exit_screen; read -s a
  else
    exit_screen_quiet
  fi

elif [ "$BRinterface" = "dialog" ]; then
  if [ -z $(which dialog 2>/dev/null) ];then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package dialog is not installed. Install the package and re-run the script"
    exit
  fi

  exec 3>&1
  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD

  if [ -z "$BRFOLDER" ]; then
    dialog --no-collapse --title "$BR_VERSION" --msgbox "$(info_screen)" 28 70
  fi

  if [ -z "$BRFOLDER" ]; then
    dialog --yesno "The default directory for creating the backup archive is </>.\n\nSave in the default directory?" 8 65
    if [ "$?" = "0" ]; then
      BRFOLDER="/"
    else
      BRpath=/
      while [ -z "$BRFOLDER" ]; do
        show_path
        BRselect=$(dialog --title "$BRcurrentpath" --no-cancel --extra-button --extra-label Set --menu "Set destination directory: (Highlight a directory and press Set)" 30 90 30 "<--UP" .. $(dir_list) 2>&1 1>&3)
        if [ "$?" = "3" ]; then
          if [ "$BRselect" = "<--UP" ]; then
            BRpath="$BRpath"
          else
            BRFOLDER="$BRpath${BRselect//\\/ }/"
            if [[ "$BRpath" == *//* ]]; then
              BRFOLDER="${BRFOLDER#*/}"
            fi
          fi
        else
          if [ "$BRselect" = "<--UP" ]; then
            BRpath="$(dirname "$BRpath")/"
          else
            BRpath="$BRpath$BRselect/"
            BRpath="${BRpath//\\/ }"
          fi
        fi
      done
    fi
  fi

  if [ -z "$BRNAME" ]; then
    BRNAME=$(dialog --no-cancel --inputbox "Enter archive name (without extension).\nLeave empty for default: <Backup-$(hostname)-$(date +%d-%m-%Y-%T)>." 9 70 2>&1 1>&3)
  fi

  if [ -z "$BRhome" ]; then
    REPLY=$(dialog --cancel-label Quit --menu "Home (/home) directory options:" 13 50 13 1 Include 2 "Only hidden files and folders" 3 Exclude 2>&1 1>&3)
    if [ "$?" = "1" ]; then exit; fi

    if [ "$REPLY" = "1" ]; then
      BRhome="Yes"
    elif [ "$REPLY" = "2" ]; then
      BRhome="No"
      BRhidden="Yes"
    elif [ "$REPLY" = "3" ]; then
      BRhome="No"
      BRhidden="No"
    fi
  fi

  if [ -z "$BRcompression" ]; then
    BRcompression=$(dialog --cancel-label Quit --menu "Select compression type:" 12 35 12 gzip "Fast, big file" bzip2 "Slow, smaller file" xz "Slow, smallest file" none "No compression" 2>&1 1>&3)
    if [ "$?" = "1" ]; then exit; fi
  fi

  if [ -z "$BR_USER_OPTS" ]; then
    BR_USER_OPTS=$(dialog --no-cancel --inputbox "Enter additional tar options. Leave empty for defaults.\n\n(If you want spaces in names replace them with //)\n(see tar --help)" 11 70 2>&1 1>&3)
  fi

  if which openssl &>/dev/null || which gpg &>/dev/null; then
    if [ -z "$BRencmethod" ]; then
      BRencpass=$(dialog --no-cancel --insecure --passwordbox "Enter passphrase to encrypt archive. Leave empty for no encryption." 9 70 2>&1 1>&3)
      if [ -n  "$BRencpass" ]; then
        REPLY=$(dialog --cancel-label Quit --menu "Select encryption method:" 12 35 12 1 openssl 2 gpg 2>&1 1>&3)
        if [ "$?" = "1" ]; then exit; fi
        if [ "$REPLY" = "1" ]; then
          BRencmethod="openssl"
        elif [ "$REPLY" = "2" ]; then
          BRencmethod="gpg"
        fi
      else
        BRencmethod="none"
      fi
    fi
  fi

  set_path
  set_tar_options
  set_names
  find_old_backups

  if [ -z "$BRquiet" ]; then
    while [ -f "$BRFile.$BR_EXT" ]; do
      dialog --title "Warning" --yes-label "OK" --no-label "Rename" --yesno "Destination ($BRNAME.$BR_EXT) already exists. Overwrite?" 6 70
      if [ "$?" = "1" ]; then
        BRNAME=$(dialog --no-cancel --inputbox "Enter archive name (without extension).\nLeave empty for default 'Backup-$(hostname)-$(date +%d-%m-%Y-%T)'." 8 70 2>&1 1>&3)
        set_names
      else
        break
      fi
    done
  fi

  if [ -z "$BRcontinue" ]; then
    dialog --no-collapse --title "Summary (PgUp/PgDn:Scroll)" --yes-label "OK" --no-label "Quit" --yesno "$(show_summary) $(echo -e "\n\nPress OK to continue or Quit to abort.")" 0 0
    if [ "$?" = "1" ]; then exit; fi
  fi

  if [ -n "$BRoldbackups" ] && [ -n "$BRclean" ]; then
    for item in "${BRoldbackups[@]}"; do rm -r "$item"; done
  fi

  prepare
  show_summary >> "$BRFOLDER"/backup.log
  echo -e "\n${BR_SEP}ARCHIVER STATUS" >> "$BRFOLDER"/backup.log
  (echo "Calculating: Wait..."
   run_calc | while read ln; do a=$((a + 1)) && echo "Calculating: $a Files"; done) | dialog --progressbox 3 40
  total=$(cat /tmp/b_filelist | wc -l)
  sleep 1

  run_tar |
  while read ln; do
    b=$((b + 1))
    per=$(($b*100/$total))
    if [[ $per -gt $lastper ]]; then
      lastper=$per
      echo $lastper
    fi
  done | dialog --gauge "Archiving..." 0 50

  chmod ugo+rw -R "$BRFOLDER" 2>> "$BRFOLDER"/backup.log
  if [ ! -f /tmp/b_error ]; then echo "System archived successfully" >> "$BRFOLDER"/backup.log; fi

  elapsed=$(($(date +%s)-$start))
  echo "Elapsed time: $(($elapsed/3600)) hours $((($elapsed%3600)/60)) min $(($elapsed%60)) sec" >> "$BRFOLDER"/backup.log

  if [ -z "$BRquiet" ]; then
    dialog --no-collapse --yes-label "OK" --no-label "View Log" --title "$diag_tl" --yesno "$(exit_screen)" 0 0
    if [ "$?" = "1" ]; then dialog --title "Log (Up/Dn:Scroll)" --no-collapse --textbox "$BRFOLDER"/backup.log 0 0; fi
  else
    dialog --no-collapse --title "$diag_tl" --infobox "$(exit_screen_quiet)" 0 0
  fi
fi

if [ -n "$BRgen" ] && [ ! -f /tmp/b_error ]; then
  echo -e "#Auto-generated configuration file for backup.sh.\n#Place it in /etc/backup.conf.\n\nBRinterface=$BRinterface\nBRFOLDER='$(dirname "$BRFOLDER")'\nBRcompression=$BRcompression" > "$BRFOLDER"/backup.conf
  if [ -n "$BRnocolor" ]; then echo "BRnocolor=Yes" >> "$BRFOLDER"/backup.conf; fi
  if [ -n "$BRverb" ]; then echo "BRverb=Yes" >> "$BRFOLDER"/backup.conf; fi
  if [ -n "$BRquiet" ]; then echo "BRquiet=Yes" >> "$BRFOLDER"/backup.conf; fi
  if [ ! "$BRFile" = "$BRfiledefault" ]; then echo "BRNAME='$BRNAME'" >> "$BRFOLDER"/backup.conf; fi
  if [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ]; then echo "BRhome=No" >> "$BRFOLDER"/backup.conf; fi
  if [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ]; then echo -e "BRhome=No\nBRhidden=No" >> "$BRFOLDER"/backup.conf; fi
  if [ -n "$BRoverride" ]; then echo "BRoverride=Yes" >> "$BRFOLDER"/backup.conf; fi
  if [ "$BR_USER_OPTS" = " " ]; then unset BR_USER_OPTS; fi
  if [ -n "$BR_USER_OPTS" ]; then echo "BR_USER_OPTS='$BR_USER_OPTS'" >> "$BRFOLDER"/backup.conf; fi
  if [ -n "$BRencpass" ]; then echo -e "BRencmethod=$BRencmethod\nBRencpass='$BRencpass'" >> "$BRFOLDER"/backup.conf; fi
  if [ -n "$BRclean" ]; then echo "BRclean=Yes" >> "$BRFOLDER"/backup.conf; fi
fi

if [ -n "$BRhide" ]; then echo -en "${BR_SHOW}"; fi
clean_files

