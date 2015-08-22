System Tar & Restore
=================

  * [About](#about)
  * [Distribution Packages](#distribution-packages)
  * [Requirements](#requirements)
  * [Things you can do](#things-you-can-do)
  * [Backup](#backup)
  * [Restore/Transfer](#restoretransfer)
  * [GUI](#gui)
  * [Notes](#notes)
  * [Examples using arguments](#examples-using-arguments)

###ABOUT###

System tar & restore contains two bash scripts, **backup.sh** and **restore.sh**. The former makes a tar backup of your system. The latter restores the backup or transfers your system using rsync in desired partition(s). The scripts include two interfaces, cli and dialog (ncurses).

Supported distributions: Arch, Debian/Ubuntu, Fedora, openSUSE, Gentoo, Mandriva          

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

The script also supports all input as arguments:

    -i, --interface
        interface to use: cli dialog

    -N, --no-color
        disable colors

    -q, --quiet
        dont ask, just run  

    -v, --verbose
        enable verbose archiver output (cli interface only)  

    -g, --generate     
        generate configuration file (in case of successful backup)  

    -H, --hide-cursor
        hide cursor when running archiver (useful for some terminal emulators)  

    -r, --remove
        remove older backups in the destination directory

    -d, --directory
        backup destination path

    -f, --filename
        backup file name (without extension)  

    -h, --exclude-home
        exclude /home directory (keep hidden files and folders)  

    -n, --no-hidden
        dont keep home's hidden files and folders (use with -h)  

    -c, --compression
        compression type: gzip bzip2 xz none     

    -u, --user-options
        additional tar options (see tar --help)  
        
    -o, --override
        override the default tar options with user options (use with -u)
        
    -s, --exclude-sockets
        exclude sockets
        
    -m, --multi-core
        enable multi-core compression (via pigz, pbzip2 or pxz)

    -E, --encryption-method
        encryption method: openssl gpg

    -P, --passphrase
        passphrase for encryption   

    -D, --disable-genkernel
        disable genkernel check in gentoo  
        
    -C, --conf
        alternative configuration file path
        
    -w, --wrapper 
        make the script wrapper-friendly (cli interface only)

    --help
        show all arguments

The script can also read input from */etc/backup.conf*.
See the provided [sample](https://github.com/tritonas00/system-tar-and-restore/blob/master/backup.conf) or use -g to generate a configuration file.

When the process completes, you may want to check *backup.log* file in the same directory with the backup archive.


###RESTORE/TRANSFER###

The restore.sh script has two modes: **Restore** and **Transfer**. The first uses the above created archive to extract it in desired partition(s). The second transfers your system in desired partition(s) using rsync. Then, in both cases, generates the target system's fstab, rebuilds initramfs for every available kernel, generates locales and finally installs and configures the selected bootloader.

Boot from a livecd - preferably one of the target (backed up) distro - or another existing system, prepare your target partition(s) and start the script. You will be asked for:

- **Target partitions:** You must specify at least one target root partition and in case of UEFI a target ESP partition. Optionally you can choose any other partition for your /home, /boot, swap or custom mount points (/var /opt etc.)
- **Mount options:** You can specify alternative comma-seperated mount options for the target root partition. Defaults are: *defaults,noatime*.
- **Btrfs subvolumes:** If the target root filesystem is Btrfs, you will be prompted for root subvolume name. Leave empty if you dont want subvolumes. Also you can specify other subvolumes. Just enter the paths (/home /var /usr etc.) seperated by space. Recommended root subvolume name is: *__active*.
- **Bootloader:** You can choose grub (version 2) or syslinux, the target disk and in case of syslinux any additional kernel options that will be written in the target *syslinux.cfg*. If you select a raid array as bootloader disk, the script will install the bootloader in all disks that the array contains.
- **Select mode:** In *Restore mode* you have to specify the backup archive location, local or remote. If the archive is encrypted you will be prompted for the passphrase. In *Transfer mode* you will have to specify if you want to transfer your entire /home directory or only it's hidden files and folders (which are necessary to login and keep basic settings).
- **Tar/Rsync options:** You may want to specify any additional options.  
See <code>tar --help</code> or <code>rsync --help</code> for more info.

The script also supports all input as arguments:

    -i, --interface
        interface to use: cli dialog     

    -N, --no-color
        disable colors

    -q, --quiet
        dont ask, just run  

    -v, --verbose
        enable verbose tar/rsync output (cli interface only)

    -u, --user-options
        additional tar/rsync options (see tar --help or rsync --help)  

    -H, --hide-cursor
        hide cursor when running tar/rsync (useful for some terminal emulators)  

    -f, --file
        backup file path or url

    -n, --username
        username

    -p, --password
        password  

    -P, --passphrase
        passphrase for decryption    

    -t, --transfer
        activate tranfer mode  

    -o, --only-hidden
        transfer /home's hidden files and folders only  

    -x, --override
        override the default rsync options with user options (use with -u)  

    -r, --root
        target root partition

    -e, --esp
        target EFI system partition

    -h, --home
        target home partition  

    -b, --boot
        target boot partition

    -s, --swap
        swap partition

    -c, --custom-partitions
        specify custom partitions (mountpoint=device e.g /var=/dev/sda3)   

    -m, --mount-options
        comma-separated list of mount options (root partition only)

    -d, --dont-check-root
        dont check if root partition is empty (dangerous)

    -g, --grub
        target disk for grub

    -S, --syslinux
        target disk for syslinux

    -k, --kernel-options
        additional kernel options (syslinux only)  

    -R, --rootsubvolname
        subvolume name for root

    -O, --other-subvolumes
        specify other subvolumes (subvolume path e.g /home /var /usr ...)

    -D, --disable-genkernel
        disable genkernel check and initramfs building in gentoo
        
    -B, --bios
        ignore UEFI environment
        
    -w, --wrapper 
        make the script wrapper-friendly (cli interface only)

    --help
        show all arguments
 
When the process completes, you may want to check */tmp/restore.log*.

###GUI###

A gui wrapper is available (star-gui.sh). The script requires **gtkdialog 0.8.3** and **bash**. Run it as root, set your options and press *RUN* to run the generated command. Also the wrapper reads */etc/backup.conf* if exists.

![Backup](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/backup.png)
![Restore](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/restore.png)
![Log](https://raw.githubusercontent.com/tritonas00/system-tar-and-restore/master/images/log.png)

###NOTES###

- With GNU Tar 1.27+ you can add *--xattrs --acls* (and *--selinux* if available) in backup and restore additional tar options. In case of Fedora, those options are added automatically.

- In case of Gentoo package genkernel is required to build initramfs. If you dont want to use initramfs image you can use -D in both scripts to disable
genkernel check and initramfs building.

- In Restore Mode the system that runs the restore script and the target system (the one you want to restore), must have the same architecture (for chroot to work). Also it's advisable to run the restore.sh script from a LiveCD of the target distro. 

- For booting a btrfs subvolumed root successfully with Syslinux, it is recommended to have a seperate /boot partition.
Recommended subvolume name is: *__active*  

- When using LVM, it is also recommended to have a seperate /boot partition.  

- When using RAID, it is recommended to create a seperate raid1 array with metadata=1.0 as your /boot partition.  

- When using GRUB with BIOS and GPT you must create a BIOS Boot Partition: ~1 MiB unformatted partition with bios_grub flag enabled (0xEF02 for gdisk).  

- In the target system, in case of Syslinux, old */boot/syslinux/syslinux.cfg* is saved as */boot/syslinux.cfg-old*.  

- In the target system, if distribution is Fedora (or variant) and Grub is selected, old */etc/default/grub* is saved as */etc/default/grub-old*.  

- In case of UEFI, you must boot in UEFI enviroment to restore a system. The script will check if */sys/firmware/efi* exists and act accordingly.
   You must create an [ESP (EFI System Partition)](https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface#EFI_System_Partition).  


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

- root partition: /dev/sdb1
- grub  
- local file
- tar options: --acls --xattrs 

<code>./restore.sh -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tar.gz -u "--acls --xattrs"</code>  

- root partition: /dev/sda1 (ssd)
- syslinux  
- kernel options: nomodeset
- transfer mode  

<code>./restore.sh -r /dev/sda1 -m discard,errors=remount-ro -S /dev/sda -k nomodeset -t</code>  

- root partition: /dev/sdb1
- home partition: /dev/sdb2
- swap partition: /dev/sdb3
- syslinux 
- remote file on ftp server

<code>./restore.sh -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -f ftp://server/backup.tar.xz</code>

- root partition: /dev/sdb2
- boot partition: /dev/sdb1
- syslinux 
- remote file in protected http server

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -S /dev/sdb -f http://server/backup.tar.gz -n user -p pass</code>

- root partition: /dev/mapper/debian-root
- boot partition: /dev/sdb1  
- grub  
- transfer mode  

<code>./restore.sh -r /dev/mapper/debian-root -b /dev/sdb1 -g /dev/sdb -t</code>  

- root partition: /dev/sda2 (btrfs) with compression
- boot partition: /dev/sda1
- root subvolume: __active
- /var, /usr and /home subvolumes
- syslinux  
- transfer mode  

<code>./restore.sh -t -b /dev/sda1 -r /dev/sda2 -m compress=lzo -S /dev/sda -R __active -O "/var /usr /home"</code>  

- root partition: /dev/md1
- boot partition: /dev/md0
- local file  
- syslinux  

<code>./restore.sh -r /dev/md1 -b /dev/md0 -f /home/john/Downloads/backup.tar.gz -S /dev/md0</code>  

- root partition: /dev/sda2
- esp partition: /dev/sda1
- local file  
- grub

<code>./restore.sh -r /dev/sda2  -e /dev/sda1 -g /boot/efi -f /home/john/Downloads/backup.tar.gz</code>   

- root partition: /dev/sdb2
- boot partition: /dev/sdb1
- var partition: /dev/sdb4
- usr partition: /dev/sdb3
- transfer mode (/home's hidden files and folders only)
- grub

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -c "/var=/dev/sdb4 /usr=/dev/sdb3" -g /dev/sdb -to</code>