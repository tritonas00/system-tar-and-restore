#!/bin/bash

BR_VERSION="System Tar & Restore 3.6.11"
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
  echo "This script will make a tar backup image of your entire system."
  echo -e "\n==>Make sure you have enough free space."
  echo -e "\n==>Also make sure you have GRUB or SYSLINUX packages installed."
  echo -e "\n${BR_YELLOW}GRUB PACKAGES:${BR_NORM}"
  echo "->Arch: grub-bios"
  echo "->Debian: grub-pc"
  echo "->Fedora: grub2"
  echo -e "\n${BR_YELLOW}SYSLINUX PACKAGES:${BR_NORM}"
  echo "->Arch: syslinux"
  echo "->Debian: syslinux extlinux"
  echo "->Fedora: syslinux syslinux-extlinux"
  echo -e "\n${BR_CYAN}Press ENTER to continue.${BR_NORM}"
}

show_summary() {
  echo -e "${BR_YELLOW}DESTINATION:"
  echo "$BRFOLDER"

  echo -e "\nARCHIVER OPTIONS:"
  echo "Archiver: $BRarchiver"
  echo "Compression: $BRcompression"

  echo -e "\nHOME DIRECTORY:"
  if [ "$BRhome" = "Yes" ]; then
    echo "Include"
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ]; then
    echo "Only hidden files and folders"
  elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ]; then
    echo "Exclude"
  fi

  if [ "$BRfedoratar" = "y" ] && [ "$BRarchiver" = "tar" ]; then
    echo -e "\nEXTRA OPTIONS:"
    echo "--acls --selinux --xattrs"
  fi

  if [ -n "$BR_USER_OPTS" ]; then
    echo -e "\nUSER OPTIONS:"
    echo "$BR_USER_OPTS"
  fi

  echo -e "\nFOUND BOOTLOADERS:"
  if [ -d /usr/lib/grub/i386-pc ]; then
    echo "Grub"
  fi
  if which extlinux &>/dev/null; then
    echo "Syslinux"
  fi
  if [ ! -d /usr/lib/grub/i386-pc ] && [ -z $(which extlinux 2> /dev/null) ];then
    echo "None or not supported"
  fi
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
  if [ "$BRarchiver" = "tar" ]; then
    BR_TAROPTS="$BR_USER_OPTS --sparse --exclude=/run/* --exclude=/dev/* --exclude=/proc/* --exclude=lost+found --exclude=/sys/* --exclude=/media/* --exclude=/tmp/* --exclude=/mnt/* --exclude=.gvfs"
    if [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ] ; then
      BR_TAROPTS="${BR_TAROPTS} --exclude=/home/*"
    elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "Yes" ] ; then
      find /home/*/* -maxdepth 0 -iname ".*" -prune -o -print > /tmp/excludelist
      BR_TAROPTS="${BR_TAROPTS} --exclude-from=/tmp/excludelist"
    fi
    if [ "$BRfedoratar" = "y" ]; then
      BR_TAROPTS="${BR_TAROPTS} --acls --selinux --xattrs"
    fi
  elif [ "$BRarchiver" = "bsdtar" ]; then
    BR_TAROPTS=("$BR_USER_OPTS" --exclude=/run/*?* --exclude=/dev/*?* --exclude=/proc/*?* --exclude=/sys/*?* --exclude=/media/*?* --exclude=/tmp/*?* --exclude=/mnt/*?* --exclude=.gvfs --exclude=lost+found)
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
    if [ "$BRcompression" = "gzip" ]; then
      $BRarchiver cvpzf "$BRFile".tar.gz ${BR_TAROPTS} --exclude="$BRFOLDER" / && (echo "System compressed successfully" >> "$BRFOLDER"/backup.log) || touch /tmp/b_error
    elif [ "$BRcompression" = "xz" ]; then
      $BRarchiver cvpJf "$BRFile".tar.xz ${BR_TAROPTS} --exclude="$BRFOLDER" / && (echo "System compressed successfully" >> "$BRFOLDER"/backup.log) || touch /tmp/b_error
    fi
  elif [ "$BRarchiver" = "bsdtar" ]; then
    if [ "$BRcompression" = "gzip" ]; then
      $BRarchiver cvpzf "$BRFile".tar.gz ${BR_TAROPTS[@]} --exclude="$BRFOLDER" / 2>&1 && (echo "System compressed successfully" >> "$BRFOLDER"/backup.log) || touch /tmp/b_error
    elif [ "$BRcompression" = "xz" ]; then
      $BRarchiver cvpJf "$BRFile".tar.xz ${BR_TAROPTS[@]} --exclude="$BRFOLDER" / 2>&1 && (echo "System compressed successfully" >> "$BRFOLDER"/backup.log) || touch /tmp/b_error
    fi
  fi
}

prepare() {
  BRFOLDER_IN=(`echo ${BRFOLDER}/Backup-$(date +%d-%m-%Y) | sed 's://*:/:g'`)
  BRFOLDER="${BRFOLDER_IN[@]}"
  if [ "$BRinterface" = "cli" ]; then
    echo -e "\n${BR_SEP}CREATING ARCHIVE"
  fi
  mkdir -p "$BRFOLDER"
  echo "--------------$(date +%d-%m-%Y-%T)--------------" >> "$BRFOLDER"/backup.log
  sleep 1
  BRFile="$BRFOLDER"/Backup-$(hostname)-$(date +%d-%m-%Y-%T)
}

BRargs=`getopt -o "i:d:c:u:hnNa:" -l "interface:,directory:,compression:,user-options:,exclude-home,no-hidden,no-color,archiver:,help" -n "$1" -- "$@"`

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
    --help)
      BR_BOLD='\033[1m'
      BR_NORM='\e[00m'
      echo -e "
${BR_BOLD}$BR_VERSION

Interface:${BR_NORM}
  -i, --interface         interface to use (cli dialog)
  -N, --no-color          disable colors

${BR_BOLD}Destination:${BR_NORM}
  -d, --directory         backup folder path

${BR_BOLD}Home Directory:${BR_NORM}
  -h, --exclude-home	  exclude /home (keep hidden files and folders)
  -n, --no-hidden         dont keep home's hidden files and folders (use with -h)

${BR_BOLD}Archiver Options:${BR_NORM}
  -a, --archiver          select archiver (tar bsdtar)
  -c, --compression       compression type (gzip xz)
  -u, --user-options      additional tar options (See tar --help or man bsdtar)

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

if [ $(id -u) -gt 0 ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Script must run as root"
  exit
fi

if [ -f /etc/yum.conf ]; then
  BRfedoratar="y"
fi

if [ ! -d "$BRFOLDER" ] && [ -n "$BRFOLDER" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Directory does not exist: $BRFOLDER"
  BRSTOP=y
fi

if [ -n "$BRcompression" ] && [ ! "$BRcompression" = "gzip" ] && [ ! "$BRcompression" = "xz" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong compression type: $BRcompression. Supported compressors: gzip xz"
  BRSTOP=y
fi

if [ -n "$BRarchiver" ] && [ ! "$BRarchiver" = "tar" ] && [ ! "$BRarchiver" = "bsdtar" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong archiver: $BRarchiver. Available options: tar bsdtar"
  BRSTOP=y
fi

if [ -n "$BRinterface" ] && [ ! "$BRinterface" = "cli" ] && [ ! "$BRinterface" = "dialog" ]; then
  echo -e "[${BR_RED}ERROR${BR_NORM}] Wrong interface name: $BRinterface. Available options: cli dialog"
  BRSTOP=y
fi

if [ -n "$BRSTOP" ]; then
  exit
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
fi

PS3="Choice: "

while [ -z "$BRinterface" ]; do
  echo -e "\n${BR_CYAN}Select interface or enter Q to quit${BR_NORM}"
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
      echo -e "${BR_RED}Please enter a valid option from the list or enter Q to quit${BR_NORM}"
    fi
  done
done

if [ "$BRinterface" = "cli" ]; then
  clear
  echo -e "${BR_BOLD}$BR_VERSION${BR_NORM}"
  echo " "
  DEFAULTIFS=$IFS
  IFS=$'\n'

  if [ -z "$BRFOLDER" ]; then
    info_screen
    read -s a
    clear
  fi

  while [ -z "$BRFOLDER" ]; do
    echo -e "\n${BR_CYAN}The default folder for creating the backup image is / (root).\nSave in the default folder?${BR_NORM}"
    read -p "(Y/n): " an

    if [ -n "$an" ]; then
      def=$an
    else
      def="y"
    fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRFOLDER="/"
    elif [ "$def" = "n" ] || [ "$def" = "N" ]; then
      while [ -z "$BRFOLDER" ] || [ ! -d "$BRFOLDER" ]; do
        echo -e "\n${BR_CYAN}Enter the path where the backup will be created${BR_NORM}"
        read -p "Path: " BRFOLDER
        if [ ! -d "$BRFOLDER" ]; then
          echo -e "${BR_RED}Directory does not exist.${BR_NORM}"
        fi
      done
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  while [ -z "$BRhome" ] ; do
    echo -e "\n${BR_CYAN}Home (/home) directory options:${BR_NORM}"
    select c in "Include" "Only hidden files and folders" "Exclude"; do
      if [ "$REPLY" = "1" ]; then
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
  done

  while [ -z "$BRarchiver" ]; do
    echo -e "\n${BR_CYAN}Select archiver:${BR_NORM}"
    select c in "tar    (GNU Tar)" "bsdtar (Libarchive Tar)"; do
      if [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        BRarchiver="tar"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        BRarchiver="bsdtar"
        break
      else
        echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
      fi
    done
  done

  if [ "$BRarchiver" = "bsdtar" ] && [ -z $(which bsdtar 2> /dev/null) ]; then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
    exit
  fi

  while [ -z "$BRcompression" ]; do
    echo -e "\n${BR_CYAN}Select the type of compression:${BR_NORM}"
    select c in "gzip (Fast, big file)" "xz   (Slow, smaller file)"; do
      if [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 1 ]; then
        BRcompression="gzip"
        break
      elif [[ "$REPLY" = [0-9]* ]] && [ "$REPLY" -eq 2 ]; then
        BRcompression="xz"
        break
      else
        echo -e "${BR_RED}Please enter a valid option from the list${BR_NORM}"
      fi
    done
  done

  while [ -z "$BRuseroptions" ]; do
    echo -e "\n${BR_CYAN}Enter additional $BRarchiver options?${BR_NORM}"
    read -p "(y/N):" an

    if [ -n "$an" ]; then
      def=$an
    else
      def="n"
    fi

    if [ "$def" = "y" ] || [ "$def" = "Y" ]; then
      BRuseroptions="Yes"
      read -p "Enter options (See tar --help or man bsdtar):" BR_USER_OPTS
    elif [ $def = "n" ] || [ $def = "N" ]; then
      BRuseroptions="No"
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  IFS=$DEFAULTIFS

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
      BRcontinue="n"
      echo -e "${BR_YELLOW}Aborted by User${BR_NORM}"
      exit
    else
      echo -e "${BR_RED}Please enter a valid option${BR_NORM}"
    fi
  done

  if [  "x$BRcontinue" = "xy" ]; then
    prepare
    set_tar_options
    run_calc
    total=$(cat /tmp/filelist | wc -l)
    sleep 1
    echo " "
    if [ "$BRarchiver" = "bsdtar" ]; then
      run_tar | tee /tmp/bsdtar_out
    elif [ "$BRarchiver" = "tar" ]; then
      run_tar 2>>"$BRFOLDER"/backup.log
    fi | while read ln; do b=$(( b + 1 )) && echo -en "\rCompressing: $(($b*100/$total))%"; done

    echo -ne "\nSetting permissions "
    OUTPUT=$(chmod ugo+rw -R "$BRFOLDER" 2>&1) && echo -e "[${BR_GREEN}OK${BR_NORM}]" || echo -e "[${BR_RED}FAILED${BR_NORM}]\n$OUTPUT"

    if [ "$BRarchiver" = "bsdtar" ] && [ -f /tmp/b_error ]; then
      cat /tmp/bsdtar_out >> "$BRFOLDER"/backup.log
    fi

    if [ -f /tmp/b_error ]; then
      echo -e "${BR_RED}\nAn error occurred. Check "$BRFOLDER"/backup.log for details.\n${BR_CYAN}Press ENTER to exit.${BR_NORM}"
    else
      echo -e "${BR_CYAN}\nCompleted. Backup archive and log saved in $BRFOLDER.\nPress ENTER to exit.${BR_NORM}"
    fi
  fi

  read -s a

elif [ "$BRinterface" = "dialog" ]; then
  if [ -z $(which dialog 2> /dev/null) ];then
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package dialog is not installed. Install the package and re-run the script"
    exit
  fi

  exec 3>&1
  unset BR_NORM BR_RED BR_GREEN BR_YELLOW BR_BLUE BR_MAGENTA BR_CYAN BR_BOLD

  if [ -z "$BRFOLDER" ]; then
    dialog --title "$BR_VERSION" --msgbox "$(info_screen)" 22 70
  fi

  while [ -z "$BRFOLDER" ]; do
    dialog --yesno "The default folder for creating the backup image is / (root).\n\nSave in the default folder?" 8 65
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
  done

  while [ -z "$BRhome" ]; do
    REPLY=$(dialog --no-cancel --menu "Home (/home) directory options:" 13 50 13 1 Include 2 "Only hidden files and folders" 3 Exclude 2>&1 1>&3)
    if [ "$REPLY" = "1" ]; then
      BRhome="Yes"
    elif [ "$REPLY" = "2" ]; then
      BRhome="No"
      BRhidden="Yes"
    elif [ "$REPLY" = "3" ]; then
      BRhome="No"
      BRhidden="No"
    fi
  done

  while [ -z "$BRarchiver" ]; do
    BRarchiver=$(dialog --no-cancel --menu "Select archiver:" 12 35 12 tar "GNU Tar" bsdtar "Libarchive Tar" 2>&1 1>&3)
  done

  if [ "$BRarchiver" = "bsdtar" ] && [ -z $(which bsdtar 2> /dev/null) ]; then
    if [ -z "$BRnocolor" ]; then
      color_variables
    fi
    echo -e "[${BR_RED}ERROR${BR_NORM}] Package bsdtar is not installed. Install the package and re-run the script"
    exit
  fi

  while [ -z "$BRcompression" ]; do
    BRcompression=$(dialog --no-cancel --menu "Select compression type:" 12 35 12 gzip "Fast, big file" xz "Slow, smaller file" 2>&1 1>&3)
  done

  while [ -z "$BRuseroptions" ]; do
    dialog --yesno "Specify additional $BRarchiver options?" 6 39
    if [ "$?" = "0" ]; then
      BRuseroptions="Yes"
      BR_USER_OPTS=$(dialog --no-cancel --inputbox "Enter options: (See tar --help or man bsdtar)" 8 70 2>&1 1>&3)
    else
      BRuseroptions="No"
    fi
  done

  dialog --title "Summary" --yes-label "OK" --no-label "Quit" --yesno "$(show_summary) $(echo -e "\n\nPress OK to continue or Quit to abort.")" 0 0
  if [ "$?" = "1" ]; then
    exit
  fi

  prepare
  set_tar_options
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

  if [ -f /tmp/b_error ]; then
    dialog --yes-label "OK" --no-label "View Log" --title "Error" --yesno "An error occurred.\n\nCheck $BRFOLDER/backup.log for details.\n\nPress OK to exit." 10 80
  else
    dialog --yes-label "OK" --no-label "View Log" --title "Info" --yesno "Completed.\n\nBackup archive and log saved in $BRFOLDER.\n\nPress OK to exit." 10 80
  fi
  if [ "$?" = "1" ]; then
    dialog --textbox "$BRFOLDER"/backup.log 0 0
  fi
fi

if [ -f /tmp/excludelist ]; then rm /tmp/excludelist; fi
if [ -f /tmp/b_error ]; then rm /tmp/b_error; fi
if [ -f /tmp/filelist ]; then rm /tmp/filelist; fi
if [ -f /tmp/bsdtar_out ]; then rm /tmp/bsdtar_out; fi
