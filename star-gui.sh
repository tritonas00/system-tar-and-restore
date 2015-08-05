#!/bin/bash

cd $(dirname $0)

if [ -f /etc/backup.conf ]; then
  source /etc/backup.conf
elif [ -f ~/.backup.conf ]; then
  source ~/.backup.conf
fi

if [ -n "$BRNAME" ]; then export BRNAME; else BRNAME="Backup-$(hostname)-$(date +%d-%m-%Y-%T)"; fi
if [ -n "$BRFOLDER" ]; then export BRFOLDER; else BRFOLDER=$(echo ~); fi
if [ -n "$BRcompression" ]; then export BRcompression; else BRcompression="gzip"; fi
if [ -n "$BRencmethod" ]; then export BRencmethod; else BRencmethod="none"; fi
if [ -n "$BRencpass" ]; then export BRencpass; fi
if [ -n "$BR_USER_OPTS" ]; then export BR_USER_OPTS; fi
if [ -n "$BRmcore" ]; then export ENTRY3="true"; else export ENTRY3="false"; fi
if [ -n "$BRverb" ]; then export ENTRY4="true"; else export ENTRY4="false"; fi
if [ -n "$BRnosockets" ]; then export ENTRY5="true"; else export ENTRY5="false"; fi
if [ -n "$BRnocolor" ]; then export ENTRY6="true"; else export ENTRY6="false"; fi
if [ -n "$BRhide" ]; then export ENTRY8="true"; else export ENTRY8="false"; fi
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
  if [ -n "$BRencpass" ]; then echo '<default>'"$BRencpass"'</default>'; fi
}

set_default_opts() {
  if [ -n "$BR_USER_OPTS" ]; then echo '<default>'"$BR_USER_OPTS"'</default>'; fi
}

scan_parts() {
  for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(lsblk -d -n -o fstype $f)"; done | sort
  for f in $(find /dev/mapper/ | grep '-'); do echo "$f $(lsblk -d -n -o size $f) $(lsblk -d -n -o fstype $f)"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f) $(lsblk -d -n -o fstype $f)"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(lsblk -d -n -o fstype $f)"; done
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
  touch /tmp/empty

  if [[ ! "$BR_NAME" == Backup-$(hostname)-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
    BACKUP_ARGS+=(-f "$BR_NAME")
  fi

  if [ "$ENTRY1" = "Only hidden files and folders" ]; then
    BACKUP_ARGS+=(-h)
  elif [ "$ENTRY1" = "Exclude" ]; then
    BACKUP_ARGS+=(-hn)
  fi

  if [ "$ENTRY2" = "openssl" ] || [ "$ENTRY2" = "gpg" ]; then
    BACKUP_ARGS+=(-E "$ENTRY2")
  fi

  if [ -n "$BR_PASS" ]; then BACKUP_ARGS+=(-P "$BR_PASS"); fi
  if [ -n "$BR_OPTIONS" ]; then BACKUP_ARGS+=(-u "$BR_OPTIONS"); fi

  if [ "$ENTRY3" = "true" ]; then BACKUP_ARGS+=(-m); fi
  if [ "$ENTRY4" = "true" ]; then BACKUP_ARGS+=(-v); fi
  if [ "$ENTRY5" = "true" ]; then BACKUP_ARGS+=(-s); fi
  if [ "$ENTRY6" = "true" ]; then BACKUP_ARGS+=(-N); fi
  if [ "$ENTRY7" = "true" ]; then BACKUP_ARGS+=(-g); fi
  if [ "$ENTRY8" = "true" ]; then BACKUP_ARGS+=(-H); fi
  if [ "$ENTRY9" = "true" ]; then BACKUP_ARGS+=(-r); fi
  if [ "$ENTRY10" = "true" ]; then BACKUP_ARGS+=(-o); fi
  if [ "$ENTRY11" = "true" ]; then BACKUP_ARGS+=(-D); fi

  if [ ! "$BR_BOOT" = "" ]; then RESTORE_ARGS+=(-b ${BR_BOOT%% *}); fi
  if [ ! "$BR_HOME" = "" ]; then RESTORE_ARGS+=(-h ${BR_HOME%% *}); fi
  if [ ! "$BR_SWAP" = "" ]; then RESTORE_ARGS+=(-s ${BR_SWAP%% *}); fi
  if [ ! "$BR_ESP" = "" ]; then RESTORE_ARGS+=(-e ${BR_ESP%% *}); fi
  if [ -n "$BR_OTHER_PARTS" ]; then RESTORE_ARGS+=(-c "$BR_OTHER_PARTS"); fi

  if [ "$ENTRY12" = "Grub" ]; then
    RESTORE_ARGS+=(-g ${BR_DISK%% *})
  elif [ "$ENTRY12" = "Syslinux" ]; then
    RESTORE_ARGS+=(-S ${BR_DISK%% *})
  fi

  if [ "$ENTRY13" = "false" ]; then
    ttl="Restore"
    RESTORE_ARGS+=(-f "$BR_FILE")
    if [ -n "$BR_USERNAME" ]; then RESTORE_ARGS+=(-n "$BR_USERNAME"); fi
    if [ -n "$BR_PASSWORD" ]; then RESTORE_ARGS+=(-p "$BR_PASSWORD"); fi
    if [ -n "$BR_PASSPHRASE" ]; then RESTORE_ARGS+=(-P "$BR_PASSPHRASE"); fi
  elif [ "$ENTRY13" = "true" ]; then
    ttl="Transfer"
    RESTORE_ARGS+=(-t)
    if [ "$ENTRY14" = "true" ]; then RESTORE_ARGS+=(-o); fi
    if [ "$ENTRY21" = "true" ]; then RESTORE_ARGS+=(-x); fi
  fi

  if [ -n "$BR_SL_OPTS" ]; then RESTORE_ARGS+=(-k "$BR_SL_OPTS"); fi
  if [ -n "$BR_TR_OPTIONS" ]; then RESTORE_ARGS+=(-u "$BR_TR_OPTIONS"); fi
  if [ -n "$BR_ROOT_SUBVOL" ]; then RESTORE_ARGS+=(-R "$BR_ROOT_SUBVOL"); fi
  if [ -n "$BR_OTHER_SUBVOLS" ]; then RESTORE_ARGS+=(-O "$BR_OTHER_SUBVOLS"); fi

  if [ "$ENTRY15" = "true" ]; then RESTORE_ARGS+=(-v); fi
  if [ "$ENTRY16" = "true" ]; then RESTORE_ARGS+=(-N); fi
  if [ "$ENTRY17" = "true" ]; then RESTORE_ARGS+=(-H); fi
  if [ "$ENTRY18" = "true" ]; then RESTORE_ARGS+=(-D); fi
  if [ "$ENTRY19" = "true" ]; then RESTORE_ARGS+=(-d); fi
  if [ "$ENTRY20" = "true" ]; then RESTORE_ARGS+=(-B); fi

  if [ -n "$BR_SHOW" ]; then act="echo"; fi

  if [ "$BR_MODE" = "0" ]; then
    xterm -hold -T Backup -e $act sudo ./backup.sh -i cli -d "$BR_DIR" -c $BR_COMP -C /tmp/empty "${BACKUP_ARGS[@]}"
  elif [ "$BR_MODE" = "1" ]; then
    xterm -hold -T $ttl -e $act sudo ./restore.sh -i cli -r ${BR_ROOT%% *} -m "$BR_MN_OPTS" "${RESTORE_ARGS[@]}"
  fi
}

export -f scan_parts scan_disks set_args hide_used_parts set_default_pass set_default_opts
export BR_ROOT=$(scan_parts | head -n 1)


export MAIN_DIALOG='

<window title="System Tar & Restore" icon-name="applications-system">
        <vbox>
                <notebook labels="Backup|Restore/Transfer">
                        <vbox scrollable="true" shadow-type="0">
                                <text height-request="30" use-markup="true"><label>"<span color='"'brown'"'>Make a tar backup image of this system.</span>"</label></text>

                                <hbox><text width-request="93"><label>Filename:</label></text>
                                <entry tooltip-text="Set backup archive name">
                                        <variable>BR_NAME</variable>
                                        <default>'"$BRNAME"'</default>
                                </entry></hbox>

                                <hbox><text width-request="93"><label>Destination:</label></text>
                                        <entry fs-action="folder" fs-title="Select a directory" tooltip-text="Choose where to save the backup archive">
                                                <variable>BR_DIR</variable>
                                                <default>'"$BRFOLDER"'</default>
                                        </entry>
                                        <button tooltip-text="Select directory">
                                                <input file stock="gtk-open"></input>
                                                <action>fileselect:BR_DIR</action>
                                        </button>
                                 </hbox>

                                <hbox><text width-request="92" space-expand="false"><label>Home directory:</label></text>
                                <comboboxtext space-expand="true" space-fill="true" tooltip-text="Choose what to do with your /home directory">
                                        <variable>ENTRY1</variable>
                                        <default>'"$ENTRY1"'</default>
                                        <item>Include</item>
	                                <item>Only hidden files and folders</item>
	                                <item>Exclude</item>
                                </comboboxtext></hbox>

                                <hbox><text width-request="92" space-expand="false"><label>Compression:</label></text>
                                <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select compressor">
	                                <variable>BR_COMP</variable>
                                        <default>'"$BRcompression"'</default>
	                                <item>gzip</item>
	                                <item>bzip2</item>
	                                <item>xz</item>
                                        <item>none</item>
	                        </comboboxtext></hbox>

                                <vbox><frame Encryption:> 
                                        <hbox><text width-request="86" space-expand="false"><label>Method:</label></text>
                                                <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select encryption method">
	                                                <variable>ENTRY2</variable>
                                                        <default>'"$BRencmethod"'</default>
                                                        <item>none</item>
	                                                <item>openssl</item>
	                                                <item>gpg</item>
                                                </comboboxtext>
                                        </hbox>
                                        <hbox><text width-request="87" space-expand="false"><label>Passphrase:</label></text>
                                                <entry tooltip-text="Set passphrase for encryption">
                                                        <variable>BR_PASS</variable>
                                                        '"`set_default_pass`"'
                                                </entry>
                                        </hbox>
                                </frame></vbox>

                                <text xalign="0"><label>Additional options:</label></text>
                                <comboboxentry tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_OPTIONS</variable>
                                       '"`set_default_opts`"'
                                        <item>--acls --xattrs</item>
                                </comboboxentry>
                                
                                <checkbox tooltip-text="Enable multi-core compression via pigz, pbzip2 or pxz">
                                        <label>Enable multi-core compression</label>
                                        <variable>ENTRY3</variable>
                                        <default>'"$ENTRY3"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Make tar output verbose">
                                        <label>Verbose</label>
                                        <variable>ENTRY4</variable>
                                        <default>'"$ENTRY4"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Exclude sockets">
                                        <label>Exclude sockets</label>
                                        <variable>ENTRY5</variable>
                                        <default>'"$ENTRY5"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Disable colors">
                                        <label>Disable colors</label>
                                        <variable>ENTRY6</variable>
                                        <default>'"$ENTRY6"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Generate configuration file in case of successful backup">
                                        <label>Generate backup.conf</label>
                                        <variable>ENTRY7</variable>
                                </checkbox>

                                <checkbox tooltip-text="Hide the cursor when running archiver (useful for some terminal emulators)">
                                        <label>Hide cursor</label>
                                        <variable>ENTRY8</variable>
                                        <default>'"$ENTRY8"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Remove older backups in the destination directory">
                                        <label>Remove older backups</label>
                                        <variable>ENTRY9</variable>
                                        <default>'"$ENTRY9"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Override the default tar options with user options">
                                        <label>Override</label>
                                        <variable>ENTRY10</variable>
                                        <default>'"$ENTRY10"'</default>
                                </checkbox>

                                <checkbox tooltip-text="Disable genkernel check in gentoo">
                                        <label>Disable genkernel</label>
                                        <variable>ENTRY11</variable>
                                        <default>'"$ENTRY11"'</default>
                                </checkbox>
                               
                        </vbox>

                        <vbox scrollable="true" shadow-type="0" height="560" width="435">
                                <text wrap="false" height-request="30" use-markup="true"><label>"<span color='"'brown'"'>Restore a backup image or transfer this system in user defined partitions.</span>"</label></text>

                                <frame Target partitions:>
                                <hbox><text width-request="30" space-expand="false"><label>Root:</label></text>

		                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target root partition">
	                                        <variable>BR_ROOT</variable>
                                                <input>echo "$BR_ROOT"</input>
	                                        <input>scan_parts | hide_used_parts</input>
                                                <action>refresh:BR_BOOT</action><action>refresh:BR_HOME</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
			                </comboboxtext>
                                        <entry tooltip-text="Set comma-separated list of mount options for the root partition">
                                                <variable>BR_MN_OPTS</variable>
                                                <input>echo "defaults,noatime"</input>
                                        </entry>
                                </hbox>

                                <expander label="More">
                                        <vbox>
                                                <hbox><text width-request="55" space-expand="false"><label>/boot:</label></text>        
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /boot partition">
	                                                        <variable>BR_BOOT</variable>
                                                                <input>echo "$BR_BOOT"</input>
	                                                        <input>scan_parts | hide_used_parts</input>
                                                                <input>if [ -n "$BR_BOOT" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
			                                </comboboxtext>
                                                </hbox>
                                                <hbox><text width-request="55" space-expand="false"><label>/boot/efi:</label></text>                 
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(UEFI only) Select target ESP partition">
	                                                        <variable>BR_ESP</variable>
                                                                <input>echo "$BR_ESP"</input>
	                                                        <input>scan_parts | hide_used_parts</input>
                                                                <input>if [ -n "$BR_ESP" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_BOOT</action><action>refresh:BR_SWAP</action>
			                                </comboboxtext>
                                                </hbox>
                                                <hbox><text width-request="55" space-expand="false"><label>/home:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target /home partition">
	                                                        <variable>BR_HOME</variable>
                                                                <input>echo "$BR_HOME"</input>
	                                                        <input>scan_parts | hide_used_parts</input>
                                                                <input>if [ -n "$BR_HOME" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_BOOT</action><action>refresh:BR_ROOT</action><action>refresh:BR_SWAP</action><action>refresh:BR_ESP</action>
         	                                        </comboboxtext>
                                                </hbox>
                                                <hbox><text width-request="55" space-expand="false"><label>swap:</label></text>
		                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="(Optional) Select target swap partition">
	                                                        <variable>BR_SWAP</variable>
                                                                <input>echo "$BR_SWAP"</input>
	                                                        <input>scan_parts | hide_used_parts</input>
                                                                <input>if [ -n "$BR_SWAP" ]; then echo ""; fi</input>
                                                                <action>refresh:BR_ROOT</action><action>refresh:BR_HOME</action><action>refresh:BR_BOOT</action><action>refresh:BR_ESP</action>
			                                </comboboxtext>
                                                </hbox>

                                                <hbox><text width-request="56" space-expand="false"><label>Other:</label></text>
                                                        <entry tooltip-text="Set other partitions (mountpoint=device e.g /var=/dev/sda3). If you want spaces in mountpoints replace them with //">
                                                                <variable>BR_OTHER_PARTS</variable>
                                                        </entry>
                                                </hbox>
                                               
                                        </vbox>
                                </expander></frame>

                                <frame Bootloader:><hbox>
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select bootloader">
                                                <variable>ENTRY12</variable>
                                                <item>none</item>
	                                        <item>Grub</item>
	                                        <item>Syslinux</item>
                                        </comboboxtext>
                                                     
                                        <comboboxtext space-expand="true" space-fill="true" tooltip-text="Select target disk for bootloader">
                                                <default>""</default>
	                                        <variable>BR_DISK</variable>
	                                        <input>scan_disks</input>
                                                <item>""</item>
	                                </comboboxtext>
                                       
                                        <entry tooltip-text="Set additional kernel options (Syslinux only)">
                                                <variable>BR_SL_OPTS</variable>
                                        </entry>
                                </hbox></frame>

                                <frame Restore Mode:>
                                        <hbox tooltip-text="Choose a local archive or enter URL">
                                                <entry fs-action="file" fs-title="Select a backup archive">
                                                        <variable>BR_FILE</variable>
                                                </entry>
                                                <button tooltip-text="Select archive">
                                                        <variable>BTN</variable>
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
                                                        <hbox><text width-request="86" space-expand="false"><label>Passphrase:</label></text>
                                                                <entry tooltip-text="Set passphrase for decryption">
                                                                        <variable>BR_PASSPHRASE</variable>
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
                                        </checkbox>
                                        <checkbox sensitive="false" tooltip-text="Transfer only hidden files and folders from /home">
                                                <label>"Only hidden files and folders from /home"</label>
                                                <variable>ENTRY14</variable>
                                        </checkbox>
                                        <checkbox sensitive="false" tooltip-text="Override the default rsync options with user options">
                                                <label>Override</label>
                                               <variable>ENTRY21</variable>
                                        </checkbox>
                                </frame>

                                <frame Btrfs subvolumes:>
                                        <hbox><text width-request="40" space-expand="false"><label>Root:</label></text>
                                                <entry tooltip-text="Set subvolume name for /">
                                                        <variable>BR_ROOT_SUBVOL</variable>
                                                </entry>
                                        </hbox>
                                        <hbox><text width-request="40" space-expand="false"><label>Other:</label></text>
                                                <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                        <variable>BR_OTHER_SUBVOLS</variable>
                                                </entry>
                                        </hbox>
                                </frame>
                               
                               <text xalign="0"><label>Additional options:</label></text>
                                <comboboxentry tooltip-text="Set extra tar/rsync options. See tar --help  or rsync --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_TR_OPTIONS</variable>
                                        <item>--acls --xattrs</item>
                                </comboboxentry>

                                <vbox>
                                        <checkbox tooltip-text="Make tar/rsync output verbose">
                                                <label>Verbose</label>
                                                <variable>ENTRY15</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Disable colors">
                                                <label>Disable colors</label>
                                                <variable>ENTRY16</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Hide the cursor when running tar/rsync (useful for some terminal emulators)">
                                                <label>Hide cursor</label>
                                                <variable>ENTRY17</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Disable genkernel check and initramfs building in gentoo">
                                                <label>Disable genkernel</label>
                                                <variable>ENTRY18</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Dont check if root partition is empty (dangerous)">
                                                <label>Dont check root</label>
                                                <variable>ENTRY19</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Ignore UEFI environment">
                                                <label>Bios</label>
                                                <variable>ENTRY20</variable>
                                        </checkbox>
                                </vbox>

			</vbox>
                        <variable>BR_MODE</variable>
		</notebook>

                <hbox homogeneous="true" space-expand="true">
                        <button tooltip-text="Run generated command in xterm">
                                <input file icon="gtk-ok"></input>
                                <label>RUN</label>
                                <action>set_args</action>
                        </button>
                        <button tooltip-text="Show generated command in xterm">
                                <input file icon="system-run"></input>
                                <label>SHOW</label>
                                <action>BR_SHOW=y && set_args</action>
                        </button>
                        <button tooltip-text="Exit">
                                <input file icon="gtk-cancel"></input>
                                <label>EXIT</label>
                        </button>
                </hbox>
        </vbox>
</window>
'

gtkdialog --program=MAIN_DIALOG

if [ -f /tmp/empty ]; then rm /tmp/empty; fi
