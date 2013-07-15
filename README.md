###ABOUT###

System tar & restore contains two bash scripts, **backup.sh** and **restore.sh**.

The purpose is to make the process of backing up and restoring a full GNU/Linux installation easier, 
using tar or transfer an existing installation using rsync.

Supported distributions: Arch, Debian, Fedora*   
<sub>*Fedora 19 tar: xattrs patch bug(?), decompressed system can't login. Downgrading to 1.26-12.fc18 fixes the problem. Transfer Mode works.</sub>

[Demo Video](http://www.youtube.com/watch?v=o03AEflC6qI&hd=1)  
[Stable Releases](https://github.com/tritonas00/system-tar-and-restore/releases)  

###LIMITATIONS###

- UEFI (not supported - not tested)

###REQUIREMENTS###

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

- If you want to include your /home directory

- If /home directory is excluded, it will ask if you want to keep only hidden files and folders inside it

- If you want to enter any additional tar options (See tar --help)  

- Compression type. GZIP and XZ are supported.


The script also supports all input as arguments:

**-i, --interface**   
interface to use (CLI Dialog)

**-N, --no-color**   
disable colors

**-d, --directory**  
backup folder path

**-h, --exclude-home**  
exclude /home (keep hidden files and folders)  

**-n, --no-hidden**       
dont keep home's hidden files and folders (use with -h)  

**-c, --compression**  
compression type (GZIP XZ)  

**-u, --user-options**   
additional tar options (See tar --help)  

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

- Interface to use (CLI Dialog)  

- Target root partition  and additional mount options  

- (Optional) Target home partition   

- (Optional) Target boot partition    

- (Optional) Swap partition   

- (Optional) Bootloader and target disk (MBR). Grub2 and Syslinux are both supported.
   If Syslinux is selected, it will ask for additional kernel options which will be written in syslinux.cfg.
   If a raid array is selected, the script will install the bootloader in all disks that the array contains.  

- Select Mode

- If the root filesystem is btrfs, the script will ask if you want to create a subvolume for it.
   If yes, it will ask for the subvolume's name and also if you want to create seperate
   subvolumes for /home, /usr and /var inside root subvolume.  

- If Restore Mode is selected it will ask for the backup archive. This can be obtained locally (by entering the full path of the file), or remotelly (by entering the url of the file).
   Also protected url is supported, which will ask for server's username and password.  

- If Transfer Mode is selected, it will ask you if you want to transfer entire /home directory or only it's hidden files and folders.    

- Later it will ask you if you want to edit the generated fstab file further. Old fstab file is saved as */mnt/target/etc/fstab-old*.  

- At the end, if you didn't choose a bootloader or the selected bootloader not found in the target system, the script will help you to chroot and install a bootloader manually.

Log file is saved as */tmp/restore.log*

The script also supports all input as arguments:

**-i, --interface**   
interface to use (CLI Dialog)  

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

**-m, --mount-options**     
comma-separated list of mount options (root partition)

**-g, --grub**    
target disk for grub

**-S, --syslinux**      
target disk for syslinux

**-k, --kernel-options**      
additional kernel options (syslinux)

**-f, --file**      
backup file path

**-u, --url**     
url

**-n, --username**     
username

**-p, --password**     
password

**-R, --rootsubvolname**   
subvolume name for root

**-H, --homesubvol**   
 make subvolume for /home

**-V, --varsubvol**   
make subvolume for /var

**-U, --usrsubvol**   
make subvolume for /usr

**--help**   
 show all arguments

###NOTES###

The system that runs the restore script and the target system (the one you want to restore), must have the same architecture (for chroot to work).

For booting a btrfs subvolumed root successfully with Syslinux, it is recommended to have a seperate /boot partition.
Recommended subvolume name is: *__active*  

When using LVM, it is also recommended to have a seperate /boot partition.  

When using RAID, it is recommended to create a seperate raid1 array with metadata=1.0 as your /boot partition.  

When using GRUB with BIOS and GPT you must create a BIOS Boot Partition: ~1 MiB unformatted partition with bios_grub flag enabled (0xEF02 for gdisk).  

In the target system, in case of Syslinux, old */boot/syslinux/syslinux.cfg* is saved as */boot/syslinux.cfg-old*.  

In the target system, if distribution is Fedora and Grub is selected, old */etc/default/grub* is saved as */etc/default/grub-old*.  


###EXAMPLES USING ARGUMENTS###

- Backup directory=/home/john/
- Compression: GZIP  

<code>sudo ./backup.sh -d /home/john/ -c GZIP</code>  

- Backup directory=/home/john/
- Compression: XZ  
- Exclude /home directory  

<code>sudo ./backup.sh -d /home/john/ -c XZ -h -n</code>   

- Backup directory=/home/john/
- Compression: GZIP  
- Keep only /home's hidden files and folders

<code>sudo ./backup.sh -d /home/john/ -c GZIP -h</code>   

- root = /dev/sdb1
- grub  
- local file

<code>sudo ./restore.sh -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tar.gz</code>  

- root = /dev/sda1 (ssd)
- syslinux  
- kernel options: nomodeset
- transfer mode  

<code>sudo ./restore.sh -r /dev/sda1 -m discard,errors=remount-ro -S /dev/sda -k nomodeset -t</code>  

- root = /dev/sdb1
- home = /dev/sdb2
- swap = /dev/sdb3
- syslinux 
- remote file on ftp server

<code>sudo ./restore.sh -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -u ftp://server/data/backup.tar.xz</code>

- root = /dev/sdb2
- boot = /dev/sdb1
- syslinux 
- remote file in protected http server

<code>sudo ./restore.sh -r /dev/sdb2 -b /dev/sdb1 -S /dev/sdb -u http://server/backup.tar.gz -n user -p pass</code>

- root = /dev/mapper/debian-root
- boot = /dev/sdb1  
- grub  
- transfer mode  

<code>sudo ./restore.sh -r /dev/mapper/debian-root -b /dev/sdb1 -g /dev/sdb -t</code>  

- root = /dev/sda2 (btrfs) with compression
- boot = /dev/sda1
- root subvolume = __active
- /var, /usr and /home subvolumes
- syslinux  
- transfer mode  

<code>sudo ./restore.sh -t -b /dev/sda1 -r /dev/sda2 -m compress=lzo -S /dev/sda -R __active -V -U -H </code>  

- root = /dev/md1
- boot = /dev/md0
- local file  
- syslinux  

<code>sudo ./restore.sh -r /dev/md1 -b /dev/md0 -f /home/john/Downloads/backup.tar.gz -S /dev/md0</code>  

###WRAPPERS###

There are available two zenity wrappers for the main scripts, **backup-zenity** and **restore-zenity**.
Wrappers and main scripts must be in the same directory and executed as normal user.

###REQUIREMENTS###

- zenity
- xterm

###WRAPPER SCREENSHOTS###

![ScreenShot] (https://raw.github.com/tritonas00/system-tar-and-restore/master/screenshots/backup.jpg)

![ScreenShot] (https://raw.github.com/tritonas00/system-tar-and-restore/master/screenshots/restore.jpg)
