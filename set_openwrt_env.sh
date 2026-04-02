#!/bin/bash

#Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
#SPDX-License-Identifier: BSD-3-Clause-Clear

TOPDIR=$(pwd)
PRPL_VERSION=$(sed -n -e 's/^PRPL_VERSION_NUMBER:= *//p' "include/version.mk" | grep -oE '[0-9]+([.][0-9]+)?')
PRPL_VERSION=$(echo $PRPL_VERSION | awk '{print $1}')
OWRT_VERSION=$(sed -n -e 's/^VERSION_NUMBER:= *//p' "include/version.mk" | grep -oE '[0-9]+([.][0-9]+)?')
OWRT_VERSION=$(echo $OWRT_VERSION | awk '{print $1}')
echo ${PRPL_VERSION}
echo ${OWRT_VERSION}
/bin/cp $TOPDIR/owrt-qti-conf/feeds.conf $TOPDIR

bazel_based_target=0
if (( "${OWRT_VERSION%%.*}"=="23")) || (( "${OWRT_VERSION%%.*}"=="24")); then
        /bin/cp $TOPDIR/owrt-qti-conf/V${OWRT_VERSION%%.*}/feeds.conf $TOPDIR
fi

function feeds_conf_path(){
	if [ -n "${PRPL_VERSION}" ] && (( "${PRPL_VERSION%%.*}"=="4" )) ; then

	src_dir="$TOPDIR/owrt-qti-conf/P4/${1}"
	src_profile="$src_dir/feeds_${2}.conf"
	src_default="$src_dir/feeds.conf"

	if [ -f "$src_profile" ]; then
		/bin/cp "$src_profile" "$TOPDIR/feeds.conf" || { echo "ERROR: Failed to copy '$src_profile'"; return 1; }
	elif [ -f "$src_default" ]; then
		/bin/cp "$src_default" "$TOPDIR/feeds.conf" || { echo "ERROR: Failed to copy '$src_default'"; return 1; }
	else
		echo "ERROR: Neither '$src_profile' nor '$src_default' exists"
		return 1
	fi

	fi
}

cd $TOPDIR
umask 022

function set_sectools_path(){
        if [ -z "${SECTOOLS_PATH}" ]; then
                echo "Please export SECTOOLS_PATH variable..."
                return 1
        fi
	sed -i "s|SEC_PATH:=.*|SEC_PATH:=${SECTOOLS_PATH}|g" include/package.mk || return
}

## Add mechanism to differentiate between internal & external build;
## Further check to determine external build variant: HY11 & HY22.

if [ ! -d owrt-qti-internal ]; then
	sed -i '1s/^/EXTERNAL_BUILD=1\n/' owrt-qti-conf/sdx.mk;
	sed -i '1s/^/EXTERNAL_BUILD=1\n/' owrt-qti-conf/qmb415.mk;
	set_sectools_path || return
	if [ -d $TOPDIR/../prebuilt_HY11 ]; then
		sed -i '1s/^/EXTERNAL_VARIANT=HY11\n/' include/package.mk;
	fi

	if [ -d $TOPDIR/../prebuilt_HY22 ]; then
		sed -i '1s/^/EXTERNAL_VARIANT=HY22\n/' include/package.mk;
	fi
else
	mkdir -p $TOPDIR/../prebuilt_HY11;
	mkdir -p $TOPDIR/../prebuilt_HY22;
fi

function uname_version(){
	KERNEL_VERSION=5.15
	set_bazel_target ${1}
	if [ "${bazel_based_target}" == "1" ]; then
		KERNEL_VERSION=6.6
	fi
	IFS=''
	read -ra TARGET <<< "$(sed -n -e '/KERNEL_PLATFORM_TARGET/ s/.*= *//p' "target/linux/${1}/Makefile")"
	IFS=' '
	read DEFINE UTSRELEASE VERSION <<< $(cat src/kernel-${KERNEL_VERSION}/out/msm-kernel-${TARGET}-${2}_defconfig/dist/kernel-headers/include/generated/utsrelease.h)
	UNAME_R=$(echo ${VERSION} | tr -d '"')
	sed -i "s/UNAME_VERSION:=.*/UNAME_VERSION:=${UNAME_R}/" target/linux/${1}/Makefile
}

function set_up_feeds(){
	rm -rf feeds
	./scripts/feeds update -a -b || return
	./scripts/feeds install -a || return
	if [[ "${OWRT_VERSION%%.*}" == "23" || "${OWRT_VERSION%%.*}" == "24" ]]; then
		./scripts/feeds uninstall bash || return
		./scripts/feeds uninstall xz || return
		./scripts/feeds install -a -f -p qtigplv2 || return
	fi

	if [[ ( "${1}" == "sdx85" && "${2}" == "cpe-v1" ) || ( -n "$PRPL_VERSION" && "${PRPL_VERSION%%.*}" == "4" ) ]]; then
		# Adding pci and pcie support
		sed -i '/^FEATURES:=/ {/pci/!{/pcie/! s/$/ pci pcie/}}' target/linux/${1}/Makefile || return
		./scripts/feeds install -a -f -p qtiipqopen || return
	fi
}

function set_bazel_target(){
	if [ "${1}" == "sdx75" ] || [ "${1}" == "sdx35" ]; then
		bazel_based_target=0
	elif [ "${1}" == "sdx85" ]; then
		bazel_based_target=1
	elif [ "${1}" == "qmb415" ]; then
		bazel_based_target=1
	fi
}

function patch_upstream_feeds(){
	feeds=(packages luci routing)
	feeds_path=$TOPDIR/feeds
	patches=$TOPDIR/owrt-qti-conf/feeds_patches
	if [ -n "${PRPL_VERSION}" ] && (( "${PRPL_VERSION%%.*}"=="4" )) ; then
	echo "Using feeds for Prplos version:$PRPL_VERSION"
		if [ "${2}" != "recovery" ]; then
		feeds=(packages luci routing feed_amx feed_lcm feed_prplmesh feed_prplos)
		fi
        patches=$TOPDIR/owrt-qti-conf/P4/feeds_patches
	elif (( "${OWRT_VERSION%%.*}"=="23")) || (( "${OWRT_VERSION%%.*}"=="24")); then
	echo "Using feeds for Openwrt version:$OWRT_VERSION"
        patches=$TOPDIR/owrt-qti-conf/V${OWRT_VERSION%%.*}/feeds_patches
	fi
	for feed in ${feeds[@]}; do
		for patch in $patches/$feed/*.patch; do
			cd $feeds_path/$feed
			if [ -f "$patch" ]; then
				git am $patch
				if [ $? -ne 0 ]; then
					echo "----------------------------------------------------------------------------------------------------------------"
					echo "Patch $patch failed to apply."
					echo "Please resolve any conflicts before moving forward with patch application."
					echo "Once conflicts are resolved, please re-apply patches to upstream feeds following one of the options below:"
					echo "	1) re-run configure step; it will automatically ensure patching of upstream feeds:"
					echo "		$ configure <target> <profile> <variant>"
					echo "	2) individual invocation of patch_upstream_feeds function after resetting upstream feeds:"
					echo "		$ set_up_feeds"
					echo "		$ patch_upstream_feeds"
					echo ""
					echo "Note: make sure to $ source owrt-qti-conf/set_openwrt_env.sh before proceeding with either of the above options."
					echo "----------------------------------------------------------------------------------------------------------------"
					cd $TOPDIR
					return 1
				fi
			fi
		done
	done
	cd $TOPDIR
}

function patch_openssl(){
	if (( "${OWRT_VERSION%%.*}"=="23")) || (( "${OWRT_VERSION%%.*}"=="24")); then
		OPENSSL_VERSION=$(sed -n -e '/PKG_VERSION:/ s/.*= *//p' "$TOPDIR/package/libs/openssl/Makefile")
	else
		OPENSSL_VERSION=$(sed -n -e '/PKG_BASE:/ s/.*= *//p' "$TOPDIR/package/libs/openssl/Makefile")
	fi

	if [ "${1}" == "sdx75" ] || [ "${1}" == "sdx85" ] || [ "${1}" == "qmb415" ] && [ "${OPENSSL_VERSION%%.*}" != "3" ]; then
		OPENSSL_VERSION=3.0.10
		cd $TOPDIR/package/libs
		git am $TOPDIR/owrt-qti-conf/feeds_patches/package/libs/opensslv3.patch
		cd $TOPDIR
	fi
	grep -q "OPENSSL_VERSION:=" include/package.mk;
	if [ $? -ne 0 ]
	then
		sed -i '1s/^/OPENSSL_VERSION:='$OPENSSL_VERSION'\n/' include/package.mk;
	else
		sed -i 's/OPENSSL_VERSION:=.*/OPENSSL_VERSION:='$OPENSSL_VERSION'/g' include/package.mk;
	fi
}

function update_configs(){
	if [ -f "owrt-qti-conf/V${OWRT_VERSION%%.*}/${1}/${2}.config" ]; then
		IFS='='
		#read line by line from owrt-qti-conf/V23/${1}/${2}.config
		while read -r line; do
			read -a configarr <<<"$line"
			if grep  "${configarr[0]}=" ".config"
			then
				# if found
				sed -i "s/${configarr[0]}=.*/$line/" .config
			else
				echo "$line" >> ".config"
			fi
		done < "owrt-qti-conf/V${OWRT_VERSION%%.*}/${1}/${2}.config"
	fi
}

verify_target_configuration(){

	CHECK_TARGET=$(grep -x "CONFIG_TARGET_${1}=y" ".config")

	if [ -n "$CHECK_TARGET" ] ; then
		echo "Target configured successfully!"
	else
		echo "ERROR: Incorrect target configuration, TARGET ${1} was not configured successfully; see logs/target/linux/${1}/dump.txt for details."
		echo "If package group .mk file in sdx.mk is target specific, please move .mk include line in target/linux/${1}/profiles/${1}.mk"
		if [ -f "$TOPDIR/logs/target/linux/${1}/dump.txt" ]; then
			echo "---- Error Log ----"
			cat "$TOPDIR/logs/target/linux/${1}/dump.txt"
		fi
		return 1
	fi
}

function build_abl_user(){
	read -ra LINUX_VERSION <<< "$(sed -n -e '/LINUX_VERSION/ s/.*= *//p' "target/linux/${1}/Makefile")"
	cd /$TOPDIR/src/kernel-${LINUX_VERSION}/kernel_platform
	echo "Compiling abl"
	if [ "${bazel_based_target}" == "0" ]; then
	export TARGET_BUILD_VARIANT=user && BUILD_CONFIG=msm-kernel/build.config.msm.${1} VARIANT=${2}_defconfig OUT_DIR=../out/msm-kernel-${1}-${2}_defconfig ./build/build_abl.sh
	elif  [ "${bazel_based_target}" == "1" ]; then
	export TARGET_BUILD_VARIANT=user && ./tools/bazel run --lto=thin //msm-kernel:${2}_${3}-defconfig_abl_dist
	fi
	if [ $? -ne 0 ]; then
		echo "ABL user build failed. Please check logs above for error..."
		cd $TOPDIR
		return 1
	fi
	cd $TOPDIR
}


# arguments: sdx_target, kp_variant
# dedicated function to set only TARGET_VARIANT, handles 'user' variant edge case
# invoked in set_kernel_target -> used in build.py
# invoked in configure for recovery profile case
#	set only TARGET_VARIANT, but not KERNEL_PLATFORM_TARGET
#	neccessary to maintain backward compatibility with build_all
function set_kernel_variant(){
#****** USER Variant Support : dynamically set/reset flags for target build *******
	sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=0/" target/linux/${1}/Makefile || return 1

	if [ "${2}" == "user" ]; then
		set ${1} perf # user build uses perf kernel artifacts, ${2} now set to perf
		sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=1/" target/linux/${1}/Makefile || return 1
	fi
	#**********************************************************************

	# Dynamically set/update TARGET_VARIANT in ${1}/Makefile accordingly based on ${2}=kp_variant argument
	# Variable will be used to consume the right kp_artifacts in build.py sequence of configuration & build
	sed -i "s/TARGET_VARIANT:=.*/TARGET_VARIANT:=${2}/" target/linux/${1}/Makefile || return 1
}

# arguments: sdx_target, kp_target, kp_variant
# To be used:
#	build_kernel_platform --> local build either via build.py or via configure (where kernel re-build is mandated)
#	automation --> to only set kernel target & variant required for consumption of kernel products, but no kernel re-build
function set_kernel_target(){

	# Dynamically set/update KERNEL_PLATFORM_TARGET in ${1}/Makefile accordingly based on ${2}=kp_target argument
	# Variable will be used to consume the right kp_artifacts in build.py sequence of configuration & build
	sed -i "s/KERNEL_PLATFORM_TARGET:=.*/KERNEL_PLATFORM_TARGET:=${2}/" target/linux/${1}/Makefile || return 1
	set_kernel_variant ${1} ${3}
}

function compile_kernel(){
	if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
	then
		echo "Please provide all the arguments required to build kernel: chip_target, kp_target, kp_variant"
		return
	fi

	if [ "${bazel_based_target}" == "0" ]; then
		if [ -f prebuilts/qcom_boot_artifacts/build.config.qc.standalone ]; then
		BUILD_CONFIG=msm-kernel/build.config.msm.${2} EXTRA_CONFIGS=./prebuilts/qcom_boot_artifacts/build.config.qc.standalone VARIANT=${3}_defconfig OUT_DIR=../out/msm-kernel-${2}-${3}_defconfig ./build/build.sh
		else
		BUILD_CONFIG=msm-kernel/build.config.msm.${2} VARIANT=${3}_defconfig OUT_DIR=../out/msm-kernel-${2}-${3}_defconfig ./build/build.sh
		fi
	elif  [ "${bazel_based_target}" == "1" ]; then
		./build_with_bazel.py -t ${2} ${3}-defconfig --out_dir ../out/msm-kernel-${2}-${3}_defconfig
	fi

	#Flag kernel build failure
	if [ $? -ne 0 ]; then
		echo "Kernel Build failed. Please check logs above for error..."
		cd $TOPDIR
		return 1
	elif [ $? -eq 0 ]; then
		echo "Kernel Build succeeded."
	fi
}

# plain kernel platform build, takes as arguments sdx_target, kp_target and kp_variant
# profile input not required (no consumption of kp products)
# to be individually called ONLY in build.py to trigger plain kernel build prior to any profile configuration
#  if {3}=kp_variant is passed as user, set USER flag for target build in sdx_target/Makefile, set {3} to perf, user build uses perf kernel artifacts
#        This ensures individual invocations of "build_kernel sdx_target user" or "build_kernel_platform sdx_target kp_target user" are supported
#        Flag in sdx_target/Makefile to be used for target only related operations: trigger build for abl_user & deplying of user images
# In addition, build_kernel_platform:
#        sets/updates KERNEL_PLATFORM_TARGET in ${1}/Makefile accordingly based on ${2}=kp_target argument
#        sets/updates TARGET_VARIANT in ${1}/Makefile accordingly based ${3}=kp_variant argument
#			edge case, ${3} passed as user, set/updated as 'perf' prior to dynamically setting TARGET_VARIANT
function build_kernel_platform(){
	if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
	then
		echo "Please provide all the arguments required to build kernel: chip_target, kp_target, kp_variant"
		return
	fi

	set_bazel_target ${1} || return 1
	set_kernel_target ${1} ${2} ${3} || return 1

	if [ "${3}" == "user" ]; then
		set ${1} ${2} perf # user build uses perf kernel artifacts, ${3} now set to perf
	fi

	# Build/re-build kernel
	echo "Building kernel for: TARGET=${2}, VARIANT=${3}"
	read -ra LINUX_VERSION <<< "$(sed -n -e '/LINUX_VERSION/ s/.*= *//p' "target/linux/${1}/Makefile")"
	cd /$TOPDIR/src/kernel-${LINUX_VERSION}/kernel_platform
	rm -rf ../out/msm-kernel-${2}-${3}_defconfig
	compile_kernel ${1} ${2} ${3}|| return 1
	cd $TOPDIR
	# If USER_VARIANT flag in sdx_target/Makefile is set, trigger build for abl_user
	USER_VARIANT=$(sed -n -e '/USER_VARIANT/ s/.*= *//p' "target/linux/${1}/Makefile")
	if [ "${USER_VARIANT}" == "1" ]; then
		build_abl_user ${1} ${2} ${3}
	fi
}

# called in build_kernel function during:
#	non-recovery profile configuration step (called as part of configure)
#	incremental kernel builds, in a non-recovery profile configured workspace
# called in build.py post build_kernel_platform call, prior to any profile configuration
#	Case 1: fresh sync / distclean -->
#		NO OP: make toolchain/kernel-headers/{clean,compile} will be skipped since build_dir not present
#		Kernel Products will be consumed ONCE during the FIRST overall toolchain build
#	Case 2: incremental builds (post make clean)
#		Since make clean only nukes target folder, build_dir remains present
#		It will trigger {clean,compile} of toolchain/kernel-headers and re-consume the kernel artifacts
# no arguments, operates based on following variables dynamically set in target/linux/sdx_target/Makefile:
#        KERNEL_PLATFORM_TARGET
#        TARGET_VARIANT
# BOTH build_kernel_platform & configure tool CAN set/update KERNEL_PLATFORM_TARGET
# ONLY build_kernel_platform CAN set/update TARGET_VARIANT
function consume_kernel_artifacts(){
	# Re-process/re-extract the latest generated kernel artifacts into the build system
	if [ -d build_dir ]; then
		make toolchain/kernel-headers/{clean,compile}
	fi
}

# takes as argument ${1}=sdx_target
# called in build_kernel to read the configured kernel platform target
# required to avoid having to input profile for build_kernel tool
# KERNEL_PLATFOFRM_TARGET can be deduced from target/linux/${1}/Makefile
function get_kernel_platform_target(){
	if [ -z "${1}" ]
	then
		echo "Please provide all the arguments required to get/read kernel platform target: sdx_target"
		return
	fi
	IFS=''
	read -ra TARGET <<< "$(sed -n -e '/KERNEL_PLATFORM_TARGET/ s/.*= *//p' "target/linux/${1}/Makefile")"
	echo ${TARGET}
}

# takes as argument: sdx_target, variant
# used in individual configuration of non-recovery profiles, called within configure function
# used for incremental kernel-builds in post-configured non-recovery profile workspaces
# can read but not set/update KERNEL_PLATFORM_TARGET in target/linux/${1}/Makefile
function build_kernel(){

	if [ -z "${1}" ] || [ -z "${2}" ]
	then
		echo "Please provide all the arguments required to build kernel: sdx_target & variant"
		return 1
	fi

	TARGET=$(get_kernel_platform_target ${1})
	build_kernel_platform ${1} ${TARGET} ${2} || return 1
	consume_kernel_artifacts || return 1

	echo "Kernel Build complete!"
	cd $TOPDIR
}

function run_gen_config(){
	# Do not run gen_config for recovery and initramfs profile
	if [ "${2}" != "recovery" ] && [ "${2}" != "initramfs" ]; then
		if [ -f "profiles/${1}_${2}.yml" ]; then
			./scripts/gen_config.py ${1}_${2} prpl cellular || return
		else
			./scripts/gen_config.py prpl cellular || return
		fi
	fi
}

# core function, used to configure OpenWrt enviroment for specific target, profile, variant
# 	sets up upstream feeds, ensures patching of upstream feeds
# 	based on target, profile, variant provided:
# 		enables respective package groups part of profile definition for that specific target
# 		runs make defconfig to construct complete userspace config: upstream + downstream
# 		validates final target configuration by verifying .config output from make defconfig
# 		determines and sets KENREL_PLATFORM_TARGET variable for non-recovery profiles
# 		accordingly triggers kernel build & consumption of kernel products via build_kernel function call
# based on variant provided:
# 		USER case, sets neccessary userspace flags to support USER build
function configure(){
	if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
	then
		echo "Please provide all the arguments required to set up OpenWrt environment: TARGET PROFILE VARIANT" && return
	fi
	echo "Setting up OpenWrt environment..."
	echo "Target:  ${1}"
	echo "Profile: ${2}"
	echo "Variant: ${3}"
	## Add a mechanism to pass BOARD variable for use in feeds update, while scanning owrt Makefile
	local TARGET_NAME=${1}
	grep -q "BOARD=" include/package.mk;
	if [ $? -ne 0 ]
	then
		sed -i '1s/^/BOARD='$TARGET_NAME'\n/' include/package.mk;
	else
		sed -i 's/BOARD=.*/BOARD='$TARGET_NAME'/g' include/package.mk;
	fi

	echo "OWRT_VERSION: $OWRT_VERSION"
	echo "PRPL_VERSION: $PRPL_VERSION"
	## Add owrt version info in Makefile and package.mk
	files_to_add_owrt_ver=("target/linux/${1}/Makefile" "include/package.mk" "include/target.mk")
	for files_to_update in ${files_to_add_owrt_ver[@]};
	do
		grep -q "OWRT_VERSION:=" $files_to_update
		if [ $? -ne 0 ]
		then
			sed -i '1s/^/OWRT_VERSION:='$OWRT_VERSION'\n/' $files_to_update
		else
			sed -i 's/OWRT_VERSION:=.*/OWRT_VERSION:='$OWRT_VERSION'/g' $files_to_update
		fi
		grep -q "PRPL_VERSION:=" $files_to_update
		if [ $? -ne 0 ]
		then
			sed -i '1s/^/PRPL_VERSION:='$PRPL_VERSION'\n/' $files_to_update
		else
			sed -i 's/PRPL_VERSION:=.*/PRPL_VERSION:='$PRPL_VERSION'/g' $files_to_update
		fi
	done

	feeds_conf_path ${1} ${2} || return 1
	set_up_feeds ${1} ${2} || return 1
	rm -rf .config
	rm -rf tmp
	if [ -n "${PRPL_VERSION}" ]; then
		cp owrt-qti-conf/P4/${1}/${2}.config .config || return
		run_gen_config ${1} ${2} || return
		./scripts/feeds uninstall bash || return
		./scripts/feeds uninstall xz || return
		./scripts/feeds install -a -f -p qtigplv2 || return
		./scripts/feeds install -a -f -p qtiipqopen || return
		if [ "${PRPL_VERSION}" = "4.0" ]; then
			patch_upstream_feeds ${1} ${2} || return 1
		fi
	else
		cp owrt-qti-conf/${1}/${2}.config .config || return
		update_configs ${1} ${2} || return
		patch_upstream_feeds ${1} ${2} || return 1
	fi
	patch_openssl ${1} || return 1

	#Create separate rootfs for recovery and initramfs profile
	if [ "${2}" == "recovery" ] || [ "${2}" == "initramfs" ]; then
		ARCH=$(sed -n -e '/ARCH:/ s/.*= *//p' "target/linux/${1}/Makefile")
		CPU=$(sed -n -e '/CPU_TYPE:/ s/.*= *//p' "target/linux/${1}/Makefile")
		if [ "${1}" == "sdx35" ]; then
			CPU_SUBTYPE=$(sed -n -e '/CPU_SUBTYPE:/ s/.*= *//p' "target/linux/${1}/Makefile")
			BUILD_DIR_CONFIG="CONFIG_TARGET_ROOTFS_DIR="\"$TOPDIR"/build_dir/target-"${ARCH}"_"${CPU}"+"${CPU_SUBTYPE}"_musl_eabi/recovery"\"
		else
			BUILD_DIR_CONFIG="CONFIG_TARGET_ROOTFS_DIR="\"$TOPDIR"/build_dir/target-"${ARCH}"_"${CPU}"_musl/${2}"\"
		fi
		sed -i '$a'"$BUILD_DIR_CONFIG"'' .config
	fi

	make defconfig
	verify_target_configuration ${1} || return 1

	# ----- USER Variant support : set/reset userspace FLAG -----
	sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=0/" include/package.mk || return
	if [ "${3}" == "user" ]; then
		sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=1/" include/package.mk || return
	fi
	# -----------------------------------------------------------

	if [ "${1}" == "sdx35" ]; then
		BUILD_WITH_MEMOPT=0
		if [ "${2}" == "mbb" ]; then
			TARGET=sdxbaagha
		elif [ "${2}" == "iot" ]; then
			TARGET=sdxbaagha-iot
		elif [ "${2}" == "mbb-128m" ] || [ "${2}" == "m2-128m" ]; then
			BUILD_WITH_MEMOPT=1
			TARGET=sdxbaagha-128m
		else
			TARGET=sdxbaagha
		fi
		sed -i "s/BUILD_WITH_MEMOPT:=.*/BUILD_WITH_MEMOPT:=${BUILD_WITH_MEMOPT}/" target/linux/${1}/Makefile || return
		sed -i "s/TARGET_PROFILE:=.*/TARGET_PROFILE:=${2}/" target/linux/${1}/Makefile || return
	fi

	if [ -n "${PRPL_VERSION}" ] && (( "${PRPL_VERSION%%.*}"=="4" )); then
		if [ "${1}" == "sdx75" ]; then
			TARGET=sdxpinn-prpl
		fi
		if [ "${1}" == "sdx85" ]; then
			TARGET=sdxkova.prpl
		fi
	else
		if [ "${1}" == "sdx75" ]; then
			if [ "${2}" = "mbb" ] || [ "${2}" = "mbb-min" ] || [ "${2}" = "iot" ]; then
				TARGET=sdxpinn
			fi
			if [ "${2}" = "cpe" ]; then
				TARGET=sdxpinn-cpe-wkk
			fi
			if [ "${2}" = "cpe-v1" ]; then
				TARGET=sdxpinn-cpe-wkk-v1
			fi
			if [ "${2}" = "mbb-512" ]; then
				TARGET=sdxpinn-512
			fi
		fi

		if [ "${1}" == "sdx85" ]; then
		        if [ "${2}" = "mbb" ] || [ "${2}" = "mbb-min" ]; then
		            TARGET=sdxkova
		        fi
		        if [ "${2}" = "cpe" ]; then
		            TARGET=sdxkova.cpe.wkk
		        fi
			if [ "${2}" = "cpe-v1" ]; then
			    TARGET=sdxkova.prpl
			fi
		        if [ "${2}" = "cpe-tarang" ]; then
		            TARGET=sdxkova.cpe.tarang
		        fi
			if [ "${2}" = "cpe-min" ]; then
		            TARGET=sdxkova.cpe.min
			fi
		        if [ "${2}" = "mbb-512" ]; then
		            TARGET=sdxkova.512
		        fi
		fi

		if [ "${1}" == "qmb415" ]; then
		        if [ "${2}" = "mbb" ]; then
		            TARGET=taycan
		        fi
		fi
	fi

	# REQUIRED to maintain backward compatability for the cases of configure invocations with disable_kernel parameter
	# 	use case: build_all.sh in automation
	# --> non-recovery profiles case:
	#	set both: KERNEL_PLATFORM_TARGET & TARGET_VARIANT via set_kernel_target(sdx_target,kp_target,kp_variant) invocation
	#	all non-recovery profiles are associated to a respective kernel config
	# --> recovery profile case:
	#	set TARGET_VARIANT only via set_kernel_variant(sdx_target,kp_variant) invocation, do NOT set KERNEL_PLATFORM_TARGET
	#	standalone recovery profile is not associated to ANY kernel config
	#	standalone recovery build via configure utilizes KERNEL_PLATFORM_TARGET value in sdx_target/Makefile
	#NOTE:
	# redundant logic for build.py usage; can be safely removed once transition to build.py is complete
	# 	in build.py KERNEL_PLATFORM_TARGET & TARGET_VARIANT are set prior to any profile configuration
	if [ "${2}" != "recovery" ]; then
		set_kernel_target ${1} ${TARGET} ${3} || return 1
	else
		set_kernel_variant ${1} ${3} || return 1
	fi

	#Add check to differentiate between local builds and crm builds
	if [ -z "${4}" ] || [ "${4}" != "disable_kernel" ]; then
		build_kernel ${1} ${3} || return 1
	fi

	echo "OpenWrt set up environment complete... Ready for make!"
}

# build commands for Kuno
function build-sdxbaagha-image(){
    configure sdx35 mbb debug
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-perf-image(){
    configure sdx35 mbb perf
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}


function build-sdxbaagha-128m-image(){
    configure sdx35 mbb-128m debug
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-128m-perf-image(){
    configure sdx35 mbb-128m perf
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-m2-image(){
    configure sdx35 m2 debug
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-m2-perf-image(){
    configure sdx35 m2 perf
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-all-sdxbaagha-images(){
    make dirclean
    build-sdxbaagha-image
    make dirclean
    build-sdxbaagha-perf-image
    make dirclean
    build-sdxbaagha-128m-image
    make dirclean
    build-sdxbaagha-128m-perf-image
    make dirclean
    build-sdxbaagha-m2-image
    make dirclean
    build-sdxbaagha-m2-perf-image
}

if [ ! -z "${TARGET_MACHINE}" ]; then

./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1

if [ ${TARGET_MACHINE} == 'sdx75' ] || [ ${TARGET_MACHINE} == 'sdx65' ] || [ ${TARGET_MACHINE} == 'sdx85' ] || [ ${TARGET_MACHINE} == 'qmb415' ]; then
	cp owrt-qti-conf/${TARGET_MACHINE}/mbb.config .config || exit 1
fi

if [ ${TARGET_MACHINE} == 'sdx35' ]; then
	cp owrt-qti-conf/${TARGET_MACHINE}/mbb.config .config || exit 1
fi

make defconfig

fi
