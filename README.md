System Tar & Restore
=================

  * [About](#about)
  * [Distribution Packages](#distribution-packages)
  * [Requirements](#requirements)
  * [Things you can do](#things-you-can-do)
  * [Backup Mode](#backup-mode)
  * [Restore/Transfer Mode](#restoretransfer-mode)
  * [Notes](#notes)
  * [Tested partition schemes](#tested-partition-schemes)
  * [Examples using arguments](#examples-using-arguments)

![Backup](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/backup.png)

###ABOUT###

System tar & restore contains two bash scripts, the main program **star.sh** and a gui wrapper **star-gui.sh**.  
Three modes are available: Backup, Restore and Transfer.

Supported distributions: Arch, Debian/Ubuntu, Fedora, openSUSE, Gentoo, Mandriva/Mageia          

[Stable Releases](https://github.com/tritonas00/system-tar-and-restore/releases)  

### DISTRIBUTION PACKAGES

**Archlinux**  
See the [wiki page](https://wiki.archlinux.org/index.php/System-tar-and-restore).

**Gentoo**  
The package is provided by the <code>gentoo-el</code> overlay. You can install it with the following commands as root. (you need to have `layman` installed and configured)

    layman -a gentoo-el  
    emerge app-backup/system-tar-and-restore

###REQUIREMENTS###

- gtkdialog 0.8.3 or later (for the gui)
- tar 1.27+ (acls and xattrs support)
- rsync (for Transfer Mode)
- wget   (for downloading backup archives)
- gptfdisk/gdisk (for GPT and Syslinux)
- openssl/gpg (for encryption)

###THINGS YOU CAN DO###

- Full system or partial backup
- Restore or transfer to the same or different disk/partition layout.
- Restore or transfer to an external device such as usb flash drive, sd card etc.
- Restore a BIOS-based system to UEFI and vice versa.
- Prepare a system in a virtual machine (such as virtualbox), back it up and restore it in a normal machine.

###BACKUP MODE###

With this mode you can make a tar backup archive of your system. You can define:

- **Archive filename:** A desired name for the backup archive. Default is <code>Backup-$(hostname)-$(date +%Y-%m-%d-%T)</code>.
- **Destination directory:** Set where you want to save the backup archive. Default is <code>/</code>.
- **/home directory:** You have three options: fully include it, keep only it's hidden files and folders (which are necessary to login and keep basic settings) or completely exclude it (in case it's located in separate partition and you want to use that in restore mode).
- **Compression:** You can choose between gzip, bzip2, xz and none (for no compression). Gzip should be fine.
- **Encryption method and passphrase:** Select encryption method (openssl or gpg) and enter a passphrase if you want to encrypt the archive.
- **Archiver options:** You can pass your own extra options in the archiver. See <code>tar --help</code> for more info.

The script can read input from */etc/backup.conf*. Alternative path can also be specified: <code>star.sh -C /path/backup.conf</code> or <code>star-gui.sh /path/backup.conf<code>.
See the provided [sample](https://github.com/tritonas00/system-tar-and-restore/blob/master/backup.conf) or use -g to generate a configuration file.

When the process completes, you may want to check *backup.log* file in the same directory with the backup archive.

###RESTORE/TRANSFER MODE###

Restore mode uses the above created archive to extract it in desired partition(s). Transfer mode transfers your system in desired partition(s) using rsync. Then, in both cases, the script generates the target system's fstab, rebuilds initramfs for every available kernel, generates locales and finally installs and configures the selected bootloader.

Boot from a livecd - preferably one of the target (backed up) distro - or another existing system, prepare your target partition(s) and start the script. You can define:

- **Target partitions:** You must specify a target root partition. Optionally you can choose any other partition for your /home, /boot, swap or custom mount points (/var /opt etc.) and in case of UEFI a target ESP partition and it's mount point (/boot/efi or /boot).
- **Mount options:** You can specify alternative comma-seperated mount options for the target root partition. Defaults are: *defaults,noatime*.
- **Btrfs subvolumes:** If the target root filesystem is Btrfs, you can create subvolumes. Set the root subvolume name and also you can specify other subvolumes. Just enter the paths (/home /var /usr etc.) seperated by space. Recommended root subvolume name is: *__active*.
- **Bootloader:** In BIOS systems you can choose Grub (version 2) or Syslinux and the target device. If you select a raid array as bootloader device, the script will install the bootloader in all devices that the array contains. In case of UEFI you can choose Grub, EFISTUB/efibootmgr or Systemd/bootctl. Also you can define additional kernel options.
- **Modes:** In *Restore mode* you have to specify the backup archive (local path or remote url). If the archive is encrypted you must specify the passphrase. In *Transfer mode* you can choose if you want to transfer your entire /home directory, only it's hidden files and folders (which are necessary to login and keep basic settings) or exclude it.
- **Tar/Rsync options:** You may want to specify any additional options. See <code>tar --help</code> or <code>rsync --help</code> for more info.
 
When the process completes check */tmp/restore.log*. 

See <code>star.sh --help</code> for all available options.

###NOTES###

- In case of Gentoo package genkernel is required to build initramfs. If you dont want initramfs image you can use -D to disable genkernel check and initramfs building.

- In the target system, the script saves configuration files before generate/modify them with *-old* suffix.  

- In case of UEFI, you must boot in UEFI enviroment to restore a system. The script will check if */sys/firmware/efi* exists and act accordingly.
   You must create an [ESP (EFI System Partition)](https://wiki.archlinux.org/index.php/EFI_System_Partition). 

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
|/dev/mapper/X<br>/dev/A/B<br>/dev/sdX1|/<br><br>/boot|Grub<br>Syslinux|BIOS&nbsp;MBR|luks on lvm|
|/dev/mapper/X<br>/dev/md1<br>/dev/md0*|/<br><br>/boot|Syslinux|BIOS&nbsp;GPT|luks on mdadm<br>level=1<br>metadata=1.0*|
|/dev/mapper/X<br>/dev/mapper/A-B<br>/dev/md1<br>/dev/md0*|/<br><br><br>/boot|Syslinux|BIOS&nbsp;GPT|luks on lvm on mdadm<br>level=1<br>metadata=1.0*|
|/dev/sdX2<br>/dev/sdX1*|/<br>/boot/efi|Grub<br>EFISTUB/efibootmgr<br>Systemd/bootctl|UEFI&nbsp;GPT|ESP*<br>efibootmgr 0.12<br>efivar 0.21<br>systemd >= 222|
|/dev/sdX2<br>/dev/sdX1*|/<br>/boot|Grub<br>EFISTUB/efibootmgr<br>Systemd/bootctl|UEFI&nbsp;GPT|ESP*<br>efibootmgr 0.12<br>efivar 0.21<br>systemd >= 222|
|/dev/mapper/X<br>/dev/sdX2<br>/dev/sdX1*|/<br>/boot<br>/boot/efi|Grub<br>EFISTUB/efibootmgr<br>Systemd/bootctl|UEFI&nbsp;GPT|luks<br>ESP*<br>efibootmgr 0.12<br>efivar 0.21<br>systemd >= 222|

###EXAMPLES USING ARGUMENTS###

**Backup Mode:**

- Destination: /home/john/
- Compression: gzip  
- Additional options: --exclude=/home/john/.cache/* --warning=none  

<code>star.sh -i 0 -d /home/john/ -c gzip -u "--exclude=/home/john/.cache/* --warning=none"</code>  

- Destination: /home/john/
- Compression: xz  
- Exclude /home directory  

<code>star.sh -i 0 -d /home/john/ -c xz -H</code>   

- Destination: /home/john/
- Compression: bzip2  
- Keep only /home's hidden files and folders
- Encryption

<code>star.sh -i 0 -d /home/john/ -c bzip2 -E openssl -P 1234 -O</code>   

**Restore Mode:**

- root: /dev/sdb1
- grub  
- local archive  

<code>star.sh -i 1 -r /dev/sdb1 -G /dev/sdb -f /home/john/backup.tar.gz</code>  

- root: /dev/sdb1, /home: /dev/sdb2, swap: /dev/sdb3
- syslinux 
- remote archive on ftp server

<code>star.sh -i 1 -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -f ftp://server/backup.tar.xz</code>

- root: /dev/md1, /boot: /dev/md0
- local archive  
- syslinux  

<code>star.sh -i 1 -r /dev/md1 -b /dev/md0 -f /home/john/backup.tar.gz -S /dev/md0</code>  

- root: /dev/sdb1
- syslinux 
- remote file in protected http server

<code>star.sh -i 1 -r /dev/sdb1 -S /dev/sdb -f http://server/backup.tar.gz -y username -p password</code>

- root: /dev/sda2, esp: /dev/sda1
- local archive  
- grub

<code>star.sh -i 1 -r /dev/sda2 -e /dev/sda1 -l /boot/efi -G auto -f /home/john/backup.tar.gz</code>   

**Transfer Mode:**

- root: /dev/sda1 (ssd)
- syslinux  
- kernel options: nomodeset

<code>star.sh -i 2 -r /dev/sda1 -m discard,errors=remount-ro -S /dev/sda -k nomodeset</code>  

- root: /dev/mapper/debian-root, /boot: /dev/sdb1  
- grub  

<code>star.sh -i 2 -r /dev/mapper/debian-root -b /dev/sdb1 -G /dev/sdb</code>  

- root: /dev/sda2 (btrfs with compression), /boot: /dev/sda1
- root subvolume: __active
- /var, /usr and /home subvolumes
- syslinux  

<code>star.sh -i 2 -r /dev/sda2 -m compress=lzo -b /dev/sda1 -S /dev/sda -R __active -B "/var /usr /home"</code>  

- root: /dev/sdb2, /boot: /dev/sdb1, /var: /dev/sdb4, /usr: /dev/sdb3
- transfer /home's hidden files and folders only
- grub

<code>star.sh -i 2 -r /dev/sdb2 -b /dev/sdb1 -t "/var=/dev/sdb4 /usr=/dev/sdb3" -G /dev/sdb -O</code>
