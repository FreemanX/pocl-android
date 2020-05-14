#!/bin/bash
PWD=`pwd`
I_AM=`id -un`
MY_GROUP=`id -gn` 

POCL_DEPENDENCY=$HOME/Project/pocl-dependency/
ANDROID_NDK=$HOME/toolchains/android-ndk-r17c
ANDROID_TOOLCHAIN=/tmp/android-toolchain_r17

ANDROID_TOOLCHAIN_BIN=$ANDROID_TOOLCHAIN/bin/
ANDROID_TOOLCHAIN_SYSROOT_USR=$ANDROID_TOOLCHAIN/sysroot/usr/
ANDROID_TOOLCHAIN_SYSROOT_AARCH64_LIB=$ANDROID_TOOLCHAIN/sysroot/usr/lib/


if [ ! -e $POCL_DEPENDENCY ]; then
	echo "Can't find pocl dependencies, you may download from https://github.com/FreemanX/pocl-android-dependency"
	echo "Please reset ANDROID_NDK, now is $ANDROID_NDK"
	echo "Please read through this script if this is the first time you run it"
	exit -1
fi 

if [ ! -f $ANDROID_NDK/build/tools/make_standalone_toolchain.py ]; then
	echo "Can't find make_standalone_toolchain.py"
	echo "Please reset ANDROID_NDK, now is $ANDROID_NDK"
	echo "Please read through this script if this is the first time you run it"
	exit -1
fi 

echo "NDK standalone toolchain setup..."
$ANDROID_NDK/build/tools/make_standalone_toolchain.py \
	--arch=arm64 \
	--api=26 \
	--stl=libc++ \
	--install-dir=$ANDROID_TOOLCHAIN \
	--force

INSTALL_PREFIX=$HOME/Project/pocl/
# Create directories for PREFIX, target location in android
if [ ! -e $INSTALL_PREFIX ]; then
	mkdir -p $INSTALL_PREFIX
	mkdir -p $INSTALL_PREFIX/lib/pkgconfig/
	#chown -R $I_AM:$MY_GROUP $INSTALL_PREFIX
	#chmod 755 -R $INSTALL_PREFIX
fi

# Prebuilt llvm lib that run on(android) -> target(android)
# Prebuilt llvm bin that run on(x64) -> target(android)
echo "copying llvm to $ANDROID_TOOLCHAIN_SYSROOT_USR ..."
cp -rf $POCL_DEPENDENCY/llvm/* $ANDROID_TOOLCHAIN_SYSROOT_USR


echo "copying ncurses to $ANDROID_TOOLCHAIN_SYSROOT_USR ..."
cp -rf $POCL_DEPENDENCY/ncurses/* $ANDROID_TOOLCHAIN_SYSROOT_USR
ln -sf $ANDROID_TOOLCHAIN_SYSROOT_USR/lib/libncurses.a $ANDROID_TOOLCHAIN_SYSROOT_USR/lib/libcurses.a
ln -sf $ANDROID_TOOLCHAIN_SYSROOT_USR/lib/libncurses.a $ANDROID_TOOLCHAIN_SYSROOT_USR/lib/libtinfo.a


echo "copying ltdl to $ANDROID_TOOLCHAIN_SYSROOT_USR ..."
cp -rf $POCL_DEPENDENCY/libtool/* $ANDROID_TOOLCHAIN_SYSROOT_USR


echo "copying hwloc to $ANDROID_TOOLCHAIN_SYSROOT_USR ..."
cp -rf $POCL_DEPENDENCY/hwloc/* $ANDROID_TOOLCHAIN_SYSROOT_USR


echo "copying ld to $ANDROID_TOOLCHAIN_SYSROOT_USR ..."
cp -rf $POCL_DEPENDENCY/binutils/* $ANDROID_TOOLCHAIN_SYSROOT_USR


ln -sf $ANDROID_TOOLCHAIN_SYSROOT_AARCH64_LIB/libc.a $ANDROID_TOOLCHAIN_SYSROOT_AARCH64_LIB/libpthread.a
ln -sf $ANDROID_TOOLCHAIN_SYSROOT_AARCH64_LIB/libc.a $ANDROID_TOOLCHAIN_SYSROOT_AARCH64_LIB/librt.a
ln -sf $ANDROID_TOOLCHAIN_SYSROOT_USR/include/GLES3 $ANDROID_TOOLCHAIN_SYSROOT_USR/include/GL

ln -sf $ANDROID_TOOLCHAIN_BIN/aarch64-linux-android-clang $ANDROID_TOOLCHAIN_SYSROOT_USR/bin/clang
ln -sf $ANDROID_TOOLCHAIN_BIN/aarch64-linux-android-clang++ $ANDROID_TOOLCHAIN_SYSROOT_USR/bin/clang++

ln -sf $ANDROID_TOOLCHAIN_BIN/clang* $ANDROID_TOOLCHAIN_SYSROOT_USR/bin/

ln -sf $ANDROID_TOOLCHAIN_BIN/llvm-as $ANDROID_TOOLCHAIN_SYSROOT_USR/bin/
ln -sf $ANDROID_TOOLCHAIN_BIN/llvm-link $ANDROID_TOOLCHAIN_SYSROOT_USR/bin/
ln -sf $ANDROID_TOOLCHAIN_SYSROOT_USR/lib/aarch64-linux-android/* $ANDROID_TOOLCHAIN_SYSROOT_USR/lib/

export PATH=$ANDROID_TOOLCHAIN_SYSROOT_USR/bin:$ANDROID_TOOLCHAIN_BIN:$PATH
export LD_LIBRARY_PATH=$ANDROID_TOOLCHAIN_SYSROOT_USR/lib:$ANDROID_TOOLCHAIN_SYSROOT_AARCH64_LIB:$LD_LIBRARY_PATH
export HOST=aarch64-linux-android
#export TARGET_CPU="kryo"
export TARGET_CPU="cortex-a75"
export CC=$ANDROID_TOOLCHAIN_BIN/$HOST-clang
export CXX=$ANDROID_TOOLCHAIN_BIN/$HOST-clang++
export AR=$ANDROID_TOOLCHAIN_BIN/$HOST-ar
export LD=$ANDROID_TOOLCHAIN_BIN/$HOST-ld.gold
export RANLIB=$ANDROID_TOOLCHAIN_BIN/$HOST-ranlib
export LDFLAGS=" -pie "
export PREFIX=$INSTALL_PREFIX

cp -r $ANDROID_TOOLCHAIN/aarch64-linux-android/lib $ANDROID_TOOLCHAIN/sysroot/usr/ 

reStart=0
reBuild=0
push2Phone=0
makej8=0
while [ "$1" != "" ]; do
	case $1 in
		-R | --restart ) reStart=1
			;;
		-r | --rebuild ) reBuild=1
			;;
		-p | --push ) push2Phone=1
			;;
		-f | --fast ) makej8=1
			;;
		-mp | --makePush ) makej8=1
			push2Phone=1
			;;
	esac
	shift
done

if [ "$reStart" = "1" ]; then
	echo "Rebuild everything"	
	rm -rf build-android
fi

[ ! -d "build-android" ] && mkdir build-android
cd build-android

if [ ! "$(ls -A .)" ] || [ "$reBuild" = "1" ]; then 
	cmake \
		-DANDROID_TOOLCHAIN=$ANDROID_TOOLCHAIN \
		-DCMAKE_CROSSCOMPILING=ON \
		-DCMAKE_TOOLCHAIN_FILE=../androideabi.cmake \
		-DCMAKE_C_COMPILER=$CC \
		-DCMAKE_CXX_COMPILER=$CXX \
		-DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo \
		-DCMAKE_AR:FILEPATH=$HOST-ar \
		-DCMAKE_RANLIB:FILEPATH=$HOST-ranlib \
		-DCMAKE_CXX_FLAGS:STRING=" -O3 -static-libstdc++ -fPIE -fPIC -fuse-ld=$LD " \
		-DCMAKE_C_FLAGS:STRING=" -O3 -static-libstdc++ -fPIE -fPIC " \
		-DPOCL_DEBUG_MESSAGES=ON \
		-DCMAKE_INSTALL_PREFIX:PATH=$PREFIX \
		-DLLC_HOST_CPU=$TARGET_CPU \
		..
fi


if [ "$makej8" = "1" ]; then
	make -j8
else
	make
fi 

if [ "$push2Phone" = "1" ]; then
	make install
	INSTALL_PREFIX=/data/local/tmp/pocl/
	adb push $HOME/Project/pocl/lib/* $INSTALL_PREFIX/lib/
	adb push $HOME/Project/pocl/bin/* $INSTALL_PREFIX/bin
	adb push $HOME/Project/pocl/share $INSTALL_PREFIX
	adb push $POCL_DEPENDENCY/binutils/bin/ld $INSTALL_PREFIX
fi
