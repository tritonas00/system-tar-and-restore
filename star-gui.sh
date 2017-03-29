#!/bin/bash

if [ -z "$(which gtkdialog 2>/dev/null)" ]; then
  echo "Package gtkdialog is not installed. Install the package and re-run the script"
  exit
fi

cd "$(dirname "$0")"

clean_tmp_files() {
  if [ -f /tmp/wr_proc ]; then rm /tmp/wr_proc; fi
  if [ -f /tmp/wr_upt ]; then rm /tmp/wr_upt; fi
  if [ -f /tmp/wr_log ]; then rm /tmp/wr_log; fi
  if [ -f /tmp/wr_pid ]; then rm /tmp/wr_pid; fi
  if [ -f /tmp/wr_functions ]; then rm /tmp/wr_functions; fi
}

clean_tmp_files

export BR_TITLE="System Tar & Restore"

echo -n > /tmp/wr_log
echo true > /tmp/wr_upt
echo "$BR_TITLE" > /tmp/wr_proc

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
  export ENTRY1="$BRNAME"
else
  export ENTRY1="Backup-$(hostname)-$(date +%Y-%m-%d-%T)"
fi

if [ -n "$BRFOLDER" ]; then
  export ENTRY2="$BRFOLDER"
else
  export ENTRY2="/"
fi

if [ -n "$BRtopdir" ]; then
  export ENTRY44="$BRtopdir"
else
  export ENTRY44="/"
fi

if [ -n "$BRonlyhidden" ] && [ -n "$BRnohome" ]; then
  echo "Error parsing configuration file. Choose only one option for the /home directory"
  exit
elif [ -n "$BRonlyhidden" ]; then
  export ENTRY3="Only hidden files and folders"
elif [ -n "$BRnohome" ]; then
  export ENTRY3="Exclude"
else
  export ENTRY3="Include"
fi

if [ -n "$BRcompression" ]; then
  export ENTRY4="$BRcompression"
else
  export ENTRY4="gzip"
fi

if [ -n "$BRencmethod" ]; then
  export ENTRY5="$BRencmethod"
else
  export ENTRY5="none"
fi

# Set user tar options if given from configuration file, separate entries
if [ -n "$BR_USER_OPTS" ]; then
  for opt in $BR_USER_OPTS; do
    if [[ "$opt" == --exclude=* ]]; then
      export ENTRY8="$(echo "$opt" | cut -f2 -d"=") $ENTRY8"
    elif [[ "$opt" == -* ]]; then
      export ENTRY7="$opt $ENTRY7"
    fi
  done
fi

# Store needed functions to a temporary file so we can source it inside gtkdialog
# This ensures compatibility with Ubuntu 16.04 and variants
echo '
set_args() {
  if [ "$BR_TAB" = "0" ]; then
    SCR_ARGS=(-i 0 -jwq)
  elif [ "$RT_TAB" = "0" ]; then
    SCR_ARGS=(-i 1 -jwq)
  elif [ "$RT_TAB" = "1" ]; then
    SCR_ARGS=(-i 2 -jwq)
  fi

  if [ "$BR_TAB" = "0" ]; then
    SCR_ARGS+=(-d "$ENTRY2" -c "$ENTRY4")

    if [ -n "$ENTRY1" ] && [[ ! "$ENTRY1" == Backup-$(hostname)-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
      SCR_ARGS+=(-n "$ENTRY1")
    fi

    if [ ! "$ENTRY44" = "/" ]; then SCR_ARGS+=(-T "$ENTRY44"); fi

    if [ "$ENTRY3" = "Only hidden files and folders" ]; then
      SCR_ARGS+=(-O)
    elif [ "$ENTRY3" = "Exclude" ]; then
      SCR_ARGS+=(-H)
    fi

    if [ ! "$ENTRY5" = "none" ]; then SCR_ARGS+=(-E "$ENTRY5" -P "$ENTRY6"); fi
    set -f
    for i in $ENTRY8; do ENTRY7="$ENTRY7 --exclude=$i"; done
    set +f
    if [ -n "$ENTRY7" ]; then SCR_ARGS+=(-u "$ENTRY7"); fi

    if [ "$ENTRY9" = "true" ] && [ ! "$ENTRY4" = "none" ]; then
      SCR_ARGS+=(-M)
      if [ ! "$ENTRY43" = "0" ]; then SCR_ARGS+=(-z "$ENTRY43"); fi
    fi

    if [ "$ENTRY10" = "true" ]; then SCR_ARGS+=(-g); fi
    if [ "$ENTRY11" = "true" ]; then SCR_ARGS+=(-a); fi
    if [ "$ENTRY12" = "true" ]; then SCR_ARGS+=(-o); fi
    if [ "$ENTRY13" = "true" ]; then SCR_ARGS+=(-D); fi

  elif [ "$BR_TAB" = "1" ]; then
    if [ "$ENTRY16" = "true" ]; then
      SCR_ARGS+=(-r "${ENTRY14%% *}"@)
    else
      SCR_ARGS+=(-r "${ENTRY14%% *}")
    fi
    if [ -n "$ENTRY15" ]; then SCR_ARGS+=(-m "$ENTRY15"); fi

    if [ ! "$ENTRY17" = "" ] && [ "$ENTRY19" = "true" ]; then
      SCR_ARGS+=(-e "${ENTRY17%% *}"@ -l "$ENTRY18")
    elif [ ! "$ENTRY17" = "" ]; then
      SCR_ARGS+=(-e "${ENTRY17%% *}" -l "$ENTRY18")
    fi

    if [ ! "$ENTRY20" = "" ] && [ "$ENTRY21" = "true" ]; then
      SCR_ARGS+=(-b "${ENTRY20%% *}"@)
    elif [ ! "$ENTRY20" = "" ]; then
      SCR_ARGS+=(-b "${ENTRY20%% *}")
    fi

    if [ ! "$ENTRY22" = "" ] && [ "$ENTRY23" = "true" ]; then
      SCR_ARGS+=(-h "${ENTRY22%% *}"@)
    elif [ ! "$ENTRY22" = "" ]; then
      SCR_ARGS+=(-h "${ENTRY22%% *}")
    fi

    if [ ! "$ENTRY24" = "" ]; then SCR_ARGS+=(-s "${ENTRY24%% *}"); fi
    if [ -n "$ENTRY25" ]; then SCR_ARGS+=(-t "$ENTRY25"); fi
    if [ -n "$ENTRY26" ]; then SCR_ARGS+=(-R "$ENTRY26"); fi
    if [ -n "$ENTRY27" ]; then SCR_ARGS+=(-B "$ENTRY27"); fi

    if [ "$ENTRY28" = "Grub" ]; then
      SCR_ARGS+=(-G "${ENTRY29%% *}")
    elif [ "$ENTRY28" = "Grub-efi" ]; then
      SCR_ARGS+=(-G auto)
    elif [ "$ENTRY28" = "Syslinux" ]; then
      SCR_ARGS+=(-S "${ENTRY29%% *}")
    elif [ "$ENTRY28" = "EFISTUB/efibootmgr" ]; then
      SCR_ARGS+=(-F)
    elif [ "$ENTRY28" = "Systemd/bootctl" ]; then
      SCR_ARGS+=(-L)
    fi

    if [ ! "$ENTRY28" = "none" ] && [ -n "$ENTRY30" ]; then SCR_ARGS+=(-k "$ENTRY30"); fi

    if [ "$RT_TAB" = "0" ]; then
      SCR_ARGS+=(-f "$ENTRY31")
      if [ -n "$ENTRY32" ]; then SCR_ARGS+=(-P "$ENTRY32"); fi
      if [ -n "$ENTRY33" ]; then SCR_ARGS+=(-u "$ENTRY33"); fi
      if [ -n "$ENTRY34" ]; then SCR_ARGS+=(-y "$ENTRY34"); fi
      if [ -n "$ENTRY35" ]; then SCR_ARGS+=(-p "$ENTRY35"); fi
    elif [ "$RT_TAB" = "1" ]; then
      if [ "$ENTRY36" = "Only hidden files and folders" ]; then
        SCR_ARGS+=(-O)
      elif [ "$ENTRY36" = "Exclude" ]; then
        SCR_ARGS+=(-H)
      fi
      set -f
      for i in $ENTRY38; do ENTRY37="$ENTRY37 --exclude=$i"; done
      set +f
      if [ -n "$ENTRY37" ]; then SCR_ARGS+=(-u "$ENTRY37"); fi
    fi

    if [ "$ENTRY39" = "true" ]; then SCR_ARGS+=(-o); fi
    if [ "$ENTRY40" = "true" ]; then SCR_ARGS+=(-D); fi
    if [ "$ENTRY41" = "true" ]; then SCR_ARGS+=(-x); fi
    if [ "$ENTRY42" = "true" ]; then SCR_ARGS+=(-W); fi
  fi
}

run_main() {
  if [ "$BR_TAB" = "0" ] || [ "$BR_TAB" = "1" ]; then
    if [ "$BR_DEBUG" = "true" ]; then
      echo star.sh "${SCR_ARGS[@]}" > /tmp/wr_proc
    else
      echo false > /tmp/wr_upt
      setsid ./star.sh "${SCR_ARGS[@]}" >&3 2> /tmp/wr_log
      sleep 0.1
      echo "$BR_TITLE" > /tmp/wr_proc
      echo true > /tmp/wr_upt
    fi
  fi
}
' > /tmp/wr_functions

# Scan normal partitions, lvm, md arrays, sd card partitions and devices, initialize target root partition
export BR_PARTS="$(for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done | sort
                   for f in $(find /dev/mapper/ -maxdepth 1 -mindepth 1 ! -name "control"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                   for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                   for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                   for f in $(find /dev -regex "/dev/nvme[0-9]+n[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done)"

export BR_DISKS="$(for f in /dev/[vhs]d[a-z]; do echo "$f $(lsblk -d -n -o size $f)"; done
                   for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f)"; done
                   for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done
                   for f in $(find /dev -regex "/dev/nvme[0-9]+n[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done)"

export ENTRY14="$(echo "$BR_PARTS" | head -n 1)"

export MAIN_DIALOG='
<window icon-name="gtk-preferences" height-request="645" width-request="515">
        <vbox>
                <checkbox visible="false" auto-refresh="true">
                        <input file>/tmp/wr_upt</input>
                        <action condition="file_is_true(/tmp/wr_upt)">enable:BTN_RUN</action>
                        <action condition="file_is_true(/tmp/wr_upt)">enable:BTN_EXIT</action>
                        <action condition="file_is_true(/tmp/wr_upt)">enable:BR_TAB</action>
                        <action condition="file_is_true(/tmp/wr_upt)">disable:BTN_CANCEL</action>
                        <action condition="file_is_true(/tmp/wr_upt)">refresh:BR_TAB</action>
                        <action condition="file_is_false(/tmp/wr_upt)">disable:BTN_RUN</action>
                        <action condition="file_is_false(/tmp/wr_upt)">disable:BTN_EXIT</action>
                        <action condition="file_is_false(/tmp/wr_upt)">enable:BTN_CANCEL</action>
                </checkbox>
                <entry visible="false" auto-refresh="true">
                        <input file>/tmp/wr_proc</input>
                        <action>refresh:BR_WND</action>
                        <action condition="file_is_false(/tmp/wr_upt)">disable:BR_TAB</action>
                </entry>
                <notebook labels="Backup|Restore/Transfer|Log|About" space-expand="true" space-fill="true">
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="35" tooltip-text="==>Make sure destination has enough space

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
                                        <entry text="'"$ENTRY1"'" tooltip-text="Set backup archive name">
                                                <variable>ENTRY1</variable>
                                        </entry>
                                </hbox>

                                <hbox>
                                        <text width-request="135" label="Destination:"></text>
                                        <entry text="'"$ENTRY2"'" fs-action="folder" fs-title="Select a directory" tooltip-text="Choose where to save the backup archive">
                                                <variable>ENTRY2</variable>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:ENTRY2</action>
                                        </button>
                                </hbox>

                                <hbox>
                                        <text width-request="135" label="Source:"></text>
                                        <entry text="'"$ENTRY44"'" fs-action="folder" fs-title="Select a directory" tooltip-text="Choose an alternative source directory to create a non-system backup archive">
                                                <variable>ENTRY44</variable>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:ENTRY44</action>
                                        </button>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                <variable>ENTRY3</variable>
                                                <default>'"$ENTRY3"'</default>
                                                <item>Include</item>
	                                        <item>Only hidden files and folders</item>
	                                        <item>Exclude</item>
                                        </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Compression:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select compressor">
	                                        <variable>ENTRY4</variable>
                                                <default>'"$ENTRY4"'</default>
	                                        <item>gzip</item>
	                                        <item>bzip2</item>
	                                        <item>xz</item>
                                                <item>none</item>
                                                <action condition="command_is_true([ $ENTRY4 = none ] && echo true)">disable:ENTRY9</action>
                                                <action condition="command_is_true([ ! $ENTRY4 = none ] && echo true)">enable:ENTRY9</action>
	                                </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Encryption:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select encryption method">
	                                        <variable>ENTRY5</variable>
                                                <default>'"$ENTRY5"'</default>
                                                <item>none</item>
	                                        <item>openssl</item>
	                                        <item>gpg</item>
                                                <action condition="command_is_true([ $ENTRY5 = none ] && echo true)">disable:ENTRY6</action>
                                                <action condition="command_is_true([ ! $ENTRY5 = none ] && echo true)">enable:ENTRY6</action>
                                        </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                        <entry visibility="false" tooltip-text="Set passphrase for encryption">
                                                '"$(if [ "$ENTRY5" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                <variable>ENTRY6</variable>
                                                '"$(if [ -n "$BRencpass" ]; then echo "<default>$BRencpass</default>"; fi)"'
                                        </entry>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                        <entry text="'"$ENTRY7"'" space-expand="true" space-fill="true" tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //

Default options:
--sparse
--acls
--xattrs
--selinux (Fedora)">
                                                <variable>ENTRY7</variable>
                                        </entry>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Exclude:"></text>
                                        <entry text="'"$ENTRY8"'" space-expand="true" space-fill="true" tooltip-text="Exclude files and directories. If you want spaces in names replace them with //

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
                                                <variable>ENTRY8</variable>
                                        </entry>
                                </hbox>

                                <vbox>
                                        <frame Misc options:>
                                                <hbox>
                                                        <checkbox space-expand="true" label="Enable multi-core compression" tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz">
                                                                '"$(if [ "$ENTRY4" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                                <variable>ENTRY9</variable>
                                                                '"$(if [ -n "$BRmcore" ]; then echo "<default>true</default>"; fi)"'
                                                        </checkbox>

                                                        <text space-fill="true" label="Number of threads:"></text>
                                                        <spinbutton range-max="'"$(nproc --all)"'" tooltip-text="Specify the number of threads for multi-core compression (max = 0)">
	                                                        <variable>ENTRY43</variable>
                                                                '"$(if [ -n "$BRmcore" ] && [ -n "$BRthreads" ]; then echo "<default>$BRthreads</default>"; fi)"'
                                                        </spinbutton>
                                                </hbox>

                                                <checkbox label="Generate backup.conf" tooltip-text="Generate configuration file in case of successful backup">
                                                        <variable>ENTRY10</variable>
                                                </checkbox>

                                                <checkbox label="Remove older backups" tooltip-text="Remove older backups in the destination directory">
                                                        <variable>ENTRY11</variable>
                                                        '"$(if [ -n "$BRclean" ]; then echo "<default>true</default>"; fi)"'
                                                </checkbox>

                                                <checkbox label="Override" tooltip-text="Override the default tar options/excludes with user defined ones">
                                                        <variable>ENTRY12</variable>
                                                        '"$(if [ -n "$BRoverride" ]; then echo "<default>true</default>"; fi)"'
                                                </checkbox>

                                                <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check in gentoo">
                                                        <variable>ENTRY13</variable>
                                                        '"$(if [ -n "$BRgenkernel" ]; then echo "<default>true</default>"; fi)"'
                                                </checkbox>
                                        </frame>
                                </vbox>
                        </vbox>

                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="35" wrap="false" tooltip-text="==>In the first case, you should use a LiveCD of the
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
	                                                        <variable>ENTRY14</variable>
                                                                <input>echo "$ENTRY14"</input>
	                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY17#*/}" -e "/${ENTRY20#*/}" -e "/${ENTRY22#*/}" -e "/${ENTRY24#*/}"</input>
                                                                <action>refresh:ENTRY17</action>
                                                                <action>refresh:ENTRY20</action>
                                                                <action>refresh:ENTRY22</action>
                                                                <action>refresh:ENTRY24</action>
			                                </comboboxtext>
                                                        <entry tooltip-text="Set comma-separated list of mount options. Default options: defaults,noatime">
                                                                <variable>ENTRY15</variable>
                                                        </entry>
                                                        <checkbox label="Clean" tooltip-text="Clean the target root partition if it is not empty">
                                                                <variable>ENTRY16</variable>
                                                        </checkbox>
                                                </hbox>

                                                <expander label="More partitions">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Esp:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional-UEFI only) Select target EFI System Partition">
	                                                                        <variable>ENTRY17</variable>
                                                                                <input>echo "$ENTRY17"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY17#*/}" -e "/${ENTRY20#*/}" -e "/${ENTRY22#*/}" -e "/${ENTRY24#*/}"</input>
                                                                                <input>if [ -n "$ENTRY17" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY20</action>
                                                                                <action>refresh:ENTRY22</action>
                                                                                <action>refresh:ENTRY24</action>
			                                                </comboboxtext>
                                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select mountpoint">
	                                                                        <variable>ENTRY18</variable>
	                                                                        <item>/boot/efi</item>
	                                                                        <item>/boot</item>
	                                                                </comboboxtext>
                                                                        <checkbox label="Clean" tooltip-text="Clean the target esp partition if it is not empty">
                                                                                <variable>ENTRY19</variable>
                                                                        </checkbox>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/boot:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                                        <variable>ENTRY20</variable>
                                                                                <input>echo "$ENTRY20"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY17#*/}" -e "/${ENTRY20#*/}" -e "/${ENTRY22#*/}" -e "/${ENTRY24#*/}"</input>
                                                                                <input>if [ -n "$ENTRY20" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY17</action>
                                                                                <action>refresh:ENTRY22</action>
                                                                                <action>refresh:ENTRY24</action>
			                                                </comboboxtext>
                                                                        <checkbox label="Clean" tooltip-text="Clean the target /boot partition if it is not empty">
                                                                                <variable>ENTRY21</variable>
                                                                        </checkbox>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/home:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                                        <variable>ENTRY22</variable>
                                                                                <input>echo "$ENTRY22"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY17#*/}" -e "/${ENTRY20#*/}" -e "/${ENTRY22#*/}" -e "/${ENTRY24#*/}"</input>
                                                                                <input>if [ -n "$ENTRY22" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY17</action>
                                                                                <action>refresh:ENTRY20</action>
                                                                                <action>refresh:ENTRY24</action>
                                                                        </comboboxtext>
                                                                        <checkbox label="Clean" tooltip-text="Clean the target /home partition if it is not empty">
                                                                                <variable>ENTRY23</variable>
                                                                        </checkbox>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Swap:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                                        <variable>ENTRY24</variable>
                                                                                <input>echo "$ENTRY24"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY17#*/}" -e "/${ENTRY20#*/}" -e "/${ENTRY22#*/}" -e "/${ENTRY24#*/}"</input>
                                                                                <input>if [ -n "$ENTRY24" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY17</action>
                                                                                <action>refresh:ENTRY20</action>
                                                                                <action>refresh:ENTRY22</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other partitions. Syntax is mountpoint=partition

e.g /var=/dev/sda3 or /var=/dev/sda3@ if it is not empty and you want to clean it.

If you want spaces in mountpoints replace them with //">
                                                                                <variable>ENTRY25</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                                <expander label="Btrfs subvolumes">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Root:"></text>
                                                                        <entry tooltip-text="Set subvolume name for /">
                                                                                <variable>ENTRY26</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                                                <variable>ENTRY27</variable>
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
                                                                <variable>ENTRY28</variable>
                                                                <item>none</item>
	                                                        <item>Grub</item>
	                                                        <item>Grub-efi</item>
	                                                        <item>Syslinux</item>
	                                                        <item>EFISTUB/efibootmgr</item>
	                                                        <item>Systemd/bootctl</item>
                                                                <action condition="command_is_true([ $ENTRY28 = none ] && echo true)">disable:ENTRY29</action>
                                                                <action condition="command_is_true([ ! $ENTRY28 = none ] && echo true)">enable:ENTRY29</action>
                                                                <action condition="command_is_true([ $ENTRY28 = none ] && echo true)">disable:ENTRY30</action>
                                                                <action condition="command_is_true([ ! $ENTRY28 = none ] && echo true)">enable:ENTRY30</action>
                                                                <action condition="command_is_true([ $ENTRY28 = EFISTUB/efibootmgr ] && echo true)">disable:ENTRY29</action>
                                                                <action condition="command_is_true([ $ENTRY28 = Systemd/bootctl ] && echo true)">disable:ENTRY29</action>
                                                                <action condition="command_is_true([ $ENTRY28 = Grub-efi ] && echo true)">disable:ENTRY29</action>
                                                        </comboboxtext>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target device" sensitive="false">
	                                                        <variable>ENTRY29</variable>
	                                                        <input>echo "$BR_DISKS"</input>
	                                                </comboboxtext>
                                                        <entry tooltip-text="Set additional kernel options" sensitive="false">
                                                                <variable>ENTRY30</variable>
                                                        </entry>
                                                </hbox>
                                        </frame>
                                </vbox>

                                <notebook labels="Restore Mode|Transfer Mode">
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Backup archive:"></text>
                                                        <entry fs-action="file" tooltip-text="Choose a local backup archive or enter URL" fs-title="Select a backup archive">
                                                                <variable>ENTRY31</variable>
                                                        </entry>
                                                        <button tooltip-text="Select backup archive">
                                                                <input file stock="gtk-open"></input>
                                                                <action>fileselect:ENTRY31</action>
                                                        </button>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                                        <entry tooltip-text="Set passphrase for decryption" visibility="false">
                                                                <variable>ENTRY32</variable>
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
                                                                <variable>ENTRY33</variable>
                                                        </entry>
                                                </hbox>
                                                <expander label="Server authentication">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Username:"></text>
                                                                        <entry tooltip-text="Set ftp/http username">
                                                                                <variable>ENTRY34</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Password:"></text>
                                                                        <entry tooltip-text="Set ftp/http password" visibility="false">
                                                                                <variable>ENTRY35</variable>
                                                                        </entry>
                                                                </hbox>

                                                        </vbox>
                                                </expander>
                                        </vbox>
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                                <variable>ENTRY36</variable>
                                                                <item>Include</item>
	                                                        <item>Only hidden files and folders</item>
	                                                        <item>Exclude</item>
                                                        </comboboxtext>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Set extra rsync options. See rsync --help for more info. If you want spaces in names replace them with //">
                                                                <variable>ENTRY37</variable>
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
                                                                <variable>ENTRY38</variable>
                                                        </entry>
                                                </hbox>
                                        </vbox>
                                        <variable>RT_TAB</variable>
                                </notebook>

                                <vbox>
                                        <frame Misc options:>
                                                <checkbox label="Override" tooltip-text="Override the default tar/rsync options/excludes with user defined ones">
                                                        <variable>ENTRY39</variable>
                                                </checkbox>

                                                <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                                        <variable>ENTRY40</variable>
                                                </checkbox>

                                                <checkbox label="Dont check root" tooltip-text="Dont check if the target root partition is empty (dangerous)">
                                                        <variable>ENTRY41</variable>
                                                </checkbox>

                                                <checkbox label="Bios" tooltip-text="Ignore UEFI environment">
                                                        <variable>ENTRY42</variable>
                                                </checkbox>
                                        </frame>
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
                                <text use-markup="true" label="<i><small>Version 6.6 tritonas00@gmail.com 2012-2017</small></i>"></text>
                                <hseparator></hseparator>
                                <vbox scrollable="true" shadow-type="0">
                                        <text xalign="0" wrap="false">
				                <input>if [ -f "$BRchangelog" ]; then cat "$BRchangelog"; else echo "Changelog file not found"; fi</input>
                                        </text>
                                </vbox>
                                <hseparator></hseparator>
                                <checkbox label="Debug" tooltip-text="Show the generated command instead of run it">
                                        <variable>BR_DEBUG</variable>
                                        <action> if true echo "$BR_TITLE (debug)" > /tmp/wr_proc</action>
                                        <action> if false echo "$BR_TITLE" > /tmp/wr_proc</action>
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
                                <action>kill -9 -$(cat /tmp/wr_pid)</action>
                                <action>echo "PID $(cat /tmp/wr_pid) Killed" > /tmp/wr_log</action>
                        </button>
                        <button tooltip-text="Exit">
                                <variable>BTN_EXIT</variable>
                                <input file stock="gtk-close"></input>
                                <label>Exit</label>
                        </button>
                </hbox>
        </vbox>
	<variable>BR_WND</variable>
	<input file>/tmp/wr_proc</input>
</window>
'
exec 3>&1
gtkdialog --program=MAIN_DIALOG > /dev/null

clean_tmp_files
