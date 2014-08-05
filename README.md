###ABOUT###

System tar & restore contains two bash scripts, **backup.sh** and **restore.sh**.

The purpose is to make the process of backing up and restoring a full GNU/Linux installation easier 
using tar or transfer an existing installation using rsync.

Supported distributions: Arch, Debian, Fedora, openSUSE, Gentoo        

[![Demo Video](http://img.youtube.com/vi/dr5ZB3ajhTQ/maxresdefault.jpg)](https://www.youtube.com/watch?v=dr5ZB3ajhTQ&hd=1)  

[Stable Releases](https://github.com/tritonas00/system-tar-and-restore/releases)  

### Distribution packages

#### Archlinux

The package is provided by the AUR. You can install it with an AUR helper of your choice: [`system-tar-and-restore`](https://aur.archlinux.org/packages/system-tar-and-restore/)
or manually by invoking the following commands as a regular user. (to build packages from the AUR, the `base-devel` package group is assumed to be installed)

<code>wget https://aur.archlinux.org/packages/sy/system-tar-and-restore/system-tar-and-restore.tar.gz
 tar xf system-tar-and-restore.tar.gz
 cd system-tar-and-restore
 makepkg -si</code>  

#### Gentoo

The package is provided by the `gentoo-el` overlay. You can install it with the following commands as root. (you need to have `layman` installed and configured)

<code>layman -a gentoo-el
emerge app-backup/system-tar-and-restore</code>  

###REQUIREMENTS###

- bsdtar (for libarchive tar)  
- rsync (for Transfer Mode)
- dialog (for ncurses interface)
- wget   (for downloading backup archives)
- gptfdisk/gdisk (for GPT and Syslinux)  
- efibootmgr (for UEFI)  
- dosfstools (for UEFI)  

###BACKUP###

Backup script makes a tar backup of / in a given location. It will make a folder in that location which 
contains the archive and the log file *backup.log* (usefull for tracking tar errors/warnings).

The script will ask for:

- Interface to use 

- If you want to save the backup in the default directory (/), or enter your desired path

- If you want to specify a backup filename (without extension) or use the default name  

- What to do with /home directory

- Archiver: tar and bsdtar are supported.  

- Compression type: gzip bzip2 xz and none are supported.

- If you want to specify any additional archiver options (see tar --help or man bsdtar)  


The script also supports all input as arguments:

**-i, --interface**   
interface to use (cli dialog)

**-N, --no-color**   
disable colors

**-q,  --quiet**  
dont ask, just run  

**-v, --verbose**           
enable verbose archiver output (cli only)

**-g, --generate**                     
generate configuration file (in case of successful backup)  

**-d, --directory**  
backup destination path

**-f, --filename**  
backup file name (without extension)  

**-h, --exclude-home**  
exclude /home directory (keep hidden files and folders)  

**-n, --no-hidden**       
dont keep home's hidden files and folders (use with -h)  

**-c, --compression**  
compression type (gzip bzip2 xz none)  

**-a, --archiver**  
select archiver (tar bsdtar)    

**-u, --user-options**   
additional tar options (see tar --help or man bsdtar)  

**-D, --disable-genkernel**   
disable genkernel check in gentoo  

**--help**   
show all arguments

The script can also read input from */etc/backup.conf*.
See the provided [sample](https://github.com/tritonas00/system-tar-and-restore/blob/master/backup.conf) or use -g to generate a configuration file. 


###RESTORE###

User must create and format partitions using his favorite partition manager before running the script.
At least one / (root) partition is required and optionally seperate partitions for any other desired 
mountpoint (/home /boot /var etc...).

Restore script contains two modes: **Restore** and **Transfer**.

In **Restore Mode**, the script uses the above created archive to extract it in user defined partitions.

In **Transfer Mode**, the script uses rsync to transfer the root filesystem (/) in user defined partitions.

Then generates fstab, rebuilds initramfs image for every available kernel, re-generates locales, 
installs and auto-configures Grub or Syslinux and finally unmounts and cleans everything.


The script will ask for:

- Interface to use (cli dialog)  

- Target root partition

- Target EFI system partition (if UEFI environment detected)  

- (Optional) Target home partition   

- (Optional) Target boot partition    

- (Optional) Swap partition   

- (Optional) Set custom partitions. Syntax is mountpoint=device (e.g /usr=/dev/sda3 /var/cache=/dev/sda4).  

- (Optional) Additional mount options for the root partition. 

- (Optional) If the root filesystem is btrfs, the script will ask if you want to create a subvolume for it. If yes, 
    it will ask for the subvolume's name and also if you want to create other subvolumes. Just enter the 
    subvolume paths (e.g /home /var /usr ...) seperated by space.
   
- (Optional) Bootloader and target disk. Grub2 and Syslinux are both supported.
   If Syslinux is selected, it will ask for additional kernel options which will be written in syslinux.cfg.
   If a raid array is selected, the script will install the bootloader in all disks that the array contains.
   In case of UEFI, only Grub2 is supported by the script and */boot/efi* will be used automatically.

- Select Mode. If **Restore Mode** is selected it will ask the archiver you used to create the backup archive
    and the backup archive itself.  This can be obtained locally (by entering the full path of the file), or remotelly
   (by entering the url of the file). Also protected url is supported, which will ask for server's username and password.
   If **Transfer Mode** is selected, it will ask if you want to transfer entire /home directory or only it's hidden files and folders. 
   In both modes, it will ask if you want to specify any additional tar/rsync options (see tar --help, man bsdtar or rsync --help).  

- Later it will ask you if you want to edit the generated fstab file further. Old fstab file is saved as */mnt/target/etc/fstab-old*.  

- At the end, if you didn't choose a bootloader, the script will help you to chroot and install a bootloader manually.

Log file is saved as */tmp/restore.log*

The script also supports all input as arguments:

**-i, --interface**   
interface to use (cli dialog)  

**-N, --no-color**   
disable colors

**-q,  --quiet**  
dont ask, just run  

**-v,  --verbose**            
enable verbose tar/rsync output (cli only)

**-t, --transfer**   
activate tranfer mode  

**-o,  --only-hidden**  
transfer /home's hidden files and folders only  

**-U,  --user-options**  
additional tar/rsync options (see tar --help, man bsdtar or rsync --help)  

**-r, --root**    
target root partition

**-e, --esp**    
target EFI system partition

**-b, --boot**     
target boot partition

**-h, --home**     
target home partition

**-s, --swap**     
swap partition

**-c,  --custom-partitions**  
specify custom partitions (mountpoint=device)

**-m, --mount-options**     
comma-separated list of mount options (root partition)

**-d,  --dont-check-root**  
dont check if root partition is empty (dangerous)

**-g, --grub**    
target disk for grub

**-S, --syslinux**      
target disk for syslinux

**-k, --kernel-options**      
additional kernel options (syslinux)

**-f, --file**      
backup file path or url

**-n, --username**     
username

**-p, --password**     
password

**-a, --archiver**  
select archiver (tar bsdtar)    

**-u, --url**     
same as -f (for compatibility)    

**-R, --rootsubvolname**   
subvolume name for root

**-O, --other-subvolumes**   
 specify other subvolumes (subvolume path e.g /home /var /usr ...)

**-D, --disable-genkernel**   
disable genkernel check and initramfs building in gentoo  

**--help**   
 show all arguments

###NOTES###

- With GNU Tar 1.27, you can add *--xattrs --acls* (and *--selinux* if available) in backup and restore additional tar options.

- In case of Gentoo, package genkernel is required to build initramfs. If you dont want to use initramfs image you can use -D in both scripts to disable
genkernel check and initramfs building.

- In case of Fedora *--xattrs --acls --selinux* are added automatically in backup. In order to successfully restore the target system (Fedora 19+)
using GNU Tar, you need to add _--selinux --acls --xattrs-include='*'_ in restore additional tar options.

- The system that runs the restore script and the target system (the one you want to restore), must have the same architecture (for chroot to work).

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
- Archiver: tar
- Additional options: --acls --xattrs 

<code>./backup.sh -d /home/john/ -c gzip -a tar -u "--acls --xattrs"</code>  

- Destination: /home/john/
- Compression: xz  
- Archiver: bsdtar   
- Exclude /home directory  

<code>./backup.sh -d /home/john/ -c xz -hn -a bsdtar</code>   

- Destination: /home/john/
- Compression: gzip  
- Archiver: tar  
- Keep only /home's hidden files and folders

<code>./backup.sh -d /home/john/ -c gzip -h -a tar</code>   

- root partition: /dev/sdb1
- grub  
- local file
- tar options: --acls --xattrs 

<code>./restore.sh -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tar.gz -a tar -U "--acls --xattrs"</code>  

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

<code>./restore.sh -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -f ftp://server/backup.tar.xz -a bsdtar</code>

- root partition: /dev/sdb2
- boot partition: /dev/sdb1
- syslinux 
- remote file in protected http server

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -S /dev/sdb -f http://server/backup.tar.gz -n user -p pass -a tar</code>

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

<code>./restore.sh -r /dev/md1 -b /dev/md0 -f /home/john/Downloads/backup.tar.gz -S /dev/md0 -a bsdtar</code>  

- root partition: /dev/sda2
- esp partition: /dev/sda1
- local file  
- grub

<code>./restore.sh -r /dev/sda2  -e /dev/sda1 -g /boot/efi -f /home/john/Downloads/backup.tar.gz -a tar</code>   

- root partition: /dev/sdb2
- boot partition: /dev/sdb1
- var partition: /dev/sdb4
- usr partition: /dev/sdb3
- transfer mode (/home's hidden files and folders only)
- grub

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -c "/var=/dev/sdb4 /usr=/dev/sdb3" -g /dev/sdb -to</code>