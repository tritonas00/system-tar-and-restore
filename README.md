###ABOUT###

System tar & restore contains two bash scripts, backup and restore.

The purpose is to make the process of backing up and restoring a full GNU/Linux installation easier, 
using tar or transfer an existing installation using rsync.

Supported distributions: Arch, Debian, Fedora

###LIMITATIONS###

- UEFI (not supported - not tested)

###REQUIREMENTS###

- rsync (for Transfer Mode)
- dialog (for ncurses interface)
- wget   (for downloading backup images)

###BACKUP###

Backup script makes a tar backup of / in a given location. It will make a folder in that location which 
contains the *.tgz file, the "errors" file (usefull for tracking tar errors/warnings) and the "log" file which contains the standard tar output.

The script will ask:

- Interface to use 

- If you want to save the backup in the default folder (/root), or enter your desired path

- If you want to include your /home directory

- If /home directory is excluded, it will ask if you want to keep hidden files and folders inside it


The script also supports all input as arguments:

**-i, --interface**   
interface to use

**-d, --directory**  
path for backup folder

**-h, --exclude-home**  
exclude /home directory

**-n, --no-hidden**       
dont keep home's hidden files and folders

**--help**   
show all arguments


Example:

- Backup directory=/home/john/

<code>sudo ./backup -d /home/john/</code>



###RESTORE###

User must create partitions using his favorite partition manager before running the script.
At least one / (root) partition is required and optionally a seperate partition for /home, /boot and a swap partition.

In case of LVM, make sure that all logical volumes are formatted and activated.  

Restore script contains two modes: **Restore** and **Transfer**.

In **Restore Mode**, the script uses the above created archive to extract it in user defined partitions.

In **Transfer Mode**, the script uses rsync to transfer the root filesystem (/) in user defined partitions.

Then generates fstab using uuids, rebuilds initramfs image for every available kernel, re-generates locales, 
installs and auto-configures Grub or Syslinux in MBR of given device and finally unmounts and cleans everything.

The script will ask for:

- Interface to use  

- Root partition ( / )  

- Swap partition ( Optional )  

- Home partition ( Optional )  

- Boot partition   ( Optional )  

- Bootloader. Grub(2) and syslinux/extlinux are both supported.  ( Optional )  

- Bootloader install location. (MBR of the given device)  

- Select Mode

- If the root filesystem is btrfs, the script will ask if you want to create a subvolume for it.
   If yes, it will ask for the subvolume's name and also if you want to create seperate
   subvolumes for /home, /usr and /var inside root subvolume.  

- If Restore Mode is selected it will ask for the *.tgz image file. This can be obtained locally (by entering the full path of the file), or remotelly (by entering full url of the file).
   Also protected url is supported, which will ask for server's username and password.  

- Later it will ask you if you want to edit the generated fstab file further. Old fstab kept as fstab-old.

- At the end, If you didn't choose a bootloader or the selected bootloader not found in the target system, the script will help you to chroot and install a bootloader manually.


The script also supports all input as arguments:

**-i, --interface**   
interface to use

**-t, --transfer**   
activate tranfer mode  

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

**-y, --yes**     
yes to all

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

Recommended subvolume name is: __active.

When using LVM, it also recommended to have a seperate /boot partition.  

###EXAMPLES###

- root = /dev/sdb1
- grub  
- local file

<code>sudo ./restore -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tgz</code>

- root = /dev/sdb1
- home = /dev/sdb2
- swap = /dev/sdb3
- syslinux 
- remote file on ftp server

<code>sudo ./restore -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -S /dev/sdb -u ftp://server/data/backup.tgz</code>

- root = /dev/sdb2
- boot = /dev/sdb1
- home = /dev/sdb3
- syslinux 
- remote file in protected http server

<code>sudo ./restore -r /dev/sdb2 -b /dev/sdb1 -h /dev/sdb3 -S /dev/sdb -u http://server/data/backup.tgz -n user -p pass</code>

- root = /dev/sdb3
- syslinux  
- transfer mode  

<code>sudo ./restore -r /dev/sdb3 -S /dev/sdb -t</code>  

###DEMOS###

http://www.youtube.com/watch?v=GpNSEyaynLk 

http://www.youtube.com/watch?v=QHkCsEW-qY8 

http://www.youtube.com/watch?v=kvExZYeaCZI 