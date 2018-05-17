#!/bin/bash

# Set program version
BR_VERSION="System Tar & Restore 6.8"

# Set EFI detection directory
BR_EFI_DIR="/sys/firmware/efi"

# Delete temporary files if exist
clean_tmp_files() {
  if [ -f /tmp/filelist ]; then rm /tmp/filelist; fi
  if [ -f /tmp/error ]; then rm /tmp/error; fi
  if [ -f /target_architecture.$(uname -m) ]; then rm /target_architecture.$(uname -m); fi
}

# Calculate percentage and compose a simple progress bar
pstr="========================"
dstr="                        "
lastper="-1"

pgrs_bar() {
  while read ln; do
    x="$((x + 1))"
    per="$((x*100/total))"
    # If -v is given print percentage and full output
    if [ -n "$BRverb" ] && [[ "$per" -le "100" ]]; then
      echo -e "${CYAN}[$x / $total] ${YELLOW}[$per%] ${GREEN}$ln${NORM}"
    elif [[ "$per" -gt "$lastper" ]] && [[ "$per" -le "100" ]]; then
      lastper="$per"
      print_msg 0 "$mode_job: $per% ($x / $total Files)"
      # The main progress bar
      echo -ne "\r$mode_job: [${pstr:0:$((x*24/total))}${dstr:0:24-$((x*24/total))}] $per%"
    fi
  done
}

# Print various messages and update the gui wrapper if -w is given
print_msg() {
  if [ ! "$1" = "0" ]; then echo ${1}; fi
  if [ -n "$BRwrap" ]; then echo "$2" > /tmp/wr_proc; fi
}

# Print various error messages and exit
print_err() {
  echo ${1} >&2
  BRabort="y"
  if [ "$2" = "0" ]; then exit; fi
  if [ "$2" = "1" ]; then clean_unmount; fi
}

# Show version
echo -e "\n$BR_VERSION"

# Set arguments and help page
BRargs="$(getopt -o "i:d:n:c:u:HOjqvgDP:E:oaC:Mwr:e:l:s:b:h:G:S:f:y:p:R:m:k:t:B:xWFLz:T:" -l "mode:,directory:,filename:,compression:,user-opts:,exclude-home,only-hidden,no-color,quiet,verbose,generate,disable-genkernel,passphrase:,encryption:,override,clean,conf:,multi-core,wrapper,root:,esp:,esp-mpoint:,swap:,boot:,home:,grub:,syslinux:,file:,username:,password:,rootsubvol:,mount-opts:,kernel-opts:,other-parts:,other-subvols:,dont-check-root,bios,efistub,bootctl,threads:,src-dir:,help" -n "$1" -- "$@")"

if [ "$?" -ne "0" ]; then
  echo "See star.sh --help"
  exit
fi

eval set -- "$BRargs";

while true; do
  case "$1" in
    -i|--mode)
      BRmode="$2"
      shift 2
    ;;
    -u|--user-opts)
      _BR_USER_OPTS="$2"
      shift 2
    ;;
    -d|--directory)
      _BRFOLDER="$2"
      shift 2
    ;;
    -n|--filename)
      _BRNAME="$2"
      shift 2
    ;;
    -c|--compression)
      _BRcompression="$2"
      shift 2
    ;;
    -H|--exclude-home)
      _BRnohome="y"
      shift
    ;;
    -O|--only-hidden)
      _BRonlyhidden="y"
      shift
    ;;
    -P|--passphrase)
      _BRencpass="$2"
      shift 2
    ;;
    -E|--encryption)
      _BRencmethod="$2"
      shift 2
    ;;
    -z|--threads)
      _BRthreads="$2"
      shift 2
    ;;
    -T|--top-dir)
      _BRsrc="$2"
      shift 2
    ;;
    -j|--no-color)
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
    -o|--override)
      BRoverride="y"
      shift
    ;;
    -a|--clean)
      BRclean="y"
      shift
    ;;
    -C|--conf)
      BRconf="$2"
      shift 2
    ;;
    -M|--multi-core)
      BRmcore="y"
      shift
    ;;
    -w|--wrapper)
      BRwrap="y"
      shift
    ;;
    -r|--root)
      BRroot="$2"
      shift 2
    ;;
    -e|--esp)
      BResp="$2"
      shift 2
    ;;
    -l|--esp-mpoint)
      BRespmpoint="$2"
      shift 2
    ;;
    -s|--swap)
      BRswap="$2"
      shift 2
    ;;
    -b|--boot)
      BRboot="$2"
      shift 2
    ;;
    -h|--home)
      BRhome="$2"
      shift 2
    ;;
    -G|--grub)
      BRgrub="$2"
      shift 2
    ;;
    -S|--syslinux)
      BRsyslinux="$2"
      shift 2
    ;;
    -f|--file)
      BRuri="$2"
      shift 2
    ;;
    -y|--username)
      BRusername="$2"
      shift 2
    ;;
    -p|--password)
      BRpassword="$2"
      shift 2
    ;;
    -R|--rootsubvol)
      BRrootsubvol="$2"
      shift 2
    ;;
    -m|--mount-opts)
      BRmountopts="$2"
      shift 2
    ;;
    -k|--kernel-opts)
      BRkernopts="$2"
      shift 2
    ;;
    -t|--other-parts)
      BRparts=($2)
      shift 2
    ;;
    -B|--other-subvols)
      BRsubvols=($2)
      shift 2
    ;;
    -x|--dont-check-root)
      BRdontckroot="y"
      shift
    ;;
    -W|--bios)
      unset BR_EFI_DIR
      shift
    ;;
    -F|--efistub)
      BRefistub="y"
      shift
    ;;
    -L|--bootctl)
      BRbootctl="y"
      shift
    ;;
    --help)
      echo "Usage: star.sh -i mode [options]

General Options:
  -i, --mode                  Select mode: 0 (Backup) 1 (Restore) 2 (Transfer)
  -j, --no-color              Disable colors
  -q, --quiet                 Don't ask, just run
  -v, --verbose               Enable verbose archiver output
  -w, --wrapper               Make the script wrapper-friendly
  -u, --user-opts             Additional tar/rsync options. See tar/rsync --help
                              If you want spaces in names replace them with //
  -o, --override              Override the default tar/rsync options with user options (use with -u)
  -D, --disable-genkernel     Disable genkernel check and initramfs building in gentoo
      --help	              Print this page

Backup Mode:
  Destination:
    -d, --directory           Backup destination path
    -n, --filename            Backup filename (without extension)

  Home Directory:
    -H, --exclude-home	      Exclude /home directory
    -O, --only-hidden         Keep /home's hidden files and folders only

  Archiver Options:
    -c, --compression         Compression type: gzip bzip2 xz none
    -M, --multi-core          Enable multi-core compression (via pigz, pbzip2 or pxz)
    -z, --threads             Specify the number of threads for multi-core compression

  Encryption Options:
    -E, --encryption          Encryption method: openssl gpg
    -P, --passphrase          Passphrase for encryption

  Misc Options:
    -C, --conf                Alternative configuration file path
    -g, --generate            Generate configuration file (in case of successful backup)
    -a, --clean               Remove older backups in the destination directory
    -T, --src-dir             Create a non-system backup archive of a specified directory

Restore / Transfer Mode:
  Partitions:
    -r,  --root               Target root partition
    -m,  --mount-opts         Comma-separated list of mount options for the root partition
    -e,  --esp                Target EFI system partition
    -l,  --esp-mpoint         Mount point for ESP: /boot/efi /boot
    -b,  --boot               Target /boot partition
    -h,  --home               Target /home partition
    -s,  --swap               Swap partition
    -t,  --other-parts        Specify other partitions. Syntax is mountpoint=partition (e.g /var=/dev/sda3)
                              If you want spaces in mountpoints replace them with //
     Add a trailing @ in any of the above, if it is not empty and you want to clean it (e.g -r /dev/sda2@)

  Btrfs Subvolumes:
    -R,  --rootsubvol         Subvolume name for /
    -B,  --other-subvols      Specify other subvolumes (subvolume path e.g /home /var /usr ...)

  Bootloaders:
    -G,  --grub               Target grub device
    -S,  --syslinux           Target syslinux device
    -F,  --efistub            Enable EFISTUB/efibootmgr
    -L,  --bootctl            Enable Systemd/bootctl
    -k,  --kernel-opts        Additional kernel options

  Restore Mode:
    -f,  --file               Backup file path or url
    -y,  --username           Ftp/http username
    -p,  --password           Ftp/http password
    -P,  --passphrase         Passphrase for decryption

  Transfer Mode:
    -O,  --only-hidden        Transfer /home's hidden files and folders only
    -H,  --exclude-home	      Don't transfer /home directory

  Misc Options:
    -x,  --dont-check-root    Don't check if the target root partition is empty (dangerous)
    -W,  --bios               Ignore UEFI environment"
      exit
      shift
    ;;
    --)
      shift
      break
    ;;
  esac
done

# Give PID to gui wrapper if -w is given
if [ -n "$BRwrap" ]; then
  echo "$$" >> /tmp/wr_pid
fi

# Set colors if -j is not given
if [ -z "$BRnocolor" ]; then
  NORM='\e[00m'
  RED='\e[00;31m'
  GREEN='\e[00;32m'
  YELLOW='\e[00;33m'
  CYAN='\e[00;36m'
  BOLD='\033[1m'
fi

# Check if run with root privileges
if [ "$(id -u)" -gt "0" ]; then
  print_err "-e [${RED}ERROR${NORM}] Script must run as root" 0
fi

# Check mode
if [ -z "$BRmode" ]; then
  print_err "-e [${RED}ERROR${NORM}] You must specify a mode" 0
elif [ -n "$BRmode" ] && [ ! "$BRmode" = "0" ] && [ ! "$BRmode" = "1" ] && [ ! "$BRmode" = "2" ]; then
  print_err "-e [${RED}ERROR${NORM}] Wrong mode: $BRmode. Available options: 0 (Backup) 1 (Restore) 2 (Transfer)" 0
fi

clean_tmp_files

# Set and source the configuration file for Backup mode. If -w is given don't source, the gui wrapper will source it
if [ "$BRmode" = "0" ] && [ -z "$BRwrap" ]; then
  if [ -z "$BRconf" ]; then
    BRconf="/etc/backup.conf"
  elif [ -n "$BRconf" ] && [ ! -f "$BRconf" ]; then
    print_err "-e [${RED}ERROR${NORM}] File does not exist: $BRconf" 0
  fi
  if [ -f "$BRconf" ]; then
    source "$BRconf"
  fi
fi

# Check /home directory options for Backup and Transfer mode
if [ "$BRmode" = "0" ] || [ "$BRmode" = "2" ] && [ -n "$_BRnohome" ] && [ -n "$_BRonlyhidden" ]; then
  print_err "-e [${YELLOW}WARNING${NORM}] Choose only one option for the /home directory" 0
elif [ "$BRmode" = "0" ] && [ -n "$BRnohome" ] && [ -n "$BRonlyhidden" ]; then
  print_err "-e [${RED}ERROR${NORM}] Error parsing configuration file. Choose only one option for the /home directory" 0
fi

# Arguments should override configuration file
if [ -n "$_BR_USER_OPTS" ]; then BR_USER_OPTS="$_BR_USER_OPTS"; fi
if [ -n "$_BRFOLDER" ]; then BRFOLDER="$_BRFOLDER"; fi
if [ -n "$_BRNAME" ]; then BRNAME="$_BRNAME"; fi
if [ -n "$_BRcompression" ]; then BRcompression="$_BRcompression"; fi
if [ -n "$_BRencmethod" ]; then BRencmethod="$_BRencmethod"; fi
if [ -n "$_BRencpass" ]; then BRencpass="$_BRencpass"; fi
if [ -n "$_BRnohome" ]; then BRnohome="$_BRnohome"; fi
if [ -n "$_BRonlyhidden" ]; then BRonlyhidden="$_BRonlyhidden"; fi
if [ -n "$_BRnohome" ] && [ -n "$BRonlyhidden" ]; then unset BRonlyhidden; fi
if [ -n "$_BRonlyhidden" ] && [ -n "$BRnohome" ]; then unset BRnohome; fi
if [ -n "$_BRthreads" ]; then BRthreads="$_BRthreads"; fi
if [ -n "$_BRsrc" ]; then BRsrc="$_BRsrc"; fi

# Add tar/rsync user options to the main array, replace any // with space, add only options starting with -
for opt in $BR_USER_OPTS; do
  if [[ "$opt" == -* ]]; then
    BR_TR_OPTS+=("${opt///\//\ }")
  fi
done

# Backup mode
if [ "$BRmode" = "0" ]; then

  # Unset Restore/Transfer mode vars
  unset BRroot BResp BRespmpoint BRswap BRboot BRhome BRgrub BRsyslinux BRuri BRusername BRpassword BRrootsubvol BRmountopts BRkernopts BRparts BRsubvols BRdontckroot BRefistub BRbootctl

  # Show a nice summary
  show_summary() {
    echo "ARCHIVE"
    echo "$BRFOLDER/$BRNAME.$BR_EXT ($BRsrc) $mcinfo"

    echo -e "\nARCHIVER OPTIONS"
    for opt in "${BR_TR_OPTS[@]}"; do echo "$opt"; done

    if [ "$BRsrc" = "/" ]; then
      echo -e "\nHOME DIRECTORY"
      if [ -n "$BRonlyhidden" ]; then
        echo "Only hidden files and folders"
      elif [ -n "$BRnohome" ]; then
        echo "Exclude"
      else
        echo "Include"
      fi

      echo -e "\nFOUND BOOTLOADERS"
      # If grub(2)-mkconfig found, probably grub is installed
      if which grub-mkconfig &>/dev/null || which grub2-mkconfig &>/dev/null; then echo "Grub"; else BRgrub="n"; fi
      # If sys/extlinux found, probably syslinux is installed
      if which extlinux &>/dev/null && which syslinux &>/dev/null; then echo "Syslinux"; else BRsyslinux="n"; fi
      # Check if efibootmgr is installed
      if which efibootmgr &>/dev/null; then echo "EFISTUB/efibootmgr"; else BRefibootmgr="n"; fi
      # If bootctl found, probably systemd-boot is available
      if which bootctl &>/dev/null; then echo "Systemd/bootctl"; else BRbootctl="n"; fi
      # In case none of the above found
      if [ -n "$BRgrub" ] && [ -n "$BRsyslinux" ] && [ -n "$BRefibootmgr" ] && [ -n "$BRbootctl" ]; then
        echo "None or not supported"
      fi
    fi

    # Show older backup directories that we remove later if -a is given
    if [ -n "$BRoldbackups" ] && [ -n "$BRclean" ]; then
      echo -e "\nREMOVE BACKUPS"
      for backup in "${BRoldbackups[@]}"; do echo "$backup"; done
    fi
  }

  # Calculate files to create percentage and progress bar
  run_calc() {
    tar cvf /dev/null "${BR_TR_OPTS[@]}" "$BRsrc" 2>/dev/null | tee /tmp/filelist
  }

  # Run tar with given input
  run_tar() {
    # In case of openssl encryption
    if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
      tar "${BR_MAIN_OPTS[@]}" >(openssl aes-256-cbc -salt -k "$BRencpass" -out "$BRFOLDER"/"$BRNAME"."$BR_EXT" 2>> "$BRFOLDER"/backup.log) "${BR_TR_OPTS[@]}" "$BRsrc"
    # In case of gpg encryption
    elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
      tar "${BR_MAIN_OPTS[@]}" >(gpg -c --batch --yes --passphrase "$BRencpass" -z 0 -o "$BRFOLDER"/"$BRNAME"."$BR_EXT" 2>> "$BRFOLDER"/backup.log) "${BR_TR_OPTS[@]}" "$BRsrc"
    # Without encryption
    else
      tar "${BR_MAIN_OPTS[@]}" "$BRFOLDER"/"$BRNAME"."$BR_EXT" "${BR_TR_OPTS[@]}" "$BRsrc"
    fi
  }

 # Generate configuration file
  generate_conf() {
    echo -e "# Auto-generated configuration file for backup mode. Place it in /etc\n"
    echo BRFOLDER=\"$(dirname "$BRFOLDER")\"
    if [ -n "$BRNAME" ] && [[ ! "$BRNAME" == Backup-$(hostname)-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] ]]; then echo BRNAME=\"$BRNAME\"; fi # Strictly check the default filename format
    if [ -n "$BR_USER_OPTS" ]; then echo BR_USER_OPTS=\"$(echo $BR_USER_OPTS)\"; fi # trim leading/trailing and multiple spaces
    echo BRcompression=\"$BRcompression\"
    if [ -n "$BRnohome" ]; then echo BRnohome=\"Yes\"; fi
    if [ -n "$BRonlyhidden" ]; then echo BRonlyhidden=\"Yes\"; fi
    if [ -n "$BRnocolor" ]; then echo BRnocolor=\"Yes\"; fi
    if [ -n "$BRverb" ]; then echo BRverb=\"Yes\"; fi
    if [ -n "$BRquiet" ]; then echo BRquiet=\"Yes\"; fi
    if [ -n "$BRoverride" ]; then echo BRoverride=\"Yes\"; fi
    if [ -n "$BRencpass" ]; then echo -e "BRencmethod=\"$BRencmethod\"\nBRencpass=\"$BRencpass\""; fi
    if [ -n "$BRclean" ]; then echo BRclean=\"Yes\"; fi
    if [ -n "$BRgenkernel" ]; then echo BRgenkernel=\"No\"; fi
    if [ -n "$BRmcore" ]; then echo BRmcore=\"Yes\"; fi
    if [ -n "$BRmcore" ] && [ -n "$BRthreads" ]; then echo BRthreads=\"$BRthreads\"; fi
    if [ -n "$BRsrc" ] && [ ! "$BRsrc" = "/" ]; then echo BRsrc=\"$BRsrcfull\"; fi
  }

  # Check user input, exit on error
  if [ -n "$BRFOLDER" ] && [ ! -d "$BRFOLDER" ]; then
    print_err "-e [${RED}ERROR${NORM}] Directory does not exist: $BRFOLDER" 0
  fi

  if [ -n "$BRsrc" ] && [ ! -d "$BRsrc" ]; then
    print_err "-e [${RED}ERROR${NORM}] Directory does not exist: $BRsrc" 0
  fi

  if [ -n "$BRcompression" ] && [ ! "$BRcompression" = "gzip" ] && [ ! "$BRcompression" = "xz" ] && [ ! "$BRcompression" = "bzip2" ] && [ ! "$BRcompression" = "none" ]; then
    print_err "-e [${RED}ERROR${NORM}] Wrong compression type: $BRcompression. Available options: gzip bzip2 xz none" 0
  fi

  if [ -f /etc/portage/make.conf ] || [ -f /etc/make.conf ] && [ -z "$BRgenkernel" ] && [ -z "$(which genkernel 2>/dev/null)" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] Package genkernel is not installed. Install the package and re-run the script (you can disable this check with -D)" 0
  fi

  if [ -z "$BRencmethod" ] || [ "$BRencmethod" = "none" ] && [ -n "$BRencpass" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] You must specify an encryption method" 0
  fi

  if [ -z "$BRencpass" ] && [ -n "$BRencmethod" ] && [ ! "$BRencmethod" = "none" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] You must specify a passphrase" 0
  fi

  if [ -n "$BRencmethod" ] && [ ! "$BRencmethod" = "openssl" ] && [ ! "$BRencmethod" = "gpg" ] && [ ! "$BRencmethod" = "none" ]; then
    print_err "-e [${RED}ERROR${NORM}] Wrong encryption method: $BRencmethod. Available options: openssl gpg" 0
  fi

  if [ -n "$BRmcore" ] && [ -z "$BRcompression" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] You must specify compression type" 0
  elif [ -n "$BRmcore" ] && [ "$BRcompression" = "gzip" ] && [ -z "$(which pigz 2>/dev/null)" ]; then
    print_err "-e [${RED}ERROR${NORM}] Package pigz is not installed. Install the package and re-run the script" 0
  elif [ -n "$BRmcore" ] && [ "$BRcompression" = "bzip2" ] && [ -z "$(which pbzip2 2>/dev/null)" ]; then
    print_err "-e [${RED}ERROR${NORM}] Package pbzip2 is not installed. Install the package and re-run the script" 0
  elif [ -n "$BRmcore" ] && [ "$BRcompression" = "xz" ] && [ -z "$(which pxz 2>/dev/null)" ]; then
    print_err "-e [${RED}ERROR${NORM}] Package pxz is not installed. Install the package and re-run the script" 0
  elif [ -n "$BRmcore" ] && [ -n "$BRthreads" ] && [ "$BRthreads" -gt "$(nproc --all)" ]; then
    print_err "-e [${RED}ERROR${NORM}] Maximum number of processing units: $(nproc --all)" 0
  fi

  if [ -n "$BRwrap" ] && [ -z "$BRFOLDER" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] You must specify destination directory" 0
  fi

  # Set some defaults if not given by the user
  if [ -z "$BRFOLDER" ]; then BRFOLDER="/"; fi
  if [ -z "$BRNAME" ]; then BRNAME="Backup-$(hostname)-$(date +%Y%m%d-%H%M%S)"; fi
  if [ -z "$BRcompression" ]; then BRcompression="gzip"; fi
  if [ -z "$BRsrc" ]; then BRsrc="/"; fi

 # Set backup subdirectory
  BRFOLDER="$(echo "$BRFOLDER"/Backup-$(date +%Y-%m-%d) | sed 's://*:/:g')" # Also eliminate multiple forward slashes in the path

  if [ ! "$BRsrc" = "/" ]; then
    BRsrc="$(echo "$BRsrc" | sed 's://*:/:g')" # Eliminate multiple forward slashes in the path
  fi

  # Set tar compression options and backup file extension
  if [ "$BRcompression" = "gzip" ] && [ -n "$BRmcore" ] && [ -n "$BRthreads" ]; then
    BR_MAIN_OPTS=(-c -I "pigz -p$BRthreads" -vpf)
    BR_EXT="tar.gz"
    mcinfo="(pigz $BRthreads threads)"
  elif [ "$BRcompression" = "gzip" ] && [ -n "$BRmcore" ]; then
    BR_MAIN_OPTS=(-c -I pigz -vpf)
    BR_EXT="tar.gz"
    mcinfo="(pigz)"
  elif [ "$BRcompression" = "gzip" ]; then
    BR_MAIN_OPTS=(cvpzf)
    BR_EXT="tar.gz"
  elif [ "$BRcompression" = "xz" ] && [ -n "$BRmcore" ] && [ -n "$BRthreads" ]; then
    BR_MAIN_OPTS=(-c -I "pxz -T$BRthreads" -vpf)
    BR_EXT="tar.xz"
    mcinfo="(pxz $BRthreads threads)"
  elif [ "$BRcompression" = "xz" ] && [ -n "$BRmcore" ]; then
    BR_MAIN_OPTS=(-c -I pxz -vpf)
    BR_EXT="tar.xz"
    mcinfo="(pxz)"
  elif [ "$BRcompression" = "xz" ]; then
    BR_MAIN_OPTS=(cvpJf)
    BR_EXT="tar.xz"
  elif [ "$BRcompression" = "bzip2" ] && [ -n "$BRmcore" ] && [ -n "$BRthreads" ]; then
    BR_MAIN_OPTS=(-c -I "pbzip2 -p$BRthreads" -vpf)
    BR_EXT="tar.bz2"
    mcinfo="(pbzip2 $BRthreads threads)"
  elif [ "$BRcompression" = "bzip2" ] && [ -n "$BRmcore" ]; then
    BR_MAIN_OPTS=(-c -I pbzip2 -vpf)
    BR_EXT="tar.bz2"
    mcinfo="(pbzip2)"
  elif [ "$BRcompression" = "bzip2" ]; then
    BR_MAIN_OPTS=(cvpjf)
    BR_EXT="tar.bz2"
  elif [ "$BRcompression" = "none" ]; then
    BR_MAIN_OPTS=(cvpf)
    BR_EXT="tar"
  fi

  # Set backup file extension based on encryption
  if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
    BR_EXT="$BR_EXT.aes"
  elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
    BR_EXT="$BR_EXT.gpg"
  fi

  # Set tar default options
  if [ -z "$BRoverride" ] && [ "$BRsrc" = "/" ]; then
    BR_TR_OPTS+=(--sparse               \
                 --acls                 \
                 --xattrs               \
                 --exclude=/run/*       \
                 --exclude=/dev/*       \
                 --exclude=/sys/*       \
                 --exclude=/tmp/*       \
                 --exclude=/mnt/*       \
                 --exclude=/proc/*      \
                 --exclude=/media/*     \
                 --exclude=/var/run/*   \
                 --exclude=/var/lock/*  \
                 --exclude=.gvfs        \
                 --exclude=lost+found)

    # Needed by Fedora
    if [ -f /etc/yum.conf ] || [ -f /etc/dnf/dnf.conf ]; then
      BR_TR_OPTS+=(--selinux)
    fi
  fi
  BR_TR_OPTS+=(--exclude="$(basename "$BRFOLDER")")

  # Set /home directory options
  if [ -n "$BRnohome" ] && [ "$BRsrc" = "/" ]; then
    BR_TR_OPTS+=(--exclude=/home/*)
  elif [ -n "$BRonlyhidden" ] && [ "$BRsrc" = "/" ]; then
    # Find everything that doesn't start with dot and exclude it
    while read item; do
      BR_TR_OPTS+=(--exclude="$item")
    done< <(find /home/*/* -maxdepth 0 -iname ".*" -prune -o -print)
  fi

  # Check destination for backup directories with older date, strictly check directory name format
  if [ -n "$BRclean" ]; then
    while read dir; do
      if [ "${dir//[^0-9]/}" -lt "${BRFOLDER//[^0-9]/}" ]; then # Compare the date numbers
        BRoldbackups+=("$dir")
      fi
    done < <(find "$(dirname "$BRFOLDER")" -mindepth 1 -maxdepth 1 -type d -iname "Backup-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]")
  fi

  # Check if backup file already exists and prompt the user to overwrite. If -q is given overwrite automatically
  if [ -z "$BRquiet" ]; then
    while [ -f "$BRFOLDER/$BRNAME.$BR_EXT" ]; do
      echo -e "${BOLD}"
      read -p "File $BRNAME.$BR_EXT already exists. Overwrite? [y/N]: $(echo -e "${NORM}")" an
      if [ "$an" = "y" ] || [ "$an" = "Y" ]; then
        break
      elif [ "$an" = "n" ] || [ "$an" = "N" ] || [ -z "$an" ]; then
        exit
      else
        echo -e "${RED}Please enter a valid option${NORM}"
      fi
    done
  fi

  # Show summary and prompt the user to continue. If -q is given continue automatically
  echo -e "\n${BOLD}[SUMMARY]${CYAN}"
  show_summary
  echo -ne "${NORM}"

  while [ -z "$BRquiet" ]; do
    echo -e "${BOLD}"
    read -p "Continue? [Y/n]: $(echo -e "${NORM}")" an
    if [ "$an" = "y" ] || [ "$an" = "Y" ] || [ -z "$an" ]; then
      break
    elif [ "$an" = "n" ] || [ "$an" = "N" ]; then
      exit
    else
      echo -e "${RED}Please enter a valid option${NORM}"
    fi
  done

  # Delete older backup directories if -a is given
  if [ -n "$BRoldbackups" ] && [ -n "$BRclean" ]; then
    for backup in "${BRoldbackups[@]}"; do rm -r "$backup"; done
  fi

  echo -e "\n${BOLD}[PROCESSING]${NORM}"
  print_msg 0 "Preparing"
  # Restore mode will check and read this file in the archive
  if [ "$BRsrc" = "/" ]; then touch /target_architecture.$(uname -m); fi
  # Create the destination subdirectory
  mkdir -p "$BRFOLDER"
  sleep 1
  # Start the log
  echo -e "$BR_VERSION\n\n[SUMMARY]\n$(show_summary)\n\n[ARCHIVER]" > "$BRFOLDER"/backup.log
  # Store start time
  start=$(date +%s)

  # If custom source directory specified, cd in it's parent and backup the child
  if [ ! "$BRsrc" = "/" ]; then
    cd "$(dirname "$BRsrc")"
    BRsrcfull="$BRsrc"
    BRsrc="$(basename "$BRsrc")"
  fi

  # Calculate the number of files
  print_msg 0 "Please wait while calculating files"
  run_calc | while read ln; do a="$((a + 1))" && echo -en "\rCalculating: $a Files"; done
  # Store the number of files we found from run_calc
  total="$(cat /tmp/filelist | wc -l)"
  sleep 1
  echo

  # Run tar and pipe it through the progress calculation, give errors to log
  mode_job="Archiving"
  (run_tar 2>> "$BRFOLDER"/backup.log && echo "$total Files archived successfully" >> "$BRFOLDER"/backup.log || touch /tmp/error) | pgrs_bar
  echo

  # Generate configuration file if -g is given and no error occurred
  if [ -n "$BRgen" ] && [ ! -f /tmp/error ]; then
    echo "Generating backup.conf..."
    generate_conf > "$BRFOLDER"/backup.conf
  fi

  # Give destination subdirectory full permissions with some nice messages
  OUTPUT="$(chmod ugo+rw -R "$BRFOLDER" 2>&1)" && echo -ne "Setting permissions: Done\n" || echo -ne "Setting permissions: Failed\n$OUTPUT\n"

  # Calculate elapsed time
  elapsed="$(($(($(date +%s)-start))/3600)) hours $((($(($(date +%s)-start))%3600)/60)) min $(($(($(date +%s)-start))%60)) sec"

  # Complete the log
  echo "Elapsed time: $elapsed" >> "$BRFOLDER"/backup.log

  # Inform the user if error occurred or not
  if [ -f /tmp/error ]; then
    echo -e "${RED}\nAn error occurred.\n\nCheck $BRFOLDER/backup.log for details.\nElapsed time: $elapsed${NORM}"
  else
    echo -e "${CYAN}\nBackup archive and log saved in $BRFOLDER\nElapsed time: $elapsed${NORM}"
  fi

  # Give log to gui wrapper if -w is given
  if [ -n "$BRwrap" ]; then
    cat "$BRFOLDER"/backup.log > /tmp/wr_log
    # Give generated configuration file to gui wrapper also
    if [ -n "$BRgen" ] && [ ! -f /tmp/error ]; then
      echo -e "\n[CONFIGURATION FILE]\n$(cat "$BRFOLDER"/backup.conf)" >> /tmp/wr_log
    fi
  fi

  clean_tmp_files

# Restore / Transfer Mode
elif [ "$BRmode" = "1" ] || [ "$BRmode" = "2" ]; then

  # Unset Backup mode vars
  unset BRFOLDER BRNAME BRcompression BRgen BRencmethod BRclean BRconf BRthreads BRsrc

  # Print success message, set var for processing partitions
  ok_status() {
    echo -e "\r[${GREEN}SUCCESS${NORM}]"
    BRcontinue="y"
  }

  # Print failure message, set var for stop processing partitions
  error_status() {
    echo -e "\r[${RED}FAILURE${NORM}]\n$OUTPUT"
    BRstop="y"
  }

  # Detect backup archive encryption
  detect_encryption() {
    if [ "$(file -b "$BRsource")" = "data" ] || file -b "$BRsource" | grep -qw openssl; then
      BRencmethod="openssl"
    elif file -b "$BRsource" | grep -qw GPG; then
      BRencmethod="gpg"
    fi
  }

  # Detect backup archive filetype and set tar options accordingly
  detect_filetype() {
    print_msg "Checking archive type" "Checking archive type"
    # If archive is encrypted decrypt first, pipe output to 'file'
    if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
      BRtype="$(openssl aes-256-cbc -d -salt -in "$BRsource" -k "$BRencpass" 2>/dev/null | file -b -)"
    elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
      BRtype="$(gpg -d --batch --passphrase "$BRencpass" "$BRsource" 2>/dev/null | file -b -)"
    else
      # Check archive directly
      BRtype="$(file -b "$BRsource")"
    fi

    if echo "$BRtype" | grep -q -w gzip; then
      BRfiletype="gzip compressed"
      BRreadopts="tfz"
      BR_MAIN_OPTS="xvpfz"
    elif echo "$BRtype" | grep -q -w bzip2 && [ -n $BRmcore ]; then
      BRfiletype="pbzip2 compressed"
      BRreadopts="-I pbzip2 -tf"
      BR_MAIN_OPTS="-I pbzip2 -xvpf"
    elif echo "$BRtype" | grep -q -w bzip2; then
      BRfiletype="bzip2 compressed"
      BRreadopts="tfj"
      BR_MAIN_OPTS="xvpfj"
    elif echo "$BRtype" | grep -q -w XZ; then
      BRfiletype="xz compressed"
      BRreadopts="tfJ"
      BR_MAIN_OPTS="xvpfJ"
    elif echo "$BRtype" | grep -q -w POSIX; then
      BRfiletype="uncompressed"
      BRreadopts="tf"
      BR_MAIN_OPTS="xvpf"
    else
      BRfiletype="wrong"
    fi
  }

  # Detect the distro by checking for known package manager files
  detect_distro() {
    # In Restore mode check the archive contents
    if [ "$BRmode" = "1" ]; then
      if grep -Fxq "etc/yum.conf" /tmp/filelist || grep -Fxq "etc/dnf/dnf.conf" /tmp/filelist; then
        BRdistro="Fedora"
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

    # In Transfer mode check the running system
    elif [ "$BRmode" = "2" ]; then
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

  # Detect the partition table for Syslinux so we can use the corresponding bin files
  detect_partition_table_syslinux() {
    # Check if the target Syslinux device is a raid array first
    if [[ "$BRsyslinux" == *md* ]]; then
      BRsyslinuxdev="$BRdevice" # We set BRdevice in install_bootloader
    else
      BRsyslinuxdev="$BRsyslinux"
    fi
    # Check the first 8 bytes for EFI PART
    if dd if="$BRsyslinuxdev" skip=64 bs=8 count=1 2>/dev/null | grep -qw "EFI PART"; then
      BRtable="gpt"
    else
      BRtable="mbr"
    fi
  }

  # Apply appropriate partition flags for Syslinux and search known locations for bin and com32 Syslinux files.
  set_syslinux_flags_and_paths() {
    if [ "$BRtable" = "gpt" ]; then
      # Set legacy_boot flag in GPT, use gptmbr.bin
      echo "Setting legacy_boot flag on partition $BRpartition of $BRdevice" # We set BRpartition in install_bootloader
      sgdisk "$BRdevice" --attributes="$BRpartition":set:2 &>> /tmp/restore.log || touch /tmp/error
      BRsyslinuxmbr="gptmbr.bin"
    else
      # Set boot flag in MBR, use mbr.bin
      echo "Setting boot flag on partition $BRpartition of $BRdevice" # We set BRpartition in install_bootloader
      sfdisk "$BRdevice" -A "$BRpartition" &>> /tmp/restore.log || touch /tmp/error
      BRsyslinuxmbr="mbr.bin"
    fi

    for BIN in /mnt/target/usr/lib/syslinux/"$BRsyslinuxmbr" \
      /mnt/target/usr/lib/syslinux/mbr/"$BRsyslinuxmbr" \
      /mnt/target/usr/share/syslinux/"$BRsyslinuxmbr"; do
      if [ -f "$BIN" ]; then
        BRsyslinuxmbrpath="$(dirname "$BIN")"
      fi
    done

    for COM32 in /mnt/target/usr/lib/syslinux/menu.c32 \
      /mnt/target/usr/lib/syslinux/modules/bios/menu.c32 \
      /mnt/target/usr/share/syslinux/menu.c32; do
      if [ -f "$COM32" ]; then
        BRsyslinuxcompath="$(dirname "$COM32")"
      fi
    done
  }

  # Generate Syslinux configuration file
  generate_syslinux_cfg() {
    echo -e "UI menu.c32\nPROMPT 0\nMENU TITLE Boot Menu\nTIMEOUT 50"

    # Search target system for kernels
    for FILE in /mnt/target/boot/*; do
      if file -b -k "$FILE" | grep -qw "bzImage"; then
        cn=$(echo "$FILE" | sed -n 's/[^-]*-//p') # Cutted kernel name without any prefix (eg without vmlinuz-)
        kn=$(basename "$FILE") # Full kernel name (eg vmlinuz-linux)

        # Create entries. We set ipn in detect_initramfs_prefix
        if [ "$BRdistro" = "Arch" ]; then
          echo -e "LABEL arch\n\tMENU LABEL $BRdistro $cn\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn-$cn.img"
          echo -e "LABEL archfallback\n\tMENU LABEL $BRdistro $cn fallback\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn-$cn-fallback.img"
        elif [ "$BRdistro" = "Debian" ]; then
          echo -e "LABEL debian\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn.img-$cn"
        elif [ "$BRdistro" = "Fedora" ]; then
          echo -e "LABEL fedora\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn-$cn.img"
        elif [ "$BRdistro" = "Suse" ]; then
          echo -e "LABEL suse\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn-$cn"
        elif [ "$BRdistro" = "Mandriva" ]; then
          echo -e "LABEL suse\n\tMENU LABEL $BRdistro-$cn\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn-$cn.img"
        elif [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ]; then
          echo -e "LABEL gentoo\n\tMENU LABEL $BRdistro-$kn\n\tLINUX ../$kn\n\tAPPEND root=$bl_root $BRkernopts\n\tINITRD ../$ipn-$cn"
        elif [ "$BRdistro" = "Gentoo" ]; then
          echo -e "LABEL gentoo\n\tMENU LABEL $BRdistro-$kn\n\tLINUX ../$kn\n\tAPPEND root=$BRroot $BRkernopts"
        fi
      fi
    done
  }

  # Set tar default options
  set_tar_opts() {
   if [ "$BRdistro" = "Fedora" ] && [ -z "$BRoverride" ]; then
     BR_TR_OPTS+=(--selinux --acls "--xattrs-include='*'")
   elif [ -z "$BRoverride" ]; then
     BR_TR_OPTS+=(--acls --xattrs)
   fi
  }

  # Run tar with given input
  run_tar() {
    # In case of openssl encryption
    if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
      openssl aes-256-cbc -d -salt -in "$BRsource" -k "$BRencpass" 2>> /tmp/restore.log | tar ${BR_MAIN_OPTS} - "${BR_TR_OPTS[@]}" -C /mnt/target
    # In case of gpg encryption
    elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
      gpg -d --batch --passphrase "$BRencpass" "$BRsource" 2>> /tmp/restore.log | tar ${BR_MAIN_OPTS} - "${BR_TR_OPTS[@]}" -C /mnt/target
    # Without encryption
    else
      tar ${BR_MAIN_OPTS} "$BRsource" "${BR_TR_OPTS[@]}" -C /mnt/target
    fi
  }

  # Set default rsync options if -o is not given
  set_rsync_opts() {
    if [ -z "$BRoverride" ]; then
      BR_TR_OPTS+=(--exclude=/run/*         \
                   --exclude=/dev/*         \
                   --exclude=/sys/*         \
                   --exclude=/tmp/*         \
                   --exclude=/mnt/*         \
                   --exclude=/proc/*        \
                   --exclude=/media/*       \
                   --exclude=/var/run/*     \
                   --exclude=/var/lock/*    \
                   --exclude=/home/*/.gvfs  \
                   --exclude=lost+found)
    fi
    if [ -n "$BRonlyhidden" ]; then
      BR_TR_OPTS+=(--exclude=/home/*/[^.]*)
    elif [ -n "$BRnohome" ]; then
      BR_TR_OPTS+=(--exclude=/home/*)
    fi
  }

  # Calculate files to create percentage and progress bar in Transfer mode
  run_calc() {
    rsync -a --out-format=%n / /mnt/target "${BR_TR_OPTS[@]}" --dry-run 2>/dev/null | tee /tmp/filelist
  }

  # Run rsync with given input
  run_rsync() {
    rsync -aAX --out-format=%n / /mnt/target "${BR_TR_OPTS[@]}"
  }

  # Scan normal partitions, lvm, md arrays and sd card partitions
  scan_parts() {
    for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f"; done | sort
    for f in $(find /dev/mapper/ -maxdepth 1 -mindepth 1 ! -name "control"); do echo "$f"; done
    for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f"; done
    for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f"; done
    for f in $(find /dev -regex "/dev/nvme[0-9]+n[0-9]+p[0-9]+"); do echo "$f"; done
  }

  # Scan disks, md arrays and sd card devices
  scan_disks() {
    for f in /dev/[vhs]d[a-z]; do echo "$f"; done
    for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f"; done
    for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f"; done
    for f in $(find /dev -regex "/dev/nvme[0-9]+n[0-9]+"); do echo "$f"; done
  }

  # Main mount function. Exit and clean on errors
  mount_all() {
    # Check the target root partition
    BRrootfs="$(blkid -s TYPE -o value "$BRroot")"
    BRrootsize="$(lsblk -d -n -o size 2>/dev/null "$BRroot" | sed -e 's/ *//')" # Remove leading spaces
    if [ -z "$BRrootfs" ]; then
      print_err "-e [${RED}ERROR${NORM}] Unknown root file system" 0
    fi

    # Create directory to mount the target root partition
    echo -e "\n${BOLD}[MOUNTING]${NORM}"
    print_msg "-ne ${WRK}Making working directory" "Making working directory"
    OUTPUT="$(mkdir /mnt/target 2>&1)" && ok_status || error_status

    # Mount the target root partition
    print_msg "-ne ${WRK}Mounting $BRroot" "Mounting $BRroot"
    OUTPUT="$(mount -o "$BRmountopts" "$BRroot" /mnt/target 2>&1)" && ok_status || error_status
    # Store it's size
    BRsizes+=(`lsblk -n -b -o size "$BRroot" 2>/dev/null`=/mnt/target)
    if [ -n "$BRstop" ]; then
      rm -r /mnt/target
      print_err "-e [${RED}ERROR${NORM}] Error while mounting partitions" 0
    fi

    # Check if the target root partition is not empty
    if [ "$(ls -A /mnt/target | grep -vw "lost+found")" ]; then
      if [ -n "$BRrootclean" ]; then
        print_msg "-e [${YELLOW}WARNING${NORM}] Root partition not empty, cleaning" "Cleaning $BRroot"
        rm -r /mnt/target/*
        sleep 1
      elif [ -z "$BRdontckroot" ]; then
        print_msg "-ne ${WRK}Unmounting $BRroot" "Unmounting $BRroot"
        sleep 1
        OUTPUT="$(umount "$BRroot" 2>&1)" && (ok_status && sleep 1 && rm -r /mnt/target) || (error_status && echo -e "[${YELLOW}WARNING${NORM}] /mnt/target remained")
        print_err "-e [${RED}ERROR${NORM}] Root partition not empty, refusing to use it" 0
      else
        # Just warn if -x is given
        echo -e "[${YELLOW}WARNING${NORM}] Root partition not empty"
      fi
    fi

    # Create btrfs root subvolume if specified by the user
    if [ "$BRrootfs" = "btrfs" ] && [ -n "$BRrootsubvol" ]; then
      print_msg "-ne ${WRK}Creating $BRrootsubvol" "Creating $BRrootsubvol"
      OUTPUT="$(btrfs subvolume create /mnt/target/"$BRrootsubvol" 2>&1 1>/dev/null)" && ok_status || error_status

      # Create other btrfs subvolumes if specified by the user
      if [ -n "$BRsubvols" ]; then
        while read ln; do
          print_msg "-ne ${WRK}Creating $BRrootsubvol$ln" "Creating $BRrootsubvol$ln"
          OUTPUT="$(btrfs subvolume create /mnt/target/"$BRrootsubvol$ln" 2>&1 1>/dev/null)" && ok_status || error_status
        done< <(for subvol in "${BRsubvols[@]}"; do echo "$subvol"; done | sort)
      fi

     # Unmount the target root partition
      print_msg "-ne ${WRK}Unmounting $BRroot" "Unmounting $BRroot"
      OUTPUT="$(umount "$BRroot" 2>&1)" && ok_status || error_status

     # Mount the root btrfs subvolume
      print_msg "-ne ${WRK}Mounting $BRrootsubvol" "Mounting $BRrootsubvol"
      OUTPUT="$(mount -t btrfs -o "$BRmountopts",subvol="$BRrootsubvol" "$BRroot" /mnt/target 2>&1)" && ok_status || error_status
      if [ -n "$BRstop" ]; then
        unset BRstop
        print_err "-e [${RED}ERROR${NORM}] Error while making subvolumes" 1
      fi
    fi

    # Mount any other target partition if given by the user
    if [ -n "$BRparts" ]; then
      # Sort target partitions array by their mountpoint so we can mount in order, keep trailing @ if given so we know what to clean
      BRpartsorted=(`for part in "${BRparts[@]}"; do echo "$part"; done | sort -k 1,1 -t =`)
      unset BRcontinue
      # We read a sorted array with items in the form of mountpoint=partition (e.g /home=/dev/sda2) and we use = as delimiter
      for part in "${BRpartsorted[@]}"; do
        BRpart=$(echo "$part" | cut -f2 -d"=")
        BRmpoint=$(echo "$part" | cut -f1 -d"=")
        # Replace any // with space
        BRmpoint="${BRmpoint///\//\ }"
        print_msg "-ne ${WRK}Mounting ${BRpart//@}" "Mounting ${BRpart//@}"
        # Create the corresponding mounting directory
        mkdir -p /mnt/target"$BRmpoint"
        # Mount it
        OUTPUT="$(mount "${BRpart//@}" /mnt/target"$BRmpoint" 2>&1)" && ok_status || error_status
        # Store sizes
        BRsizes+=(`lsblk -n -b -o size "${BRpart//@}" 2>/dev/null`=/mnt/target"$BRmpoint")
        if [ -n "$BRcontinue" ]; then
          unset BRcontinue
          # Store successfully mounted partitions so we can unmount them later
          BRumountparts+=("$BRmpoint"="${BRpart//@}")
          # Check if partitions are not empty and warn, clean if they end with @
          if [ "$(ls -A /mnt/target"$BRmpoint" | grep -vw "lost+found")" ]; then
            if [[ "$BRpart" == *@ ]]; then
              print_msg "-e [${YELLOW}WARNING${NORM}] $BRmpoint partition not empty, cleaning" "Cleaning ${BRpart//@}"
              rm -r /mnt/target"$BRmpoint"/*
              sleep 1
            else
              echo -e "[${CYAN}INFO${NORM}] $BRmpoint partition not empty"
            fi
          fi
        fi
      done
      if [ -n "$BRstop" ]; then
        unset BRstop
        print_err "-e [${RED}ERROR${NORM}] Error while mounting partitions" 1
      fi
      # Now trim trailing @ from partitions, we dont need it any more
      if [[ "$BRhome" == *@ ]]; then BRhome="${BRhome//@}"; fi
      if [[ "$BRboot" == *@ ]]; then BRboot="${BRboot//@}"; fi
      BRpartsorted=(`for part in "${BRparts[@]}"; do echo "${part//@}"; done | sort -k 1,1 -t =`)
    fi
    # Find the bigger partition to save the downloaded backup archive
    BRmaxsize="$(for size in "${BRsizes[@]}"; do echo "$size"; done | sort -nr -k 1,1 -t = | head -n1 | cut -f2 -d"=")"
  }

  # Show a nice summary
  show_summary() {
    echo "TARGET PARTITION SCHEME"
    BRpartitions="Partition|Mountpoint|Filesystem|Size|Options\n$BRroot $BRmap|/|$BRrootfs|$BRrootsize|$BRmountopts"
    if [ -n "$BRparts" ]; then
      for part in "${BRpartsorted[@]}"; do
        BRpart=$(echo "$part" | cut -f2 -d"=")
        BRmpoint=$(echo "$part" | cut -f1 -d"=")
        # Replace any // with space
        BRmpoint="${BRmpoint///\//\ }"
        # Find filesystem type
        BRpartfs="$(blkid -s TYPE -o value "$BRpart")"
        # Find partition size
        BRpartsize="$(lsblk -d -n -o size 2>/dev/null "$BRpart" | sed -e 's/ *//')" # Remove leading spaces
        BRpartitions="$BRpartitions\n$BRpart|$BRmpoint|$BRpartfs|$BRpartsize"
      done
    fi
    if [ -n "$BRswap" ]; then
      BRpartitions="$BRpartitions\n$BRswap|swap"
    fi
    # Create columns
    echo -e "$BRpartitions" | column -t -s '|'

    if [ "$BRrootfs" = "btrfs" ] && [ -n "$BRrootsubvol" ]; then
      echo -e "\nSUBVOLUMES"
      echo "$BRrootsubvol"
      if [ -n "$BRsubvols" ]; then
        for subvol in "${BRsubvols[@]}"; do echo "$BRrootsubvol$subvol"; done | sort
      fi
    fi

    echo -e "\nBOOTLOADER"
    if [ -n "$BRgrub" ]; then
      if [ -d "$BR_EFI_DIR" ]; then
        echo "$BRbootloader ($BRgrubefiarch)"
      else
        echo "$BRbootloader (i386-pc)"
      fi
      # If the target Grub device is a raid array, show all devices the array contains
      if [[ "$BRgrub" == *md* ]]; then
        echo Devices: $(grep -w "${BRgrub##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]')
      elif [ ! -d "$BR_EFI_DIR" ]; then
        echo "Device: $BRgrub"
      fi
    elif [ -n "$BRsyslinux" ]; then
      echo "$BRbootloader ($BRtable)"
      # If the target Syslinux device is a raid array, show all devices the array contains
      if [[ "$BRsyslinux" == *md* ]]; then
        echo Devices: $(grep -w "${BRsyslinux##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]')
      else
        echo "Device: $BRsyslinux"
      fi
    elif [ -n "$BRefistub" ] || [ -n "$BRbootctl" ]; then
      echo "$BRbootloader"
    else
      echo "None (WARNING)"
    fi

    if [ -n "$BRbootloader" ] && [ -n "$BRkernopts" ]; then
      echo "Kernel Options: $BRkernopts"
    fi

    echo -e "\nPROCESS"
    if [ "$BRmode" = "1" ]; then
      echo "Mode:    Restore"
      if [ -n "$BRencmethod" ]; then
        enc_info="$BRencmethod encrypted"
      fi
      echo "Archive: $BRfiletype $enc_info"
    elif [ "$BRmode" = "2" ]; then
      echo "Mode:    Transfer"
      if [ -n "$BRonlyhidden" ]; then
        echo "Home:    Only hidden files and folders"
      elif [ -n "$BRnohome" ]; then
        echo "Home:    Exclude"
      else
        echo "Home:    Include"
      fi
    fi

    if [ "$BRdistro" = "Unsupported" ]; then
      echo "System:  $BRdistro (WARNING)"
    elif [ "$BRmode" = "1" ]; then
      echo "System:  $BRdistro based $target_arch"
    elif [ "$BRmode" = "2" ]; then
      echo "System:  $BRdistro based $(uname -m)"
    fi

    if [ "$BRdistro" = "Gentoo" ] && [ -n "$BRgenkernel" ]; then
      echo "Info:    Skip initramfs building"
    fi

    if [ "$BRmode" = "2" ] && [ -n "$BR_TR_OPTS" ]; then
      echo -e "\nRSYNC OPTIONS"
    elif [ "$BRmode" = "1" ] && [ -n "$BR_TR_OPTS" ]; then
      echo -e "\nARCHIVER OPTIONS"
    fi
    for opt in "${BR_TR_OPTS[@]}"; do echo "$opt"; done
  }

  # Bind needed directories so we can chroot in the target system
  prepare_chroot() {
    print_msg "-e \nPreparing chroot environment" "Preparing chroot environment"
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
    if [ -d "$BR_EFI_DIR" ]; then
      echo "Binding /sys/firmware/efi/efivars"
      mount --bind /sys/firmware/efi/efivars /mnt/target/sys/firmware/efi/efivars
    fi
  }

  # Generate target system's fstab
  generate_fstab() {
  # Set the root partition. If it is on raid use the normal name, otherwise use UUID
    if [[ "$BRroot" == *dev/md* ]]; then
      fstab_root="$BRroot"
    else
      fstab_root="UUID=$(blkid -s UUID -o value "$BRroot")"
    fi

    # Root partition
    if [ "$BRrootfs" = "btrfs" ] && [ -n "$BRrootsubvol" ] && [ ! "$BRdistro" = "Suse" ]; then # Suse seems to boot without defining subvol= option
      echo -e "# $BRroot\n$fstab_root  /  btrfs  $BRmountopts,subvol=$BRrootsubvol  0  0"
    elif [ "$BRrootfs" = "btrfs" ]; then
      echo -e "# $BRroot\n$fstab_root  /  btrfs  $BRmountopts  0  0"
    else
      echo -e "# $BRroot\n$fstab_root  /  $BRrootfs  $BRmountopts  0  1"
    fi

    # Other partitions
    if [ -n "$BRparts" ]; then
      for part in "${BRpartsorted[@]}"; do
        BRpart="$(echo "$part" | cut -f2 -d"=")"
        BRmpoint="$(echo "$part" | cut -f1 -d"=")"
        # Convert // with 040, needed for paths with spaces
        BRmpoint="${BRmpoint///\//\\040}"
        BRpartfs="$(blkid -s TYPE -o value "$BRpart")"
        echo -e "\n# $BRpart"
        if [[ "$BRpart" == *dev/md* ]]; then
          echo "$BRpart  $BRmpoint  $BRpartfs  defaults  0  2"
        else
          echo "UUID=$(blkid -s UUID -o value "$BRpart")  $BRmpoint  $BRpartfs  defaults  0  2"
        fi
      done
    fi

    # Swap partition
    if [ -n "$BRswap" ] && [[ "$BRswap" == *dev/md* ]]; then
      echo -e "\n# $BRswap\n$BRswap  none  swap  defaults  0  0"
    elif [ -n "$BRswap" ]; then
      echo -e "\n# $BRswap\nUUID=$(blkid -s UUID -o value "$BRswap")  none  swap  defaults  0  0"
    fi
    # Inform the log
    echo -e "\nGenerated fstab:\n$(cat /mnt/target/etc/fstab)" >> /tmp/restore.log
  }

  # Generate a basic mdadm.conf and crypttab, rebuild initramfs images for all available kernels
  build_initramfs() {
    echo -e "\nRebuilding initramfs images"
    # If raid partitions found in fstab or by detect_root_map
    if grep -q dev/md /mnt/target/etc/fstab || [[ "$BRmap" == *raid* ]]; then
      echo "Generating mdadm.conf..."
      # Set mdadm.conf path
      if [ "$BRdistro" = "Debian" ]; then
        BR_MDADM_PATH="/mnt/target/etc/mdadm"
      else
        BR_MDADM_PATH="/mnt/target/etc"
      fi
      # Save old mdadm.conf if found
      if [ -f "$BR_MDADM_PATH/mdadm.conf" ]; then
        mv "$BR_MDADM_PATH/mdadm.conf" "$BR_MDADM_PATH/mdadm.conf-old"
      fi
      # Generate mdadm.conf
      mdadm --examine --scan > "$BR_MDADM_PATH/mdadm.conf"
      cat "$BR_MDADM_PATH/mdadm.conf"
      echo
    fi

    # If encrypted root found by detect_root_map
    if [ -n "$BRencdev" ] && [ ! "$BRdistro" = "Arch" ] && [ ! "$BRdistro" = "Gentoo" ]; then # Arch and Gentoo don't need it apparently
      # Save old crypttab file if found
      if [ -f /mnt/target/etc/crypttab ]; then
        mv /mnt/target/etc/crypttab /mnt/target/etc/crypttab-old
      fi
      # Generate a basic crypttab file for the root partition
      echo "Generating basic crypttab..."
      echo "$crypttab_root UUID=$(blkid -s UUID -o value "$BRencdev") none luks" > /mnt/target/etc/crypttab # We set crypttab_root in set_kern_opts
      cat /mnt/target/etc/crypttab
      echo
    fi

   # Search target system for kernels
    for FILE in /mnt/target/boot/*; do
      if file -b -k "$FILE" | grep -qw "bzImage"; then
        cn=$(echo "$FILE" | sed -n 's/[^-]*-//p') # Cutted kernel name without any prefix (eg without vmlinuz-)

        if [ ! "$BRdistro" = "Gentoo" ] && [ ! "$BRdistro" = "Unsupported" ]; then
          print_msg 0 "Building initramfs image for $cn"
        fi

        # Use distro tools to rebuild initramfs images
        if [ "$BRdistro" = "Arch" ]; then
          chroot /mnt/target mkinitcpio -p "$cn"
        elif [ "$BRdistro" = "Debian" ]; then
          chroot /mnt/target update-initramfs -u -k "$cn"
        elif [ "$BRdistro" = "Suse" ]; then
          chroot /mnt/target mkinitrd -k vmlinuz-"$cn" -i "$ipn"-"$cn"
        elif [ "$BRdistro" = "Mandriva" ] || [ "$BRdistro" = "Fedora" ]; then
          chroot /mnt/target dracut -f -v /boot/"$ipn"-"$cn".img "$cn"
        fi
      fi
    done

    # Use genkernel in Gentoo if -D is not given
    if [ "$BRdistro" = "Gentoo" ] && [ -n "$BRgenkernel" ]; then
      echo "Skipping..."
    elif [ "$BRdistro" = "Gentoo" ]; then
      print_msg 0 "Building initramfs images"
      chroot /mnt/target genkernel --no-color --install initramfs
    fi
  }

  # Check the initramfs name prefix. Other distros use initramfs-* other initrd-*
  detect_initramfs_prefix() {
    if ls /mnt/target/boot/ | grep -q "initramfs-"; then
      ipn="initramfs"
    else
      ipn="initrd"
    fi
  }

  # Find and copy Grub efi bootloader executable. Usually we need it in EFI/boot/ and as bootx64/32.efi
  cp_grub_efi() {
    if [ ! -d /mnt/target"$BRespmpoint"/EFI/boot ]; then
      mkdir /mnt/target"$BRespmpoint"/EFI/boot
    fi

    # Check for both architectures
    BR_GRUBX64_EFI="$(find /mnt/target"$BRespmpoint"/EFI ! -path "*/EFI/boot/*" ! -path "*/EFI/BOOT/*" -name "grubx64.efi" 2>/dev/null)"
    BR_GRUBIA32_EFI="$(find /mnt/target"$BRespmpoint"/EFI ! -path "*/EFI/boot/*" ! -path "*/EFI/BOOT/*" -name "grubia32.efi" 2>/dev/null)"

    if [ -f "$BR_GRUBX64_EFI" ]; then
      echo "Copying "$BR_GRUBX64_EFI" as /mnt/target$BRespmpoint/EFI/boot/bootx64.efi..."
      cp "$BR_GRUBX64_EFI" /mnt/target"$BRespmpoint"/EFI/boot/bootx64.efi
    elif [ -f "$BR_GRUBIA32_EFI" ]; then
      echo "Copying "$BR_GRUBIA32_EFI" as /mnt/target$BRespmpoint/EFI/boot/bootx32.efi..."
      cp "$BR_GRUBIA32_EFI" /mnt/target"$BRespmpoint"/EFI/boot/bootx32.efi
    fi
  }

  # Find and copy kernels and initramfs images in case of ESP in /boot/efi
  cp_kernels() {
    # Search target system for kernels
    for FILE in /mnt/target/boot/*; do
      if file -b -k "$FILE" | grep -qw "bzImage"; then
        echo "Copying $FILE in /mnt/target/boot/efi/"
        cp "$FILE" /mnt/target/boot/efi/
      fi
    done

    # Search target system for initramfs images
    for FILE in /mnt/target/boot/*; do
      if [[ "$FILE" == *initramfs* ]] || [[ "$FILE" == *initrd* ]]; then
        echo "Copying $FILE in /mnt/target/boot/efi/"
        cp "$FILE" /mnt/target/boot/efi/
      fi
    done
  }

  # Detect root luks/lvm/raid combinations
  detect_root_map() {
    # If the target root partition contains mapper and cryptsetup status succeeds on it then find the underlying block device (BRencdev)
    if [[ "$BRroot" == *mapper* ]] && cryptsetup status "$BRroot" &>/dev/null; then
      BRencdev="$(cryptsetup status "$BRroot" 2>/dev/null | grep device | sed -e "s/ *device:[ \t]*//")"

      # If the underlying block device contains mapper and lvdisplay succeeds on it then find the physical volume (BRphysical)
      if [[ "$BRencdev" == *mapper* ]] && lvdisplay "$BRencdev" &>/dev/null; then
        BRphysical="$(lvdisplay --maps "$BRencdev" 2>/dev/null | grep "Physical volume" | sed -e "s/ *Physical volume[ \t]*//")"
        # If the physical volume is in the form of /dev/md* then probably we have LUKS on LVM on RAID
        if [[ "$BRphysical" == *dev/md* ]]; then
          BRmap="luks->lvm->raid"
        # Else probably we have LUKS on LVM
        else
          BRmap="luks->lvm"
        fi
      # If the underlying block device is in the form of /dev/md* then we probably have LUKS on RAID
      elif [[ "$BRencdev" == *dev/md* ]]; then
        BRmap="luks->raid"
      # Else we have simple LUKS
      else
        BRmap="luks"
      fi

    # If the target root partition contains mapper and lvdisplay succeeds on it then find the physical volume (BRphysical) and the volume group (BRvgname)
    elif [[ "$BRroot" == *mapper* ]] && lvdisplay "$BRroot" &>/dev/null; then
      BRphysical="$(lvdisplay --maps "$BRroot" 2>/dev/null | grep "Physical volume" | sed -e "s/ *Physical volume[ \t]*//")"
      BRvgname="$(lvdisplay "$BRroot" 2>/dev/null | grep "VG Name" | sed -e "s/ *VG Name[ \t]*//")"

      # If the physical volume contains mapper and cryptsetup status succeeds on it then find the underlying block device (BRencdev)
      if [[ "$BRphysical" == *mapper* ]] && cryptsetup status "$BRphysical" &>/dev/null; then
        BRencdev="$(cryptsetup status "$BRphysical" 2>/dev/null | grep device | sed -e "s/ *device:[ \t]*//")"
        # If the underlying block device is in the form of /dev/md* then we probably have LVM on LUKS on RAID
        if [[ "$BRencdev" == *dev/md* ]]; then
          BRmap="lvm->luks->raid"
        # Else we have simple LVM on LUKS
        else
          BRmap="lvm->luks"
        fi
      # If the physical volume is in the form of /dev/md* then probably we have LVM on RAID
      elif [[ "$BRphysical" == *dev/md* ]]; then
        BRmap="lvm->raid"
      # Else we have simple LVM
      else
        BRmap="lvm"
      fi
    # If the target root partition is in the form of /dev/md* then probably we have RAID
    elif [[ "$BRroot" == *dev/md* ]]; then
      BRmap="raid"
    fi
  }

  # Set some default and user kernel boot options
  set_kern_opts() {
    if [ -n "$BRsyslinux" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ]; then
      if [ "$BRdistro" = "Arch" ]; then
        BRkernopts="rw ${BRkernopts}"
      else
        BRkernopts="ro quiet ${BRkernopts}"
      fi
      if [ "$BRrootfs" = "btrfs" ] && [ -n "$BRrootsubvol" ]; then
        BRkernopts="rootflags=subvol=$BRrootsubvol ${BRkernopts}"
      fi
    # We need a clean configuration to boot Fedora with grub
    elif [ -n "$BRgrub" ] && [ "$BRdistro" = "Fedora" ]; then
      BRkernopts="quiet rhgb ${BRkernopts}"
    fi

    # In case of Gentoo add dolvm and domdadm if we have root on LVM/RAID
    if [ "$BRdistro" = "Gentoo" ] && [[ "$BRmap" == *lvm* ]]; then
      BRkernopts="dolvm ${BRkernopts}"
    fi
    if [ "$BRdistro" = "Gentoo" ] && [[ "$BRmap" == *raid* ]]; then
      BRkernopts="domdadm ${BRkernopts}"
    fi

    if [ "$BRmap" = "luks" ] || [ "$BRmap" = "luks->lvm" ] || [ "$BRmap" = "luks->raid" ] || [ "$BRmap" = "luks->lvm->raid" ]; then
      if [ -n "$BRencdev" ] && [ "$BRdistro" = "Gentoo" ]; then
        BRkernopts="crypt_root=UUID=$(blkid -s UUID -o value "$BRencdev") ${BRkernopts}"
      elif [ -n "$BRencdev" ]; then
        BRkernopts="cryptdevice=UUID=$(blkid -s UUID -o value "$BRencdev"):${BRroot##*/} ${BRkernopts}"
        # Also set root for crypttab file
        crypttab_root="${BRroot##*/}"
      fi
    elif [ "$BRmap" = "lvm->luks" ] || [ "$BRmap" = "lvm->luks->raid" ]; then
      if [ -n "$BRencdev" ] && [ "$BRdistro" = "Gentoo" ]; then
        BRkernopts="crypt_root=UUID=$(blkid -s UUID -o value "$BRencdev") ${BRkernopts}"
      elif [ -n "$BRencdev" ]; then
        BRkernopts="cryptdevice=UUID=$(blkid -s UUID -o value "$BRencdev"):$BRvgname ${BRkernopts}"
        # Also set root for crypttab file
        crypttab_root="${BRphysical##*/}"
      fi
    fi
  }

  # Install the selected bootloader
  install_bootloader() {
  # Set the root partition in Syslinux, EFISTUB and Bootctl configuration entries. If it is on lvm use the normal name, otherwise use UUID
    if [[ "$BRroot" == *mapper* ]]; then
      bl_root="$BRroot"
    else
      bl_root="UUID=$(blkid -s UUID -o value "$BRroot")"
    fi

    # GRUB
    if [ -n "$BRgrub" ]; then
      print_msg "-e \nInstalling and updating Grub in $BRgrub" "Installing Grub in $BRgrub"
      # In case of ESP on /boot, if target boot/efi exists move it as boot/efi-old so we have a clean directory to work
      if [ -d "$BR_EFI_DIR" ] && [ "$BRespmpoint" = "/boot" ] && [ -d /mnt/target/boot/efi ]; then
        # Also if boot/efi-old already exists remove it
        if [ -d /mnt/target/boot/efi-old ]; then rm -r /mnt/target/boot/efi-old; fi
        mv /mnt/target/boot/efi /mnt/target/boot/efi-old
      fi

      # If raid array selected, install in all devices the array contains
      if [[ "$BRgrub" == *md* ]]; then
        for device in $(grep -w "${BRgrub##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]'); do
          if [ "$BRdistro" = "Arch" ]; then
            chroot /mnt/target grub-install --target=i386-pc --recheck /dev/"$device" || touch /tmp/error
          elif [ "$BRdistro" = "Debian" ]; then
            chroot /mnt/target grub-install --recheck /dev/"$device" || touch /tmp/error
          else
            chroot /mnt/target grub2-install --recheck /dev/"$device" || touch /tmp/error
          fi
        done
      # Normal install
      elif [ "$BRdistro" = "Arch" ] && [ -d "$BR_EFI_DIR" ]; then
        chroot /mnt/target grub-install --target="$BRgrubefiarch" --efi-directory="$BRgrub" --bootloader-id=grub --recheck || touch /tmp/error
      elif [ "$BRdistro" = "Arch" ]; then
        chroot /mnt/target grub-install --target=i386-pc --recheck "$BRgrub" || touch /tmp/error
      elif [ "$BRdistro" = "Debian" ] && [ -d "$BR_EFI_DIR" ]; then
        chroot /mnt/target grub-install --efi-directory="$BRgrub" --recheck || touch /tmp/error
      elif [ "$BRdistro" = "Debian" ]; then
        chroot /mnt/target grub-install --recheck "$BRgrub" || touch /tmp/error
      elif [ -d "$BR_EFI_DIR" ]; then
        chroot /mnt/target grub2-install --efi-directory="$BRgrub" --recheck || touch /tmp/error
      else
        chroot /mnt/target grub2-install --recheck "$BRgrub" || touch /tmp/error
      fi

      # Fedora already does this
      if [ ! "$BRdistro" = "Fedora" ] && [ -d "$BR_EFI_DIR" ]; then cp_grub_efi; fi
      # In case of ESP in /boot we do it for Fedora
      if [ "$BRdistro" = "Fedora" ] && [ -d "$BR_EFI_DIR" ] && [ "$BRespmpoint" = "/boot" ]; then cp_grub_efi; fi

      # Save old grub configuration
      if [ -n "$BRkernopts" ]; then
        if [ -f /mnt/target/etc/default/grub ]; then
          cp /mnt/target/etc/default/grub /mnt/target/etc/default/grub-old
        fi

        # Apply grub options. If GRUB_CMDLINE_LINUX already exists replace the line
        if grep -q "^GRUB_CMDLINE_LINUX=" /mnt/target/etc/default/grub; then
          sed -i 's\GRUB_CMDLINE_LINUX=.*\GRUB_CMDLINE_LINUX="'"$BRkernopts"'"\' /mnt/target/etc/default/grub
        else
          # Else write new line
          echo GRUB_CMDLINE_LINUX='"'$BRkernopts'"' >> /mnt/target/etc/default/grub
        fi

        # Inform the log
        echo -e "\nModified grub config:\n$(cat /mnt/target/etc/default/grub)\n" >> /tmp/restore.log
      fi

      # Run also mkconfig (update-grub equivalent)
      if [ "$BRdistro" = "Gentoo" ]; then
        chroot /mnt/target grub2-mkconfig -o /boot/grub/grub.cfg
      elif [ "$BRdistro" = "Arch" ] || [ "$BRdistro" = "Debian" ]; then
        chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg
      else
        chroot /mnt/target grub2-mkconfig -o /boot/grub2/grub.cfg
      fi

    # SYSLINUX
    elif [ -n "$BRsyslinux" ]; then
      print_msg "-e \nInstalling and configuring Syslinux in $BRsyslinux" "Installing Syslinux in $BRsyslinux"
      # If target boot/syslinux exists remove it so we have a clean directory to work
      if [ -d /mnt/target/boot/syslinux ]; then
        # Save the configuration file first
        mv /mnt/target/boot/syslinux/syslinux.cfg /mnt/target/boot/syslinux.cfg-old 2>/dev/null
        chattr -i /mnt/target/boot/syslinux/* 2>/dev/null
        rm -r /mnt/target/boot/syslinux/* 2>/dev/null
      # Else create the directory and the configuration file
      else
        mkdir -p /mnt/target/boot/syslinux
      fi
      touch /mnt/target/boot/syslinux/syslinux.cfg

      # In case of Arch syslinux-install_update does all the job
      if [ "$BRdistro" = "Arch" ]; then
        chroot /mnt/target syslinux-install_update -i -a -m || touch /tmp/error
      # For other distros
      else
        # If raid array selected, install in all devices the array contains
        if [[ "$BRsyslinux" == *md* ]]; then
          chroot /mnt/target extlinux --raid -i /boot/syslinux || touch /tmp/error
          # Search for raid devices for the selected array
          for device in $(grep -w "${BRsyslinux##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z][0-9]'); do
            # Seperate the device
            BRdevice="$(echo /dev/"$device" | cut -c -8)"
            # Seperate the partition number
            BRpartition="$(echo /dev/"$device" | cut -c 9-)"
            detect_partition_table_syslinux
            set_syslinux_flags_and_paths
            # Install the corresponding bin file
            echo "Installing $BRsyslinuxmbr in $BRdevice ($BRtable)"
            dd bs=440 count=1 conv=notrunc if="$BRsyslinuxmbrpath"/"$BRsyslinuxmbr" of="$BRdevice" &>> /tmp/restore.log || touch /tmp/error
          done
        # Normal install
        else
          # install extlinux
          chroot /mnt/target extlinux -i /boot/syslinux || touch /tmp/error
          # Device already given by the user
          BRdevice="$BRsyslinux"
          # If target /boot partition defined use that partition number
          if [ -n "$BRboot" ]; then
            BRpartition="${BRboot##*[[:alpha:]]}"
          # Else use target root partition number
          else
            BRpartition="${BRroot##*[[:alpha:]]}"
          fi
          detect_partition_table_syslinux
          set_syslinux_flags_and_paths
          echo "Installing $BRsyslinuxmbr in $BRsyslinux ($BRtable)"
          # Install the corresponding bin file
          dd bs=440 count=1 conv=notrunc if="$BRsyslinuxmbrpath"/"$BRsyslinuxmbr" of="$BRsyslinux" &>> /tmp/restore.log || touch /tmp/error
        fi
        # Copy com32 files we found in set_syslinux_flags_and_paths
        echo "Copying com32 modules"
        cp "$BRsyslinuxcompath"/*.c32 /mnt/target/boot/syslinux/
      fi
      # Generate syslinux configuration file
      echo "Generating syslinux.cfg"
      generate_syslinux_cfg >> /mnt/target/boot/syslinux/syslinux.cfg
      # Inform the log
      echo -e "\nGenerated syslinux config:\n$(cat /mnt/target/boot/syslinux/syslinux.cfg)" >> /tmp/restore.log

   # EFISTUB
    elif [ -n "$BRefistub" ]; then
      print_msg "-e \nSetting boot entries" "Setting boot entries using efibootmgr"
      # Seperate device and partition number
      if [[ "$BResp" == *mmcblk* ]] || [[ "$BResp" == *nvme* ]]; then
        BRespdev="${BResp%[[:alpha:]]*}"
      else
        BRespdev="${BResp%%[[:digit:]]*}"
      fi
      BRespart="${BResp##*[[:alpha:]]}"

      if [ "$BRespmpoint" = "/boot/efi" ]; then cp_kernels; fi

      # Search target ESP for kernels
      for FILE in /mnt/target$BRespmpoint/*; do
        if file -b -k "$FILE" | grep -qw "bzImage"; then
          cn="$(echo "$FILE" | sed -n 's/[^-]*-//p')" # Cutted kernel name without any prefix (eg without vmlinuz-)
          kn="$(basename "$FILE")" # Full kernel name (eg vmlinuz-linux)

          # Create boot entries using efibootmgr. We set ipn in detect_initramfs_prefix
          if [ "$BRdistro" = "Arch" ]; then
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro $cn fallback" -l /"$kn" -u "root=$bl_root $BRkernopts initrd=/$ipn-$cn-fallback.img" || touch /tmp/error
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro $cn" -l /"$kn" -u "root=$bl_root $BRkernopts initrd=/$ipn-$cn.img" || touch /tmp/error
          elif [ "$BRdistro" = "Debian" ]; then
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro-$cn" -l /"$kn" -u "root=$bl_root $BRkernopts initrd=/$ipn.img-$cn" || touch /tmp/error
          elif [ "$BRdistro" = "Fedora" ] || [ "$BRdistro" = "Mandriva" ]; then
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro-$cn" -l /"$kn" -u "root=$bl_root $BRkernopts initrd=/$ipn-$cn.img" || touch /tmp/error
          elif [ "$BRdistro" = "Suse" ]; then
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro-$cn" -l /"$kn" -u "root=$bl_root $BRkernopts initrd=/$ipn-$cn" || touch /tmp/error
          elif [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ]; then
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro-$kn" -l /"$kn" -u "root=$bl_root $BRkernopts initrd=/$ipn-$cn" || touch /tmp/error
          elif [ "$BRdistro" = "Gentoo" ]; then
            chroot /mnt/target efibootmgr -d "$BRespdev" -p "$BRespart" -c -L "$BRdistro-$kn" -l /"$kn" -u "root=$BRroot $BRkernopts" || touch /tmp/error
          fi
        fi
      done
      # Print entries and info
      chroot /mnt/target efibootmgr -v

    # BOOTCTL
    elif [ -n "$BRbootctl" ]; then
      print_msg "-e \nInstalling Bootctl in $BRespmpoint" "Installing Bootctl in $BRespmpoint"
      # Save old configuration entries first
      if [ -d /mnt/target"$BRespmpoint"/loader/entries ]; then
        for CONF in /mnt/target"$BRespmpoint"/loader/entries/*; do
          mv "$CONF" "$CONF"-old
        done
      fi
      if [ "$BRespmpoint" = "/boot/efi" ]; then cp_kernels; fi

      # Install systemd-boot
      chroot /mnt/target bootctl --path="$BRespmpoint" install || touch /tmp/error

      # Save old loader.conf if found
      if [ -f /mnt/target"$BRespmpoint"/loader/loader.conf ]; then
        mv /mnt/target"$BRespmpoint"/loader/loader.conf /mnt/target"$BRespmpoint"/loader/loader.conf-old
      fi
      # Generate loader.conf
      echo "timeout 5" > /mnt/target"$BRespmpoint"/loader/loader.conf
      echo "Generating configuration entries"

      # Search target ESP for kernels
      for FILE in /mnt/target"$BRespmpoint"/*; do
        if file -b -k "$FILE" | grep -qw "bzImage"; then
          cn="$(echo "$FILE" | sed -n 's/[^-]*-//p')" # Cutted kernel name without any prefix (eg without vmlinuz-)
          kn="$(basename "$FILE")" # Full kernel name (eg vmlinuz-linux)

          # Generate loader.conf entries. We set ipn in detect_initramfs_prefix
          if [ "$BRdistro" = "Arch" ]; then
            echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn.img\noptions root=$bl_root $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf
            echo -e "title $BRdistro $cn fallback\nlinux /$kn\ninitrd /$ipn-$cn-fallback.img\noptions root=$bl_root $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn"-fallback.conf
          elif [ "$BRdistro" = "Debian" ]; then
            echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn.img-$cn\noptions root=$bl_root $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf
          elif [ "$BRdistro" = "Fedora" ] || [ "$BRdistro" = "Mandriva" ]; then
            echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn.img\noptions root=$bl_root $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf
          elif [ "$BRdistro" = "Suse" ]; then
            echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn\noptions root=$bl_root $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf
          elif [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ]; then
            echo -e "title $BRdistro $cn\nlinux /$kn\ninitrd /$ipn-$cn\noptions root=$bl_root $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf
          elif [ "$BRdistro" = "Gentoo" ]; then
            echo -e "title $BRdistro $cn\nlinux /$kn\noptions root=$BRroot $BRkernopts" > /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf
          fi
          # Inform the log
          echo -e "\nGenerated $BRdistro-$cn.conf:\n$(cat /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn".conf)" >> /tmp/restore.log
          if [ "$BRdistro" = "Arch" ]; then
            echo -e "\nGenerated $BRdistro-$cn-fallback.conf:\n$(cat /mnt/target"$BRespmpoint"/loader/entries/"$BRdistro"-"$cn"-fallback.conf)" >> /tmp/restore.log
          fi
        fi
      done
    fi
  }

  # Set the bootloader, check for gptfdisk/gdisk packages, check backup archive if contains the selected bootloader, exit on errors
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
      # If the target Syslinux device is a raid array detect the partition table of one of the underlying devices. Probably all have the same partition table
      if [[ "$BRsyslinux" == *md* ]]; then
        for device in $(grep -w "${BRsyslinux##*/}" /proc/mdstat | grep -oP '[vhs]d[a-z]'); do
          BRdevice="/dev/$device"
        done
      fi
      detect_partition_table_syslinux
      # Search for sgdisk in case of GPT
      if [ ! "$BRdistro" = "Arch" ] && [ "$BRtable" = "gpt" ] && [ -z "$(which sgdisk 2>/dev/null)" ]; then
        print_err "-e [${RED}ERROR${NORM}] Package gptfdisk/gdisk is not installed. Install the package and re-run the script"
      elif [ "$BRdistro" = "Arch" ] && [ "$BRtable" = "gpt" ] && [ "$BRmode" = "2" ] && [ -z "$(which sgdisk 2>/dev/null)" ]; then
        print_err "-e [${RED}ERROR${NORM}] Package gptfdisk/gdisk is not installed. Install the package and re-run the script"
      # In case of Arch we run syslinux-install_update from chroot so it calls sgdisk from chroot also. Thats why in Restore mode sgdisk has to be in the archive
      elif [ "$BRdistro" = "Arch" ] && [ "$BRtable" = "gpt" ] && [ "$BRmode" = "1" ] && ! grep -Fq "bin/sgdisk" /tmp/filelist; then
        print_err "-e [${RED}ERROR${NORM}] sgdisk not found in the archived system"
      fi
    fi

    if [ "$BRmode" = "1" ]; then
      # Search archive contents for grub(2)-mkconfig
      if [ -n "$BRgrub" ] && ! grep -Fq "bin/grub-mkconfig" /tmp/filelist && ! grep -Fq "bin/grub2-mkconfig" /tmp/filelist; then
        print_err "-e [${RED}ERROR${NORM}] Grub not found in the archived system"
      # Search archive contents for sys/extlinux
      elif [ -n "$BRsyslinux" ]; then
        if ! grep -Fq "bin/extlinux" /tmp/filelist; then
          print_err "-e [${RED}ERROR${NORM}] Extlinux not found in the archived system"
        fi
        if ! grep -Fq "bin/syslinux" /tmp/filelist; then
          print_err "-e [${RED}ERROR${NORM}] Syslinux not found in the archived system"
        fi
      fi

      # Search archive contents for efibootmgr
      if [ -n "$BRgrub" ] || [ -n "$BRefistub" ] && [ -d "$BR_EFI_DIR" ] && ! grep -Fq "bin/efibootmgr" /tmp/filelist; then
        print_err "-e [${RED}ERROR${NORM}] efibootmgr not found in the archived system"
      fi
      # Search archive contents for mkfs.vfat
      if [ -n "$BRgrub" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DIR" ] && ! grep -Fq "bin/mkfs.vfat" /tmp/filelist; then
        print_err "-e [${RED}ERROR${NORM}] dosfstools not found in the archived system"
      fi
      # Search archive contents for bootctl
      if [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DIR" ] && ! grep -Fq "bin/bootctl" /tmp/filelist; then
        print_err "-e [${RED}ERROR${NORM}] Bootctl not found in the archived system"
      fi
      # Set the EFI Grub architecture in Restore Mode
      if [ "$target_arch" = "x86_64" ]; then
        BRgrubefiarch="x86_64-efi"
      elif [ "$target_arch" = "i686" ]; then
        BRgrubefiarch="i386-efi"
      fi
    fi

    # Set the EFI Grub architecture in Transfer Mode
    if [ -n "$BRgrub" ] && [ "$BRmode" = "2" ] && [ -d "$BR_EFI_DIR" ]; then
      if [ "$(uname -m)" = "x86_64" ]; then
        BRgrubefiarch="x86_64-efi"
      elif [ "$(uname -m)" = "i686" ]; then
        BRgrubefiarch="i386-efi"
      fi
    fi

    # In case of EFI and Grub, set the defined ESP mountpoint as --efi-directory
    if [ -n "$BRgrub" ] && [ -d "$BR_EFI_DIR" ]; then
      BRgrub="$BRespmpoint"
    fi

    if [ -n "$BRabort" ]; then
      clean_unmount
    fi
  }

  # Generate target system's locales
  generate_locales() {
    if [ "$BRdistro" = "Arch" ] || [ "$BRdistro" = "Debian" ] || [ "$BRdistro" = "Gentoo" ]; then
      print_msg "-e \nGenerating locales" "Generating locales"
      chroot /mnt/target locale-gen
    fi
  }

  # Clean and unmount
  clean_unmount() {
    echo -e "\n${BOLD}[CLEANING AND UNMOUNTING]${NORM}"
    # Make sure we are outside of /mnt/target
    cd /
    # Delete the downloaded backup archive
    rm "$BRmaxsize"/downloaded_backup 2>/dev/null

    if [ -n "$post_umt" ]; then
      # Unmount everything we mounted in prepare_chroot
      umount /mnt/target/dev/pts
      umount /mnt/target/proc
      umount /mnt/target/dev
      if [ -d "$BR_EFI_DIR" ]; then
        umount /mnt/target/sys/firmware/efi/efivars
      fi
      umount /mnt/target/sys
      umount /mnt/target/run
    fi

    # Read BRumountparts we created in mount_all and unmount backwards
    if [ -n "$BRparts" ]; then
      while read ln; do
        sleep 1
        print_msg "-ne ${WRK}Unmounting $ln" "Unmounting $ln"
        OUTPUT="$(umount "$ln" 2>&1)" && ok_status || error_status
      done < <(for BRpart in "${BRumountparts[@]}"; do echo "$BRpart" | cut -f2 -d"="; done | tac)
    fi

    if [ -z "$post_umt" ]; then
      # In case of btrfs subvolumes, unmount the root subvolume and mount the target root partition again
      if [ "$BRrootfs" = "btrfs" ] && [ -n "$BRrootsubvol" ]; then
        print_msg "-ne ${WRK}Unmounting $BRrootsubvol" "Unmounting $BRrootsubvol"
        OUTPUT="$(umount "$BRroot" 2>&1)" && ok_status || error_status
        sleep 1
        print_msg "-ne ${WRK}Mounting $BRroot" "Mounting $BRroot"
        OUTPUT="$(mount "$BRroot" /mnt/target 2>&1)" && ok_status || error_status

        # Delete the created subvolumes
        if [ -n "$BRsubvols" ]; then
          while read ln; do
            sleep 1
            print_msg "-ne ${WRK}Deleting $BRrootsubvol$ln" "Deleting $BRrootsubvol$ln"
            OUTPUT="$(btrfs subvolume delete /mnt/target/"$BRrootsubvol$ln" 2>&1 1>/dev/null)" && ok_status || error_status
          done < <(for subvol in "${BRsubvols[@]}"; do echo "$subvol"; done | sort -r)
        fi
        print_msg "-ne ${WRK}Deleting $BRrootsubvol" "Deleting $BRrootsubvol"
        OUTPUT="$(btrfs subvolume delete /mnt/target/"$BRrootsubvol" 2>&1 1>/dev/null)" && ok_status || error_status
      fi

      # If no error occured above and -x is not given clean the target root partition from created mountpoints
      if [ -z "$BRstop" ] && [ -z "$BRdontckroot" ]; then
        rm -r /mnt/target/* 2>/dev/null
      fi
    fi

    # Remove leftovers and unmount the target root partition
    rm /mnt/target/target_architecture.$(uname -m) 2>/dev/null
    sleep 1
    print_msg "-ne ${WRK}Unmounting $BRroot" "Unmounting $BRroot"
    OUTPUT="$(umount "$BRroot" 2>&1)" && (ok_status && sleep 1 && rm -r /mnt/target) || (error_status && echo -e "[${YELLOW}WARNING${NORM}] /mnt/target remained")

    if [ -n "$BRwrap" ] && [ -n "$post_umt" ]; then cat /tmp/restore.log > /tmp/wr_log; fi
    clean_tmp_files
    exit
  }

  # Quick read backup archive
  read_archive() {
    # In case of openssl encryption
    if [ -n "$BRencpass" ] && [ "$BRencmethod" = "openssl" ]; then
      openssl aes-256-cbc -d -salt -in "$BRsource" -k "$BRencpass" 2>/dev/null | tar "$BRreadopts" - "${BR_TR_OPTS[@]}" || touch /tmp/error
    # In case of gpg encryption
    elif [ -n "$BRencpass" ] && [ "$BRencmethod" = "gpg" ]; then
      gpg -d --batch --passphrase "$BRencpass" "$BRsource" 2>/dev/null | tar "$BRreadopts" - "${BR_TR_OPTS[@]}" || touch /tmp/error
    # Without encryption
    else
      tar ${BRreadopts} "$BRsource" "${BR_TR_OPTS[@]}" || touch /tmp/error
    fi
  }

  # Download the backup archive
  run_wget() {
    if [ -n "$BRusername" ] || [ -n "$BRpassword" ]; then
      wget --user="$BRusername" --password="$BRpassword" -O "$BRsource" "$BRuri" --tries=2 || touch /tmp/error
    else
      wget -O "$BRsource" "$BRuri" --tries=2 || touch /tmp/error
    fi
  }

  # Check if root partition is given
  if [ -z "$BRroot" ]; then
    print_err "-e [${RED}ERROR${NORM}] You must specify a target root partition" 0
  fi

  # Check if root partition ends with @, trim it and set var for clean it in mount_all
  if [[ "$BRroot" == *@ ]]; then
    BRroot="${BRroot//@}"
    BRrootclean="y"
  fi

  # Check if backup archive is given in Restore Mode
  if [ "$BRmode" = "1" ] && [ -z "$BRuri" ]; then
    print_err "-e [${RED}ERROR${NORM}] You must specify a backup archive" 0
  fi

  # If backup archive is a local file use it directly
  if [[ "$BRuri" == /* ]]; then
    BRsource="$BRuri"
  fi

  # A nice working info
  WRK="[${CYAN}WORKING${NORM}] "

  # Add ESP, /home and /boot partitions if given by the user
  if [ -n "$BResp" ] && [ -n "$BRespmpoint" ]; then
    BRparts+=("$BRespmpoint"="$BResp")
  fi
  if [ -n "$BRhome" ]; then
    BRparts+=(/home="$BRhome")
  fi
  if [ -n "$BRboot" ]; then
    BRparts+=(/boot="$BRboot")
  fi

  # Set default root mount options
  if [ -z "$BRmountopts" ]; then
    BRmountopts="defaults,noatime"
  fi

  # Exit if no partitions found by scan_parts
  if [ -z "$(scan_parts 2>/dev/null)" ]; then
    print_err "-e [${RED}ERROR${NORM}] No partitions found" 0
  fi

  # Check if working directory already exists
  if [ -d /mnt/target ]; then
    print_err "-e [${RED}ERROR${NORM}] /mnt/target exists, aborting" 0
  fi

  PATH="$PATH:/usr/sbin:/bin:/sbin"

  # Inform in case of UEFI environment
  if [ -d "$BR_EFI_DIR" ]; then
    echo -e "[${CYAN}INFO${NORM}] UEFI environment detected. (use -W to ignore)"
  fi

  # Check user input in many possible ways
  if [ "$BRmode" = "1" ]; then
    if [ -n "$BRsource" ] && [ ! -f "$BRsource" ]; then
      print_err "-e [${RED}ERROR${NORM}] File not found: $BRsource" 0
    elif [ -n "$BRsource" ] && [ -f "$BRsource" ] && [ -z "$BRfiletype" ]; then
      detect_encryption
      detect_filetype
      if [ "$BRfiletype" = "wrong" ]; then
        print_err "-e [${RED}ERROR${NORM}] Invalid file type or wrong passphrase" 0
      fi
    fi
    if [ -n "$BRuri" ] && [[ ! "$BRuri" == /* ]] && [ -z "$(which wget 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Package wget is not installed. Install the package and re-run the script" 0
    fi
  fi

  if [ "$BRmode" = "2" ]; then
    if [ -z "$(which rsync 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Package rsync is not installed. Install the package and re-run the script" 0
    fi
    if [ -f /etc/portage/make.conf ] || [ -f /etc/make.conf ] && [ -z "$BRgenkernel" ] && [ -z "$(which genkernel 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Package genkernel is not installed. Install the package and re-run the script (you can disable this check with -D)" 0
    fi
    if [ -n "$BRgrub" ] && [ -z "$(which grub-mkconfig 2>/dev/null)" ] && [ -z "$(which grub2-mkconfig 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Grub not found. Install it and re-run the script" 0
    elif [ -n "$BRsyslinux" ]; then
      if [ -z "$(which extlinux 2>/dev/null)" ]; then
        print_err "-e [${RED}ERROR${NORM}] Extlinux not found. Install it and re-run the script" 0
      fi
      if [ -z "$(which syslinux 2>/dev/null)" ]; then
        print_err "-e [${RED}ERROR${NORM}] Syslinux not found. Install it and re-run the script" 0
      fi
    fi
    if [ -n "$BRbootctl" ] || [ -n "$BRefistub" ] || [ -n "$BRgrub" ] && [ -d "$BR_EFI_DIR" ] && [ -z "$(which mkfs.vfat 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Package dosfstools is not installed. Install the package and re-run the script" 0
    fi
    if [ -n "$BRefistub" ] || [ -n "$BRgrub" ] && [ -d "$BR_EFI_DIR" ] && [ -z "$(which efibootmgr 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Package efibootmgr is not installed. Install the package and re-run the script" 0
    fi
    if [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DIR" ] && [ -z "$(which bootctl 2>/dev/null)" ]; then
      print_err "-e [${RED}ERROR${NORM}] Bootctl not found" 0
    fi
  fi

  if [ -n "$BRroot" ]; then
    for i in $(scan_parts); do if [ "$i" = "$BRroot" ]; then BRrootcheck="true"; fi; done
    if [ ! "$BRrootcheck" = "true" ]; then
      print_err "-e [${RED}ERROR${NORM}] Wrong root partition: $BRroot" 0
    elif [ ! -z "$(lsblk -d -n -o mountpoint 2>/dev/null "$BRroot")" ]; then
      print_err "-e [${YELLOW}WARNING${NORM}] $BRroot is already mounted as $(lsblk -d -n -o mountpoint 2>/dev/null "$BRroot"), refusing to use it" 0
    fi
  fi

  if [ -n "$BRswap" ]; then
    for i in $(scan_parts); do if [ "$i" = "$BRswap" ]; then BRswapcheck="true"; fi; done
    if [ ! "$BRswapcheck" = "true" ]; then
      print_err "-e [${RED}ERROR${NORM}] Wrong swap partition: $BRswap" 0
    fi
    if [ "$BRswap" = "$BRroot" ]; then
      print_err "-e [${YELLOW}WARNING${NORM}] $BRswap already used" 0
    fi
  fi

  if [ -n "$BRparts" ]; then
    BRpartused=(`for BRpart in "${BRparts[@]}"; do echo "${BRpart//@}" | cut -f2 -d"="; done | sort | uniq -d`)
    BRmpointused=(`for BRmpoint in "${BRparts[@]}"; do echo "$BRmpoint" | cut -f1 -d"="; done | sort | uniq -d`)
    if [ -n "$BRpartused" ]; then
      print_err "-e [${YELLOW}WARNING${NORM}] $BRpartused already used" 0
    fi
    if [ -n "$BRmpointused" ]; then
      print_err "-e [${YELLOW}WARNING${NORM}] Duplicate mountpoint: $BRmpointused" 0
    fi

    for part in "${BRparts[@]}"; do
      BRmpoint=$(echo "$part" | cut -f1 -d"=")
      BRpart=$(echo "${part//@}" | cut -f2 -d"=")

      for i in $(scan_parts); do if [ "$i" = "$BRpart" ]; then BRpartscheck="true"; fi; done
      if [ ! "$BRpartscheck" = "true" ]; then
        print_err "-e [${RED}ERROR${NORM}] Wrong $BRmpoint partition: $BRpart" 0
      elif [ ! -z "$(lsblk -d -n -o mountpoint 2>/dev/null "$BRpart")" ]; then
        print_err "-e [${YELLOW}WARNING${NORM}] $BRpart is already mounted as $(lsblk -d -n -o mountpoint 2>/dev/null "$BRpart"), refusing to use it" 0
      fi
      if [ "$BRpart" = "$BRroot" ] || [ "$BRpart" = "$BRswap" ]; then
        print_err "-e [${YELLOW}WARNING${NORM}] $BRpart already used" 0
      fi
      if [ "$BRmpoint" = "/" ]; then
        print_err "-e [${YELLOW}WARNING${NORM}] Use -r for the root partition" 0
      fi
      if [[ ! "$BRmpoint" == /* ]]; then
        print_err "-e [${RED}ERROR${NORM}] Wrong mountpoint syntax: $BRmpoint" 0
      fi
      unset BRpartscheck
    done
  fi

  if [ -n "$BRsubvols" ] && [ -z "$BRrootsubvol" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] You must specify a root subvolume name" 0
  fi

  if [ -n "$BRsubvols" ]; then
    BRsubvolused=(`for BRsubvol in "${BRsubvols[@]}"; do echo "$BRsubvol"; done | sort | uniq -d`)
    if [ -n "$BRsubvolused" ]; then
      for a in "${BRsubvolused[@]}"; do
        print_err "-e [${YELLOW}WARNING${NORM}] Duplicate subvolume: $a" 0
      done
    fi

    for b in "${BRsubvols[@]}"; do
      if [[ ! "$b" == /* ]]; then
        print_err "-e [${RED}ERROR${NORM}] Wrong subvolume syntax: $b" 0
      fi
      if [ "$b" = "/" ]; then
        print_err "-e [${YELLOW}WARNING${NORM}] Use -R to assign root subvolume" 0
      fi
    done
  fi

  if [ -n "$BRgrub" ] && [ ! "$BRgrub" = "auto" ]; then
    for i in $(scan_disks); do if [ "$i" = "$BRgrub" ]; then BRgrubcheck="true"; fi; done
    if [ ! "$BRgrubcheck" = "true" ]; then
      print_err "-e [${RED}ERROR${NORM}] Wrong grub device: $BRgrub" 0
    fi
  fi

  if [ -n "$BRgrub" ] && [ "$BRgrub" = "auto" ] && [ ! -d "$BR_EFI_DIR" ]; then
    print_err "-e [${RED}ERROR${NORM}] Use 'auto' in UEFI environment only" 0
  fi

  if [ -n "$BRgrub" ] && [ ! "$BRgrub" = "auto" ] && [ -d "$BR_EFI_DIR" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] In UEFI environment use 'auto' for grub device" 0
  fi

  if [ -n "$BRsyslinux" ]; then
    for i in $(scan_disks); do if [ "$i" = "$BRsyslinux" ]; then BRsyslinuxcheck="true"; fi; done
    if [ ! "$BRsyslinuxcheck" = "true" ]; then
      print_err "-e [${RED}ERROR${NORM}] Wrong syslinux device: $BRsyslinux" 0
    fi
    if [ -d "$BR_EFI_DIR" ]; then
      print_err "-e [${RED}ERROR${NORM}] The script does not support Syslinux as UEFI bootloader" 0
    fi
  fi

  if [ -n "$BRsyslinux" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -n "$BRgrub" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] Don't use multiple bootloaders" 0
  elif [ -n "$BRefistub" ] && [ -n "$BRbootctl" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] Don't use multiple bootloaders" 0
  fi

  if [ ! -d "$BR_EFI_DIR" ] && [ -n "$BResp" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] Don't use EFI system partition in bios mode" 0
  fi

  if [ -n "$BRgrub" ] || [ -n "$BRefistub" ] || [ -n "$BRbootctl" ] && [ -d "$BR_EFI_DIR" ] && [ -n "$BRroot" ] && [ -z "$BResp" ]; then
    print_err "-e [${RED}ERROR${NORM}] You must specify a target EFI system partition" 0
  fi

  if [ -n "$BRefistub" ] && [ ! -d "$BR_EFI_DIR" ]; then
    print_err "-e [${RED}ERROR${NORM}] EFISTUB is available in UEFI environment only" 0
  fi

  if [ -n "$BRbootctl" ] && [ ! -d "$BR_EFI_DIR" ]; then
    print_err "-e [${RED}ERROR${NORM}] Bootctl is available in UEFI environment only" 0
  fi

  if [ -n "$BResp" ] && [ -z "$BRespmpoint" ] && [ -d "$BR_EFI_DIR" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] You must specify mount point for ESP ($BResp)" 0
  elif [ -n "$BResp" ] && [ ! "$BRespmpoint" = "/boot/efi" ] && [ ! "$BRespmpoint" = "/boot" ] && [ -d "$BR_EFI_DIR" ]; then
    print_err "-e [${YELLOW}WARNING${NORM}] Wrong ESP mount point: $BRespmpoint. Available options: /boot/efi /boot" 0
  fi

  mount_all

  # In Restore mode download the backup archive if url is given, read it and check it
  if [ "$BRmode" = "1" ]; then
    echo -e "\n${BOLD}[BACKUP ARCHIVE]${NORM}"

    if [[ ! "$BRuri" == /* ]]; then
      BRsource="$BRmaxsize/downloaded_backup"
      # Give percentage to gui wrapper if -w is given
      if [ -n "$BRwrap" ]; then
        lastperc="-1"
        run_wget 2>&1 | sed -nru '/[0-9]%/ s/.* ([0-9]+)%.*/\1/p' |
        while read perc; do
          if [[ "$perc" -gt "$lastperc" ]]; then
            lastperc="$perc"
            echo "Downloading in $BRmaxsize: $perc%" > /tmp/wr_proc
          fi
        done
      else
        run_wget
      fi
      if [ -f /tmp/error ]; then
        print_err "-e [${RED}ERROR${NORM}] Error downloading file. Wrong URL, wrong authentication or network is down." 1
      else
        detect_encryption
        # If the downloaded archive is encrypted prompt the user for passphrase
        if [ -n "$BRencmethod" ] && [ -z "$BRencpass" ] && [ -z "$BRwrap" ]; then
          echo -ne "${BOLD}"
          read -p "Enter Passphrase: $(echo -e "${NORM}")" BRencpass
        fi
        detect_filetype
        if [ "$BRfiletype" = "wrong" ]; then
          print_err "-e [${RED}ERROR${NORM}] Invalid file type or wrong passphrase" 1
        fi
      fi
    fi

    print_msg 0 "Please wait while checking and reading archive"
    # Read the backup archive and give list of files in /tmp/filelist also
    read_archive | tee /tmp/filelist | while read ln; do a="$((a + 1))" && echo -en "\rChecking and reading archive ($a Files) "; done
    echo
    if [ -f /tmp/error ]; then
      print_err "-e [${RED}ERROR${NORM}] Error reading archive" 1
    else
      target_arch="$(grep -F 'target_architecture.' /tmp/filelist | cut -f2 -d".")"
      if [ ! "$(uname -m)" = "$target_arch" ]; then
        print_err "-e [${RED}ERROR${NORM}] Running and target system architecture mismatch or invalid archive" 1
      fi
    fi
  fi

  detect_distro
  set_bootloader
  detect_root_map

  # Check archive for genkernel in case of Gentoo if -D is not given
  if [ "$BRmode" = "1" ] && [ "$BRdistro" = "Gentoo" ] && [ -z "$BRgenkernel" ] && ! grep -Fq "bin/genkernel" /tmp/filelist; then
    print_err "-e [${YELLOW}WARNING${NORM}] Genkernel not found in the archived system. (you can disable this check with -D)" 1
  fi

  if [ "$BRmode" = "1" ]; then
    set_tar_opts
  elif [ "$BRmode" = "2" ]; then
    set_rsync_opts
  fi
  if [ -n "$BRbootloader" ]; then
    set_kern_opts
  fi

  # Show summary and prompt the user to continue. If -q is given continue automatically
  echo -e "\n${BOLD}[SUMMARY]${CYAN}"
  show_summary
  echo -ne "${NORM}"

  while [ -z "$BRquiet" ]; do
    echo -e "${BOLD}"
    read -p "Continue? [Y/n]: $(echo -e "${NORM}")" an
    if [ "$an" = "y" ] || [ "$an" = "Y" ] || [ -z "$an" ]; then
      break
    elif [ "$an" = "n" ] || [ "$an" = "N" ]; then
      clean_unmount
    else
      echo -e "${RED}Please enter a valid option${NORM}"
    fi
  done

  # Start the log
  echo -e "$BR_VERSION\n\n[SUMMARY]\n$(show_summary)\n\n[PROCESSING]" > /tmp/restore.log

  echo -e "\n${BOLD}[PROCESSING]${NORM}"
  # Restore mode
  if [ "$BRmode" = "1" ]; then
    # Store the number of files we found from read_archive
    total="$(cat /tmp/filelist | wc -l)"
    sleep 1
    # Run tar and pipe it through the progress calculation, give errors to log
    mode_job="Extracting"
    (run_tar 2>>/tmp/restore.log && echo "$total Files extracted successfully" >> /tmp/restore.log) | pgrs_bar

  # Transfer mode
  elif [ "$BRmode" = "2" ]; then
    # Calculate the number of files
    print_msg 0 "Please wait while calculating files"
    run_calc | while read ln; do a="$((a + 1))" && echo -en "\rCalculating: $a Files"; done
    sleep 1
    # Store the number of files we found from run_calc
    total="$(cat /tmp/filelist | wc -l)"
    echo
    # Run rsync and pipe it through the progress calculation, give errors to log
    mode_job="Transferring"
    (run_rsync 2>>/tmp/restore.log && echo "$total Files transferred successfully" >> /tmp/restore.log) | pgrs_bar
  fi

  if [ -z "$BRverb" ]; then echo; fi
  prepare_chroot 1> >(tee -a /tmp/restore.log) 2>&1
  sleep 1

  print_msg "-e \nGenerating fstab" "Generating fstab"
  # Save the old fstab first
  cp /mnt/target/etc/fstab /mnt/target/etc/fstab-old
  generate_fstab > /mnt/target/etc/fstab
  cat /mnt/target/etc/fstab
  detect_initramfs_prefix

  # Prompt the user to edit the generated fstab if -q is not given
  while [ -z "$BRquiet" ]; do
    echo -e "${BOLD}"
    read -p "Edit fstab? [y/N]: $(echo -e "${NORM}")" an
    if [ "$an" = "y" ] || [ "$an" = "Y" ]; then
      PS3="Enter number: "
      echo -e "\n${CYAN}Select editor${NORM}"
      select BReditor in "nano" "vi"; do
        if [[ "$REPLY" = [1-2] ]]; then
          "$BReditor" /mnt/target/etc/fstab
          # Inform the log
          echo -e "\nEdited fstab:\n$(cat /mnt/target/etc/fstab)" >> /tmp/restore.log
          break
        else
          echo -e "${RED}Please select a valid option${NORM}"
        fi
      done
      break
    elif [ "$an" = "n" ] || [ "$an" = "N" ] || [ -z "$an" ]; then
      break
    else
      echo -e "${RED}Please enter a valid option${NORM}"
    fi
  done

  # Run post processing functions, update the log and pray :p
  (build_initramfs; generate_locales; install_bootloader) 1> >(tee -a /tmp/restore.log) 2>&1

  # Inform the user if error occurred or not
  if [ -f /tmp/error ]; then
    echo -e "\n${RED}Error installing $BRbootloader. Check /tmp/restore.log for details.${NORM}"
  else
    echo -e "\n${CYAN}Completed. Log: /tmp/restore.log${NORM}"
    if [ -z "$BRbootloader" ] && [ -z "$BRquiet" ]; then
      echo -e "\n${YELLOW}You didn't choose a bootloader, so this is the right time to install and\nupdate one. To do so:"
      echo -e "\n==>For internet connection to work, on a new terminal with root\n   access enter: cp -L /etc/resolv.conf /mnt/target/etc/resolv.conf"
      echo -e "\n==>Then chroot into the target system: chroot /mnt/target"
      echo -e "\n==>Install and update a bootloader"
      echo -e "\n==>When done exit chroot, return here and press ENTER${NORM}"
    fi
  fi
  if [ -z "$BRquiet" ]; then
    echo -e "\n${CYAN}Press ENTER to unmount all remaining (engaged) devices.${NORM}"
    read -s
  fi

  sleep 1
  post_umt="y"
  clean_unmount
fi
