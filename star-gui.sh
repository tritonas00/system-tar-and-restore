#!/bin/bash

if [ -z "$(which gtkdialog 2>/dev/null)" ]; then
  echo "Package gtkdialog is not installed. Install the package and re-run the script"
  exit
fi

cd "$(dirname "$0")"

clean_tmp_files() {
  if [ -f /tmp/wr_proc ]; then rm /tmp/wr_proc; fi
  if [ -f /tmp/wr_log ]; then rm /tmp/wr_log; fi
  if [ -f /tmp/wr_pid ]; then rm /tmp/wr_pid; fi
  if [ -f /tmp/wr_functions ]; then rm /tmp/wr_functions; fi
}

clean_tmp_files

export BRtitle="System Tar & Restore"

echo -n > /tmp/wr_log
echo true > /tmp/wr_pid
echo "$BRtitle" > /tmp/wr_proc

if [ -f changelog ]; then
  export BRchangelog="changelog"
else
  export BRchangelog="/usr/share/system-tar-and-restore/changelog"
fi

if [ -f "$1" ]; then
  source "$1"
elif [ -f /etc/backup.conf ]; then
  source /etc/backup.conf
fi

# Export basic vars from configuration file, set defaults if not given
if [ -n "$BRNAME" ]; then
  export BC_FILENAME="$BRNAME"
else
  export BC_FILENAME="Backup-$(hostname)-$(date +%Y-%m-%d-%T)"
fi

if [ -n "$BRFOLDER" ]; then
  export BC_DESTINATION="$BRFOLDER"
else
  export BC_DESTINATION="/"
fi

if [ -n "$BRsrc" ]; then
  export BC_SOURCE="$BRsrc"
else
  export BC_SOURCE="/"
fi

if [ -n "$BRonlyhidden" ] && [ -n "$BRnohome" ]; then
  echo "Error parsing configuration file. Choose only one option for the /home directory"
  exit
elif [ -n "$BRonlyhidden" ]; then
  export BC_HOME="Only hidden files and folders"
elif [ -n "$BRnohome" ]; then
  export BC_HOME="Exclude"
else
  export BC_HOME="Include"
fi

if [ -n "$BRcompression" ]; then
  export BC_COMPRESSION="$BRcompression"
else
  export BC_COMPRESSION="gzip"
fi

if [ -n "$BRencmethod" ]; then
  export BC_ENCRYPTION="$BRencmethod"
else
  export BC_ENCRYPTION="none"
fi

# Set user tar options if given from configuration file, separate entries
if [ -n "$BR_USER_OPTS" ]; then
  for opt in $BR_USER_OPTS; do
    if [[ "$opt" == --exclude=* ]]; then
      export BC_EXCLUDE="$(echo "$opt" | cut -f2 -d"=") $BC_EXCLUDE"
    elif [[ "$opt" == -* ]]; then
      export BC_OPTIONS="$opt $BC_OPTIONS"
    fi
  done
fi

# Store needed functions to a temporary file so we can source it inside gtkdialog
# This ensures compatibility with Ubuntu 16.04 and variants
echo '
set_args() {
  # Backup mode arguments
  if [ "$BR_TAB" = "0" ]; then
    SCR_ARGS=(-i 0 -jwq -d "$BC_DESTINATION" -c "$BC_COMPRESSION")

    if [ -n "$BC_FILENAME" ] && [[ ! "$BC_FILENAME" == Backup-$(hostname)-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
      SCR_ARGS+=(-n "$BC_FILENAME")
    fi

    if [ -n "$BC_SOURCE" ] && [ ! "$BC_SOURCE" = "/" ]; then
      SCR_ARGS+=(-T "$BC_SOURCE")
    fi

    if [ "$BC_HOME" = "Only hidden files and folders" ]; then
      SCR_ARGS+=(-O)
    elif [ "$BC_HOME" = "Exclude" ]; then
      SCR_ARGS+=(-H)
    fi

    if [ ! "$BC_ENCRYPTION" = "none" ]; then
      SCR_ARGS+=(-E "$BC_ENCRYPTION" -P "$BC_PASSPHRASE")
    fi

    set -f
    for i in $BC_EXCLUDE; do BC_OPTIONS="$BC_OPTIONS --exclude=$i"; done
    set +f

    if [ -n "$BC_OPTIONS" ]; then
      SCR_ARGS+=(-u "$BC_OPTIONS")
    fi

    if [ "$BC_MULTICORE" = "true" ] && [ ! "$BC_COMPRESSION" = "none" ]; then
      SCR_ARGS+=(-M)
      if [ ! "$BC_THREADS" = "0" ]; then
        SCR_ARGS+=(-z "$BC_THREADS")
      fi
    fi

    if [ "$BC_GENERATE" = "true" ]; then
      SCR_ARGS+=(-g)
    fi

    if [ "$BC_CLEAN" = "true" ]; then
      SCR_ARGS+=(-a)
    fi

    if [ "$BC_OVERRIDE" = "true" ]; then
      SCR_ARGS+=(-o)
    fi

    if [ "$BC_GENKERNEL" = "true" ]; then
      SCR_ARGS+=(-D)
    fi

  elif [ "$BR_TAB" = "1" ]; then
    # Restore mode arguments
    if [ "$RT_TAB" = "0" ]; then
      SCR_ARGS=(-i 1 -jwq -f "$RS_ARCHIVE")

      if [ -n "$RS_PASSPHRASE" ]; then
        SCR_ARGS+=(-P "$RS_PASSPHRASE")
      fi

      if [ -n "$RS_OPTIONS" ]; then
        SCR_ARGS+=(-u "$RS_OPTIONS")
      fi

      if [ -n "$RS_USERNAME" ]; then
        SCR_ARGS+=(-y "$RS_USERNAME")
      fi

      if [ -n "$RS_PASSWORD" ]; then
        SCR_ARGS+=(-p "$RS_PASSWORD")
      fi
    # Transfer mode arguments
    elif [ "$RT_TAB" = "1" ]; then
      SCR_ARGS=(-i 2 -jwq)
      if [ "$TS_HOME" = "Only hidden files and folders" ]; then
        SCR_ARGS+=(-O)
      elif [ "$TS_HOME" = "Exclude" ]; then
        SCR_ARGS+=(-H)
      fi

      set -f
      for i in $TS_EXCLUDE; do TS_OPTIONS="$TS_OPTIONS --exclude=$i"; done
      set +f

      if [ -n "$TS_OPTIONS" ]; then
        SCR_ARGS+=(-u "$TS_OPTIONS")
      fi
    fi

    # Restore/Transfer mode common arguments
    if [ "$RT_ROOT_CLEAN" = "true" ]; then
      SCR_ARGS+=(-r "${RT_ROOT%% *}"@)
    else
      SCR_ARGS+=(-r "${RT_ROOT%% *}")
    fi

    if [ -n "$RT_ROOT_OPTIONS" ]; then
      SCR_ARGS+=(-m "$RT_ROOT_OPTIONS")
    fi

    if [ -n "$RT_ESP" ] && [ "$RT_ESP_CLEAN" = "true" ]; then
      SCR_ARGS+=(-e "${RT_ESP%% *}"@ -l "$RT_ESP_MOUNTPOINT")
    elif [ -n "$RT_ESP" ]; then
      SCR_ARGS+=(-e "${RT_ESP%% *}" -l "$RT_ESP_MOUNTPOINT")
    fi

    if [ -n "$RT_BOOT" ] && [ "$RT_BOOT_CLEAN" = "true" ]; then
      SCR_ARGS+=(-b "${RT_BOOT%% *}"@)
    elif [ -n "$RT_BOOT" ]; then
      SCR_ARGS+=(-b "${RT_BOOT%% *}")
    fi

    if [ -n "$RT_HOME" ] && [ "$RT_HOME_CLEAN" = "true" ]; then
      SCR_ARGS+=(-h "${RT_HOME%% *}"@)
    elif [ -n "$RT_HOME" ]; then
      SCR_ARGS+=(-h "${RT_HOME%% *}")
    fi

    if [ -n "$RT_SWAP" ]; then
      SCR_ARGS+=(-s "${RT_SWAP%% *}")
    fi

    if [ -n "$RT_OTHER_PARTS" ]; then
      SCR_ARGS+=(-t "$RT_OTHER_PARTS")
    fi

    if [ -n "$RT_ROOT_SUBVOL" ]; then
      SCR_ARGS+=(-R "$RT_ROOT_SUBVOL")
    fi

    if [ -n "$RT_OTHER_SUBVOLS" ]; then
      SCR_ARGS+=(-B "$RT_OTHER_SUBVOLS")
    fi

    if [ "$RT_BOOTLOADER" = "Grub" ]; then
      SCR_ARGS+=(-G "${RT_BOOTLOADER_DEVICE%% *}")
    elif [ "$RT_BOOTLOADER" = "Grub-efi" ]; then
      SCR_ARGS+=(-G auto)
    elif [ "$RT_BOOTLOADER" = "Syslinux" ]; then
      SCR_ARGS+=(-S "${RT_BOOTLOADER_DEVICE%% *}")
    elif [ "$RT_BOOTLOADER" = "EFISTUB/efibootmgr" ]; then
      SCR_ARGS+=(-F)
    elif [ "$RT_BOOTLOADER" = "Systemd/bootctl" ]; then
      SCR_ARGS+=(-L)
    fi

    if [ ! "$RT_BOOTLOADER" = "none" ] && [ -n "$RT_KERNEL_OPTIONS" ]; then
      SCR_ARGS+=(-k "$RT_KERNEL_OPTIONS")
    fi

    if [ "$RT_OVERRIDE" = "true" ]; then
      SCR_ARGS+=(-o)
    fi

    if [ "$RT_GENKERNEL" = "true" ]; then
      SCR_ARGS+=(-D)
    fi

    if [ "$RT_CHECK_ROOT" = "true" ]; then
      SCR_ARGS+=(-x)
    fi

    if [ "$RT_BIOS" = "true" ]; then
      SCR_ARGS+=(-W)
    fi
  fi
}

run_main() {
  if [ "$BR_TAB" = "0" ] || [ "$BR_TAB" = "1" ] && [ "$BR_DEBUG" = "true" ]; then
    echo star.sh "${SCR_ARGS[@]}" > /tmp/wr_proc
  elif [ "$BR_TAB" = "0" ] || [ "$BR_TAB" = "1" ]; then
    echo false > /tmp/wr_pid
    setsid ./star.sh "${SCR_ARGS[@]}" >&3 2> /tmp/wr_log
    sleep 0.1
    echo "$BRtitle" > /tmp/wr_proc
    echo true > /tmp/wr_pid
  fi
}
' > /tmp/wr_functions

# Scan normal partitions, lvm, md arrays, sd card partitions and devices, initialize target root partition
export RT_PARTS="$(for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done | sort
                   for f in $(find /dev/mapper/ -maxdepth 1 -mindepth 1 ! -name "control"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                   for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                   for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                   for f in $(find /dev -regex "/dev/nvme[0-9]+n[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done)"

export RT_DISKS="$(for f in /dev/[vhs]d[a-z]; do echo "$f $(lsblk -d -n -o size $f)"; done
                   for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f)"; done
                   for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done
                   for f in $(find /dev -regex "/dev/nvme[0-9]+n[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done)"

export RT_ROOT="$(echo "$RT_PARTS" | head -n 1)"

export MAIN_DIALOG='
<window icon-name="gtk-preferences" height-request="645" width-request="515">
        <vbox>
                <checkbox visible="false" auto-refresh="true">
                        <input file>/tmp/wr_pid</input>
                        <action> if true enable:BTN_RUN</action>
                        <action> if true enable:BTN_EXIT</action>
                        <action> if true enable:BR_TAB</action>
                        <action> if true disable:BTN_CANCEL</action>
                        <action> if true refresh:BR_TAB</action>
                        <action> if false disable:BTN_RUN</action>
                        <action> if false disable:BTN_EXIT</action>
                        <action> if false enable:BTN_CANCEL</action>
                </checkbox>
                <entry visible="false" auto-refresh="true">
                        <input file>/tmp/wr_proc</input>
                        <action>refresh:WND_TITLE</action>
                        <action condition="file_is_false(/tmp/wr_pid)">disable:BR_TAB</action>
                </entry>
                <notebook labels="Backup|Restore/Transfer|Log|About" space-expand="true" space-fill="true">
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="25" tooltip-text="==>Make sure destination has enough space

==>If you plan to restore in lvm/mdadm/luks,
       configure this system accordingly

==>Supported bootloaders:
       Grub Syslinux EFISTUB/efibootmgr Systemd/bootctl

GRUB PACKAGES
**Arch/Gentoo:
    grub
**Fedora/openSUSE:
    grub2
**Debian/Ubuntu:
    grub-pc grub-efi
**Mandriva/Mageia:
    grub2 grub2-efi

SYSLINUX PACKAGES
**Arch/openSUSE/Gentoo:
    syslinux
**Debian/Ubuntu/Mandriva/Mageia:
    syslinux extlinux
**Fedora:
    syslinux syslinux-extlinux

OTHER PACKAGES
efibootmgr dosfstools systemd"><label>"Make a backup archive of this system"</label></text>
                                <hseparator></hseparator>
                                <hbox>
                                        <text width-request="135" label="Filename:"></text>
                                        <entry text="'"$BC_FILENAME"'" tooltip-text="Set backup archive name">
                                                <variable>BC_FILENAME</variable>
                                        </entry>
                                </hbox>
                                <hbox>
                                        <text width-request="135" label="Destination:"></text>
                                        <entry text="'"$BC_DESTINATION"'" fs-action="folder" fs-title="Select a directory" tooltip-text="Choose where to save the backup archive">
                                                <variable>BC_DESTINATION</variable>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:BC_DESTINATION</action>
                                        </button>
                                </hbox>
                                <hbox>
                                        <text width-request="135" label="Source:"></text>
                                        <entry text="'"$BC_SOURCE"'" fs-action="folder" fs-title="Select a directory" tooltip-text="Choose an alternative source directory to create a non-system backup archive">
                                                <variable>BC_SOURCE</variable>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:BC_SOURCE</action>
                                        </button>
                                </hbox>
                                <hbox>
                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                <variable>BC_HOME</variable>
                                                <default>'"$BC_HOME"'</default>
                                                <item>Include</item>
	                                        <item>Only hidden files and folders</item>
	                                        <item>Exclude</item>
                                        </comboboxtext>
                                </hbox>
                                <hbox>
                                        <text width-request="135" space-expand="false" label="Compression:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select compressor">
	                                        <variable>BC_COMPRESSION</variable>
                                                <default>'"$BC_COMPRESSION"'</default>
	                                        <item>gzip</item>
	                                        <item>bzip2</item>
	                                        <item>xz</item>
                                                <item>none</item>
                                                <action condition="command_is_true([ $BC_COMPRESSION = none ] && echo true)">disable:BC_MULTICORE</action>
                                                <action condition="command_is_true([ ! $BC_COMPRESSION = none ] && echo true)">enable:BC_MULTICORE</action>
                                                <action condition="command_is_true([ $BC_COMPRESSION = none ] && echo true)">disable:BC_THREADS</action>
                                                <action condition="command_is_true([ ! $BC_COMPRESSION = none ] && [ $BC_MULTICORE = true ] && echo true)">enable:BC_THREADS</action>
                                                <action condition="command_is_true([ $BC_COMPRESSION = none ] && echo true)">disable:BC_THREADS_TXT</action>
                                                <action condition="command_is_true([ ! $BC_COMPRESSION = none ] && [ $BC_MULTICORE = true ] && echo true)">enable:BC_THREADS_TXT</action>
	                                </comboboxtext>
                                </hbox>
                                <hbox>
                                        <text width-request="135" space-expand="false" label="Encryption:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select encryption method">
	                                        <variable>BC_ENCRYPTION</variable>
                                                <default>'"$BC_ENCRYPTION"'</default>
                                                <item>none</item>
	                                        <item>openssl</item>
	                                        <item>gpg</item>
                                                <action condition="command_is_true([ $BC_ENCRYPTION = none ] && echo true)">disable:BC_PASSPHRASE</action>
                                                <action condition="command_is_true([ ! $BC_ENCRYPTION = none ] && echo true)">enable:BC_PASSPHRASE</action>
                                        </comboboxtext>
                                </hbox>
                                <hbox>
                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                        <entry visibility="false" tooltip-text="Set passphrase for encryption">
                                                '"$(if [ "$BC_ENCRYPTION" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                <variable>BC_PASSPHRASE</variable>
                                                '"$(if [ -n "$BRencpass" ]; then echo "<default>$BRencpass</default>"; fi)"'
                                        </entry>
                                </hbox>
                                <hbox>
                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                        <entry text="'"$BC_OPTIONS"'" space-expand="true" space-fill="true" tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //

Default options:
--sparse
--acls
--xattrs
--selinux (Fedora)">
                                                <variable>BC_OPTIONS</variable>
                                        </entry>
                                </hbox>
                                <hbox>
                                        <text width-request="135" space-expand="false" label="Exclude:"></text>
                                        <entry text="'"$BC_EXCLUDE"'" space-expand="true" space-fill="true" tooltip-text="Exclude files and directories. If you want spaces in names replace them with //

Excluded by default:
/run/*
/dev/*
/sys/*
/tmp/*
/mnt/*
/proc/*
/media/*
/var/run/*
/var/lock/*
.gvfs
lost+found">
                                                <variable>BC_EXCLUDE</variable>
                                        </entry>
                                </hbox>
                                <vbox>
                                        <hseparator></hseparator>
                                        <hbox>
                                                <checkbox space-expand="true" label="Multi-core compression" tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz">
                                                        '"$(if [ "$BC_COMPRESSION" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                        <variable>BC_MULTICORE</variable>
                                                        '"$(if [ -n "$BRmcore" ]; then echo "<default>true</default>"; fi)"'
                                                        <action>if true enable:BC_THREADS</action>
                                                        <action>if false disable:BC_THREADS</action>
                                                        <action>if true enable:BC_THREADS_TXT</action>
                                                        <action>if false disable:BC_THREADS_TXT</action>
                                                </checkbox>
                                                <text space-fill="true" label="Threads:">
                                                        '"$(if [ "$BC_COMPRESSION" = "none" ] || [ -z "$BRmcore" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                        <variable>BC_THREADS_TXT</variable>
                                                </text>
                                                <spinbutton range-max="'"$(nproc --all)"'" tooltip-text="Specify the number of threads for multi-core compression (max = 0)">
                                                        '"$(if [ "$BC_COMPRESSION" = "none" ] || [ -z "$BRmcore" ]; then echo "<sensitive>false</sensitive>"; fi)"'
	                                                <variable>BC_THREADS</variable>
                                                        '"$(if [ -n "$BRmcore" ] && [ -n "$BRthreads" ]; then echo "<default>$BRthreads</default>"; fi)"'
                                                </spinbutton>
                                        </hbox>
                                        <checkbox label="Generate configuration file" tooltip-text="Generate configuration file in case of successful backup">
                                                <variable>BC_GENERATE</variable>
                                        </checkbox>
                                        <checkbox label="Remove older backups" tooltip-text="Remove older backups in the destination directory">
                                                <variable>BC_CLEAN</variable>
                                                '"$(if [ -n "$BRclean" ]; then echo "<default>true</default>"; fi)"'
                                        </checkbox>
                                        <checkbox label="Override options" tooltip-text="Override the default tar options/excludes with user defined ones">
                                                <variable>BC_OVERRIDE</variable>
                                                '"$(if [ -n "$BRoverride" ]; then echo "<default>true</default>"; fi)"'
                                        </checkbox>
                                        <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check in gentoo">
                                                <variable>BC_GENKERNEL</variable>
                                                '"$(if [ -n "$BRgenkernel" ]; then echo "<default>true</default>"; fi)"'
                                        </checkbox>
                                </vbox>
                        </vbox>
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="25" wrap="false" tooltip-text="==>In the first case, you should use a LiveCD of the
       backed up distro

==>A target root partition is required. Optionally you
       can use any other partition for /boot /home
       esp swap or custom mountpoints

==>If you plan to transfer in lvm/mdadm/luks,
       configure this system accordingly"><label>"Restore a backup archive or transfer this system in user defined partitions"</label></text>
                                <hseparator></hseparator>
                                <vbox>
                                        <frame Target partitions:>
                                                <hbox>
                                                        <text width-request="55" space-expand="false" label="Root:"></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target root partition">
	                                                        <variable>RT_ROOT</variable>
                                                                <input>echo "$RT_ROOT"</input>
	                                                        <input>echo "$RT_PARTS" | grep -vw -e "/${RT_ROOT#*/}" -e "/${RT_ESP#*/}" -e "/${RT_BOOT#*/}" -e "/${RT_HOME#*/}" -e "/${RT_SWAP#*/}"</input>
                                                                <action>refresh:RT_ESP</action>
                                                                <action>refresh:RT_BOOT</action>
                                                                <action>refresh:RT_HOME</action>
                                                                <action>refresh:RT_SWAP</action>
			                                </comboboxtext>
                                                        <entry tooltip-text="Set comma-separated list of mount options. Default options: defaults,noatime">
                                                                <variable>RT_ROOT_OPTIONS</variable>
                                                        </entry>
                                                        <checkbox label="Clean" tooltip-text="Clean the target root partition if it is not empty">
                                                                <variable>RT_ROOT_CLEAN</variable>
                                                        </checkbox>
                                                </hbox>
                                                <expander label="More partitions">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Esp:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional-UEFI only) Select target EFI System Partition">
	                                                                        <variable>RT_ESP</variable>
                                                                                <input>echo "$RT_ESP"</input>
	                                                                        <input>echo "$RT_PARTS" | grep -vw -e "/${RT_ROOT#*/}" -e "/${RT_ESP#*/}" -e "/${RT_BOOT#*/}" -e "/${RT_HOME#*/}" -e "/${RT_SWAP#*/}"</input>
                                                                                <input>if [ -n "$RT_ESP" ]; then echo ""; fi</input>
                                                                                <action>refresh:RT_ROOT</action>
                                                                                <action>refresh:RT_BOOT</action>
                                                                                <action>refresh:RT_HOME</action>
                                                                                <action>refresh:RT_SWAP</action>
			                                                </comboboxtext>
                                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select mountpoint">
	                                                                        <variable>RT_ESP_MOUNTPOINT</variable>
	                                                                        <item>/boot/efi</item>
	                                                                        <item>/boot</item>
	                                                                </comboboxtext>
                                                                        <checkbox label="Clean" tooltip-text="Clean the target esp partition if it is not empty">
                                                                                <variable>RT_ESP_CLEAN</variable>
                                                                        </checkbox>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/boot:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                                        <variable>RT_BOOT</variable>
                                                                                <input>echo "$RT_BOOT"</input>
	                                                                        <input>echo "$RT_PARTS" | grep -vw -e "/${RT_ROOT#*/}" -e "/${RT_ESP#*/}" -e "/${RT_BOOT#*/}" -e "/${RT_HOME#*/}" -e "/${RT_SWAP#*/}"</input>
                                                                                <input>if [ -n "$RT_BOOT" ]; then echo ""; fi</input>
                                                                                <action>refresh:RT_ROOT</action>
                                                                                <action>refresh:RT_ESP</action>
                                                                                <action>refresh:RT_HOME</action>
                                                                                <action>refresh:RT_SWAP</action>
			                                                </comboboxtext>
                                                                        <checkbox label="Clean" tooltip-text="Clean the target /boot partition if it is not empty">
                                                                                <variable>RT_BOOT_CLEAN</variable>
                                                                        </checkbox>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/home:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                                        <variable>RT_HOME</variable>
                                                                                <input>echo "$RT_HOME"</input>
	                                                                        <input>echo "$RT_PARTS" | grep -vw -e "/${RT_ROOT#*/}" -e "/${RT_ESP#*/}" -e "/${RT_BOOT#*/}" -e "/${RT_HOME#*/}" -e "/${RT_SWAP#*/}"</input>
                                                                                <input>if [ -n "$RT_HOME" ]; then echo ""; fi</input>
                                                                                <action>refresh:RT_ROOT</action>
                                                                                <action>refresh:RT_ESP</action>
                                                                                <action>refresh:RT_BOOT</action>
                                                                                <action>refresh:RT_SWAP</action>
                                                                        </comboboxtext>
                                                                        <checkbox label="Clean" tooltip-text="Clean the target /home partition if it is not empty">
                                                                                <variable>RT_HOME_CLEAN</variable>
                                                                        </checkbox>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Swap:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                                        <variable>RT_SWAP</variable>
                                                                                <input>echo "$RT_SWAP"</input>
	                                                                        <input>echo "$RT_PARTS" | grep -vw -e "/${RT_ROOT#*/}" -e "/${RT_ESP#*/}" -e "/${RT_BOOT#*/}" -e "/${RT_HOME#*/}" -e "/${RT_SWAP#*/}"</input>
                                                                                <input>if [ -n "$RT_SWAP" ]; then echo ""; fi</input>
                                                                                <action>refresh:RT_ROOT</action>
                                                                                <action>refresh:RT_ESP</action>
                                                                                <action>refresh:RT_BOOT</action>
                                                                                <action>refresh:RT_HOME</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other partitions. Syntax is mountpoint=partition

e.g /var=/dev/sda3 or /var=/dev/sda3@ if it is not empty and you want to clean it.

If you want spaces in mountpoints replace them with //">
                                                                                <variable>RT_OTHER_PARTS</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                                <expander label="Btrfs subvolumes">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Root:"></text>
                                                                        <entry tooltip-text="Set subvolume name for /">
                                                                                <variable>RT_ROOT_SUBVOL</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                                                <variable>RT_OTHER_SUBVOLS</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                        </frame>
                                </vbox>
                                <vbox>
                                        <frame Bootloader:>
                                                <hbox>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select bootloader">
                                                                <variable>RT_BOOTLOADER</variable>
                                                                <item>none</item>
	                                                        <item>Grub</item>
	                                                        <item>Grub-efi</item>
	                                                        <item>Syslinux</item>
	                                                        <item>EFISTUB/efibootmgr</item>
	                                                        <item>Systemd/bootctl</item>
                                                                <action condition="command_is_true([ $RT_BOOTLOADER = none ] && echo true)">disable:RT_BOOTLOADER_DEVICE</action>
                                                                <action condition="command_is_true([ ! $RT_BOOTLOADER = none ] && echo true)">enable:RT_BOOTLOADER_DEVICE</action>
                                                                <action condition="command_is_true([ $RT_BOOTLOADER = none ] && echo true)">disable:RT_KERNEL_OPTIONS</action>
                                                                <action condition="command_is_true([ ! $RT_BOOTLOADER = none ] && echo true)">enable:RT_KERNEL_OPTIONS</action>
                                                                <action condition="command_is_true([ $RT_BOOTLOADER = EFISTUB/efibootmgr ] && echo true)">disable:RT_BOOTLOADER_DEVICE</action>
                                                                <action condition="command_is_true([ $RT_BOOTLOADER = Systemd/bootctl ] && echo true)">disable:RT_BOOTLOADER_DEVICE</action>
                                                                <action condition="command_is_true([ $RT_BOOTLOADER = Grub-efi ] && echo true)">disable:RT_BOOTLOADER_DEVICE</action>
                                                        </comboboxtext>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target device" sensitive="false">
	                                                        <variable>RT_BOOTLOADER_DEVICE</variable>
	                                                        <input>echo "$RT_DISKS"</input>
	                                                </comboboxtext>
                                                        <entry tooltip-text="Set additional kernel options" sensitive="false">
                                                                <variable>RT_KERNEL_OPTIONS</variable>
                                                        </entry>
                                                </hbox>
                                        </frame>
                                </vbox>
                                <notebook labels="Restore Mode|Transfer Mode">
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Backup archive:"></text>
                                                        <entry fs-action="file" tooltip-text="Choose a local backup archive or enter URL" fs-title="Select a backup archive">
                                                                <variable>RS_ARCHIVE</variable>
                                                        </entry>
                                                        <button tooltip-text="Select backup archive">
                                                                <input file stock="gtk-open"></input>
                                                                <action>fileselect:RS_ARCHIVE</action>
                                                        </button>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                                        <entry tooltip-text="Set passphrase for decryption" visibility="false">
                                                                <variable>RS_PASSPHRASE</variable>
                                                        </entry>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //

Default options:
--acls
--xattrs
--selinux (Fedora)
--xattrs-include='\''*'\'' (Fedora)">
                                                                <variable>RS_OPTIONS</variable>
                                                        </entry>
                                                </hbox>
                                                <expander label="Server authentication">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Username:"></text>
                                                                        <entry tooltip-text="Set ftp/http username">
                                                                                <variable>RS_USERNAME</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Password:"></text>
                                                                        <entry tooltip-text="Set ftp/http password" visibility="false">
                                                                                <variable>RS_PASSWORD</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                        </vbox>
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                                <variable>TS_HOME</variable>
                                                                <item>Include</item>
	                                                        <item>Only hidden files and folders</item>
	                                                        <item>Exclude</item>
                                                        </comboboxtext>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Set extra rsync options. See rsync --help for more info. If you want spaces in names replace them with //">
                                                                <variable>TS_OPTIONS</variable>
                                                        </entry>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Exclude:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Exclude files and directories. If you want spaces in names replace them with //

Excluded by default:
/run/*
/dev/*
/sys/*
/tmp/*
/mnt/*
/proc/*
/media/*
/var/run/*
/var/lock/*
/home/*/.gvfs
lost+found">
                                                                <variable>TS_EXCLUDE</variable>
                                                        </entry>
                                                </hbox>
                                        </vbox>
                                        <variable>RT_TAB</variable>
                                </notebook>
                                <vbox>
                                        <hseparator></hseparator>
                                        <checkbox label="Override options" tooltip-text="Override the default tar/rsync options/excludes with user defined ones">
                                                <variable>RT_OVERRIDE</variable>
                                        </checkbox>
                                        <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                                <variable>RT_GENKERNEL</variable>
                                        </checkbox>
                                        <checkbox label="Dont check root" tooltip-text="Dont check if the target root partition is empty (dangerous)">
                                                <variable>RT_CHECK_ROOT</variable>
                                        </checkbox>
                                        <checkbox label="Bios" tooltip-text="Ignore UEFI environment">
                                                <variable>RT_BIOS</variable>
                                        </checkbox>
                                </vbox>
			</vbox>
                        <vbox scrollable="true" shadow-type="0">
                                <edit xalign="0" wrap="false" auto-refresh="true" editable="no">
                                        <input file>/tmp/wr_log</input>
                                </edit>
                        </vbox>
                        <vbox>
                                <text use-markup="true" label="<b><big>System Tar &amp; Restore</big></b>"></text>
                                <text wrap="false" label="Backup and Restore your system using tar or Transfer it with rsync"></text>
                                <text use-markup="true" label="<i><small>Version 6.7 tritonas00@gmail.com 2012-2017</small></i>"></text>
                                <hseparator></hseparator>
                                <vbox scrollable="true" shadow-type="0">
                                        <text xalign="0" wrap="false">
				                <input>if [ -f "$BRchangelog" ]; then cat "$BRchangelog"; else echo "Changelog file not found"; fi</input>
                                        </text>
                                </vbox>
                                <hseparator></hseparator>
                                <checkbox label="Debug" tooltip-text="Show the generated command instead of run it">
                                        <variable>BR_DEBUG</variable>
                                        <action> if true echo "$BRtitle (debug)" > /tmp/wr_proc</action>
                                        <action> if false echo "$BRtitle" > /tmp/wr_proc</action>
                                </checkbox>
                        </vbox>
                        <variable>BR_TAB</variable>
                        <input>echo 2</input>
		</notebook>
                <hbox space-expand="false" space-fill="false">
                        <button tooltip-text="Run">
                                <input file stock="gtk-ok"></input>
                                <label>Run</label>
                                <variable>BTN_RUN</variable>
                                <action>bash -c "source /tmp/wr_functions; set_args && run_main &"</action>
                        </button>
                        <button tooltip-text="Kill the process" sensitive="false">
                                <input file stock="gtk-stop"></input>
                                <variable>BTN_CANCEL</variable>
                                <label>Cancel</label>
                                <action>kill -9 -$(tail -1 /tmp/wr_pid)</action>
                                <action>echo "PID $(tail -1 /tmp/wr_pid) Killed" > /tmp/wr_log</action>
                        </button>
                        <button tooltip-text="Exit">
                                <variable>BTN_EXIT</variable>
                                <input file stock="gtk-close"></input>
                                <label>Exit</label>
                        </button>
                </hbox>
        </vbox>
	<variable>WND_TITLE</variable>
	<input file>/tmp/wr_proc</input>
</window>
'
exec 3>&1
gtkdialog --program=MAIN_DIALOG > /dev/null

clean_tmp_files
