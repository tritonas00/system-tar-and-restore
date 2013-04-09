###ABOUT###

System tar & restore contains two bash scripts, backup and restore.

The purpose is to make the process of backing up and restoring a full GNU/Linux installation easier, 
using tar or transfer an existing installation using rsync.

Supported distributions: Arch, Debian, Fedora

[Demo Video](http://www.youtube.com/watch?v=X4VlZhRqSlU)  

[Download Here (Main scripts and wrappers)](http://code.google.com/p/system-tar-and-restore/downloads/list)  

###LIMITATIONS###

- UEFI (not supported - not tested)

###REQUIREMENTS###

- rsync (for Transfer Mode)
- dialog (for ncurses interface)
- wget   (for downloading backup archives)

###BACKUP###

Backup script makes a tar backup of / in a given location. It will make a folder in that location which 
contains the archive, the "errors" file (usefull for tracking tar errors/warnings) and the "log" file which contains the standard tar output.

The script will ask for:

- Interface to use 

- If you want to save the backup in the default folder (/), or enter your desired path

- If you want to include your /home directory

- If /home directory is excluded, it will ask if you want to keep only hidden files and folders inside it

- If you want to enter any additional tar options (See tar --help)  

- Compression type. GZIP and XZ are supported.


The script also supports all input as arguments:

**-i, --interface**   
interface to use

**-d, --directory**  
path for backup folder

**-h, --exclude-home**  
exclude /home directory

**-n, --no-hidden**       
dont keep home's hidden files and folders

**-c, --compression**  
compression type

**-u, --user-options**   
additional tar options (See tar --help)  

**--help**   
show all arguments



###RESTORE###

User must create partitions using his favorite partition manager before running the script.
At least one / (root) partition is required and optionally a seperate partition for /home, /boot and a swap partition.

In case of LVM, make sure that the target volume group is activated.  

Restore script contains two modes: **Restore** and **Transfer**.

In **Restore Mode**, the script uses the above created archive to extract it in user defined partitions.

In **Transfer Mode**, the script uses rsync to transfer the root filesystem (/) in user defined partitions.

Then generates fstab using uuids, rebuilds initramfs image for every available kernel, re-generates locales, 
installs and auto-configures Grub or Syslinux in MBR of given device and finally unmounts and cleans everything.

The script will ask for:

- Interface to use  

- Root partition  

- (Optional) Swap partition   

- (Optional) Home partition   

- (Optional) Boot partition    

- (Optional) Bootloader and target disk (MBR). Grub2 and Syslinux are both supported.  

- Select Mode

- If the root filesystem is btrfs, the script will ask if you want to create a subvolume for it.
   If yes, it will ask for the subvolume's name and also if you want to create seperate
   subvolumes for /home, /usr and /var inside root subvolume.  

- If Restore Mode is selected it will ask for the backup archive. This can be obtained locally (by entering the full path of the file), or remotelly (by entering the url of the file).
   Also protected url is supported, which will ask for server's username and password.  

- If Transfer Mode is selected, it will ask you if you want to transfer entire /home directory or only it's hidden files and folders.    

- Later it will ask you if you want to edit the generated fstab file further. Old fstab file is saved as */mnt/target/etc/fstab-old*.  

- At the end, if you didn't choose a bootloader or the selected bootloader not found in the target system, the script will help you to chroot and install a bootloader manually.


The script also supports all input as arguments:

**-i, --interface**   
interface to use

**-t, --transfer**   
activate tranfer mode  

**-o,  --only-hidden**  
transfer /home's hidden files and folders only  

**-r, --root**    
root partition

**-s, --swap**     
swap partition

**-b, --boot**     
boot partition

**-h, --home**     
home partition

**-g, --grub**    
disk for grub

**-S, --syslinux**      
disk for syslinux

**-f, --file**      
backup file path

**-u, --url**     
url

**-n, --username**     
username

**-p, --password**     
password

**-q,  --quiet**  
dont ask, just run  

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

In the target system, in case of Syslinux, old directory */boot/syslinux* is saved as */boot/syslinux-old*.  

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

- root = /dev/sdb1
- home = /dev/sdb2
- swap = /dev/sdb3
- syslinux 
- remote file on ftp server

<code>sudo ./restore.sh -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -u ftp://server/data/backup.tar.xz</code>

- root = /dev/sdb2
- boot = /dev/sdb1
- home = /dev/sdb3
- syslinux 
- remote file in protected http server

<code>sudo ./restore.sh -r /dev/sdb2 -b /dev/sdb1 -h /dev/sdb3 -S /dev/sdb -u http://server/data/backup.tar.gz -n user -p pass</code>

- root = /dev/mapper/debian-root
- boot = /dev/sdb1  
- grub  
- transfer mode  

<code>sudo ./restore.sh -r /dev/mapper/debian-root -b /dev/sdb1 -g /dev/sdb -t</code>  

- root = /dev/sda2 (btrfs)
- boot = /dev/sda1
- root subvolume = __active
- /var, /usr and /home subvolumes
- syslinux  
- transfer mode  

<code>sudo ./restore.sh -t -b /dev/sda1 -r /dev/sda2 -S /dev/sda -R __active -V -U -H </code>