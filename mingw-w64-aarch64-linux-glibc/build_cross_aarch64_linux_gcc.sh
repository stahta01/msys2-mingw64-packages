#! /bin/bash
set -e
trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
trap 'echo FAILED COMMAND: $previous_command' EXIT

#-------------------------------------------------------------------------------------------
# This script will download packages for, configure, build and install a GCC cross-compiler.
# Customize the variables (INSTALL_PATH, LONG_TARGET, etc.) to your liking before running.
# If you get an error and need to resume the script from some point in the middle,
# just delete/comment the preceding lines before running it again.
#
# Forked from: https://gist.github.com/preshing/41d5c7248dea16238b60
#-------------------------------------------------------------------------------------------

INSTALL_PATH=/opt/local/cross
export PATH=$INSTALL_PATH/bin:/usr/bin
LINUX_ARCH=arm64
PARALLEL_MAKE=-j2
BASE_TARGET=aarch64-linux
LONG_TARGET=${BASE_TARGET}-gnu
CONFIGURATION_OPTIONS="--disable-multilib" # --disable-threads --disable-shared
BINUTILS_VERSION=binutils-2.34
GCC_VERSION=gcc-10.2.0
MAJOR_KERNEL_VERSION=5
LINUX_KERNEL_VERSION=linux-$MAJOR_KERNEL_VERSION.5
GLIBC_VERSION=glibc-2.32
MPFR_VERSION=mpfr-3.1.4
GMP_VERSION=gmp-6.1.2
MPC_VERSION=mpc-1.0.3
ISL_VERSION=isl-0.22

extract() {
    local tarfile="$1"
    local extracted="$(echo "$tarfile" | sed 's/\.tar.*$//')"
    if [ ! -d  "src/$extracted" ]; then
        echo "Extracting ${tarfile}"
        mkdir -p "src"
        tar -xf $tarfile -C src
    fi
}

extract_to_gcc_folder() {
    local tarfile="$1"
    local subfolder="$(echo "$tarfile" | sed 's/-.*$//')"
    if [ ! -d  "src/$GCC_VERSION/$subfolder" ]; then
        echo "Extracting ${tarfile} to src/$GCC_VERSION/$subfolder"
        mkdir -p "src/$GCC_VERSION/$subfolder"
        tar -x --strip-components=1 -f "$tarfile" -C "src/$GCC_VERSION/$subfolder"
    fi
}

# Download packages
export http_proxy=$HTTP_PROXY https_proxy=$HTTP_PROXY ftp_proxy=$HTTP_PROXY
wget -nc https://ftp.gnu.org/gnu/binutils/$BINUTILS_VERSION.tar.gz
wget -nc https://ftp.gnu.org/gnu/gcc/$GCC_VERSION/$GCC_VERSION.tar.gz
wget -nc https://www.kernel.org/pub/linux/kernel/v$MAJOR_KERNEL_VERSION.x/$LINUX_KERNEL_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/glibc/$GLIBC_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/mpfr/$MPFR_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/gmp/$GMP_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/mpc/$MPC_VERSION.tar.gz
wget -nc http://isl.gforge.inria.fr/$ISL_VERSION.tar.bz2

# Extract packages
extract                     $BINUTILS_VERSION.tar.gz
extract                     $GCC_VERSION.tar.gz
extract_to_gcc_folder       $MPFR_VERSION.tar.xz
extract_to_gcc_folder       $GMP_VERSION.tar.xz
extract_to_gcc_folder       $MPC_VERSION.tar.gz
extract_to_gcc_folder       $ISL_VERSION.tar.bz2
extract                     $LINUX_KERNEL_VERSION.tar.xz || true
extract                     $GLIBC_VERSION.tar.xz || true
cp src/$GLIBC_VERSION/benchtests/strcoll-inputs/filelist#en_US.UTF-8 src/$GLIBC_VERSION/benchtests/strcoll-inputs/filelist#C

cd src

# Step 1. Binutils
mkdir -p build-binutils
cd build-binutils
../$BINUTILS_VERSION/configure --prefix=$INSTALL_PATH --target=$LONG_TARGET $CONFIGURATION_OPTIONS
make $PARALLEL_MAKE
make install
cd ..

# Step 2. Linux Kernel Headers
cd $LINUX_KERNEL_VERSION
make ARCH=$LINUX_ARCH INSTALL_HDR_PATH=$INSTALL_PATH/$LONG_TARGET headers_install
cd ..

# Step 3. C/C++ Compilers
mkdir -p build-gcc
cd build-gcc
../$GCC_VERSION/configure --prefix=$INSTALL_PATH --target=$LONG_TARGET --enable-languages=c,c++ --disable-libsanitizer $CONFIGURATION_OPTIONS
make $PARALLEL_MAKE all-gcc
make install-gcc
cd ..

# Step 4. Standard C Library Headers and Startup Files
cd $GLIBC_VERSION
# Replace "oS" with "oZ" to avoid filename clashes
sed -i 's/.oS)/.oZ)/g; s/.oS$/.oZ/g; s/.oS =/.oZ =/g'       Makeconfig
sed -i 's/.oS,/.oZ,/g; s/.oS +=/.oZ +=/g; s/.oS)/.oZ)/g'    Makerules 
sed -i 's/.oS)/.oZ)/g; s/.oS,/.oZ,/g'                       extra-lib.mk        
sed -i 's/.oS)/.oZ)/g'                                      nptl/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  csu/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/i386/i686/Makefile
sed -i 's/.oS,/.oZ,/g'                                      sysdeps/ieee754/ldbl-opt/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/sparc/sparc32/sparcv9/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/sparc/sparc64/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/unix/sysv/linux/mips/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/x86/Makefile
sed -i 's/,oS}/,oZ}/g'                                      scripts/check-local-headers.sh
# use copy because the rellns-sh has issues under msys2
sed -i 's|$(LN_S) `$(..)scripts/rellns-sh -p $< $@` $@|cp -p $< $@|' Makerules
cd ..
mkdir -p build-glibc
cd build-glibc
../$GLIBC_VERSION/configure --prefix=$INSTALL_PATH/$LONG_TARGET --build=$MACHTYPE --host=$LONG_TARGET --target=$LONG_TARGET --with-headers=$INSTALL_PATH/$LONG_TARGET/include $CONFIGURATION_OPTIONS libc_cv_forced_unwind=yes
make install-bootstrap-headers=yes install-headers
make $PARALLEL_MAKE csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o $INSTALL_PATH/$LONG_TARGET/lib
$LONG_TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $INSTALL_PATH/$LONG_TARGET/lib/libc.so
touch $INSTALL_PATH/$LONG_TARGET/include/gnu/stubs.h
cd ..

# Step 5. Compiler Support Library
cd build-gcc
make $PARALLEL_MAKE all-target-libgcc
make install-target-libgcc
cd ..

# Step 6. Standard C Library & the rest of Glibc
cd build-glibc
make $PARALLEL_MAKE
make install
cd ..

# Step 7. Standard C++ Library & the rest of GCC
cd build-gcc
make $PARALLEL_MAKE all
make install
cd ..

trap - EXIT
echo 'Success!'
