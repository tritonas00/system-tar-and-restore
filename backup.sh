#!/bin/bash

BR_VERSION="System Tar & Restore 3.9.2"
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
  echo -e "\n${BR_YELLOW}This script will make a tar backup image of this system."
  echo -e "\n==>Make sure you have enough free space."
  echo -e "\n==>Make sure you have GRUB or SYSLINUX packages installed."
  echo -e "\nGRUB PACKAGES:"
  echo "->Arch:   grub    efibootmgr* dosfstools*"
  echo "->Debian: grub-pc grub-efi*   dosfstools*"
  echo "->Fedora: grub2   efibootmgr* dosfstools*"
  echo -e "\nSYSLINUX PACKAGES:"
  echo "->Arch:   syslinux"
  echo "->Debian: syslinux extlinux"
  echo -e "->Fedora: syslinux syslinux-extlinux"
  echo -e "\n*Required for UEFI systems"
  echo -e "\n${BR_CYAN}Press ENTER to continue.${BR_NORM}"
}

exit_screen() {
  if [ -f /tmp/b_error ]; then
    echo -e "${BR_RED}\nAn error occurred. Check "$BRFOLDER"/backup.log for details.\n\n${BR_CYAN}Press ENTER to exit.${BR_NORM}"
  else
    echo -e "${BR_CYAN}\nCompleted. Backup archive and log saved in $BRFOLDER\n\nPress ENTER to exit.${BR_NORM}"
  fi
}

exit_screen_quiet() {
  if [ -f /tmp/b_error ]; then
    echo -e "${BR_RED}\nAn error occurred.\n\nCheck "$BRFOLDER"/backup.log for details${BR_NORM}"
  else
    echo -e "${BR_CYAN}\nCompleted.\n\nBackup archive and log saved in $BRFOLDER${BR_NORM}"
  fi
}

show_summary() {
  echo -e "${BR_YELLOW}ARCHIVE:"
  echo "$BRFile.$BR_EXT"

  echo -e "\nARCHIVER INFO:"
  echo "Archiver:    $BRarchiver"
  echo "Compression: $BRcompression"

  echo -e "\nARCHIVER OPTIONS:"
  echo "--exclude=$BRFOLDER"
  echo "${BR_TAROPTS[@]}" | sed -r -e 's/\s+/\n/g' | sed 'N;s/\n/ /'

  echo -e "\nHOME DIRECTORY:"
  if [ "$BRhome" = "Yes" ]; then
    echo "Include"
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ]; then
    echo "Only hidden files and folders"
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ]; then
    echo "Exclude"
  fi

  echo -e "\nFOUND BOOTLOADERS:"
  if [ -d /usr/lib/grub ]; then echo "Grub"; fi
  if which extlinux &>/dev/null; then BRextlinux="y"; fi
  if which syslinux &>/dev/null; then BRsyslinux="y"; fi
  if [ -n "$BRextlinux" ] && [ -n "$BRsyslinux" ]; then
    echo "Syslinux"
  fi
  if [ -z "$BRextlinux" ] || [ -z "$BRsyslinux" ] && [ ! -d /usr/lib/grub ]; then
    echo "None or not supported"
  fi
  echo -e "${BR_NORM}"
}

dir_list() {
  DEFAULTIFS=$IFS
  IFS=$'\n'
  for D in "$BRpath"*; do [ -d "${D}" ] && echo "$( basename ${D// /\\} ) dir"; done
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
  fi

  if [ "$BRarchiver" = "tar" ]; then
    BR_TAROPTS="--exclude=/run/* --exclude=/proc/* --exclude=/dev/* --exclude=/media/* --exclude=/sys/* --exclude=/tmp/* --exclude=/mnt/* --exclude=.gvfs --exclude=lost+found --sparse $BR_USER_OPTS"
    if [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ] ; then
      BR_TAROPTS="${BR_TAROPTS} --exclude=/home/*"
    elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ] ; then
      find /home/*/* -maxdepth 0 -iname ".*" -prune -o -print > /tmp/excludelist
      BR_TAROPTS="${BR_TAROPTS} --exclude-from=/tmp/excludelist"
    fi
  elif [ "$BRarchiver" = "bsdtar" ]; then
    BR_TAROPTS=(--exclude=/run/*?* --exclude=/proc/*?* --exclude=/dev/*?* --exclude=/media/*?* --exclude=/sys/*?* --exclude=/tmp/*?* --exclude=/mnt/*?* --exclude=.gvfs --exclude=lost+found "$BR_USER_OPTS")
    if [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ] ; then
      BR_TAROPTS+=(--exclude=/home/*?*)
    elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ] ; then
      find /home/*/* -maxdepth 0 -iname ".*" -prune -o -print > /tmp/excludelist
      BR_TAROPTS+=(--exclude-from=/tmp/excludelist)
    fi
  fi
}

run_calc() {
  if [ "$BRarchiver" = "tar" ]; then
    $BRarchiver cvf /dev/null ${BR_TAROPTS} --exclude="$BRFOLDER" / 2> /dev/null | tee /tmp/filelist | while read ln; do a=$(( a + 1 )) && echo -en "\rCalculating: $a Files"; done
  elif [ "$BRarchiver" = "bsdtar" ]; then
    $BRarchiver cvf /dev/null ${BR_TAROPTS[@]} --exclude="$BRFOLDER" / 2>&1 | tee /tmp/filelist | while read ln; do a=$(( a + 1 )) && echo -en "\rCalculating: $a Files"; done
  fi
}

run_tar() {
  if [ "$BRarchiver" = "tar" ]; then
    $BRarchiver ${BR_MAINOPTS} "$BRFile".${BR_EXT} ${BR_TAROPTS} --exclude="$BRFOLDER" / && (echo "System compressed successfully" >> "$BRFOLDER"/backup.log) || touch /tmp/b_error
  elif [ "$BRarchiver" = "bsdtar" ]; then
    $BRarchiver ${BR_MAINOPTS} "$BRFile".${BR_EXT} ${BR_TAROPTS[@]} --exclude="$BRFOLDER" / 2>&1 && (echo "System compressed successfully" >> "$BRFOLDER"/backup.log) || touch /tmp/b_error
  fi
}

set_paths() {
  BRFOLDER_IN=(`echo ${BRFOLDER}/Backup-$(date +%d-%m-%Y) | sed 's://*:/:g'`)
  BRFOLDER="${BRFOLDER_IN[@]}"
  if [ -n "$BRNAME" ]; then
    BRFile="$BRFOLDER"/"$BRNAME"
  else
    BRFile="$BRFOLDER"/Backup-$(hostname)-$(date +%d-%m-%Y-%T)
  fi
}

set_names() {
  if [ -n "$BRNAME" ]; then
    BRFile="$BRFOLDER"/"$BRNAME"
  else
    BRFile="$BRFOLDER"/Backup-$(hostname)-$(date +%d-%m-%Y-%T)
  fi
}

prepare() {
  touch /target_architecture.$(uname -m)
  if [ "$BRinterface" = "cli" ]; then echo -e "\n${BR_SEP}CREATING ARCHIVE"; fi
  mkdir -p "$BRFOLDER"
  echo "--------------$(date +%d-%m-%Y-%T)--------------" >> "$BRFOLDER"/backup.log
  sleep 1
}

report_vars_log() {
  echo -e "\n${BR_SEP}VERBOSE SUMMARY"
  echo "Archive: $BRNAME.${BR_EXT}"
  echo "Archiver: $BRarchiver"
  echo "Compression: $BRcompression"
  echo "Options: ${BR_TAROPTS[@]} --exclude=$BRFOLDER"
  echo "Home: $BRhome"
  echo "Hidden: $BRhidden"
  if [ -d /usr/lib/grub ]; then echo "Bootloader: Grub"; fi
  if which extlinux &>/dev/null; then BRextlinux="y"; fi
  if which syslinux &>/dev/null; then BRsyslinux="y"; fi
  if [ -n "$BRextlinux" ] && [ -n "$BRsyslinux" ]; then
    echo "Bootloader: Syslinux"
  fi

  if [ -z "$BRextlinux" ] || [ -z "$BRsyslinux" ] && [ ! -d /usr/lib/grub ]; then
    echo "Bootloader: None or not supported"
  fi

  echo -e "\n${BR_SEP}ARCHIVER STATUS"
}

options_info() {
  if [ "$BRarchiver" = "tar" ]; then
    BRoptinfo="see tar --help"
  elif [ "$BRarchiver" = "bsdtar" ]; then
    BRoptinfo="see man bsdtar"
  fi
}

out_pgrs_cli() {
  if [ -n "$BRverb" ]; then
    echo -e "\rCompressing: $(($b*100/$total))% ${BR_GREEN}$ln${BR_NORM}"
  else
    echo -en "\rCompressing: $(($b*100/$total))%"
  fi
}

BRargs=`getopt -o "i:d:f:c:u:hnNa:qv" -l "interface:,directory:,filename:,compression:,user-options:,exclude-home,no-hidden,no-color,archiver:,quiet,verbose,help" -n "$1" -- "$@"`

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
      BRuseroptions="Yes"
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
    -a|--archiver)
      BRarchiver=$2
      shift 2
    ;;
    -q|--quiet)
      BRcontinue="y"
      BRquiet="y"
      shift
    ;;
    -v|--verbose)
      BRverb="y"
      shift
    ;;
    --help)
      BR_BOLD='\033[1m'
      BR_NORM='\e[00m'
      echo -e "
${BR_BOLD}$BR_VERSION

Interface:${BR_NORM}
  -i, --interface         interface to use (cli dialog)
  -N, --no-color          disable colors
  -q, --quiet             dont ask, just run
  -v, --verbose           enable verbose archiver output (cli only)

${BR_BOLD}Destination:${BR_NORM}
  -d, --directory         backup folder path
  -f, --filename          backup file name (without extension)

${BR_BOLD}Home Directory:${BR_NORM}
  -h, --exclude-home	  exclude /home directory (keep hidden files and folders)
  -n, --no-hidden         dont keep home's hidden files and folders (use with -h)

${BR_BOLD}Archiver Options:${BR_NORM}
  -a, --archiver          select archiver (tar bsdtar)
  -c, --compression       compression type (gzip bzip2 xz)
  -u, --user-options      additional tar options (see tar --help or man bsdtar)

--help	print this page
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

BR_WRK="[${BR_CYAN}WORKING${BR_NORM}] "

if [ $(id -u) -gt 0 ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Script must run as root"
  exit
fi

if [ -f /etc/yum.conf ] && [ "$BRarchiver" = "tar" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Only bsdtar is supported on Fedora"
  BRSTOP="y"
fi

if [ ! -d "$BRFOLDER" ] && [ -n "$BRFOLDER" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Directory does not exist: $BRFOLDER"
  BRSTOP="y"
fi

if [ -n "$BRcompression" ] && [ ! "$BRcompression" = "gzip" ] && [ ! "$BRcompression" = "xz" ] && [ ! "$BRcompression" = "bzip2" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong compression type: $BRcompression. Supported compressors: gzip bzip2 xz"
  BRSTOP="y"
fi

if [ -n "$BRarchiver" ] && [ ! "$BRarchiver" = "tar" ] && [ ! "$BRarchiver" = "bsdtar" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong archiver: $BRarchiver. Available options: tar bsdtar"
  BRSTOP="y"
fi

if [ -n "$BRinterface" ] && [ ! "$BRinterface" = "cli" ] && [ ! "$BRinterface" = "dialog" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong interface name: $BRinterface. Available options: cli dialog"
  BRSTOP="y"
fi

if [ -f /etc/yum.conf ] && [ -z $(which bsdtar 2> /dev/null) ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
  BRSTOP="y"
fi

if [ -n "$BRSTOP" ]; then
  exit
fi

if [ -f /etc/yum.conf ]; then
  BRarchiver="bsdtar"
fi

if [ -z "$BRhidden" ]; then
  BRhidden="Yes"
fi

if [ -n "$BRFOLDER" ]; then
  if [ -z "$BRhome" ]; then
    BRhome="Yes"
  fi
  if [ -z "$BRuseroptions" ]; then
    BRuseroptions="No"
  fi
  if [ -z "$BRNAME" ]; then
    BRNAME="Backup-$(hostname)-$(date +%d-%m-%Y-%T)"
  fi
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
  DEFAULTIFS=$IFS
  IFS=$'\n'

  if [ -z "$BRFOLDER" ]; then
    info_screen
    read -s a
  fi

  while [ -z "$BRFOLDER" ] || [ ! -d "$BRFOLDER" ]; do
    echo -e "\n${BR_CYAN}Enter path to save the backup archive (leave blank for default '/')${BR_NORM}"
    read -e -p "Path: " BRFOLDER
    if [ -z "$BRFOLDER" ]; then
      BRFOLDER="/"
    elif [ ! -d "$BRFOLDER" ]; then
      echo -e "${BR_RED}Directory does not exist${BR_NORM}"
    fi
  done

  if [ -z "$BRNAME" ]; then
    echo -e "\n${BR_CYAN}Enter archive name (leave blank for default 'Backup-$(hostname)-$(date +%d-%m-%Y-%T)')${BR_NORM}"
    read -e -p "Name (without extension): " BRNAME
  fi

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

  if [ -z "$BRarchiver" ]; then
    echo -e "\n${BR_CYAN}Select archiver:${BR_NORM}"
    select c in "tar    (GNU Tar)" "bsdtar (Libarchive Tar)"; do
      if [ $REPLY = "q" ] || [ $REPLY = "Q" ]; then
        echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
        exit
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        BRarchiver="tar"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        BRarchiver="bsdtar"
        break
      else
        echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
      fi
    done
  fi

  if [ "$BRarchiver" = "bsdtar" ] && [ -z $(which bsdtar 2> /dev/null) ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
    exit
  fi

  if [ -z "$BRcompression" ]; then
    echo -e "\n${BR_CYAN}Select the type of compression:${BR_NORM}"
    select c in "gzip  (Fast, big file)" "bzip2 (Slow, smaller file)" "xz    (Slow, smallest file)"; do
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
      else
        echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
      fi
    done
  fi

  options_info

  if [ -z "$BRuseroptions" ]; then
    echo -e "\n${BR_CYAN}Enter additional $BRarchiver options (leave blank for defaults)${BR_NORM}"
    read -p "Options ($BRoptinfo): " BR_USER_OPTS
  fi

  IFS=$DEFAULTIFS
  set_tar_options
  set_paths
  set_names

  if [ -z "$BRquiet" ]; then
    while [ -f "$BRFile.$BR_EXT" ]; do
      echo -e "\n${BR_CYAN}File $BRFile.$BR_EXT already exists.\nOverwrite?${BR_NORM}"
      read -p "(y/N):" an

      if [ -n "$an" ]; then def=$an; else def="n"; fi

      if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
        break
      elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
        echo -e "\n${BR_CYAN}Enter archive name (leave blank for default 'Backup-$(hostname)-$(date +%d-%m-%Y-%T)')${BR_NORM}"
        read -e -p "Name (without extension): " BRNAME
        set_names
      else
        echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
      fi
    done
  fi

  echo -e "\n${BR_SEP}SUMMARY"
  show_summary

  while [ -z "$BRcontinue" ]; do
    echo -e "${BR_CYAN}Continue?${BR_NORM}"
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

  prepare
  report_vars_log >> "$BRFOLDER"/backup.log
  run_calc
  total=$(cat /tmp/filelist | wc -l)
  sleep 1
  echo " "
  if [ "$BRarchiver" = "bsdtar" ]; then
    run_tar | tee /tmp/bsdtar_out
  elif [ "$BRarchiver" = "tar" ]; then
    run_tar 2>>"$BRFOLDER"/backup.log
  fi | while read ln; do b=$(( b + 1 )) && out_pgrs_cli; done

  echo -ne "\n${BR_WRK}Setting permissions"
  OUTPUT=$(chmod ugo+rw -R "$BRFOLDER" 2>&1) && echo -e "\r[${BR_GREEN}SUCCESS${BR_NORM}]" || echo -e "\r[${BR_RED}FAILURE${BR_NORM}]\n$OUTPUT"

  if [ "$BRarchiver" = "bsdtar" ] && [ -f /tmp/b_error ]; then
    cat /tmp/bsdtar_out >> "$BRFOLDER"/backup.log
  fi

  if [ -z "$BRquiet" ]; then
    exit_screen; read -s a
  else
    exit_screen_quiet
  fi

elif [ "$BRinterface" = "dialog" ]; then
  if [ -z $(which dialog 2> /dev/null) ];then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package dialog is not installed. Install the package and re-run the script"
    exit
  fi

  exec 3>&1
  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD

  if [ -z "$BRFOLDER" ]; then
    dialog --no-collapse --title "$BR_VERSION" --msgbox "$(info_screen)" 24 70
  fi

  if [ -z "$BRFOLDER" ]; then
    dialog --yesno "The default folder for creating the backup archive is / (root).\n\nSave in the default folder?" 8 65
    if [ "$?" = "0" ]; then
      BRFOLDER="/"
    else
      BRpath=/
      while [ -z "$BRFOLDER" ]; do
        show_path
        BRselect=$(dialog --title "$BRcurrentpath" --no-cancel --extra-button --extra-label Set --menu "Set destination folder: (Highlight a directory and press Set)" 30 90 30 "<--UP" .. $(dir_list) 2>&1 1>&3)
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
    BRNAME=$(dialog --no-cancel --inputbox "Enter archive name (without extension).\nLeave empty for default 'Backup-$(hostname)-$(date +%d-%m-%Y-%T)'." 8 70 2>&1 1>&3)
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

  if [ -z "$BRarchiver" ]; then
    BRarchiver=$(dialog --cancel-label Quit --menu "Select archiver:" 12 35 12 tar "GNU Tar" bsdtar "Libarchive Tar" 2>&1 1>&3)
    if [ "$?" = "1" ]; then exit; fi
  fi

  if [ "$BRarchiver" = "bsdtar" ] && [ -z $(which bsdtar 2> /dev/null) ]; then
    if [ -z "$BRnocolor" ]; then color_variables; fi
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
    exit
  fi

  if [ -z "$BRcompression" ]; then
    BRcompression=$(dialog --cancel-label Quit --menu "Select compression type:" 12 35 12 gzip "Fast, big file" bzip2 "Slow, smaller file" xz "Slow, smallest file" 2>&1 1>&3)
    if [ "$?" = "1" ]; then exit; fi
  fi

  options_info

  if [ -z "$BRuseroptions" ]; then
    BR_USER_OPTS=$(dialog --no-cancel --inputbox "Enter additional $BRarchiver options. Leave empty for defaults.\n($BRoptinfo)" 8 70 2>&1 1>&3)
  fi

  set_tar_options
  set_paths
  set_names

  if [ -z "$BRquiet" ]; then
    while [ -f "$BRFile.$BR_EXT" ]; do
      dialog --title "Warning" --yes-label "OK" --no-label "Rename" --yesno "$BRFile.$BR_EXT already exists. Overwrite?" 0 0
      if [ "$?" = "1" ]; then
        BRNAME=$(dialog --no-cancel --inputbox "Enter archive name (without extension).\nLeave empty for default 'Backup-$(hostname)-$(date +%d-%m-%Y-%T)'." 8 70 2>&1 1>&3)
        set_names
      else
        break
      fi
    done
  fi

  if [ -z "$BRcontinue" ]; then
    dialog --no-collapse --title "Summary" --yes-label "OK" --no-label "Quit" --yesno "$(show_summary) $(echo -e "\n\nPress OK to continue or Quit to abort.")" 0 0
    if [ "$?" = "1" ]; then exit; fi
  fi

  prepare
  report_vars_log >> "$BRFOLDER"/backup.log
  run_calc | dialog --progressbox 3 40
  total=$(cat /tmp/filelist | wc -l)
  sleep 1

  if [ "$BRarchiver" = "bsdtar" ]; then
    run_tar | tee /tmp/bsdtar_out
  elif [ "$BRarchiver" = "tar" ]; then
    run_tar 2>>"$BRFOLDER"/backup.log
  fi |

  while read ln; do
    b=$(( b + 1 ))
    per=$(($b*100/$total))
    if [[ $per -gt $lastper ]]; then
      lastper=$per
      echo $lastper
    fi
  done | dialog --gauge "Compressing..." 0 50

  chmod ugo+rw -R "$BRFOLDER" 2>> "$BRFOLDER"/backup.log

  if [ "$BRarchiver" = "bsdtar" ] && [ -f /tmp/b_error ]; then
    cat /tmp/bsdtar_out >> "$BRFOLDER"/backup.log
  fi

  if [ -f /tmp/b_error ]; then diag_tl="Error"; else diag_tl="Info"; fi

  if [ -z "$BRquiet" ]; then
    dialog --yes-label "OK" --no-label "View Log" --title "$diag_tl" --yesno "$(exit_screen)" 0 0
    if [ "$?" = "1" ]; then dialog --textbox "$BRFOLDER"/backup.log 0 0; fi
  else
    dialog --title "$diag_tl" --infobox "$(exit_screen_quiet)" 0 0
  fi
fi

if [ -f /tmp/excludelist ]; then rm /tmp/excludelist; fi
if [ -f /tmp/b_error ]; then rm /tmp/b_error; fi
if [ -f /tmp/filelist ]; then rm /tmp/filelist; fi
if [ -f /tmp/bsdtar_out ]; then rm /tmp/bsdtar_out; fi
if [ -f /target_architecture.$(uname -m) ]; then rm /target_architecture.$(uname -m); fi
