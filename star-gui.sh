#!/bin/bash

cd $(dirname $0)

scan_parts() {
  for f in $(find /dev -regex "/dev/[vhs]d[a-z][0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done | sort
  for f in $(find /dev/mapper/ | grep '-'); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+p[0-9]+"); do echo "$f $(lsblk -d -n -o size $f) $(blkid -s TYPE -o value $f)"; done
}

scan_disks() {
  for f in /dev/[vhs]d[a-z]; do echo "$f $(lsblk -d -n -o size $f)"; done
  for f in $(find /dev -regex "^/dev/md[0-9]+$"); do echo "$f $(lsblk -d -n -o size $f)"; done
  for f in $(find /dev -regex "/dev/mmcblk[0-9]+"); do echo "$f $(lsblk -d -n -o size $f)"; done
}

fun_run() {
  if [[ ! "$BR_NAME" == Backup-$(hostname)-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]]; then
    ARG1="-f"
  else
    unset BR_NAME
  fi

  if [ "$ENTRY1" = "Only hidden files and folders" ]; then
    ARG2="-h"
  elif [ "$ENTRY1" = "Exclude" ]; then
    ARG2="-hn"
  fi

  if [ "$ENTRY2" = "openssl" ] || [ "$ENTRY2" = "gpg" ]; then ARG3="-E $ENTRY2"; fi
  if [ ! "$ENTRY2" = "none" ]; then ARG4="-P"; fi
  if [ -n "$BR_OPTIONS" ]; then ARG5="-u"; fi
  if [ "$ENTRY3" = "true" ]; then ARG6="-m"; fi
  if [ "$ENTRY4" = "true" ]; then ARG7="-v"; fi
  if [ "$ENTRY5" = "true" ]; then ARG8="-s"; fi
  if [ "$ENTRY6" = "true" ]; then ARG9="-N"; fi
  if [ "$ENTRY7" = "true" ]; then ARG10="-g"; fi
  if [ "$ENTRY8" = "true" ]; then ARG11="-H"; fi
  if [ "$ENTRY9" = "true" ]; then ARG12="-r"; fi
  if [ "$ENTRY10" = "true" ]; then ARG13="-o"; fi
  if [ "$ENTRY11" = "true" ]; then ARG14="-D"; fi
  if [ ! "$BR_BOOT" = "" ]; then ARG15="-b"; fi
  if [ ! "$BR_HOME" = "" ]; then ARG16="-h"; fi
  if [ ! "$BR_ESP" = "" ]; then ARG17="-e"; fi
  if [ ! "$BR_SWAP" = "" ]; then ARG18="-s"; fi
  if [ -n "$BR_OTHER_PARTS" ]; then ARG19="-c"; fi

  if [ "$ENTRY12" = "Grub" ]; then
    ARG20="-g"
  elif [ "$ENTRY12" = "Syslinux" ]; then
    ARG20="-S"
  fi

  if [ -n "$BR_SL_OPTS" ]; then ARG21="-k"; fi
  if [ -n "$BR_USERNAME" ]; then ARG22="-n"; fi
  if [ -n "$BR_PASSWORD" ]; then ARG23="-p"; fi
  if [ -n "$BR_PASSPHRASE" ]; then ARG24="-P"; fi
  if [ -n "$BR_ROOT_SUBVOL" ]; then ARG25="-R"; fi
  if [ -n "$BR_OTHER_SUBVOLS" ]; then ARG26="-O"; fi
  if [ -n "$BR_TR_OPTIONS" ]; then ARG27="-u"; fi
  if [ "$ENTRY15" = "true" ]; then ARG28="-v"; fi
  if [ "$ENTRY16" = "true" ]; then ARG29="-N"; fi
  if [ "$ENTRY17" = "true" ]; then ARG30="-H"; fi
  if [ "$ENTRY18" = "true" ]; then ARG31="-D"; fi
  if [ "$ENTRY19" = "true" ]; then ARG32="-d"; fi
  if [ "$ENTRY20" = "true" ]; then ARG33="-B"; fi
  if [ "$ENTRY14" = "true" ]; then ARG34="-o"; fi
  if [ "$ENTRY21" = "true" ]; then ARG35="-x"; fi

  if [ "$BR_MODE" = "0" ]; then
    xterm -hold -e sudo ./backup.sh -i cli -d "$BR_DIR" -c $BR_COMP  $ARG1 "$BR_NAME" $ARG2 $ARG3 $ARG4 "$BR_PASS" $ARG5 "$BR_OPTIONS" $ARG6 $ARG7 $ARG8 $ARG9 $ARG10 $ARG11 $ARG12 $ARG13 $ARG14
  elif [ "$BR_MODE" = "1" ] && [ "$ENTRY13" = "false" ]; then
    xterm -hold -e sudo ./restore.sh -i cli -r $BR_ROOT -m "$BR_MN_OPTS" -f "$BR_FILE" $ARG15 $BR_BOOT $ARG16 $BR_HOME $ARG17 $BR_ESP $ARG18 $BR_SWAP $ARG19 "$BR_OTHER_PARTS" $ARG20 $BR_DISK $ARG21 "$BR_SL_OPTS" $ARG22 "$BR_USERNAME" $ARG23 "$BR_PASSWORD" $ARG24 "$BR_PASSPHRASE" $ARG25 "$BR_ROOT_SUBVOL" $ARG26 "$BR_OTHER_SUBVOLS" $ARG27 "$BR_TR_OPTIONS" $ARG28 $ARG29 $ARG30 $ARG31 $ARG32 $ARG33
  elif [ "$BR_MODE" = "1" ] && [ "$ENTRY13" = "true" ]; then
    xterm -hold -e sudo  ./restore.sh -i cli -r $BR_ROOT -m "$BR_MN_OPTS" -t $ARG15 $BR_BOOT $ARG16 $BR_HOME $ARG17 $BR_ESP $ARG18 $BR_SWAP $ARG19 "$BR_OTHER_PARTS" $ARG20 $BR_DISK $ARG21 "$BR_SL_OPTS" $ARG25 "$BR_ROOT_SUBVOL" $ARG26 "$BR_OTHER_SUBVOLS" $ARG27 "$BR_TR_OPTIONS" $ARG28 $ARG29 $ARG30 $ARG31 $ARG32 $ARG33 $ARG34 $ARG35
  fi
}

export -f scan_parts
export -f scan_disks
export -f fun_run

export MAIN_DIALOG='

<window title="System Tar & Restore" icon-name="applications-system">
        <vbox scrollable="true" height="697" width="369">
                <notebook labels="Backup|Restore/Transfer">
                        <vbox>

                                <text use-markup="true"><label>"<span  weight='"'bold'"'>Make a tar backup image of this system.</span>"</label></text>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Filename</span>"</label></text>
                                <entry tooltip-text="Set backup archive name">
                                        <input>echo "Backup-$(hostname)-$(date +%d-%m-%Y-%T)"</input>
                                        <variable>BR_NAME</variable>
                                </entry>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Destination</span>"</label></text>
                                <hbox tooltip-text="Choose where to save the backup archive">
                                        <entry accept="directory">
                                                <input>echo ~</input>
                                                <variable>BR_DIR</variable>
                                        </entry>
                                        <button>
                                                <input file stock="gtk-open"></input>
                                                <action type="fileselect">BR_DIR</action>
                                        </button>
                                 </hbox>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Home directory options</span>"</label></text>
                                <comboboxtext tooltip-text="Choose what to do with your /home directory">
                                        <variable>ENTRY1</variable>
                                        <item>Include</item>
	                                <item>Only hidden files and folders</item>
	                                <item>Exclude</item>
                                </comboboxtext>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Compression</span>"</label></text>
                                <comboboxtext tooltip-text="Select compressor">
	                                <variable>BR_COMP</variable>
	                                <item>gzip</item>
	                                <item>bzip2</item>
	                                <item>xz</item>
                                        <item>none</item>
	                        </comboboxtext>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Encryption</span>"</label></text>
                                <vbox>
                                        <frame Method:>
                                                <comboboxtext tooltip-text="Select encryption method">
	                                                <variable>ENTRY2</variable>
                                                        <item>none</item>
	                                                <item>openssl</item>
	                                                <item>gpg</item>
                                                </comboboxtext>
                                        </frame>
                                        <frame Passphrase:>
                                                <entry tooltip-text="Set passphrase for encryption">
                                                        <variable>BR_PASS</variable>
                                                </entry>
                                        </frame>
                                </vbox>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Additional tar options</span>"</label></text>
                                <entry tooltip-text="Set extra tar options. See tar --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_OPTIONS</variable>
                                </entry>

                                <expander label="Advanced"><vbox>
                                        <checkbox tooltip-text="Check to enable multi-core compression via pigz, pbzip2 or pxz">
                                                <label>Enable multi-core compression</label>
                                                <variable>ENTRY3</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to make tar output verbose">
                                                <label>Verbose</label>
                                                <variable>ENTRY4</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to exclude sockets">
                                                <label>Exclude sockets</label>
                                                <variable>ENTRY5</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to disable colors">
                                                <label>Disable colors</label>
                                                <variable>ENTRY6</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to generate configuration file in case of successful backup">
                                                <label>Generate backup.conf</label>
                                                <variable>ENTRY7</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Hide the cursor when running archiver (useful for some terminal emulators)">
                                                <label>Hide cursor</label>
                                                <variable>ENTRY8</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to remove older backups in the destination directory">
                                                <label>Remove older backups</label>
                                                <variable>ENTRY9</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to override the default tar options with user options">
                                                <label>Override</label>
                                                <variable>ENTRY10</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to disable genkernel check in gentoo">
                                                <label>Disable genkernel</label>
                                                <variable>ENTRY11</variable>
                                        </checkbox>
                                </vbox></expander>
                        </vbox>

                        <vbox>

                                <text use-markup="true"><label>"<span  weight='"'bold'"'>Restore a backup image or transfer this system in user defined partitions.</span>"</label></text>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Target Partitions</span>"</label></text>
                                <hbox>
                                        <frame Root:>
		                                <comboboxtext tooltip-text="Select target root partition">
	                                                <variable>BR_ROOT</variable>
	                                                <input>scan_parts</input>
			                        </comboboxtext>
                                                <entry tooltip-text="Set comma-separated list of mount options for the root partition">
                                                        <variable>BR_MN_OPTS</variable>
                                                        <input>echo "defaults,noatime"</input>
                                                </entry>
                                        </frame>
                                </hbox>
                                <expander label="More">
                                        <vbox>
                                                <hbox>
                                                        <frame /boot:>
		                                                <comboboxtext tooltip-text="(Optional) Select target /boot partition">
                                                                        <default>""</default>
	                                                                <variable>BR_BOOT</variable>
                                                                        <item>""</item>
	                                                                <input>scan_parts</input>
			                                        </comboboxtext>
                                                        </frame>
                                                </hbox>
                                                <hbox>
                                                        <frame /boot/efi:>
		                                                <comboboxtext tooltip-text="(UEFI only) Select target ESP partition">
                                                                        <default>""</default>
	                                                                <variable>BR_ESP</variable>
                                                                        <item>""</item>
	                                                                <input>scan_parts</input>
			                                        </comboboxtext>
                                                        </frame>
                                                </hbox>
                                                <hbox>
                                                        <frame /home:>
		                                                <comboboxtext tooltip-text="(Optional) Select target /home partition">
                                                                        <default>""</default>
	                                                                <variable>BR_HOME</variable>
                                                                        <item>""</item>
	                                                                <input>scan_parts</input>
			                                        </comboboxtext>
                                                        </frame>
                                                </hbox>
                                                <hbox>
                                                        <frame swap:>
		                                                <comboboxtext tooltip-text="(Optional) Select target swap partition">
                                                                        <default>""</default>
	                                                                <variable>BR_SWAP</variable>
                                                                        <item>""</item>
	                                                                <input>scan_parts</input>
			                                        </comboboxtext>
                                                        </frame>
                                                </hbox>
                                                <hbox>
                                                        <frame Other partitions:>
                                                                <entry tooltip-text="Set other partitions (mountpoint=device e.g /var=/dev/sda3). If you want spaces in mountpoints replace them with //">
                                                                        <variable>BR_OTHER_PARTS</variable>
                                                                </entry>
                                                        </frame>
                                                </hbox>
                                        </vbox>
                                </expander>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Bootloader and target disk</span>"</label></text>
                                <hbox>
                                        <frame Bootloader:>
                                                <comboboxtext tooltip-text="Select bootloader">
                                                        <variable>ENTRY12</variable>
                                                        <item>none</item>
	                                                <item>Grub</item>
	                                                <item>Syslinux</item>
                                                </comboboxtext>
                                                <entry tooltip-text="Set additional kernel options (Syslinux only)">
                                                        <variable>BR_SL_OPTS</variable>
                                                </entry>
                                        </frame>
                                        <frame Disk:>
                                                <comboboxtext tooltip-text="Select target disk for bootloader">
                                                        <default>""</default>
	                                                <variable>BR_DISK</variable>
	                                                <input>scan_disks</input>
                                                        <item>""</item>
			                        </comboboxtext>
                                        </frame>
                                </hbox>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Mode</span>"</label></text>
                                <frame Restore:>
                                        <hbox tooltip-text="Choose a local archive or enter URL">
                                                <entry accept="file">
                                                        <variable>BR_FILE</variable>
                                                </entry>
                                                <button>
                                                        <variable>BTN</variable>
                                                        <input file stock="gtk-open"></input>
                                                        <action type="fileselect">BR_FILE</action>
                                                </button>
                                        </hbox>
                                        <expander label="Authentication">
                                                <vbox>
                                                        <frame Username:>
                                                                <entry tooltip-text="Set ftp/http username">
                                                                        <variable>BR_USERNAME</variable>
                                                                </entry>
                                                        </frame>
                                                        <frame Password:>
                                                                <entry tooltip-text="Set ftp/http password">
                                                                        <variable>BR_PASSWORD</variable>
                                                                </entry>
                                                        </frame>
                                                        <frame Passphrase:>
                                                                <entry tooltip-text="Set passphrase for decryption">
                                                                        <variable>BR_PASSPHRASE</variable>
                                                                </entry>
                                                        </frame>
                                                </vbox>
                                                <variable>EXP</variable>
                                        </expander>
                                </frame>
                                <frame Transfer:>
                                        <checkbox tooltip-text="Activate Tranfer Mode">
                                                <label>Activate</label>
                                                <variable>ENTRY13</variable>
                                                <action>if true disable:BTN</action>
                                                <action>if true disable:BR_FILE</action>
                                                <action>if true disable:EXP</action>
                                                <action>if false enable:BTN</action>
                                                <action>if false enable:BR_FILE</action>
                                                <action>if false enable:EXP</action>
                                        </checkbox>
                                        <checkbox tooltip-text="Transfer only hidden files and folders from /home">
                                                <label>"Only hidden files and folders from /home"</label>
                                                <variable>ENTRY14</variable>
                                        </checkbox>
                                </frame>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Btrfs Subvolumes</span>"</label></text>
                                <hbox>
                                        <frame Root subvolume:>
                                                <entry tooltip-text="Set subvolume name for /">
                                                        <variable>BR_ROOT_SUBVOL</variable>
                                                </entry>
                                        </frame>
                                        <frame Other subvolumes:>
                                                <entry tooltip-text="Set other subvolumes (subvolume path e.g /home /var /usr ...)">
                                                        <variable>BR_OTHER_SUBVOLS</variable>
                                                </entry>
                                        </frame>
                                </hbox>

                                <text use-markup="true"><label>"<span color='"'brown'"'>Additional tar/rsync options</span>"</label></text>
                                <entry tooltip-text="Set extra tar/rsync options. See tar --help  or rsync --help for more info. If you want spaces in names replace them with //">
                                        <variable>BR_TR_OPTIONS</variable>
                                </entry>

                                <expander label="Advanced"><vbox>
                                        <checkbox tooltip-text="Check to make tar/rsync output verbose">
                                                <label>Verbose</label>
                                                <variable>ENTRY15</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to disable colors">
                                                <label>Disable colors</label>
                                                <variable>ENTRY16</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Hide the cursor when running archiver (useful for some terminal emulators)">
                                                <label>Hide cursor</label>
                                                <variable>ENTRY17</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to disable genkernel check and initramfs building in gentoo">
                                                <label>Disable genkernel</label>
                                                <variable>ENTRY18</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Dont check if root partition is empty (dangerous)">
                                                <label>Dont check root</label>
                                                <variable>ENTRY19</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to ignore UEFI environment">
                                                <label>Bios</label>
                                                <variable>ENTRY20</variable>
                                        </checkbox>

                                        <checkbox tooltip-text="Check to override the default rsync options with user options">
                                                <label>Override</label>
                                               <variable>ENTRY21</variable>
                                        </checkbox>
                                </vbox></expander>

			</vbox>

                        <variable>BR_MODE</variable>

		</notebook>
                <hbox space-expand="true">
                        <button tooltip-text="Run generated command in xterm">
                                <input file icon="gtk-ok"></input>
                                <label>RUN</label>
                                <action>fun_run</action>
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
