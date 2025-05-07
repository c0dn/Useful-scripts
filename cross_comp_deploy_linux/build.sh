#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CUSTOM_SRC_DIR="${SCRIPT_DIR}/custom" # Default custom directory path

do_clean=false
do_modules=false
local_version=""
do_deploy=false
remote_user_host=""
tar_file_name="kernel_staging.tar.gz"

# Help function
function show_help {
  echo "Usage: $(basename $0) [OPTIONS]"
  echo "Options:"
  echo "  -c, --clean            Perform a clean build"
  echo "  -m, --module           Build custom modules"
  echo "  -v, --version STRING   Set custom LOCALVERSION (appears in uname -r output)"
  echo "  -d, --deploy HOST      Deploy kernel to remote Raspberry Pi (format: user:<password?>@host)"
  echo "  -h, --help             Show this help message"
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--clean)
      do_clean=true
      echo "Clean build requested."
      shift
      ;;
    -m|--module)
      do_modules=true
      echo "Custom module build requested."
      shift
      ;;
    -v|--version)
      if [[ -n "$2" && "${2:0:1}" != "-" ]]; then
        local_version="$2"
        echo "Custom LOCALVERSION set to: $local_version"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -d|--deploy)
      if [[ -n "$2" && "${2:0:1}" != "-" ]]; then
        do_deploy=true
        remote_user_host="$2"
        echo "Deployment to $remote_user_host requested"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -h|--help)
      show_help
      ;;
    *)
      # Unknown option
      echo "Unknown option: $1"
      show_help
      ;;
  esac
done

sudo apt install git bc bison flex libssl-dev make libc6-dev libncurses5-dev crossbuild-essential-arm64 build-essential -y

if [ ! -d "linux" ]; then
  echo "'linux' directory not found. Cloning repository..."
  git clone --depth=1 https://github.com/raspberrypi/linux.git
else
  echo "'linux' directory found. Skipping clone."
fi

cd linux
KERNEL=kernel8
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
ABS_CUSTOM_SRC_DIR=$(realpath "$CUSTOM_SRC_DIR") # Get absolute path for make M=

if [ "$do_clean" = true ]; then
  echo "Running 'make mrproper'..."
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
fi

# --- Use Custom Config if found ---
CUSTOM_CONFIG="${ABS_CUSTOM_SRC_DIR}/config"
if [ -f "$CUSTOM_CONFIG" ]; then
  echo "Found custom config at '$CUSTOM_CONFIG'. Copying to .config..."
  cp "$CUSTOM_CONFIG" .config
  echo "Running 'make olddefconfig' to update .config based on custom config."
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} olddefconfig # Update config based on the copied one
else
  echo "No custom config found at '$CUSTOM_CONFIG'. Using defaults."
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} bcm2711_defconfig
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} olddefconfig
fi

# Replace LOCALVERSION in .config if specified
if [ -n "$local_version" ]; then
  echo "Setting CONFIG_LOCALVERSION=\"$local_version\" in .config"
  sed -i '/CONFIG_LOCALVERSION=/d' .config
  echo "CONFIG_LOCALVERSION=\"$local_version\"" >> .config
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} olddefconfig
fi

# --- Build and Deployment Functions ---

function build_kernel() {
  echo "Building kernel..."
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} Image modules dtbs -j $(( $(nproc) - 1 ))
  
  # Create a staging directory for kernel built
  mkdir -p ../kernel_staging
  
  # Install modules into the staging directory
  make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} INSTALL_MOD_PATH=../kernel_staging modules_install
  
  # Copy kernel image to staging directory
  mkdir -p ../kernel_staging/boot/overlays
  sudo cp -R arch/arm64/boot/Image ../kernel_staging/boot/kernel8.img
  sudo cp -R arch/arm64/boot/dts/broadcom/*.dtb ../kernel_staging/boot/
  sudo cp -R arch/arm64/boot/dts/overlays/* ../kernel_staging/boot/overlays/
}

function deploy_kernel() {
  local localKernelStaging="../kernel_staging"
  local remoteStagingDir="/tmp/kernel_staging"
  local remoteBootPath="/boot/firmware"
  
  echo -e "\e[36mStarting 64-bit Kernel file transfer to ${remote_user_host} for RPi4...\e[0m"
  
  # --- Check Source Paths ---
  if [ ! -d "${localKernelStaging}" ]; then
    echo -e "\e[31mError: Local kernel staging directory not found: '${localKernelStaging}'. Make sure build was successful.\e[0m"
    exit 1
  fi
  
  # --- IMPORTANT PERMISSIONS WARNING ---
  echo -e "\n\e[33mWARNING: The remote user '${remote_user_host%%@*}' needs write permissions for '${remoteBootPath}'.\e[0m"
  echo -e "\e[33mIf transfers fail with 'Permission denied', you may need sudo access on the remote machine.\e[0m"
  
  # 1. Create a tar archive of the kernel_staging directory
  echo "Creating tar archive of kernel_staging directory..."
  tar czf "${tar_file_name}" -C "$(dirname "${localKernelStaging}")" "$(basename "${localKernelStaging}")"
  if [ $? -ne 0 ]; then
    echo -e "\e[31mError: Failed to create tar archive of kernel_staging directory.\e[0m"
    exit 1
  fi
  echo -e "\e[32mSuccessfully created tar archive: ${tar_file_name}\e[0m"
  
  # 2. Transfer tar file to remote machine
  echo "Transferring tar archive to remote machine..."
  scp "${tar_file_name}" "${remote_user_host}:/tmp/"
  if [ $? -ne 0 ]; then
    echo -e "\e[31mError: SCP command failed transferring tar archive.\e[0m"
    exit 1
  fi
  echo -e "\e[32mSuccessfully transferred tar archive to remote machine.\e[0m"
  
  # 3. Extract tar file on remote and install files to final locations
  echo "Extracting tar file on remote and installing files..."
  ssh "${remote_user_host}" <<EOF
  # Remove any existing staging directory
  rm -rf ${remoteStagingDir}
  
  # Extract the tar file
  mkdir -p ${remoteStagingDir}
  tar xzf /tmp/${tar_file_name} -C /tmp/
  
  # Install files to final locations
  sudo cp -R ${remoteStagingDir}/boot/* ${remoteBootPath}/
  sudo chmod -R +x ${remoteBootPath}/
  
  # Copy kernel modules - find the kernel version folder in the staging area
  if [ -d "${remoteStagingDir}/lib/modules" ]; then
    # Find the kernel version directory (should be named like 6.12.25-v8+)
    for kernelVerDir in ${remoteStagingDir}/lib/modules/*/ ; do
      if [ -d "\${kernelVerDir}" ]; then
        kernelVer=\$(basename "\${kernelVerDir}")
        echo "Found kernel module directory for version: \${kernelVer}"
        
        # Create destination directory and copy modules
        sudo mkdir -p "/lib/modules/\${kernelVer}"
        sudo cp -r "\${kernelVerDir}"/* "/lib/modules/\${kernelVer}/"
        echo "Copied kernel modules to /lib/modules/\${kernelVer}/"
        
        # Update module dependencies
        sudo depmod -a "\${kernelVer}"
      fi
    done
  else
    echo "No kernel modules found in staging area"
  fi
  
  # Clean up
  rm /tmp/${tar_file_name}
  rm -rf ${remoteStagingDir}
EOF
  
  # 4. Clean up local tar file
  echo "Cleaning up local tar file..."
  rm "${tar_file_name}"
  
  echo -e "\n\e[36mKernel deployment completed successfully.\e[0m"
}

# Build the kernel
build_kernel

# --- Build Custom Modules if requested ---
if [ "$do_modules" = true ]; then
  echo "Building custom modules from ${ABS_CUSTOM_SRC_DIR}..."
  # Determine kernel release for module staging directory
  KERNEL_RELEASE=$(make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -s kernelrelease)
  STAGING_MOD_EXTRA_DIR="../kernel_staging/lib/modules/${KERNEL_RELEASE}/extra"
  mkdir -p "$STAGING_MOD_EXTRA_DIR"
  
  found_custom_modules=false
  for mod_dir in ${ABS_CUSTOM_SRC_DIR}/*/ ; do
    if [ -d "$mod_dir" ] && [ -f "$mod_dir/Makefile" ]; then
      mod_name=$(basename "$mod_dir")
      echo "Building module in $mod_dir"
      
      # Cross-compile the module with proper kernel build path
      make -C . M="$mod_dir" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
      if [ $? -ne 0 ]; then
        echo "Error building custom module in $mod_dir"
        exit 1
      fi
      
      # Copy the compiled modules to staging directory
      echo "Installing $mod_name module to $STAGING_MOD_EXTRA_DIR"
      find "$mod_dir" -name "*.ko" -exec cp -v {} "$STAGING_MOD_EXTRA_DIR/" \;
      found_custom_modules=true
    fi
  done
  
  if [ "$found_custom_modules" = true ]; then
    echo "Successfully built and installed custom modules to staging directory"
  else
    echo "No custom modules found in ${ABS_CUSTOM_SRC_DIR}"
  fi
fi

# Deploy kernel if requested
if [ "$do_deploy" = true ]; then
  deploy_kernel
fi