#!/bin/bash

cd $(dirname $0)

clean_tmp_files() {
  if [ -f /tmp/wr_proc ]; then rm /tmp/wr_proc; fi
  if [ -f /tmp/wr_log ]; then rm /tmp/wr_log; fi
  if [ -f /tmp/wr_pid ]; then rm /tmp/wr_pid; fi
}

clean_tmp_files

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
if [ -n "$BRmcore" ]; then export ENTRY2="true"; else export ENTRY2="false"; fi
if [ -n "$BRclean" ]; then export ENTRY4="true"; else export ENTRY4="false"; fi
if [ -n "$BRoverride" ]; then export ENTRY5="true"; else export ENTRY5="false"; fi
if [ -n "$BRgenkernel" ]; then export ENTRY6="true"; else export ENTRY6="false"; fi

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
  if [ "$BR_TAB" = "0" ]; then
    SCR_MODE=0

    if [ -n "$BRFOLDER" ]; then SCR_ARGS=(-d "$BRFOLDER"); fi
    if [ -n "$BRcompression" ]; then SCR_ARGS+=(-c "$BRcompression"); fi

    if [ -n "$BRNAME" ] && [[ ! "$BRNAME" == Backup-$(hostname)-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
      SCR_ARGS+=(-n "$BRNAME")
    fi

    if [ "$ENTRY1" = "Only hidden files and folders" ]; then
      SCR_ARGS+=(-H)
    elif [ "$ENTRY1" = "Exclude" ]; then
      SCR_ARGS+=(-HN)
    fi

    if [ ! "$BRencmethod" = "none" ]; then
      SCR_ARGS+=(-E "$BRencmethod")
      if [ -n "$BRencpass" ]; then SCR_ARGS+=(-P "$BRencpass"); fi
    else
      unset BRencpass
    fi

    for i in ${BR_EXC[@]}; do BR_USER_OPTS="$BR_USER_OPTS --exclude=$i"; done # Add excludes to main options array
    if [ -n "$BR_USER_OPTS" ]; then SCR_ARGS+=(-u "$BR_USER_OPTS"); fi

    if [ "$ENTRY2" = "true" ] && [ ! "$BRcompression" = "none" ]; then SCR_ARGS+=(-M); fi
    if [ "$ENTRY3" = "true" ]; then SCR_ARGS+=(-g); fi
    if [ "$ENTRY4" = "true" ]; then SCR_ARGS+=(-a); fi
    if [ "$ENTRY5" = "true" ]; then SCR_ARGS+=(-o); fi
    if [ "$ENTRY6" = "true" ]; then SCR_ARGS+=(-D); fi

  elif [ "$BR_TAB" = "1" ]; then
    unset BRencmethod BRencpass BR_USER_OPTS # Dont use exported vars from backup.conf
    SCR_ARGS=(-r ${BR_ROOT%% *})

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

    if [ "$ENTRY8" = "false" ]; then
      SCR_MODE=1
      SCR_ARGS+=(-f "$BR_FILE")
      if [ -n "$BR_USERNAME" ] && [[ ! "$BR_FILE" == /* ]]; then SCR_ARGS+=(-y "$BR_USERNAME"); fi
      if [ -n "$BR_PASSWORD" ] && [[ ! "$BR_FILE" == /* ]]; then SCR_ARGS+=(-p "$BR_PASSWORD"); fi
      if [ -n "$BR_PASSPHRASE" ]; then SCR_ARGS+=(-P "$BR_PASSPHRASE"); fi
    elif [ "$ENTRY8" = "true" ]; then
      SCR_MODE=2
      if [ "$ENTRY9" = "true" ]; then SCR_ARGS+=(-O); fi
      if [ "$ENTRY10" = "true" ]; then SCR_ARGS+=(-o); fi
    fi

    if [ -n "$BR_MN_OPTS" ]; then SCR_ARGS+=(-m "$BR_MN_OPTS"); fi
    if [ -n "$BR_TR_OPTIONS" ]; then SCR_ARGS+=(-u "$BR_TR_OPTIONS"); fi
    if [ -n "$BR_ROOT_SUBVOL" ]; then SCR_ARGS+=(-R "$BR_ROOT_SUBVOL"); fi
    if [ -n "$BR_OTHER_SUBVOLS" ]; then SCR_ARGS+=(-B "$BR_OTHER_SUBVOLS"); fi

    if [ "$ENTRY11" = "true" ]; then SCR_ARGS+=(-D); fi
    if [ "$ENTRY12" = "true" ]; then SCR_ARGS+=(-x); fi
    if [ "$ENTRY13" = "true" ]; then SCR_ARGS+=(-W); fi
  fi
}

status_bar() {
  if [ $(id -u) -gt 0 ]; then
    echo "Script must run as root"
  elif [ -f /tmp/wr_pid ]; then
    cat /tmp/wr_proc
  else
    echo "Idle"
  fi
}

run_main() {
  setsid ./main.sh -i ${SCR_MODE} -jwq "${SCR_ARGS[@]}" 2> /tmp/wr_log
  
  if [ -f /tmp/wr_pid ]; then rm /tmp/wr_pid; fi
  echo true > /tmp/wr_proc
}

export -f scan_disks hide_used_parts set_default_pass set_default_opts set_default_multi set_args status_bar run_main
export BR_PARTS=$(scan_parts)
export BR_ROOT=$(echo "$BR_PARTS" | head -n 1)

export MAIN_DIALOG='

<window title="System Tar & Restore" icon-name="applications-system" height-request="655" width-request="515">
        <vbox>
                <timer visible="false">
                        <action>refresh:BR_SB</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">enable:BTN_RUN</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">enable:BTN_EXIT</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">enable:BR_TAB</action>
			<action condition="command_is_true([ ! -f /tmp/wr_pid ] && echo true)">disable:BTN_CANCEL</action>
                        <action condition="file_is_true(/tmp/wr_proc)">refresh:BR_TAB</action>
                        <action condition="file_is_true(/tmp/wr_proc)">echo > /tmp/wr_proc</action>
		</timer>
                <notebook labels="Backup|Restore/Transfer|Log" space-expand="true" space-fill="true">
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="30" use-markup="true" tooltip-text="==>Make sure you have enough free space.

==>If you plan to restore in lvm/mdadm/dm-crypt, make
       sure that this system is capable to boot from those
       configurations.

==>The following bootloaders are supported:
       Grub Syslinux EFISTUB/efibootmgr Systemd/bootctl

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
efibootmgr dosfstools systemd"><label>"<span color='"'brown'"'>Make a backup archive of this system.</span>"</label></text>

                                <hbox>
                                        <text width-request="92"><label>Filename:</label></text>
                                        <entry tooltip-text="Set backup archive name">
                                                <variable>BRNAME</variable>
                                                <default>'"$BRNAME"'</default>
                                        </entry>
                                </hbox>

                                <hbox>
                                        <text width-request="92"><label>Destination:</label></text>
                                        <entry fs-action="folder" fs-title="Select a directory" tooltip-text="Choose where to save the backup archive">
                                                <variable>BRFOLDER</variable>
                                                <default>'"$BRFOLDER"'</default>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:BRFOLDER</action>
                                        </button>
                                </hbox>

                                <hbox>
                                        <text width-request="92" space-expand="false"><label>Home directory:</label></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                                <variable>ENTRY1</variable>
                                                <default>'"$ENTRY1"'</default>
                                                <item>Include</item>
	                                        <item>Only hidden files and folders</item>
	                                        <item>Exclude</item>
                                        </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="92" space-expand="false"><label>Compression:</label></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select compressor">
	                                        <variable>BRcompression</variable>
                                                <default>'"$BRcompression"'</default>
	                                        <item>gzip</item>
	                                        <item>bzip2</item>
	                                        <item>xz</item>
                                                <item>none</item>
                                                <action condition="command_is_true([ $BRcompression = none ] && echo true)">disable:ENTRY2</action>
                                                <action condition="command_is_true([ ! $BRcompression = none ] && echo true)">enable:ENTRY2</action>
	                                </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="92" space-expand="false"><label>Encryption:</label></text>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select encryption method">
	                                        <variable>BRencmethod</variable>
                                                <default>'"$BRencmethod"'</default>
                                                <item>none</item>
	                                        <item>openssl</item>
	                                        <item>gpg</item>
                                                <action condition="command_is_true([ $BRencmethod = none ] && echo true)">disable:BRencpass</action>
                                                <action condition="command_is_true([ ! $BRencmethod = none ] && echo true)">enable:BRencpass</action>
                                        </comboboxtext>
                                </hbox>

                                <hbox>
                                        <text width-request="92" space-expand="false"><label>Passphrase:</label></text>
                                        '"`set_default_pass`"'
                                        </entry>
                                </hbox>

                                <text xalign="0"><label>Additional options:</label></text>
                                <comboboxentry tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_USER_OPTS</variable>
                                       '"`set_default_opts`"'
                                        <item>--acls --xattrs</item>
                                </comboboxentry>

                                <text xalign="0"><label>Exclude:</label></text>
                                <entry tooltip-text="Exclude files and directories. If you want spaces in names replace them with //">
                                        <variable>BR_EXC</variable>
                                </entry>

                                '"`set_default_multi`"'
                                        <label>Enable multi-core compression</label>
                                        <variable>ENTRY2</variable>
                                        <default>'"$ENTRY2"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Generate configuration file in case of successful backup">
                                        <label>Generate backup.conf</label>
                                        <variable>ENTRY3</variable>
                                </checkbox>

                                <checkbox tooltip-text="Remove older backups in the destination directory">
                                        <label>Remove older backups</label>
                                        <variable>ENTRY4</variable>
                                        <default>'"$ENTRY4"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Override the default tar options with user options">
                                        <label>Override</label>
                                        <variable>ENTRY5</variable>
                                        <default>'"$ENTRY5"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Disable genkernel check in gentoo">
                                        <label>Disable genkernel</label>
                                        <variable>ENTRY6</variable>
                                        <default>'"$ENTRY6"'</default>
                                </checkbox>
                        </vbox>

                        <vbox scrollable="true" shadow-type="0">
                                <text wrap="false" height-request="30" use-markup="true" tooltip-text="In the first case, you should run it from a LiveCD of the target (backed up) distro.

==>Make sure you have created one target root (/) partition.
       Optionally you can create or use any other partition
       (/boot /home /var etc).

==>Make sure that target LVM volume groups are activated,
       target RAID arrays are properly assembled and target
       encrypted partitions are opened.

==>If you plan to transfer in lvm/mdadm/dm-crypt, make
       sure that this system is capable to boot from those
       configurations."><label>"<span color='"'brown'"'>Restore a backup archive or transfer this system in user defined partitions.</span>"</label></text>

                                <vbox>
                                        <frame Target partitions:>
                                                <hbox>
                                                        <text width-request="30" space-expand="false"><label>Root:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target root partition">
	                                                        <variable>BR_ROOT</variable>
                                                                <input>echo "$BR_ROOT"</input>
	                                                        <input>echo "$BR_PARTS" | bash -c hide_used_parts</input>
                                                                <action>refresh:BR_BOOT</action><action>refresh:BR_HOME</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
			                                </comboboxtext>
                                                        <entry tooltip-text="Set comma-separated list of mount options for the root partition">
                                                                <variable>BR_MN_OPTS</variable>
                                                                <input>echo "defaults,noatime"</input>
                                                        </entry>
                                                </hbox>

                                                <expander label="More partitions">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false"><label>Esp:</label></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional-UEFI only) Select target EFI System Partition">
	                                                                        <variable>BR_ESP</variable>
                                                                                <input>echo "$BR_ESP"</input>
	                                                                        <input>echo "$BR_PARTS" | bash -c hide_used_parts</input>
                                                                                <input>if [ -n "$BR_ESP" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_BOOT</action><action>refresh:BR_SWAP</action>
			                                                </comboboxtext>
                                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select mountpoint">
	                                                                        <variable>BR_ESP_MPOINT</variable>
	                                                                        <item>/boot/efi</item>
	                                                                        <item>/boot</item>
	                                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false"><label>/boot:</label></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                                        <variable>BR_BOOT</variable>
                                                                                <input>echo "$BR_BOOT"</input>
	                                                                        <input>echo "$BR_PARTS" | bash -c hide_used_parts</input>
                                                                                <input>if [ -n "$BR_BOOT" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false"><label>/home:</label></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                                        <variable>BR_HOME</variable>
                                                                                <input>echo "$BR_HOME"</input>
	                                                                        <input>echo "$BR_PARTS" | bash -c hide_used_parts</input>
                                                                                <input>if [ -n "$BR_HOME" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_BOOT</action><action>refresh:BR_ROOT</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
                                                                        </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false"><label>swap:</label></text>
		                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                                        <variable>BR_SWAP</variable>
                                                                                <input>echo "$BR_SWAP"</input>
	                                                                        <input>echo "$BR_PARTS" | bash -c hide_used_parts</input>
                                                                                <input>if [ -n "$BR_SWAP" ]; then echo ""; fi</input>
                                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_BOOT</action><action>refresh:BR_ESP</action>
			                                                </comboboxtext>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="55" space-expand="false"><label>Other:</label></text>
                                                                        <entry tooltip-text="Set other partitions (mountpoint=device e.g /var=/dev/sda3). If you want spaces in mountpoints replace them with //">
                                                                                <variable>BR_OTHER_PARTS</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                                <expander label="Btrfs subvolumes">
                                                        <vbox>
                                                                <hbox>
                                                                        <text width-request="40" space-expand="false"><label>Root:</label></text>
                                                                        <entry tooltip-text="Set subvolume name for /">
                                                                                <variable>BR_ROOT_SUBVOL</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="40" space-expand="false"><label>Other:</label></text>
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
                                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target disk for bootloader" sensitive="false">
	                                                        <variable>BR_DISK</variable>
	                                                        <input>bash -c scan_disks</input>
	                                                </comboboxtext>
                                                        <entry tooltip-text="Set additional kernel options" sensitive="false">
                                                                <variable>BR_KL_OPTS</variable>
                                                        </entry>
                                                </hbox>
                                        </frame>
                                </vbox>

                                <vbox>
                                        <frame Restore Mode:>
                                                <hbox tooltip-text="Choose a local archive or enter URL">
                                                        <entry fs-action="file" fs-title="Select a backup archive">
                                                                <variable>BR_FILE</variable>
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
                                                                        </entry>
                                                                </hbox>
                                                                <hbox><text width-request="86" space-expand="false"><label>Password:</label></text>
                                                                        <entry tooltip-text="Set ftp/http password">
                                                                                <variable>BR_PASSWORD</variable>
                                                                        </entry>
                                                                </hbox>
                                                                <hbox>
                                                                        <text width-request="86" space-expand="false"><label>Passphrase:</label></text>
                                                                        <entry tooltip-text="Set passphrase for decryption">
                                                                                <variable>BR_PASSPHRASE</variable>
                                                                        </entry>
                                                                </hbox>
                                                        </vbox>
                                                </expander>
                                                <variable>FRM</variable>
                                        </frame>
                                </vbox>

                                <vbox>
                                        <frame Transfer Mode:>
                                                <checkbox tooltip-text="Enable Tranfer Mode">
                                                        <label>Enable</label>
                                                        <variable>ENTRY8</variable>
                                                        <action>if true disable:FRM</action>
                                                        <action>if false enable:FRM</action>
                                                        <action>if true enable:ENTRY9</action>
                                                        <action>if true enable:ENTRY10</action>
                                                        <action>if false disable:ENTRY9</action>
                                                        <action>if false disable:ENTRY10</action>
                                                </checkbox>
                                                <checkbox sensitive="false" tooltip-text="Transfer only hidden files and folders from /home">
                                                        <label>"Only hidden files and folders from /home"</label>
                                                        <variable>ENTRY9</variable>
                                                </checkbox>
                                                <checkbox sensitive="false" tooltip-text="Override the default rsync options with user options">
                                                        <label>Override</label>
                                                        <variable>ENTRY10</variable>
                                                </checkbox>
                                        </frame>
                                </vbox>

                                <text xalign="0"><label>Additional options:</label></text>
                                <comboboxentry tooltip-text="Set extra tar/rsync options. See tar --help or rsync --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_TR_OPTIONS</variable>
                                        <item>--acls --xattrs</item>
                                </comboboxentry>

                                <checkbox tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                        <label>Disable genkernel</label>
                                        <variable>ENTRY11</variable>
                                </checkbox>

                                <checkbox tooltip-text="Dont check if root partition is empty (dangerous)">
                                        <label>Dont check root</label>
                                        <variable>ENTRY12</variable>
                                </checkbox>

                                <checkbox tooltip-text="Ignore UEFI environment">
                                        <label>Bios</label>
                                        <variable>ENTRY13</variable>
                                </checkbox>
			</vbox>

                        <vbox scrollable="true" shadow-type="0">
                                <text xalign="0" wrap="false" auto-refresh="true">
                                        <input file>/tmp/wr_log</input>
                                </text>
                        </vbox>
                        <variable>BR_TAB</variable>
                        <input>echo 2</input>
		</notebook>

                <hbox homogeneous="true" space-expand="false" space-fill="false">
                        <button tooltip-text="Run">
                                <input file icon="gtk-ok"></input>
                                <label>RUN</label>
                                <variable>BTN_RUN</variable>
                                <action>bash -c "set_args && run_main &"</action>
                                <action>disable:BTN_RUN</action>
                                <action>disable:BTN_EXIT</action>
                                <action>disable:BR_TAB</action>
                                <action>enable:BTN_CANCEL</action>
                        </button>
                        <button tooltip-text="Kill the process" sensitive="false">
                                <input file icon="gtk-cancel"></input>
                                <variable>BTN_CANCEL</variable>
                                <label>CANCEL</label>
                                <action>kill -9 -$(cat /tmp/wr_pid)</action>
                                <action>echo "Aborted by User" > /tmp/wr_log</action>
                        </button>
                        <button tooltip-text="Exit">
                                <variable>BTN_EXIT</variable>
                                <input file icon="gtk-close"></input>
                                <label>EXIT</label>
                        </button>
                </hbox>

                <statusbar has-resize-grip="false">
			<variable>BR_SB</variable>
			<input>bash -c status_bar</input>
		</statusbar>
        </vbox>
</window>
'

gtkdialog --program=MAIN_DIALOG

clean_tmp_files
