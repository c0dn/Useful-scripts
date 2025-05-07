# Cross-Compile and Deploy Linux Kernel for Raspberry Pi

This script automates the process of cross-compiling the Linux kernel for Raspberry Pi 4 (ARM64) and deploying the custom kernel
to a remote Raspberry Pi device.

## Prerequisites

This script can be run on:
- Native Ubuntu/Debian Linux
- Windows Subsystem for Linux 2 (WSL2) with Ubuntu
- Other Debian-based Linux distributions

### Setting up WSL2 (for Windows users)

If you're using Windows, you can install WSL2 and Ubuntu by following these steps:
1. [Install WSL2 on Windows](https://learn.microsoft.com/en-us/windows/wsl/install)
2. [Install Ubuntu on WSL2](https://ubuntu.com/wsl)

> **⚠️ WARNING**: When using WSL2, do NOT run this script from the Windows filesystem mounted at `/mnt`. Always run the script from your Linux home directory (e.g., `/home/username/`). Running from `/mnt` will significantly slow down the compilation process due to filesystem performance limitations between Windows and WSL.

The script will automatically install the following dependencies:
- git
- bc
- bison
- flex
- libssl-dev
- make
- libc6-dev
- libncurses5-dev
- crossbuild-essential-arm64

Should you decide to adapt this script for other architectures, you will need to install the required crossbuild-essential
package
## Usage

```bash
./build.sh [OPTIONS]
```

### Options

- `-c, --clean` - Perform a clean build (runs `make mrproper`)
- `-m, --module` - Build custom modules from the `custom` directory
- `-v, --version STRING` - Set custom LOCALVERSION (appears in `uname -r` output)
- `-d, --deploy HOST` - Deploy kernel to remote Raspberry Pi (format: user:<password?>@host)
- `-h, --help` - Show help message

## Custom Modules and Configuration

The script supports a `custom` directory structure for building custom kernel modules and configurations:

```
custom/
├── config                  # Optional custom kernel config file (the .config)
└── module_directory_1/     # Directory containing custom module code
    ├── Makefile
    └── source files
└── module_directory_2/
    ├── Makefile
    └── source files
...
```

### Custom Configuration

If a file named `config` exists in the `custom` directory, it will be used as the kernel configuration instead of the default `bcm2711_defconfig`.

### Custom Modules

When using the `-m` or `--module` option, the script will:
1. Search for subdirectories in the `custom` directory
2. Build any subdirectory that contains a  Makefile
3. Install the compiled modules (.ko files) to the kernel staging directory
4. Include these modules in the deployment if deploying to a remote device

Each module directory must contain a proper Makefile for cross-compilation.

## Build Process

The script performs the following steps:
1. Clones the Raspberry Pi Linux kernel repository if not already present
2. Configures the kernel build environment for ARM64 architecture
3. Builds the kernel image, modules, and device tree blobs
4. Creates a staging directory with the compiled kernel and modules

## Deployment

When using the `-d` or `--deploy` option, the script:
1. Packages the kernel, modules, and device tree files into a tar archive
2. Transfers the archive to the remote Raspberry Pi
3. Extracts and installs the files to the appropriate locations
4. Updates module dependencies

The remote user must have write permissions to `/boot/firmware` or sudo access.

> **Note**: After deployment, you must manually reboot the Raspberry Pi to start using the newly installed custom kernel.

## Loading Custom Modules

When deploying with custom modules (`-m` or `--module` option), the compiled kernel modules (.ko files) are copied to the `/lib/modules/<kernel-version>/extra/` directory on the remote system.

For example, if your kernel version is `6.12.25T1+`, the modules will be in:
```
/lib/modules/6.12.25T1+/extra/
```

### Loading Modules on the Remote System

You can load the modules using the `insmod` or `modprobe` commands:

```bash
# Check your current kernel version
uname -r
# Example output: 6.12.25T1+

# Load a module using insmod
sudo insmod /lib/modules/$(uname -r)/extra/module_name.ko

# Or load using modprobe (if dependencies are properly configured)
sudo modprobe module_name

# Verify the module is loaded
lsmod | grep "module_name"
```

### Example Output

```
# Loading a test module
user@william:~ $ sudo insmod /lib/modules/6.12.25T1+/extra/test1.ko
user@william:~ $ dmesg
...
[ 1667.900513] test1: loading out-of-tree module taints kernel.
[ 1667.902432] Loading Module

# Verify kernel version, notice your custom version if any
user@william:~ $ uname -r
6.12.25T1+

# Verify module is loaded
user@william:~ $ lsmod | grep "test1"
test1                  12288  0
```

Note: If you need to load modules automatically at boot time, you can add the module name to `/etc/modules` or create a file in `/etc/modules-load.d/` directory.

## Examples

Build the kernel with default configuration:
```bash
./build.sh
```

Perform a clean build with custom version string:
```bash
./build.sh --clean --version "-my-custom-kernel"
```

Build with custom modules:
```bash
./build.sh --module
```

Build and deploy to a remote Raspberry Pi:
```bash
./build.sh --deploy user@192.168.1.100
```

Complete build and deploy with all options:
```bash
./build.sh --clean --module --version "-custom-v1" --deploy user:mypassword@192.168.1.100