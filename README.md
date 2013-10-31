###ABOUT###

System tar & restore contains two bash scripts, **backup.sh** and **restore.sh**.

The purpose is to make the process of backing up and restoring a full GNU/Linux installation easier 
using tar or transfer an existing installation using rsync.

Supported distributions: Arch, Debian, Fedora*   
<sub>*Fedora 19 tar: xattrs patch bug(?), decompressed system can't login. Downgrading to 1.26-12.fc18 fixes the problem. Libarchive Tar and Transfer Mode works.</sub>

[Demo Video](http://www.youtube.com/watch?v=KB5O_FQ65lo&hd=1)  
[Stable Releases](https://github.com/tritonas00/system-tar-and-restore/releases)  

###LIMITATIONS###

- UEFI (not supported - not tested)

###REQUIREMENTS###

- bsdtar (for libarchive tar)  
- rsync (for Transfer Mode)
- dialog (for ncurses interface)
- wget   (for downloading backup archives)
- gptfdisk/gdisk (for GPT)  

###BACKUP###

Backup script makes a tar backup of / in a given location. It will make a folder in that location which 
contains the archive and the log file "backup.log" (usefull for tracking tar errors/warnings).

The script will ask for:

- Interface to use 

- If you want to save the backup in the default folder (/), or enter your desired path

- What to do with /home directory

- Archiver: tar and bsdtar are supported. 

- Compression type: gzip and xz are supported.

- If you want to enter any additional tar options (See tar --help or man bsdtar)  


The script also supports all input as arguments:

**-i, --interface**   
interface to use (cli dialog)

**-N, --no-color**   
disable colors

**-q,  --quiet**  
dont ask, just run  

**-d, --directory**  
backup folder path

**-h, --exclude-home**  
exclude /home directory (keep hidden files and folders)  

**-n, --no-hidden**       
dont keep home's hidden files and folders (use with -h)  

**-c, --compression**  
compression type (gzip xz)  

**-a, --archiver**  
select archiver (tar bsdtar)    

**-u, --user-options**   
additional tar options (See tar --help or man bsdtar)  

**--help**   
show all arguments



###RESTORE###

User must create and format partitions using his favorite partition manager before running the script.
At least one / (root) partition is required and optionally a seperate partition for /home, /boot and a swap partition.

Restore script contains two modes: **Restore** and **Transfer**.

In **Restore Mode**, the script uses the above created archive to extract it in user defined partitions.

In **Transfer Mode**, the script uses rsync to transfer the root filesystem (/) in user defined partitions.

Then generates fstab, rebuilds initramfs image for every available kernel, re-generates locales, 
installs and auto-configures Grub or Syslinux in MBR of given device and finally unmounts and cleans everything.


The script will ask for:

- Interface to use (cli dialog)  

- Target root partition

- (Optional) Target home partition   

- (Optional) Target boot partition    

- (Optional) Swap partition   

- (Optional) Set custom partitions. Syntax is mountpoint=device (e.g /usr=/dev/sda3 /var/cache=/dev/sda4).  

- (Optional) Additional mount options for the root partitions. 

- (Optional) If the root filesystem is btrfs, the script will ask if you want to create a subvolume for it. If yes, 
    it will ask for the subvolume's name and also if you want to create other subvolumes. Just enter the 
    subvolume paths (e.g /home /var /usr ...) seperated by space.
   
- (Optional) Bootloader and target disk (MBR). Grub2 and Syslinux are both supported.
   If Syslinux is selected, it will ask for additional kernel options which will be written in syslinux.cfg.
   If a raid array is selected, the script will install the bootloader in all disks that the array contains.  

- Select Mode. If **Restore Mode** is selected it will ask the archiver you used to create the backup archive
    and the backup archive itself.  This can be obtained locally (by entering the full path of the file), or remotelly
   (by entering the url of the file). Also protected url is supported, which will ask for server's username and password.
   If **Transfer Mode** is selected, it will ask if you want to transfer entire /home directory or only it's hidden files and folders.  

- Later it will ask you if you want to edit the generated fstab file further. Old fstab file is saved as */mnt/target/etc/fstab-old*.  

- At the end, if you didn't choose a bootloader or the selected bootloader not found in the target system, the script will help you to chroot and install a bootloader manually.

Log file is saved as */tmp/restore.log*

The script also supports all input as arguments:

**-i, --interface**   
interface to use (cli dialog)  

**-N, --no-color**   
disable colors

**-q,  --quiet**  
dont ask, just run  

**-t, --transfer**   
activate tranfer mode  

**-o,  --only-hidden**  
transfer /home's hidden files and folders only  

**-r, --root**    
target root partition

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

**--help**   
 show all arguments

###NOTES###

- With GNU Tar 1.27, you can add --xattrs --acls --selinux in backup user options.

- The system that runs the restore script and the target system (the one you want to restore), must have the same architecture (for chroot to work).

- For booting a btrfs subvolumed root successfully with Syslinux, it is recommended to have a seperate /boot partition.
Recommended subvolume name is: *__active*  

- When using LVM, it is also recommended to have a seperate /boot partition.  

- When using RAID, it is recommended to create a seperate raid1 array with metadata=1.0 as your /boot partition.  

- When using GRUB with BIOS and GPT you must create a BIOS Boot Partition: ~1 MiB unformatted partition with bios_grub flag enabled (0xEF02 for gdisk).  

- In the target system, in case of Syslinux, old */boot/syslinux/syslinux.cfg* is saved as */boot/syslinux.cfg-old*.  

- In the target system, if distribution is Fedora and Grub is selected, old */etc/default/grub* is saved as */etc/default/grub-old*.  


###EXAMPLES USING ARGUMENTS###

- Backup directory=/home/john/
- Compression: gzip  
- Archiver: tar

<code>sudo ./backup.sh -d /home/john/ -c gzip -a tar</code>  

- Backup directory=/home/john/
- Compression: xz  
- Archiver: bsdtar   
- Exclude /home directory  

<code>sudo ./backup.sh -d /home/john/ -c xz -h -n -a bsdtar</code>   

- Backup directory=/home/john/
- Compression: gzip  
- Archiver: tar  
- Keep only /home's hidden files and folders

<code>./backup.sh -d /home/john/ -c gzip -h -a tar</code>   

- root = /dev/sdb1
- grub  
- local file

<code>./restore.sh -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tar.gz -a tar</code>  

- root = /dev/sda1 (ssd)
- syslinux  
- kernel options: nomodeset
- transfer mode  

<code>./restore.sh -r /dev/sda1 -m discard,errors=remount-ro -S /dev/sda -k nomodeset -t</code>  

- root = /dev/sdb1
- home = /dev/sdb2
- swap = /dev/sdb3
- syslinux 
- remote file on ftp server

<code>./restore.sh -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -f ftp://server/backup.tar.xz -a bsdtar</code>

- root = /dev/sdb2
- boot = /dev/sdb1
- syslinux 
- remote file in protected http server

<code>./restore.sh -r /dev/sdb2 -b /dev/sdb1 -S /dev/sdb -f http://server/backup.tar.gz -n user -p pass -a tar</code>

- root = /dev/mapper/debian-root
- boot = /dev/sdb1  
- grub  
- transfer mode  

<code>./restore.sh -r /dev/mapper/debian-root -b /dev/sdb1 -g /dev/sdb -t</code>  

- root = /dev/sda2 (btrfs) with compression
- boot = /dev/sda1
- root subvolume = __active
- /var, /usr and /home subvolumes
- syslinux  
- transfer mode  

<code>./restore.sh -t -b /dev/sda1 -r /dev/sda2 -m compress=lzo -S /dev/sda -R __active -O "/var /usr /home"</code>  

- root = /dev/md1
- boot = /dev/md0
- local file  
- syslinux  

<code>./restore.sh -r /dev/md1 -b /dev/md0 -f /home/john/Downloads/backup.tar.gz -S /dev/md0 -a bsdtar</code>  
