#!/bin/bash

if file /bin/sh | grep -q -w dash; then
  ln -sf /bin/bash /bin/sh
  force_bash="y"
fi

cd $(dirname $0)

clean_files() {
  if [ -f /tmp/wr_proc ]; then rm /tmp/wr_proc; fi
  if [ -f /tmp/wr_log ]; then rm /tmp/wr_log; fi
  if [ -f /tmp/wr_pid ]; then rm /tmp/wr_pid; fi
}

clean_files

echo > /tmp/wr_log
echo > /tmp/wr_proc

if [ -f /etc/backup.conf ]; then
  source /etc/backup.conf
fi

if [ -n "$BRNAME" ]; then export BRNAME; else export BRNAME="Backup-$(hostname)-$(date +%Y-%m-%d-%T)"; fi
if [ -n "$BRFOLDER" ]; then export BRFOLDER; else export BRFOLDER="/"; fi
if [ -n "$BRcompression" ]; then export BRcompression; else export BRcompression="gzip"; fi
if [ -n "$BRencmethod" ]; then export BRencmethod; else export BRencmethod="none"; fi
if [ -n "$BRencpass" ]; then export BRencpass; fi
if [ -n "$BR_USER_OPTS" ]; then export BR_USER_OPTS; fi
if [ -n "$BRmcore" ]; then export ENTRY3="true"; else export ENTRY3="false"; fi
if [ -n "$BRverb" ]; then export ENTRY4="true"; else export ENTRY4="false"; fi
if [ -n "$BRnosockets" ]; then export ENTRY5="true"; else export ENTRY5="false"; fi
if [ -n "$BRclean" ]; then export ENTRY9="true"; else export ENTRY9="false"; fi
if [ -n "$BRoverride" ]; then export ENTRY10="true"; else export ENTRY10="false"; fi
if [ -n "$BRgenkernel" ]; then export ENTRY11="true"; else export ENTRY11="false"; fi

if [ "$BRhome" = "No" ] && [ -z "$BRhidden" ]; then
  export ENTRY1="Only hidden files and folders"
elif [ "$BRhome" = "No" ] && [ "$BRhidden" = "No" ]; then
  export ENTRY1="Exclude"
else
  export ENTRY1="Include"
fi

set_default_pass() {
  if [ ! "$BRencmethod" = "none" ]; then
    echo '<entry tooltip-text="Set passphrase for encryption"><variable>BRencpass</variable>'
  else
    echo '<entry tooltip-text="Set passphrase for encryption" sensitive="false"><variable>BRencpass</variable>'
  fi
  if [ -n "$BRencpass" ]; then echo '<default>'"$BRencpass"'</default>';fi
}

set_default_opts() {
  if [ -n "$BR_USER_OPTS" ]; then echo '<default>'"$BR_USER_OPTS"'</default>'; fi
}

set_default_multi() {
  if [ ! "$BRcompression" = "none" ]; then
    echo '<checkbox tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz">'
  else
    echo '<checkbox tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz" sensitive="false">'
  fi
}

scan_parts() {
  for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done | sort
  for f in $(find /dev/mapper/ -maxdepth 1 -mindepth 1 ! -name "control"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
}

scan_disks() {
  for f in /dev/[vhs]d[a-z]; do echo "$f $(lsblk -d -n -o size $f)"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f)"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done
}

hide_used_parts() {
  grep -vw -e "/${BR_ROOT#*/}" -e "/${BR_BOOT#*/}" -e "/${BR_HOME#*/}" -e "/${BR_ESP#*/}" -e "/${BR_SWAP#*/}"
}

set_args() {
  if [ -n "$BRNAME" ] && [[ ! "$BRNAME" == Backup-$(hostname)-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
    BACKUP_ARGS+=(-f "$BRNAME")
  fi

  if [ "$ENTRY1" = "Only hidden files and folders" ]; then
    BACKUP_ARGS+=(-h)
  elif [ "$ENTRY1" = "Exclude" ]; then
    BACKUP_ARGS+=(-hn)
  fi

  if [ ! "$BRencmethod" = "none" ]; then
    BACKUP_ARGS+=(-E "$BRencmethod")
    if [ -n "$BRencpass" ]; then BACKUP_ARGS+=(-P "$BRencpass"); fi
  else
    unset BRencpass
  fi

  for i in ${BR_EXC[@]}; do BR_USER_OPTS="$BR_USER_OPTS --exclude=$i"; done
  if [ -n "$BR_USER_OPTS" ]; then BACKUP_ARGS+=(-u "$BR_USER_OPTS"); fi

  if [ "$ENTRY3" = "true" ] && [ ! "$BRcompression" = "none" ]; then BACKUP_ARGS+=(-m); fi
  if [ "$ENTRY4" = "true" ]; then BACKUP_ARGS+=(-v); fi
  if [ "$ENTRY5" = "true" ]; then BACKUP_ARGS+=(-s); fi
  if [ "$ENTRY7" = "true" ]; then BACKUP_ARGS+=(-g); fi
  if [ "$ENTRY9" = "true" ]; then BACKUP_ARGS+=(-r); fi
  if [ "$ENTRY10" = "true" ]; then BACKUP_ARGS+=(-o); fi
  if [ "$ENTRY11" = "true" ]; then BACKUP_ARGS+=(-D); fi

  if [ "$BR_MODE" = "1" ]; then
    unset BRencmethod BRencpass BR_USER_OPTS
  fi

  if [ ! "$BR_BOOT" = "" ]; then RESTORE_ARGS+=(-b ${BR_BOOT%% *}); fi
  if [ ! "$BR_HOME" = "" ]; then RESTORE_ARGS+=(-h ${BR_HOME%% *}); fi
  if [ ! "$BR_SWAP" = "" ]; then RESTORE_ARGS+=(-s ${BR_SWAP%% *}); fi
  if [ ! "$BR_ESP" = "" ]; then RESTORE_ARGS+=(-e ${BR_ESP%% *} -l $BR_ESP_MPOINT); fi
  if [ -n "$BR_OTHER_PARTS" ]; then RESTORE_ARGS+=(-c "$BR_OTHER_PARTS"); fi

  if [ "$ENTRY12" = "Grub" ]; then
    RESTORE_ARGS+=(-g ${BR_DISK%% *})
  elif [ "$ENTRY12" = "Syslinux" ]; then
    RESTORE_ARGS+=(-S ${BR_DISK%% *})
  elif [ "$ENTRY12" = "EFISTUB/efibootmgr" ]; then
    RESTORE_ARGS+=(-E)
  elif [ "$ENTRY12" = "Systemd/bootctl" ]; then
    RESTORE_ARGS+=(-L)
  fi

  if [ ! "$ENTRY12" = "none" ] && [ -n "$BR_KL_OPTS" ]; then RESTORE_ARGS+=(-k "$BR_KL_OPTS"); fi

  if [ "$ENTRY13" = "false" ]; then
    RESTORE_ARGS+=(-f "$BR_FILE")
    if [ -n "$BR_USERNAME" ] && [[ ! "$BR_FILE" == /* ]]; then RESTORE_ARGS+=(-n "$BR_USERNAME"); fi
    if [ -n "$BR_PASSWORD" ] && [[ ! "$BR_FILE" == /* ]]; then RESTORE_ARGS+=(-p "$BR_PASSWORD"); fi
    if [ -n "$BR_PASSPHRASE" ]; then RESTORE_ARGS+=(-P "$BR_PASSPHRASE"); fi
  elif [ "$ENTRY13" = "true" ]; then
    RESTORE_ARGS+=(-t)
    if [ "$ENTRY14" = "true" ]; then RESTORE_ARGS+=(-o); fi
    if [ "$ENTRY21" = "true" ]; then RESTORE_ARGS+=(-x); fi
  fi

  if [ -n "$BR_MN_OPTS" ]; then RESTORE_ARGS+=(-m "$BR_MN_OPTS"); fi
  if [ -n "$BR_TR_OPTIONS" ]; then RESTORE_ARGS+=(-u "$BR_TR_OPTIONS"); fi
  if [ -n "$BR_ROOT_SUBVOL" ]; then RESTORE_ARGS+=(-R "$BR_ROOT_SUBVOL"); fi
  if [ -n "$BR_OTHER_SUBVOLS" ]; then RESTORE_ARGS+=(-O "$BR_OTHER_SUBVOLS"); fi

  if [ "$ENTRY15" = "true" ]; then RESTORE_ARGS+=(-v); fi
  if [ "$ENTRY18" = "true" ]; then RESTORE_ARGS+=(-D); fi
  if [ "$ENTRY19" = "true" ]; then RESTORE_ARGS+=(-d); fi
  if [ "$ENTRY20" = "true" ]; then RESTORE_ARGS+=(-B); fi
}

status_bar() {
  if [ $(id -u) -gt 0 ]; then
    echo "Script must run as root."
  elif [ "$BR_MODE" = "0" ]; then
    echo backup.sh -i cli -Nwq -d "$BRFOLDER" -c $BRcompression "${BACKUP_ARGS[@]}"
  elif [ "$BR_MODE" = "1" ]; then
    echo restore.sh -i cli -Nwq -r ${BR_ROOT%% *} "${RESTORE_ARGS[@]}"
  elif [ "$BR_MODE" = "2" ] && [ -f /tmp/wr_pid ]; then
    echo "Running (PID $(cat /tmp/wr_pid)). Do not close the window until the process is complete."
  elif [ "$BR_MODE" = "2" ] && [ ! -f /tmp/wr_pid ]; then
    echo "Idle"
  fi
}

run_main() {
  echo > /tmp/wr_log
  echo > /tmp/wr_proc

  if [ "$BR_MODE" = "0" ]; then
    setsid ./backup.sh -i cli -Nwq -d "$BRFOLDER" -c $BRcompression "${BACKUP_ARGS[@]}" > /tmp/wr_log 2>&1
  elif [ "$BR_MODE" = "1" ]; then
    setsid ./restore.sh -i cli -Nwq -r ${BR_ROOT%% *} "${RESTORE_ARGS[@]}" > /tmp/wr_log 2>&1
  fi

  if [ -f /tmp/wr_pid ]; then rm /tmp/wr_pid; fi
}

cancel_proc() {
  kill -9 -$(cat /tmp/wr_pid)
  echo Cancelled > /tmp/wr_proc
  echo > /tmp/wr_log
}

full_log() {
  if grep -Fxq "FOUND BOOTLOADERS:" /tmp/wr_log; then
    cat "$BRFOLDER"/Backup-$(date +%Y-%m-%d)/backup.log > /tmp/wr_log
  elif grep -Fxq "BOOTLOADER:" /tmp/wr_log; then
    cat /tmp/restore.log > /tmp/wr_log
  fi
}

export -f scan_disks hide_used_parts set_default_pass set_default_opts set_default_multi set_args status_bar run_main cancel_proc full_log
export BR_PARTS=$(scan_parts)
export BR_ROOT=$(echo "$BR_PARTS" | head -n 1)
export BR_MODE="0"

export MAIN_DIALOG='

<window title="System Tar & Restore" icon-name="applications-system">
        <vbox>
                <timer visible="false">
                        <action>refresh:BR_SB</action>
                        <action>refresh:BR_PROC</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">enable:BTN_RUN</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">enable:BTN_EXIT</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">enable:BTN_LOG</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">disable:BTN_CANCEL</action>
		</timer>
                <notebook labels="Backup|Restore/Transfer|Log">
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="30" use-markup="true" tooltip-text="==>Make sure you have enough free space.

==>If you plan to restore in lvm/mdadm/dm-crypt, make
       sure that this system is capable to boot from those
       configurations.

==>The following bootloaders are supported:
       Grub Syslinux EFISTUB/efibootmgr Systemd/bootctl.

GRUB PACKAGES:
**Arch/Gentoo:
    grub
**Fedora/Suse:
    grub2
**Debian:
    grub-pc grub-efi
**Mandriva:
    grub2 grub2-efi

SYSLINUX PACKAGES:
**Arch/Suse/Gentoo:
    syslinux
**Debian/Mandriva:
    syslinux extlinux
**Fedora:
    syslinux syslinux-extlinux

OTHER PACKAGES:
efibootmgr dosfstools systemd"><label>"<span color='"'brown'"'>Make a tar backup image of this system.</span>"</label></text>

                                <hbox><text width-request="93"><label>Filename:</label></text>
                                <entry tooltip-text="Set backup archive name">
                                        <variable>BRNAME</variable>
                                        <default>'"$BRNAME"'</default>
                                        <action>refresh:BR_SB</action>
                                </entry></hbox>

                                <hbox><text width-request="93"><label>Destination:</label></text>
                                        <entry fs-action="folder" fs-title="Select a directory" tooltip-text="Choose where to save the backup archive">
                                                <variable>BRFOLDER</variable>
                                                <default>'"$BRFOLDER"'</default>
                                                <action>refresh:BR_SB</action>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:BRFOLDER</action>
                                        </button>
                                 </hbox>

                                <hbox><text width-request="92" space-expand="false"><label>Home directory:</label></text>
                                <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                        <variable>ENTRY1</variable>
                                        <default>'"$ENTRY1"'</default>
                                        <item>Include</item>
	                                <item>Only hidden files and folders</item>
	                                <item>Exclude</item>
                                        <action>refresh:BR_SB</action>
                                </comboboxtext></hbox>

                                <hbox><text width-request="92" space-expand="false"><label>Compression:</label></text>
                                <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select compressor">
	                                <variable>BRcompression</variable>
                                        <default>'"$BRcompression"'</default>
	                                <item>gzip</item>
	                                <item>bzip2</item>
	                                <item>xz</item>
                                        <item>none</item>
                                        <action>refresh:BR_SB</action>
                                        <action condition="command_is_true([ $BRcompression = none ] && echo true)">disable:ENTRY3</action>
                                        <action condition="command_is_true([ ! $BRcompression = none ] && echo true)">enable:ENTRY3</action>
	                        </comboboxtext></hbox>

                                <vbox>
                                        <hbox><text width-request="92" space-expand="false"><label>Encryption:</label></text>
                                                <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select encryption method">
	                                                <variable>BRencmethod</variable>
                                                        <default>'"$BRencmethod"'</default>
                                                        <item>none</item>
	                                                <item>openssl</item>
	                                                <item>gpg</item>
                                                        <action>refresh:BR_SB</action>
                                                        <action condition="command_is_true([ $BRencmethod = none ] && echo true)">disable:BRencpass</action>
                                                        <action condition="command_is_true([ ! $BRencmethod = none ] && echo true)">enable:BRencpass</action>
                                                </comboboxtext>
                                        </hbox>
                                        <hbox><text width-request="93" space-expand="false"><label>Passphrase:</label></text>
                                                        '"`set_default_pass`"'
                                                        <action>refresh:BR_SB</action>
                                                </entry>
                                        </hbox>
                                </vbox>

                                <text xalign="0"><label>Additional options:</label></text>
                                <comboboxentry tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_USER_OPTS</variable>
                                       '"`set_default_opts`"'
                                        <item>--acls --xattrs</item>
                                        <action>refresh:BR_SB</action>
                                </comboboxentry>

                                <text xalign="0"><label>Exclude:</label></text>
                                <entry tooltip-text="Exclude files and directories. If you want spaces in names replace them with //">
                                        <variable>BR_EXC</variable>
                                        <action>refresh:BR_SB</action>
                                </entry>

                                        '"`set_default_multi`"'
                                        <label>Enable multi-core compression</label>
                                        <variable>ENTRY3</variable>
                                        <default>'"$ENTRY3"'</default>
                                        <action>refresh:BR_SB</action>
                                </checkbox>

                                <checkbox tooltip-text="Make tar output verbose">
                                        <label>Verbose</label>
                                        <variable>ENTRY4</variable>
                                        <default>'"$ENTRY4"'</default>
                                        <action>refresh:BR_SB</action>
                                </checkbox>

                                <checkbox tooltip-text="Exclude sockets">
                                        <label>Exclude sockets</label>
                                        <variable>ENTRY5</variable>
                                        <default>'"$ENTRY5"'</default>
                                        <action>refresh:BR_SB</action>
                                </checkbox>

                                <checkbox tooltip-text="Generate configuration file in case of successful backup">
                                        <label>Generate backup.conf</label>
                                        <variable>ENTRY7</variable>
                                        <action>refresh:BR_SB</action>
                                </checkbox>

                                <checkbox tooltip-text="Remove older backups in the destination directory">
                                        <label>Remove older backups</label>
                                        <variable>ENTRY9</variable>
                                        <default>'"$ENTRY9"'</default>
                                        <action>refresh:BR_SB</action>
                                </checkbox>

                                <checkbox tooltip-text="Override the default tar options with user options">
                                        <label>Override</label>
                                        <variable>ENTRY10</variable>
                                        <default>'"$ENTRY10"'</default>
                                        <action>refresh:BR_SB</action>
                                </checkbox>

                                <checkbox tooltip-text="Disable genkernel check in gentoo">
                                        <label>Disable genkernel</label>
                                        <variable>ENTRY11</variable>
                                        <default>'"$ENTRY11"'</default>
                                        <action>refresh:BR_SB</action>
                                </checkbox>
                        </vbox>

                        <vbox scrollable="true" shadow-type="0" height="585" width="510">
                                <text wrap="false" height-request="30" use-markup="true" tooltip-text="In the first case, you should run it from a LiveCD of the target (backed up) distro.

==>Make sure you have created one target root (/) partition.
       Optionally you can create or use any other partition
       (/boot /home /var etc).

==>Make sure that target LVM volume groups are activated,
       target RAID arrays are properly assembled and target
       encrypted partitions are opened.

==>If you plan to transfer in btrfs/lvm/mdadm/dm-crypt,
       make sure that this system is capable to boot from
       those configurations."><label>"<span color='"'brown'"'>Restore a backup image or transfer this system in user defined partitions.</span>"</label></text>

                                <frame Target partitions:>
                                <hbox><text width-request="30" space-expand="false"><label>Root:</label></text>

		                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target root partition">
	                                        <variable>BR_ROOT</variable>
                                                <input>echo "$BR_ROOT"</input>
	                                        <input>echo "$BR_PARTS" | hide_used_parts</input>
                                                <action>refresh:BR_BOOT</action><action>refresh:BR_HOME</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
                                                <action>refresh:BR_SB</action>
			                </comboboxtext>
                                        <entry tooltip-text="Set comma-separated list of mount options for the root partition">
                                                <variable>BR_MN_OPTS</variable>
                                                <input>echo "defaults,noatime"</input>
                                                <action>refresh:BR_SB</action>
                                        </entry>
                                </hbox>

                                <expander label="More partitions">
                                        <vbox>
                                                <hbox><text width-request="55" space-expand="false"><label>Esp:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional-UEFI only) Select target EFI System Partition">
	                                                        <variable>BR_ESP</variable>
                                                                <input>echo "$BR_ESP"</input>
	                                                        <input>echo "$BR_PARTS" | hide_used_parts</input>
                                                                <input>if [ -n "$BR_ESP" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_BOOT</action><action>refresh:BR_SWAP</action>
                                                                <action>refresh:BR_SB</action>
			                                </comboboxtext>
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select mountpoint">
	                                                        <variable>BR_ESP_MPOINT</variable>
	                                                        <item>/boot/efi</item>
	                                                        <item>/boot</item>
                                                                <action>refresh:BR_SB</action>
	                                                </comboboxtext>
                                                </hbox>
                                                <hbox><text width-request="55" space-expand="false"><label>/boot:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                        <variable>BR_BOOT</variable>
                                                                <input>echo "$BR_BOOT"</input>
	                                                        <input>echo "$BR_PARTS" | hide_used_parts</input>
                                                                <input>if [ -n "$BR_BOOT" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
                                                                <action>refresh:BR_SB</action>
			                                </comboboxtext>
                                                </hbox>
                                                <hbox><text width-request="55" space-expand="false"><label>/home:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                        <variable>BR_HOME</variable>
                                                                <input>echo "$BR_HOME"</input>
	                                                        <input>echo "$BR_PARTS" | hide_used_parts</input>
                                                                <input>if [ -n "$BR_HOME" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_BOOT</action><action>refresh:BR_ROOT</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
                                                                <action>refresh:BR_SB</action>
                                                        </comboboxtext>
                                                </hbox>
                                                <hbox><text width-request="55" space-expand="false"><label>swap:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                        <variable>BR_SWAP</variable>
                                                                <input>echo "$BR_SWAP"</input>
	                                                        <input>echo "$BR_PARTS" | hide_used_parts</input>
                                                                <input>if [ -n "$BR_SWAP" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_BOOT</action><action>refresh:BR_ESP</action>
                                                                <action>refresh:BR_SB</action>
			                                </comboboxtext>
                                                </hbox>

                                                <hbox><text width-request="56" space-expand="false"><label>Other:</label></text>
                                                        <entry tooltip-text="Set other partitions (mountpoint=device e.g /var=/dev/sda3). If you want spaces in mountpoints replace them with //">
                                                                <variable>BR_OTHER_PARTS</variable>
                                                                <action>refresh:BR_SB</action>
                                                        </entry>
                                                </hbox>
                                        </vbox>
                                </expander>

                                <expander label="Btrfs subvolumes"><vbox>
                                        <hbox><text width-request="40" space-expand="false"><label>Root:</label></text>
                                                <entry tooltip-text="Set subvolume name for /">
                                                        <variable>BR_ROOT_SUBVOL</variable>
                                                        <action>refresh:BR_SB</action>
                                                </entry>
                                        </hbox>
                                        <hbox><text width-request="40" space-expand="false"><label>Other:</label></text>
                                                <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                        <variable>BR_OTHER_SUBVOLS</variable>
                                                        <action>refresh:BR_SB</action>
                                                </entry>
                                        </hbox>
                                </vbox></expander>
                                </frame>

                                <frame Bootloader:><hbox>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select bootloader">
                                                <variable>ENTRY12</variable>
                                                <item>none</item>
	                                        <item>Grub</item>
	                                        <item>Syslinux</item>
	                                        <item>EFISTUB/efibootmgr</item>
	                                        <item>Systemd/bootctl</item>
                                                <action>refresh:BR_SB</action>
                                                <action condition="command_is_true([ $ENTRY12 = none ] && echo true)">disable:BR_DISK</action>
                                                <action condition="command_is_true([ ! $ENTRY12 = none ] && echo true)">enable:BR_DISK</action>
                                                <action condition="command_is_true([ $ENTRY12 = none ] && echo true)">disable:BR_KL_OPTS</action>
                                                <action condition="command_is_true([ ! $ENTRY12 = none ] && echo true)">enable:BR_KL_OPTS</action>
                                                <action condition="command_is_true([ $ENTRY12 = EFISTUB/efibootmgr ] && echo true)">disable:BR_DISK</action>
                                                <action condition="command_is_true([ $ENTRY12 = Systemd/bootctl ] && echo true)">disable:BR_DISK</action>
                                        </comboboxtext>

                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target disk for bootloader" sensitive="false">
	                                        <variable>BR_DISK</variable>
	                                        <input>scan_disks</input>
                                                <item>"auto (Grub/UEFI only)"</item>
                                                <action>refresh:BR_SB</action>
	                                </comboboxtext>

                                        <entry tooltip-text="Set additional kernel options" sensitive="false">
                                                <variable>BR_KL_OPTS</variable>
                                                <action>refresh:BR_SB</action>
                                        </entry>
                                </hbox></frame>

                                <frame Restore Mode:>
                                        <hbox tooltip-text="Choose a local archive or enter URL">
                                                <entry fs-action="file" fs-title="Select a backup archive">
                                                        <variable>BR_FILE</variable>
                                                        <action>refresh:BR_SB</action>
                                                        <action condition="command_is_true([[ $BR_FILE == /* ]] && echo true)">disable:BR_USERNAME</action>
                                                        <action condition="command_is_true([[ $BR_FILE == /* ]] && echo true)">disable:BR_PASSWORD</action>
                                                        <action condition="command_is_true([[ ! $BR_FILE == /* ]] && echo true)">enable:BR_USERNAME</action>
                                                        <action condition="command_is_true([[ ! $BR_FILE == /* ]] && echo true)">enable:BR_PASSWORD</action>
                                                </entry>
                                                <button tooltip-text="Select archive">
                                                        <input file stock="gtk-open"></input>
                                                        <action>fileselect:BR_FILE</action>
                                                </button>
                                        </hbox>
                                        <expander label="Authentication">
                                                <vbox>
                                                        <hbox><text width-request="86" space-expand="false"><label>Username:</label></text>
                                                                <entry tooltip-text="Set ftp/http username">
                                                                        <variable>BR_USERNAME</variable>
                                                                        <action>refresh:BR_SB</action>
                                                                </entry>
                                                        </hbox>
                                                        <hbox><text width-request="86" space-expand="false"><label>Password:</label></text>
                                                                <entry tooltip-text="Set ftp/http password">
                                                                        <variable>BR_PASSWORD</variable>
                                                                        <action>refresh:BR_SB</action>
                                                                </entry>
                                                        </hbox>
                                                        <hbox><text width-request="86" space-expand="false"><label>Passphrase:</label></text>
                                                                <entry tooltip-text="Set passphrase for decryption">
                                                                        <variable>BR_PASSPHRASE</variable>
                                                                        <action>refresh:BR_SB</action>
                                                                </entry>
                                                        </hbox>
                                                </vbox>
                                        </expander>
                                        <variable>FRM</variable>
                                </frame>

                                <frame Transfer Mode:>
                                        <checkbox tooltip-text="Activate Tranfer Mode">
                                                <label>Activate</label>
                                                <variable>ENTRY13</variable>
                                                <action>if true disable:FRM</action>
                                                <action>if false enable:FRM</action>
                                                <action>if true enable:ENTRY14</action>
                                                <action>if true enable:ENTRY21</action>
                                                <action>if false disable:ENTRY14</action>
                                                <action>if false disable:ENTRY21</action>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>
                                        <checkbox sensitive="false" tooltip-text="Transfer only hidden files and folders from /home">
                                                <label>"Only hidden files and folders from /home"</label>
                                                <variable>ENTRY14</variable>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>
                                        <checkbox sensitive="false" tooltip-text="Override the default rsync options with user options">
                                                <label>Override</label>
                                                <variable>ENTRY21</variable>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>
                                </frame>

                               <text xalign="0"><label>Additional options:</label></text>
                                <comboboxentry tooltip-text="Set extra tar/rsync options. See tar --help  or rsync --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_TR_OPTIONS</variable>
                                        <item>--acls --xattrs</item>
                                        <action>refresh:BR_SB</action>
                                </comboboxentry>

                                <vbox>
                                        <checkbox tooltip-text="Make tar/rsync output verbose">
                                                <label>Verbose</label>
                                                <variable>ENTRY15</variable>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>

                                        <checkbox tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                                <label>Disable genkernel</label>
                                                <variable>ENTRY18</variable>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>

                                        <checkbox tooltip-text="Dont check if root partition is empty (dangerous)">
                                                <label>Dont check root</label>
                                                <variable>ENTRY19</variable>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>

                                        <checkbox tooltip-text="Ignore UEFI environment">
                                                <label>Bios</label>
                                                <variable>ENTRY20</variable>
                                                <action>refresh:BR_SB</action>
                                        </checkbox>
                                </vbox>
			</vbox>

                        <vbox>
                                <vbox>
                                        <frame Process:>
                                                <text xalign="0" wrap="false">
                                                        <input file>/tmp/wr_proc</input>
                                                        <variable>BR_PROC</variable>
                                                </text>
                                        </frame>
                                </vbox>

                                <frame Output:>
                                        <vbox scrollable="true" shadow-type="0">
                                                <text xalign="0" wrap="false" auto-refresh="true">
                                                        <input file>/tmp/wr_log</input>
                                                </text>
                                        </vbox>
                                </frame>
                                <button tooltip-text="Show scripts log">
                                        <label>Show log</label>
                                        <variable>BTN_LOG</variable>
                                        <action>full_log</action>
                                </button>
                        </vbox>

                        <variable>BR_MODE</variable>
                        <input>echo "2"</input>
                        <action signal="button-release-event">refresh:BR_SB</action>
                        <action signal="key-release-event">refresh:BR_SB</action>
		</notebook>

                <hbox homogeneous="true" space-expand="true">
                        <button tooltip-text="Run generated command">
                                <input file icon="gtk-ok"></input>
                                <label>RUN</label>
                                <variable>BTN_RUN</variable>
                                <action>set_args && run_main &</action>
                                <action>refresh:BR_MODE</action>
                                <action>disable:BTN_RUN</action>
                                <action>disable:BTN_EXIT</action>
                                <action>disable:BTN_LOG</action>
                                <action>enable:BTN_CANCEL</action>
                        </button>
                        <button tooltip-text="Kill the process" sensitive="false">
                                <input file icon="gtk-cancel"></input>
                                <variable>BTN_CANCEL</variable>
                                <label>CANCEL</label>
                                <action>cancel_proc</action>
                        </button>
                        <button tooltip-text="Exit">
                                <variable>BTN_EXIT</variable>
                                <input file icon="gtk-close"></input>
                                <label>EXIT</label>
                        </button>
                </hbox>
                <statusbar has-resize-grip="false">
			<variable>BR_SB</variable>
			<input>set_args && status_bar</input>
		</statusbar>
        </vbox>
</window>
'

gtkdialog --program=MAIN_DIALOG

clean_files

if [ -n "$force_bash" ]; then
  ln -sf /bin/dash /bin/sh
fi
