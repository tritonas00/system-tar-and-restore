#!/bin/bash

cd $(dirname $0)

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

if [ -f /etc/backup.conf ]; then
  source /etc/backup.conf
fi

if [ -n "$BRNAME" ]; then export BR_NAME="$BRNAME"; else export BR_NAME="Backup-$(hostname)-$(date +%Y-%m-%d-%T)"; fi
if [ -n "$BRFOLDER" ]; then export BR_FOLDER="$BRFOLDER"; else export BR_FOLDER="/"; fi
if [ -n "$BR_USER_OPTS" ]; then export BR_B_OPTS="$BR_USER_OPTS"; fi
if [ -n "$BRcompression" ]; then export BR_COMP="$BRcompression"; else export BR_COMP="gzip"; fi
if [ -n "$BRencmethod" ]; then export BR_ENC="$BRencmethod"; else export BR_ENC="none"; fi
if [ -n "$BRencpass" ]; then export BR_PASS="$BRencpass"; fi
if [ -n "$BRmcore" ]; then export ENTRY2="true"; else export ENTRY2="false"; fi
if [ -n "$BRclean" ]; then export ENTRY4="true"; else export ENTRY4="false"; fi
if [ -n "$BRoverride" ]; then export ENTRY5="true"; else export ENTRY5="false"; fi
if [ -n "$BRgenkernel" ]; then export ENTRY6="true"; else export ENTRY6="false"; fi

if [ -n "$BRonlyhidden" ]; then
  export ENTRY1="Only hidden files and folders"
elif [ -n "$BRnohome" ]; then
  export ENTRY1="Exclude"
else
  export ENTRY1="Include"
fi

# Echo all functions to a temporary file so we can source it inside gtkdialog
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
    SCR_ARGS+=(-d "$BR_FOLDER" -c "$BR_COMP")

    if [ -n "$BR_NAME" ] && [[ ! "$BR_NAME" == Backup-$(hostname)-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
      SCR_ARGS+=(-n "$BR_NAME")
    fi

    if [ "$ENTRY1" = "Only hidden files and folders" ]; then
      SCR_ARGS+=(-O)
    elif [ "$ENTRY1" = "Exclude" ]; then
      SCR_ARGS+=(-H)
    fi

    if [ ! "$BR_ENC" = "none" ]; then SCR_ARGS+=(-E "$BR_ENC" -P "$BR_PASS"); fi

    for i in ${BR_B_EXC[@]}; do BR_B_OPTS="$BR_B_OPTS --exclude=$i"; done
    if [ -n "$BR_B_OPTS" ]; then SCR_ARGS+=(-u "$BR_B_OPTS"); fi

    if [ "$ENTRY2" = "true" ] && [ ! "$BR_COMP" = "none" ]; then SCR_ARGS+=(-M); fi
    if [ "$ENTRY3" = "true" ]; then SCR_ARGS+=(-g); fi
    if [ "$ENTRY4" = "true" ]; then SCR_ARGS+=(-a); fi
    if [ "$ENTRY5" = "true" ]; then SCR_ARGS+=(-o); fi
    if [ "$ENTRY6" = "true" ]; then SCR_ARGS+=(-D); fi

  elif [ "$BR_TAB" = "1" ]; then
    SCR_ARGS+=(-r ${BR_ROOT%% *})

    if [ ! "$BR_BOOT" = "" ]; then SCR_ARGS+=(-b ${BR_BOOT%% *}); fi
    if [ ! "$BR_HOME" = "" ]; then SCR_ARGS+=(-h ${BR_HOME%% *}); fi
    if [ ! "$BR_SWAP" = "" ]; then SCR_ARGS+=(-s ${BR_SWAP%% *}); fi
    if [ ! "$BR_ESP" = "" ]; then SCR_ARGS+=(-e ${BR_ESP%% *} -l $BR_ESP_MPOINT); fi
    if [ -n "$BR_OTHER_PARTS" ]; then SCR_ARGS+=(-t "$BR_OTHER_PARTS"); fi

    if [ "$ENTRY7" = "Grub" ]; then
      SCR_ARGS+=(-G ${BR_DISK%% *})
    elif [ "$ENTRY7" = "Grub-efi" ]; then
      SCR_ARGS+=(-G auto)
    elif [ "$ENTRY7" = "Syslinux" ]; then
      SCR_ARGS+=(-S ${BR_DISK%% *})
    elif [ "$ENTRY7" = "EFISTUB/efibootmgr" ]; then
      SCR_ARGS+=(-F)
    elif [ "$ENTRY7" = "Systemd/bootctl" ]; then
      SCR_ARGS+=(-L)
    fi

    if [ ! "$ENTRY7" = "none" ] && [ -n "$BR_KL_OPTS" ]; then SCR_ARGS+=(-k "$BR_KL_OPTS"); fi

    if [ "$RT_TAB" = "0" ]; then
      SCR_ARGS+=(-f "$BR_FILE")
      if [ -n "$BR_USERNAME" ]; then SCR_ARGS+=(-y "$BR_USERNAME"); fi
      if [ -n "$BR_PASSWORD" ]; then SCR_ARGS+=(-p "$BR_PASSWORD"); fi
      if [ -n "$BR_PASSPHRASE" ]; then SCR_ARGS+=(-P "$BR_PASSPHRASE"); fi
      if [ -n "$BR_TR_OPTIONS" ]; then SCR_ARGS+=(-u "$BR_TR_OPTIONS"); fi
    elif [ "$RT_TAB" = "1" ]; then
      if [ "$ENTRY8" = "Only hidden files and folders" ]; then
        SCR_ARGS+=(-O)
      elif [ "$ENTRY8" = "Exclude" ]; then
        SCR_ARGS+=(-H)
      fi
      if [ "$ENTRY9" = "true" ]; then SCR_ARGS+=(-o); fi
      for i in ${BR_T_EXC[@]}; do BR_RS_OPTS="$BR_RS_OPTS --exclude=$i"; done
      if [ -n "$BR_RS_OPTS" ]; then SCR_ARGS+=(-u "$BR_RS_OPTS"); fi
    fi

    if [ -n "$BR_MN_OPTS" ]; then SCR_ARGS+=(-m "$BR_MN_OPTS"); fi
    if [ -n "$BR_ROOT_SUBVOL" ]; then SCR_ARGS+=(-R "$BR_ROOT_SUBVOL"); fi
    if [ -n "$BR_OTHER_SUBVOLS" ]; then SCR_ARGS+=(-B "$BR_OTHER_SUBVOLS"); fi

    if [ "$ENTRY10" = "true" ]; then SCR_ARGS+=(-D); fi
    if [ "$ENTRY11" = "true" ]; then SCR_ARGS+=(-x); fi
    if [ "$ENTRY12" = "true" ]; then SCR_ARGS+=(-W); fi
  fi
}

run_main() {
  if [ "$BR_TAB" = "0" ] || [ "$BR_TAB" = "1" ]; then
    if [ "$BR_DEBUG" = "true" ]; then
      echo star.sh "${SCR_ARGS[@]}" > /tmp/wr_proc
    else
      echo false > /tmp/wr_upt
      setsid ./star.sh "${SCR_ARGS[@]}" 2> /tmp/wr_log
      sleep 0.1
      echo "$BR_TITLE" > /tmp/wr_proc
      echo true > /tmp/wr_upt
    fi
  fi
}
' > /tmp/wr_functions

export BR_PARTS=$(for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done | sort
                  for f in $(find /dev/mapper/ -maxdepth 1 -mindepth 1 ! -name "control"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
                  for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done)

export BR_DISKS=$(for f in /dev/[vhs]d[a-z]; do echo "$f $(lsblk -d -n -o size $f)"; done
                  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f)"; done
                  for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done)

export BR_ROOT=$(echo "$BR_PARTS" | head -n 1)

export MAIN_DIALOG='

<window icon-name="applications-system" height-request="640" width-request="515">
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
                        <action>refresh:BR_TL</action>
                        <action condition="file_is_false(/tmp/wr_upt)">disable:BR_TAB</action>
                </entry>
                <notebook labels="Backup|Restore/Transfer|Log|About" space-expand="true" space-fill="true">
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="35" tooltip-text="==>Make sure destination has enough space

==>If you plan to restore in lvm/mdadm/luks,
       configure this system accordingly

==>Supported bootloaders:
       Grub Syslinux EFISTUB/efibootmgr Systemd/bootctl

GRUB PACKAGES:
**Arch/Gentoo:
    grub
**Fedora/openSUSE:
    grub2
**Debian/Ubuntu:
    grub-pc grub-efi
**Mandriva/Mageia:
    grub2 grub2-efi

SYSLINUX PACKAGES:
**Arch/openSUSE/Gentoo:
    syslinux
**Debian/Ubuntu/Mandriva/Mageia:
    syslinux extlinux
**Fedora:
    syslinux syslinux-extlinux

OTHER PACKAGES:
efibootmgr dosfstools systemd"><label>"Make a backup archive of this system"</label></text>
                                <hseparator></hseparator>
                                <hbox>
                                        <text width-request="135" label="Filename:"></text>
                                        <entry text="'"$BR_NAME"'" tooltip-text="Set backup archive name">
                                                <variable>BR_NAME</variable>
                                        </entry>
                                </hbox>

                                <hbox>
                                        <text width-request="135" label="Destination:"></text>
                                        <entry text="'"$BR_FOLDER"'" fs-action="folder" fs-title="Select a directory" tooltip-text="Choose where to save the backup archive">
                                                <variable>BR_FOLDER</variable>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:BR_FOLDER</action>
                                        </button>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                <variable>ENTRY1</variable>
                                                <default>'"$ENTRY1"'</default>
                                                <item>Include</item>
	                                        <item>Only hidden files and folders</item>
	                                        <item>Exclude</item>
                                        </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Compression:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select compressor">
	                                        <variable>BR_COMP</variable>
                                                <default>'"$BR_COMP"'</default>
	                                        <item>gzip</item>
	                                        <item>bzip2</item>
	                                        <item>xz</item>
                                                <item>none</item>
                                                <action condition="command_is_true([ $BR_COMP = none ] && echo true)">disable:ENTRY2</action>
                                                <action condition="command_is_true([ ! $BR_COMP = none ] && echo true)">enable:ENTRY2</action>
	                                </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Encryption:"></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select encryption method">
	                                        <variable>BR_ENC</variable>
                                                <default>'"$BR_ENC"'</default>
                                                <item>none</item>
	                                        <item>openssl</item>
	                                        <item>gpg</item>
                                                <action condition="command_is_true([ $BR_ENC = none ] && echo true)">disable:BR_PASS</action>
                                                <action condition="command_is_true([ ! $BR_ENC = none ] && echo true)">enable:BR_PASS</action>
                                        </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                        <entry text="'"$BR_PASS"'" visibility="false" tooltip-text="Set passphrase for encryption">
                                                '"$(if [ "$BR_ENC" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                <variable>BR_PASS</variable>
                                        </entry>
                                </hbox>

                                <hbox>
                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                        <entry text="'"$BR_B_OPTS"'" space-expand="true" space-fill="true" tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //">
                                                <variable>BR_B_OPTS</variable>
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
.gvfs
lost+found">
                                                <variable>BR_B_EXC</variable>
                                        </entry>
                                </hbox>

                                <vbox>
                                        <frame Misc options:>
                                                <checkbox label="Enable multi-core compression" tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz">
                                                        '"$(if [ "$BR_COMP" = "none" ]; then echo "<sensitive>false</sensitive>"; fi)"'
                                                        <variable>ENTRY2</variable>
                                                        <default>'"$ENTRY2"'</default>
                                                </checkbox>

                                                <checkbox label="Generate backup.conf" tooltip-text="Generate configuration file in case of successful backup">
                                                        <variable>ENTRY3</variable>
                                                </checkbox>

                                                <checkbox label="Remove older backups" tooltip-text="Remove older backups in the destination directory">
                                                        <variable>ENTRY4</variable>
                                                        <default>'"$ENTRY4"'</default>
                                                </checkbox>

                                                <checkbox label="Override" tooltip-text="Override the default tar options with user options">
                                                        <variable>ENTRY5</variable>
                                                        <default>'"$ENTRY5"'</default>
                                                </checkbox>

                                                <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check in gentoo">
                                                        <variable>ENTRY6</variable>
                                                        <default>'"$ENTRY6"'</default>
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
	                                                        <variable>BR_ROOT</variable>
                                                                <input>echo "$BR_ROOT"</input>
	                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${BR_ROOT#*/}" -e "/${BR_BOOT#*/}" -e "/${BR_HOME#*/}" -e "/${BR_ESP#*/}" -e "/${BR_SWAP#*/}"</input>
                                                                <action>refresh:BR_BOOT</action>
                                                                <action>refresh:BR_HOME</action>
                                                                <action>refresh:BR_SWAP</action>
                                                                <action>refresh:BR_ESP</action>
			                                </comboboxtext>
                                                        <entry tooltip-text="Set comma-separated list of mount options. Default options: defaults,noatime">
                                                                <variable>BR_MN_OPTS</variable>
                                                        </entry>
                                                </hbox>

                                                <expander label="More partitions">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Esp:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional-UEFI only) Select target EFI System Partition">
	                                                                        <variable>BR_ESP</variable>
                                                                                <input>echo "$BR_ESP"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${BR_ROOT#*/}" -e "/${BR_BOOT#*/}" -e "/${BR_HOME#*/}" -e "/${BR_ESP#*/}" -e "/${BR_SWAP#*/}"</input>
                                                                                <input>if [ -n "$BR_ESP" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_ROOT</action>
                                                                                <action>refresh:BR_HOME</action>
                                                                                <action>refresh:BR_BOOT</action>
                                                                                <action>refresh:BR_SWAP</action>
			                                                </comboboxtext>
                                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select mountpoint">
	                                                                        <variable>BR_ESP_MPOINT</variable>
	                                                                        <item>/boot/efi</item>
	                                                                        <item>/boot</item>
	                                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/boot:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                                        <variable>BR_BOOT</variable>
                                                                                <input>echo "$BR_BOOT"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${BR_ROOT#*/}" -e "/${BR_BOOT#*/}" -e "/${BR_HOME#*/}" -e "/${BR_ESP#*/}" -e "/${BR_SWAP#*/}"</input>
                                                                                <input>if [ -n "$BR_BOOT" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_ROOT</action>
                                                                                <action>refresh:BR_HOME</action>
                                                                                <action>refresh:BR_SWAP</action>
                                                                                <action>refresh:BR_ESP</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="/home:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                                        <variable>BR_HOME</variable>
                                                                                <input>echo "$BR_HOME"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${BR_ROOT#*/}" -e "/${BR_BOOT#*/}" -e "/${BR_HOME#*/}" -e "/${BR_ESP#*/}" -e "/${BR_SWAP#*/}"</input>
                                                                                <input>if [ -n "$BR_HOME" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_BOOT</action>
                                                                                <action>refresh:BR_ROOT</action>
                                                                                <action>refresh:BR_SWAP</action>
                                                                                <action>refresh:BR_ESP</action>
                                                                        </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Swap:"></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                                        <variable>BR_SWAP</variable>
                                                                                <input>echo "$BR_SWAP"</input>
	                                                                        <input>echo "$BR_PARTS" | grep -vw -e "/${BR_ROOT#*/}" -e "/${BR_BOOT#*/}" -e "/${BR_HOME#*/}" -e "/${BR_ESP#*/}" -e "/${BR_SWAP#*/}"</input>
                                                                                <input>if [ -n "$BR_SWAP" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_ROOT</action>
                                                                                <action>refresh:BR_HOME</action>
                                                                                <action>refresh:BR_BOOT</action>
                                                                                <action>refresh:BR_ESP</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other partitions (mountpoint=partition e.g /var=/dev/sda3). If you want spaces in mountpoints replace them with //">
                                                                                <variable>BR_OTHER_PARTS</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                                <expander label="Btrfs subvolumes">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Root:"></text>
                                                                        <entry tooltip-text="Set subvolume name for /">
                                                                                <variable>BR_ROOT_SUBVOL</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false" label="Other:"></text>
                                                                        <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                                                <variable>BR_OTHER_SUBVOLS</variable>
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
                                                                <variable>ENTRY7</variable>
                                                                <item>none</item>
	                                                        <item>Grub</item>
	                                                        <item>Grub-efi</item>
	                                                        <item>Syslinux</item>
	                                                        <item>EFISTUB/efibootmgr</item>
	                                                        <item>Systemd/bootctl</item>
                                                                <action condition="command_is_true([ $ENTRY7 = none ] && echo true)">disable:BR_DISK</action>
                                                                <action condition="command_is_true([ ! $ENTRY7 = none ] && echo true)">enable:BR_DISK</action>
                                                                <action condition="command_is_true([ $ENTRY7 = none ] && echo true)">disable:BR_KL_OPTS</action>
                                                                <action condition="command_is_true([ ! $ENTRY7 = none ] && echo true)">enable:BR_KL_OPTS</action>
                                                                <action condition="command_is_true([ $ENTRY7 = EFISTUB/efibootmgr ] && echo true)">disable:BR_DISK</action>
                                                                <action condition="command_is_true([ $ENTRY7 = Systemd/bootctl ] && echo true)">disable:BR_DISK</action>
                                                                <action condition="command_is_true([ $ENTRY7 = Grub-efi ] && echo true)">disable:BR_DISK</action>
                                                        </comboboxtext>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target device" sensitive="false">
	                                                        <variable>BR_DISK</variable>
	                                                        <input>echo "$BR_DISKS"</input>
	                                                </comboboxtext>
                                                        <entry tooltip-text="Set additional kernel options" sensitive="false">
                                                                <variable>BR_KL_OPTS</variable>
                                                        </entry>
                                                </hbox>
                                        </frame>
                                </vbox>

                                <notebook labels="Restore Mode|Transfer Mode">
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Backup archive:"></text>
                                                        <entry fs-action="file" tooltip-text="Choose a local backup archive or enter URL" fs-title="Select a backup archive">
                                                                <variable>BR_FILE</variable>
                                                        </entry>
                                                        <button tooltip-text="Select backup archive">
                                                                <input file stock="gtk-open"></input>
                                                                <action>fileselect:BR_FILE</action>
                                                        </button>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Passphrase:"></text>
                                                        <entry tooltip-text="Set passphrase for decryption" visibility="false">
                                                                <variable>BR_PASSPHRASE</variable>
                                                        </entry>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //">
                                                                <variable>BR_TR_OPTIONS</variable>
                                                        </entry>
                                                </hbox>
                                                <expander label="Server authentication">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Username:"></text>
                                                                        <entry tooltip-text="Set ftp/http username">
                                                                                <variable>BR_USERNAME</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="135" space-expand="false" label="Password:"></text>
                                                                        <entry tooltip-text="Set ftp/http password" visibility="false">
                                                                                <variable>BR_PASSWORD</variable>
                                                                        </entry>
                                                                </hbox>

                                                        </vbox>
                                                </expander>
                                        </vbox>
                                        <vbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Home directory:"></text>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                                <variable>ENTRY8</variable>
                                                                <item>Include</item>
	                                                        <item>Only hidden files and folders</item>
	                                                        <item>Exclude</item>
                                                        </comboboxtext>
                                                </hbox>
                                                <hbox>
                                                        <text width-request="135" space-expand="false" label="Additional options:"></text>
                                                        <entry space-expand="true" space-fill="true" tooltip-text="Set extra rsync options. See rsync --help for more info. If you want spaces in names replace them with //">
                                                                <variable>BR_RS_OPTS</variable>
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
                                                                <variable>BR_T_EXC</variable>
                                                        </entry>
                                                </hbox>

                                                <checkbox label="Override" tooltip-text="Override the default rsync options with user options">
                                                        <variable>ENTRY9</variable>
                                                </checkbox>
                                        </vbox>
                                        <variable>RT_TAB</variable>
                                </notebook>

                                <vbox>
                                        <frame Misc options:>
                                                <checkbox label="Disable genkernel" tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                                        <variable>ENTRY10</variable>
                                                </checkbox>

                                                <checkbox label="Dont check root" tooltip-text="Dont check if the target root partition is empty (dangerous)">
                                                        <variable>ENTRY11</variable>
                                                </checkbox>

                                                <checkbox label="Bios" tooltip-text="Ignore UEFI environment">
                                                        <variable>ENTRY12</variable>
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
                                <text use-markup="true" label="<i><small>Version 6.2 tritonas00@gmail.com 2012-2017</small></i>"></text>
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
                                <input file icon="gtk-ok"></input>
                                <label>Run</label>
                                <variable>BTN_RUN</variable>
                                <action>bash -c "source /tmp/wr_functions; set_args && run_main &"</action>
                        </button>
                        <button tooltip-text="Kill the process" sensitive="false">
                                <input file icon="gtk-cancel"></input>
                                <variable>BTN_CANCEL</variable>
                                <label>Cancel</label>
                                <action>kill -9 -$(cat /tmp/wr_pid)</action>
                                <action>echo "PID $(cat /tmp/wr_pid) Killed" > /tmp/wr_log</action>
                        </button>
                        <button tooltip-text="Exit">
                                <variable>BTN_EXIT</variable>
                                <input file icon="gtk-close"></input>
                                <label>Exit</label>
                        </button>
                </hbox>
        </vbox>
	<variable>BR_TL</variable>
	<input file>/tmp/wr_proc</input>
</window>
'

gtkdialog --program=MAIN_DIALOG

clean_tmp_files
