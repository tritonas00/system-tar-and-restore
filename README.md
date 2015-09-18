System Tar & Restore
=================

  * [About](#about)
  * [Distribution Packages](#distribution-packages)
  * [Requirements](#requirements)
  * [Things you can do](#things-you-can-do)
  * [Backup](#backup)
  * [Restore/Transfer](#restoretransfer)
  * [Gui](#gui)
  * [Notes](#notes)
  * [Tested partition schemes](#tested-partition-schemes)
  * [Examples using arguments](#examples-using-arguments)

###ABOUT###

System tar & restore contains two bash scripts, **backup.sh** and **restore.sh**. The former makes a tar backup of your system. The latter restores the backup or transfers your system using rsync in desired partition(s). The scripts include two interfaces, cli and dialog (ncurses).

Supported distributions: Arch, Debian/Ubuntu, Fedora, openSUSE, Gentoo, Mandriva/Mageia          

[Demo Video](https://www.youtube.com/watch?v=xonBVTCxpdc)  
[Stable Releases](https://github.com/tritonas00/system-tar-and-restore/releases)  

### DISTRIBUTION PACKAGES

**Archlinux**  
See the [wiki page](https://wiki.archlinux.org/index.php/System-tar-and-restore).

**Gentoo**  
The package is provided by the <code>gentoo-el</code> overlay. You can install it with the following commands as root. (you need to have `layman` installed and configured)

    layman -a gentoo-el  
    emerge app-backup/system-tar-and-restore

###REQUIREMENTS###

- rsync (for Transfer Mode)
- dialog (for ncurses interface)
- wget   (for downloading backup archives)
- gptfdisk/gdisk (for GPT and Syslinux)
- openssl/gpg (for encryption)

###THINGS YOU CAN DO###

- Full or partial backup
- Restore or transfer to the same or different disk/partition layout.
- Restore or transfer to an external device such as usb flash drive, sd card etc.
- Restore a BIOS-based system to UEFI and vice versa.
- Prepare a system in a virtual machine (such as virtualbox), back it up and restore it in a normal machine.

###BACKUP###

The backup.sh script makes a tar backup of your system. You will be asked for:

- **Destination directory:** Where you want to save the backup. Default is <code>/</code>.
- **Archive name:** A desired name for the backup. Default is <code>Backup-$(hostname)-$(date +%Y-%m-%d-%T)</code>.
- **/home directory options:** You have three options: fully include it, keep only it's hidden files and folders (which are necessary to login and keep basic settings) or completely exclude it (in case it's located in separate partition and you want to use that in restore).
- **Compression:** You can choose between gzip, bzip2, xz and none (for no compression). Gzip should be fine.
- **Archiver options:** You can pass your own extra options in the archiver. See <code>tar --help</code> for more info.
- **Passphrase and encryption method:** Enter a passphrase if you want to encrypt the archive and select encryption method (openssl or gpg). Leave empty for no encryption.

The script can also read input from */etc/backup.conf*.
See the provided [sample](https://github.com/tritonas00/system-tar-and-restore/blob/master/backup.conf) or use -g to generate a configuration file.

When the process completes, you may want to check *backup.log* file in the same directory with the backup archive. See <code>backup.sh --help</code> for all options.

###RESTORE/TRANSFER###

The restore.sh script has two modes: **Restore** and **Transfer**. The first uses the above created archive to extract it in desired partition(s). The second transfers your system in desired partition(s) using rsync. Then, in both cases, generates the target system's fstab, rebuilds initramfs for every available kernel, generates locales and finally installs and configures the selected bootloader.

Boot from a livecd - preferably one of the target (backed up) distro - or another existing system, prepare your target partition(s) and start the script. You will be asked for:

- **Target partitions:** You must specify at least one target root partition. Optionally you can choose any other partition for your /home, /boot, swap or custom mount points (/var /opt etc.) and in case of UEFI a target ESP partition and it's mount point.
- **Mount options:** You can specify alternative comma-seperated mount options for the target root partition. Defaults are: *defaults,noatime*.
- **Btrfs subvolumes:** If the target root filesystem is Btrfs, you will be prompted for root subvolume name. Leave empty if you dont want subvolumes. Also you can specify other subvolumes. Just enter the paths (/home /var /usr etc.) seperated by space. Recommended root subvolume name is: *__active*.
- **Bootloader:** In BIOS systems you can choose Grub (version 2) or Syslinux and the target disk. If you select a raid array as bootloader disk, the script will install the bootloader in all disks that the array contains. In case of UEFI you can choose Grub, EFISTUB/efibootmgr or Systemd/bootctl. Also you can define additional kernel options.
- **Select mode:** In *Restore mode* you have to specify the backup archive location, local or remote. If the archive is encrypted you will be prompted for the passphrase. In *Transfer mode* you will have to specify if you want to transfer your entire /home directory or only it's hidden files and folders (which are necessary to login and keep basic settings).
- **Tar/Rsync options:** You may want to specify any additional options.  
See <code>tar --help</code> or <code>rsync --help</code> for more info.
 
When the process completes, you may want to check */tmp/restore.log*. See <code>restore.sh --help</code> for all options.

###GUI###

A gui wrapper is available (star-gui.sh). The script requires **gtkdialog 0.8.3** and **bash**. Run it as root, set your options and press *RUN* to execute the generated command. Also the wrapper reads */etc/backup.conf* if exists.

![Backup](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/backup.png)
![Restore](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/restore.png)
![Log](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/log.png)

###NOTES###

- With GNU Tar 1.27+ you can add *--xattrs --acls* (and *--selinux* if available) in backup and restore additional tar options. In case of Fedora, those options are added automatically.

- In case of Gentoo package genkernel is required to build initramfs. If you dont want to use initramfs image you can use -D in both scripts to disable
genkernel check and initramfs building.

- In case of Gentoo and simple luks it is recommended to open the device as */dev/mapper/root* ([reference](http://www.gentoo-wiki.info/Initramfs)). Otherwise add *root=/dev/ram0* in kernel options.

- In the target system, in case of Syslinux, old */boot/syslinux/syslinux.cfg* is saved as */boot/syslinux.cfg-old*.  

- In the target system, if any kernel options are defined with Grub, old */etc/default/grub* is saved as */etc/default/grub-old*.  

- In case of UEFI, you must boot in UEFI enviroment to restore a system. The script will check if */sys/firmware/efi* exists and act accordingly.
   You must create an [ESP (EFI System Partition)](https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface#EFI_System_Partition).  

###TESTED PARTITION SCHEMES###

| TARGET&nbsp;PARTITION | MOUNTPOINT | BOOTLOADER | SYSTEM | NOTES |
|-----------------|----------------|--------------|------------|-------------|
|/dev/sdX1|/|Grub<br>Syslinux|BIOS&nbsp;MBR|
|/dev/sdX2<br>/dev/sdX1<br>/dev/sdX3<br>/dev/sdX4|/<br>/boot<br>/home<br>/var|Grub<br>Syslinux|BIOS&nbsp;MBR|
|/dev/md0|/|Grub<br>Syslinux|BIOS&nbsp;MBR|level=1<br>metadata=1.0|
|/dev/md1<br>/dev/md0*|/<br>/boot|Syslinux|BIOS&nbsp;GPT| level=1<br>metadata=1.0*|
|/dev/sdX2<br>/dev/sdX1|/<br>/boot|Grub<br>Syslinux|BIOS&nbsp;MBR|btrfs<br>Root Subvolume: __active<br>Other&nbsp;Subvolumes:&nbsp;/home&nbsp;/usr&nbsp;/var&nbsp;/opt|
|/dev/mapper/A-B<br>/dev/sdX1*<br>/dev/sdX3|/<br><br>/boot|Grub<br>Syslinux|BIOS&nbsp;GPT|lvm<br>Grub needs BIOS Boot Partition*|
|/dev/mapper/A-B<br>/dev/sdX1<br>/dev/mapper/A-C<br>/dev/mapper/A-D<br>/dev/mapper/X|/<br>/boot<br>/home<br>swap<br><br>|Grub<br>Syslinux|BIOS&nbsp;MBR|lvm on luks|
|/dev/mapper/A-B<br>/dev/md1<br>/dev/md0*|/<br><br>/boot|Syslinux|BIOS&nbsp;GPT|lvm on mdadm<br>level=1<br>metadata=1.0*|
|/dev/mapper/A-B<br>/dev/mapper/X<br>/dev/md1<br>/dev/md0*|/<br><br><br>/boot|Syslinux|BIOS&nbsp;GPT|lvm on luks on mdadm<br>level=1<br>metadata=1.0*|
|/dev/mapper/X<br>/dev/sdX1|/<br>/boot|Grub<br>Syslinux|BIOS&nbsp;MBR|luks|
|/dev/mapper/X<br>/dev/sdX1<br>/dev/A/B|/<br><br>/boot|Grub<br>Syslinux|BIOS&nbsp;MBR|luks on lvm|
|/dev/mapper/X<br>/dev/md1<br>/dev/md0*|/<br><br>/boot|Syslinux|BIOS&nbsp;GPT|luks on mdadm<br>level=1<br>metadata=1.0*|
|/dev/mapper/X<br>/dev/mapper/A-B<br>/dev/md1<br>/dev/md0*|/<br><br><br>/boot|Syslinux|BIOS&nbsp;GPT|luks on lvm on mdadm<br>level=1<br>metadata=1.0*|
|/dev/sdX2<br>/dev/sdX1*|/<br>/boot/efi|Grub<br>EFISTUB/efibootmgr<br>Systemd/bootctl|UEFI&nbsp;GPT|ESP*<br>efibootmgr 0.12<br>efivar 0.21<br>systemd >= 222|
|/dev/sdX2<br>/dev/sdX1*|/<br>/boot|Grub<br>EFISTUB/efibootmgr<br>Systemd/bootctl|UEFI&nbsp;GPT|ESP*<br>efibootmgr 0.12<br>efivar 0.21<br>systemd >= 222|
|/dev/mapper/X<br>/dev/sdX2<br>/dev/sdX1*|/<br>/boot<br>/boot/efi|Grub<br>EFISTUB/efibootmgr<br>Systemd/bootctl|UEFI&nbsp;GPT|luks<br>ESP*<br>efibootmgr 0.12<br>efivar 0.21<br>systemd >= 222|

###EXAMPLES USING ARGUMENTS###

- Destination: /home/john/
- Compression: gzip  
- Additional options: --acls --xattrs 

<code>./backup.sh -d /home/john/ -c gzip -u "--acls --xattrs"</code>  

- Destination: /home/john/
- Compression: xz  
- Exclude /home directory  

<code>./backup.sh -d /home/john/ -c xz -hn</code>   

- Destination: /home/john/
- Compression: gzip  
- Keep only /home's hidden files and folders

<code>./backup.sh -d /home/john/ -c gzip -h</code>   

- root: /dev/sdb1
- grub  
- local file
- tar options: --acls --xattrs 

<code>./restore.sh -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tar.gz -u "--acls --xattrs"</code>  

- root: /dev/sda1 (ssd)
- syslinux  
- kernel options: nomodeset
- transfer mode  

<code>./restore.sh -r /dev/sda1 -m discard,errors=remount-ro -S /dev/sda -k nomodeset -t</code>  

- root: /dev/sdb1, /home: /dev/sdb2, swap: /dev/sdb3
- syslinux 
- remote file on ftp server

<code>./restore.sh -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -f ftp://server/backup.tar.xz</code>

- root: /dev/sdb2, /boot: /dev/sdb1
- syslinux 
- remote file in protected http server

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -S /dev/sdb -f http://server/backup.tar.gz -n user -p pass</code>

- root: /dev/mapper/debian-root, /boot: /dev/sdb1  
- grub  
- transfer mode  

<code>./restore.sh -r /dev/mapper/debian-root -b /dev/sdb1 -g /dev/sdb -t</code>  

- root: /dev/sda2 (btrfs with compression), /boot: /dev/sda1
- root subvolume: __active
- /var, /usr and /home subvolumes
- syslinux  
- transfer mode  

<code>./restore.sh -t -b /dev/sda1 -r /dev/sda2 -m compress=lzo -S /dev/sda -R __active -O "/var /usr /home"</code>  

- root: /dev/md1, /boot: /dev/md0
- local file  
- syslinux  

<code>./restore.sh -r /dev/md1 -b /dev/md0 -f /home/john/Downloads/backup.tar.gz -S /dev/md0</code>  

- root: /dev/sda2, esp: /dev/sda1
- local file  
- grub

<code>./restore.sh -r /dev/sda2  -e /dev/sda1 -l /boot/efi -g auto -f /home/john/Downloads/backup.tar.gz</code>   

- root: /dev/sdb2, /boot: /dev/sdb1, /var: /dev/sdb4, /usr: /dev/sdb3
- transfer mode (/home's hidden files and folders only)
- grub

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -c "/var=/dev/sdb4 /usr=/dev/sdb3" -g /dev/sdb -to</code>