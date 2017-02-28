#!/bin/bash

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

# Export given vars from configuration file, set defaults if not given
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

if [ -n "$BRonlyhidden" ]; then
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

if [ -n "$BRencpass" ]; then
  export ENTRY6="$BRencpass"
fi

if [ -n "$BR_USER_OPTS" ]; then
  for opt in $BR_USER_OPTS; do
    if [[ "$opt" == --exclude=* ]]; then
      export ENTRY8="$(echo "$opt" | cut -f2 -d"=") $ENTRY8"
    elif [[ "$opt" == -* ]]; then
      export ENTRY7="$opt $ENTRY7"
    fi
  done
fi

if [ -n "$BRmcore" ]; then
  export ENTRY9="true"
else
  export ENTRY9="false"
fi

if [ -n "$BRclean" ]; then
  export ENTRY11="true"
else
  export ENTRY11="false"
fi

if [ -n "$BRoverride" ]; then
  export ENTRY12="true"
else
  export ENTRY12="false"
fi

if [ -n "$BRgenkernel" ]; then
  export ENTRY13="true"
else
  export ENTRY13="false"
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

    if [ "$ENTRY9" = "true" ] && [ ! "$ENTRY4" = "none" ]; then SCR_ARGS+=(-M); fi
    if [ "$ENTRY10" = "true" ]; then SCR_ARGS+=(-g); fi
    if [ "$ENTRY11" = "true" ]; then SCR_ARGS+=(-a); fi
    if [ "$ENTRY12" = "true" ]; then SCR_ARGS+=(-o); fi
    if [ "$ENTRY13" = "true" ]; then SCR_ARGS+=(-D); fi

  elif [ "$BR_TAB" = "1" ]; then
    SCR_ARGS+=(-r "${ENTRY14%% *}")
    if [ -n "$ENTRY15" ]; then SCR_ARGS+=(-m "$ENTRY15"); fi

    if [ ! "$ENTRY16" = "" ]; then SCR_ARGS+=(-e "${ENTRY16%% *}" -l "$ENTRY17"); fi
    if [ ! "$ENTRY18" = "" ]; then SCR_ARGS+=(-b "${ENTRY18%% *}"); fi
    if [ ! "$ENTRY19" = "" ]; then SCR_ARGS+=(-h "${ENTRY19%% *}"); fi
    if [ ! "$ENTRY20" = "" ]; then SCR_ARGS+=(-s "${ENTRY20%% *}"); fi

    if [ -n "$ENTRY21" ]; then SCR_ARGS+=(-t "$ENTRY21"); fi
    if [ -n "$ENTRY22" ]; then SCR_ARGS+=(-R "$ENTRY22"); fi
    if [ -n "$ENTRY23" ]; then SCR_ARGS+=(-B "$ENTRY23"); fi

    if [ "$ENTRY24" = "Grub" ]; then
      SCR_ARGS+=(-G "${ENTRY25%% *}")
    elif [ "$ENTRY24" = "Grub-efi" ]; then
      SCR_ARGS+=(-G auto)
    elif [ "$ENTRY24" = "Syslinux" ]; then
      SCR_ARGS+=(-S "${ENTRY25%% *}")
    elif [ "$ENTRY24" = "EFISTUB/efibootmgr" ]; then
      SCR_ARGS+=(-F)
    elif [ "$ENTRY24" = "Systemd/bootctl" ]; then
      SCR_ARGS+=(-L)
    fi

    if [ ! "$ENTRY24" = "none" ] && [ -n "$ENTRY26" ]; then SCR_ARGS+=(-k "$ENTRY26"); fi

    if [ "$RT_TAB" = "0" ]; then
      SCR_ARGS+=(-f "$ENTRY27")
      if [ -n "$ENTRY28" ]; then SCR_ARGS+=(-P "$ENTRY28"); fi
      if [ -n "$ENTRY29" ]; then SCR_ARGS+=(-u "$ENTRY29"); fi
      if [ -n "$ENTRY30" ]; then SCR_ARGS+=(-y "$ENTRY30"); fi
      if [ -n "$ENTRY31" ]; then SCR_ARGS+=(-p "$ENTRY31"); fi
    elif [ "$RT_TAB" = "1" ]; then
      if [ "$ENTRY32" = "Only hidden files and folders" ]; then
        SCR_ARGS+=(-O)
      elif [ "$ENTRY32" = "Exclude" ]; then
        SCR_ARGS+=(-H)
      fi
      set -f
      for i in $ENTRY34; do ENTRY33="$ENTRY33 --exclude=$i"; done
      set +f
      if [ -n "$ENTRY33" ]; then SCR_ARGS+=(-u "$ENTRY33"); fi
    fi

    if [ "$ENTRY35" = "true" ]; then SCR_ARGS+=(-o); fi
    if [ "$ENTRY36" = "true" ]; then SCR_ARGS+=(-D); fi
    if [ "$ENTRY37" = "true" ]; then SCR_ARGS+=(-x); fi
    if [ "$ENTRY38" = "true" ]; then SCR_ARGS+=(-W); fi
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
<window icon-name="gtk-preferences" height-request="640" width-request="515">
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
                                        <entry text="'"$ENTRY6"'" visibility="false" tooltip-text="Set passphrase for encryption">
                                                '"$(if [ "$ENTRY5" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                <variable>ENTRY6</variable>
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
                                                <checkbox label="Enable multi-core compression" tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz">
                                                        '"$(if [ "$ENTRY4" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                        <variable>ENTRY9</variable>
                                                        <default>'"$ENTRY9"'</default>
                                                </checkbox>

                                                <checkbox label="Generate backup.conf" tooltip-text="Generate configuration file in case of successful backup">
                                                        <variable>ENTRY10</variable>
                                                </checkbox>

                                                <checkbox label="Remove older backups" tooltip-text="Remove older backups in the destination directory">
                                                        <variable>ENTRY11</variable>
                                                        <default>'"$ENTRY11"'</default>
                                                </checkbox>

                                                <checkbox label="Override" tooltip-text="Override the default tar options/excludes with user defined ones">
                                                        <variable>ENTRY12</variable>
                                                        <default>'"$ENTRY12"'</default>
                                                </checkbox>

                                                <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check in gentoo">
                                                        <variable>ENTRY13</variable>
                                                        <default>'"$ENTRY13"'</default>
                                                </checkbox>
                                        </frame>
                                </vbox>
                        </vbox>

                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="35" wrap="false" tooltip-text="==>In the first case, you should use a LiveCD of the
       backed up distro

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
	                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY16#*/}" -e "/${ENTRY18#*/}" -e "/${ENTRY19#*/}" -e "/${ENTRY20#*/}"</input>
                                                                <action>refresh:ENTRY16</action>
                                                                <action>refresh:ENTRY18</action>
                                                                <action>refresh:ENTRY19</action>
                                                                <action>refresh:ENTRY20</action>
			                                </comboboxtext>
                                                        <entry tooltip-text="Set comma-separated list of mount options. Default options: defaults,noatime">
                                                                <variable>ENTRY15</variable>
                                                        </entry>
                                                </hbox>

                                                <expander label="More partitions">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Esp:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional-UEFI only) Select target EFI System Partition">
	                                                                        <variable>ENTRY16</variable>
                                                                                <input>echo "$ENTRY16"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY16#*/}" -e "/${ENTRY18#*/}" -e "/${ENTRY19#*/}" -e "/${ENTRY20#*/}"</input>
                                                                                <input>if [ -n "$ENTRY16" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY18</action>
                                                                                <action>refresh:ENTRY19</action>
                                                                                <action>refresh:ENTRY20</action>
			                                                </comboboxtext>
                                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select mountpoint">
	                                                                        <variable>ENTRY17</variable>
	                                                                        <item>/boot/efi</item>
	                                                                        <item>/boot</item>
	                                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/boot:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                                        <variable>ENTRY18</variable>
                                                                                <input>echo "$ENTRY18"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY16#*/}" -e "/${ENTRY18#*/}" -e "/${ENTRY19#*/}" -e "/${ENTRY20#*/}"</input>
                                                                                <input>if [ -n "$ENTRY18" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY16</action>
                                                                                <action>refresh:ENTRY19</action>
                                                                                <action>refresh:ENTRY20</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/home:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                                        <variable>ENTRY19</variable>
                                                                                <input>echo "$ENTRY19"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY16#*/}" -e "/${ENTRY18#*/}" -e "/${ENTRY19#*/}" -e "/${ENTRY20#*/}"</input>
                                                                                <input>if [ -n "$ENTRY19" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY16</action>
                                                                                <action>refresh:ENTRY18</action>
                                                                                <action>refresh:ENTRY20</action>

                                                                        </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Swap:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                                        <variable>ENTRY20</variable>
                                                                                <input>echo "$ENTRY20"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${ENTRY14#*/}" -e "/${ENTRY16#*/}" -e "/${ENTRY18#*/}" -e "/${ENTRY19#*/}" -e "/${ENTRY20#*/}"</input>
                                                                                <input>if [ -n "$ENTRY20" ]; then echo ""; fi</input>
                                                                                <action>refresh:ENTRY14</action>
                                                                                <action>refresh:ENTRY16</action>
                                                                                <action>refresh:ENTRY18</action>
                                                                                <action>refresh:ENTRY19</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other partitions (mountpoint=partition e.g /var=/dev/sda3). If you want spaces in mountpoints replace them with //">
                                                                                <variable>ENTRY21</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                                <expander label="Btrfs subvolumes">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Root:"></text>
                                                                        <entry tooltip-text="Set subvolume name for /">
                                                                                <variable>ENTRY22</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                                                <variable>ENTRY23</variable>
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
                                                                <variable>ENTRY24</variable>
                                                                <item>none</item>
	                                                        <item>Grub</item>
	                                                        <item>Grub-efi</item>
	                                                        <item>Syslinux</item>
	                                                        <item>EFISTUB/efibootmgr</item>
	                                                        <item>Systemd/bootctl</item>
                                                                <action condition="command_is_true([ $ENTRY24 = none ] && echo true)">disable:ENTRY25</action>
                                                                <action condition="command_is_true([ ! $ENTRY24 = none ] && echo true)">enable:ENTRY25</action>
                                                                <action condition="command_is_true([ $ENTRY24 = none ] && echo true)">disable:ENTRY26</action>
                                                                <action condition="command_is_true([ ! $ENTRY24 = none ] && echo true)">enable:ENTRY26</action>
                                                                <action condition="command_is_true([ $ENTRY24 = EFISTUB/efibootmgr ] && echo true)">disable:ENTRY25</action>
                                                                <action condition="command_is_true([ $ENTRY24 = Systemd/bootctl ] && echo true)">disable:ENTRY25</action>
                                                                <action condition="command_is_true([ $ENTRY24 = Grub-efi ] && echo true)">disable:ENTRY25</action>
                                                        </comboboxtext>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target device" sensitive="false">
	                                                        <variable>ENTRY25</variable>
	                                                        <input>echo "$BR_DISKS"</input>
	                                                </comboboxtext>
                                                        <entry tooltip-text="Set additional kernel options" sensitive="false">
                                                                <variable>ENTRY26</variable>
                                                        </entry>
                                                </hbox>
                                        </frame>
                                </vbox>

                                <notebook labels="Restore Mode|Transfer Mode">
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Backup archive:"></text>
                                                        <entry fs-action="file" tooltip-text="Choose a local backup archive or enter URL" fs-title="Select a backup archive">
                                                                <variable>ENTRY27</variable>
                                                        </entry>
                                                        <button tooltip-text="Select backup archive">
                                                                <input file stock="gtk-open"></input>
                                                                <action>fileselect:ENTRY27</action>
                                                        </button>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                                        <entry tooltip-text="Set passphrase for decryption" visibility="false">
                                                                <variable>ENTRY28</variable>
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
                                                                <variable>ENTRY29</variable>
                                                        </entry>
                                                </hbox>
                                                <expander label="Server authentication">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Username:"></text>
                                                                        <entry tooltip-text="Set ftp/http username">
                                                                                <variable>ENTRY30</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Password:"></text>
                                                                        <entry tooltip-text="Set ftp/http password" visibility="false">
                                                                                <variable>ENTRY31</variable>
                                                                        </entry>
                                                                </hbox>

                                                        </vbox>
                                                </expander>
                                        </vbox>
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                                <variable>ENTRY32</variable>
                                                                <item>Include</item>
	                                                        <item>Only hidden files and folders</item>
	                                                        <item>Exclude</item>
                                                        </comboboxtext>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Set extra rsync options. See rsync --help for more info. If you want spaces in names replace them with //">
                                                                <variable>ENTRY33</variable>
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
                                                                <variable>ENTRY34</variable>
                                                        </entry>
                                                </hbox>
                                        </vbox>
                                        <variable>RT_TAB</variable>
                                </notebook>

                                <vbox>
                                        <frame Misc options:>
                                                <checkbox label="Override" tooltip-text="Override the default tar/rsync options/excludes with user defined ones">
                                                        <variable>ENTRY35</variable>
                                                </checkbox>

                                                <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                                        <variable>ENTRY36</variable>
                                                </checkbox>

                                                <checkbox label="Dont check root" tooltip-text="Dont check if the target root partition is empty (dangerous)">
                                                        <variable>ENTRY37</variable>
                                                </checkbox>

                                                <checkbox label="Bios" tooltip-text="Ignore UEFI environment">
                                                        <variable>ENTRY38</variable>
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
                                <text use-markup="true" label="<i><small>Version 6.5 tritonas00@gmail.com 2012-2017</small></i>"></text>
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
