System tar & restore contains two bash scripts, backup and restore.

The purpose is to make the process of backing up and restoring a full GNU/Linux installation easier, 
using tar.

Supported distributions: Arch, Debian, Fedora

###BACKUP###

Backup script makes a tar backup of / in a given location. It will make a folder in that location which 
contains the *.tgz file, the "errors" file (usefull for tracking tar errors/warnings) and the "log" file which contains the standard tar output.

The script will ask:

- If you want to save the backup in the default folder (/root), or enter your desired path

- If you want to include your entire home directory. ( If selected no, only hidden files and folders 
   will be included in the backup, just to save user's configurations)

- If fedora's patched tar will be used  (Necessary if the host and the target system is Fedora)


The script also supports all input as arguments:

**-d**  
path for backup folder

**-h**  
exclude /home, keep only hidden files and folders

**-f**   
use Fedora's patched tar

Examples:

- Backup directory=/home/john/
- Include /home
- No fedora's patched tar

<code>sudo ./backup -d /home/john/</code>

- Backup directory=/home/john/
- Exclude /home ( Only include hidden folders and files)
- Fedora's tar in use

<code>sudo ./backup -f -h -d /home/john/</code>


###RESTORE###

Restore script uses the above created archive to extract it in user defined partitions, generates fstab using uuids,
rebuilds initramfs image, installs and auto-configures grub or syslinux in MBR of given device,
re-generate locales and finally unmounts and cleans everything.

User must create partitions using his favorite partition manager before running the script.
At least one / (root) partition is required and optionally a seperate partition for /home, /boot and a swap partition.
If you want the script to create and manage btrfs subvolumes, btrfs-progs must be installed before restoring.

If you want to use syslinux for booting a btrfs subvolumed root, you need 
a seperate /boot partition and also the subvolume's name must be __active

Also for Debian and Fedora a seperate /boot partition is required for booting a btrfs subvolumed root successfully.


The script will ask for:

- Target distibution's name. This is the name of the distribution which the tar backup contains.

- Root partition ( / )

- Swap partition ( Optional )

- Home partition ( Optional )

- Boot partition   ( Optional )

- Bootloader. Grub(2) and syslinux/extlinux are both supported.

- Bootloader install location. (MBR of the given device)

- If the root filesystem is btrfs, the script will ask if you want to create a subvolume for it.
   If yes, it will ask for the subvolume's name and also if you want to create seperate
   subvolumes for /home, /usr and /var inside root subvolume.

- The *.tgz image file. This can be obtained localy (by entering the full path of the file), or remotelly (by entering full url of the file).
   Also protected url is supported, which will ask for server's username and password.


The script also supports all input as arguments:

**-d, --distro**   
target distribution

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


Examples:

- Distro= Arch
- root = /dev/sdb1
- grub  
- local file

<code>sudo ./restore -d Arch -r /dev/sdb1 -g /dev/sdb -f /home/john/Downloads/backup.tgz</code>

- Distro= Debian
- root = /dev/sdb1
- home = /dev/sdb2
- swap = /dev/sdb3
- syslinux 
- remote file on ftp server

<code>sudo ./restore -d Debian -r /dev/sdb1 -h /dev/sdb2 -s /dev/sdb3 -l /dev/sdb -u ftp://server/data/backup.tgz</code>

- Distro= Fedora
- root = /dev/sdb2
- boot = /dev/sdb1
- home = /dev/sdb3
- syslinux 
- remote file in protected http server

<code>sudo ./restore -d Fedora -r /dev/sdb2 -b /dev/sdb1 -h /dev/sdb3 -l /dev/sdb -u http://server/data/backup.tgz -n user -p pass</code>


Demo : http://www.youtube.com/watch?v=eoGKI1Ls1ng