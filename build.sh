#!/bin/bash

set -ex

function prepare_build_env()
{
	snap list snapcraft && sudo snap refresh snapcraft --channel=latest/edge --classic \
		|| sudo snap install snapcraft --channel=latest/edge --classic
	snap list ubuntu-image && sudo snap refresh ubuntu-image --channel=2/stable --classic \
		|| sudo snap install ubuntu-image --channel=2/stable --classic
	snap list yq && sudo snap refresh yq --channel=latest/stable --devmode \
		|| sudo snap install yq --channel=latest/stable --devmode

	sudo apt install -y dialog
}

function choose_board()
{
	options=()
	for board in ${CONFIG_DIR}/*.conf; do
		options+=("$(basename "${board}" | cut -d'.' -f1)" "$(head -1 "${board}" | cut -d'#' -f2)")
		echo $options
	done

	TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
	TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
	BOARD=$(DIALOGRC=$temp_rc dialog --stdout --title "Choose a board" --backtitle "$backtitle" --scrollbar \
		--colors \
		--menu "Select the target board.\n$STATE_DESCRIPTION" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
}

function create_build_dir()
{
	BOARD_BUILD_DIR=${ROOT_BUILD_DIR}/${BOARD}
	[ -d ${BOARD_BUILD_DIR} ] || mkdir -p ${BOARD_BUILD_DIR}
	[ -d ${BOARD_BUILD_DIR}/${GADGET_SNAP_DIR} ] || cp -r ${GADGET_SNAP_DIR} ${BOARD_BUILD_DIR}
	[ -d ${BOARD_BUILD_DIR}/${KERNEL_SNAP_DIR} ] || cp -r ${KERNEL_SNAP_DIR} ${BOARD_BUILD_DIR}
	[ -d ${BOARD_BUILD_DIR}/${ASSERT_DIR} ] || cp -r ${ASSERT_DIR} ${BOARD_BUILD_DIR}
}

function load_config()
{
	# Load and replace configs
	CONFIG=${BOARD}.conf
	source ${CONFIG_DIR}/${CONFIG}

	GADGET_SNAP_SNAPCRAFT_YAML=${GADGET_SNAP_DIR}/snap/snapcraft.yaml
	GADGET_SNAP_GADGET_YAML=${GADGET_SNAP_DIR}/gadget.yaml

	cd ${BOARD_BUILD_DIR}

	if [ "${FIP_IS_REQUIRED}" != "true" ]; then
		# Delete the FIP related code in snapcraft.yaml
		yq -i 'del(.parts.fip)' ${GADGET_SNAP_SNAPCRAFT_YAML}
		yq -i 'del(.parts.u-boot.prime)' ${GADGET_SNAP_SNAPCRAFT_YAML}
		yq -i 'del(.volumes.ubuntu-core.structure[] | select(.name == "mbr"))' ${GADGET_SNAP_GADGET_YAML}
	fi

	if [ "${BOOTLOADER_WAIT_FOR_DEPEND}" != "true" ]; then
		# Delete the wait for depend related code in snapcraft.yaml
		yq -i 'del(.parts.u-boot.after)' ${GADGET_SNAP_SNAPCRAFT_YAML}
	fi

	if [ "${ATF_IS_REQUIRED}" != "true" ]; then
		# Delete the atf related code in snapcraft.yaml
		yq -i 'del(.parts.atf)' ${GADGET_SNAP_SNAPCRAFT_YAML}
		yq -i 'del(.parts.u-boot.after[] | select(. == "atf"))' ${GADGET_SNAP_SNAPCRAFT_YAML}
	fi

	if [ "${SCP_IS_REQUIRED}" != "true" ]; then
		# Delete the scp related code in snapcraft.yaml
		yq -i 'del(.parts.scp)' ${GADGET_SNAP_SNAPCRAFT_YAML}
		yq -i 'del(.parts.u-boot.after[] | select(. == "scp"))' ${GADGET_SNAP_SNAPCRAFT_YAML}
		cross_compiler="__SCP_CROSS_COMPILER_DEB_PACKAGE__" yq -i \
			'del(.["build-packages"][] | select(has("on amd64")) | .[][] | select(. == strenv(cross_compiler)))' ${GADGET_SNAP_SNAPCRAFT_YAML}
	fi

	if [ "${CLOUD_INIT_ENABLED}" != "true" ]; then
		# Delete the cloud-init related code in snapcraft.yaml
		yq -i 'del(.parts.cloud-init-conf)' ${GADGET_SNAP_SNAPCRAFT_YAML}
		yq -i 'del(.defaults)' ${GADGET_SNAP_GADGET_YAML}
		yq -i 'del(.volumes.ubuntu-core.structure[] | select(.name == "ubuntu-seed") | .[][] | select(.source == "cloud.conf"))' ${GADGET_SNAP_GADGET_YAML}
	fi

	local d=$'\x03'
	find . \( -path '*/parts' -prune -o -path '*/stage' -prune -o -path '*/prime' -prune \
		-o -path './work' -prune -o -path './out' -prune -o -path './*.snap' -prune \) \
		-o -print -type f \
		-exec sed -i "s${d}__DEVICE__${d}${DEVICE}${d}g" {} \; \
		-exec sed -i "s${d}__ARCH__${d}${ARCH}${d}g" {} \; \
		-exec sed -i "s${d}__CROSS_COMPILER__${d}${CROSS_COMPILER}${d}g" {} \; \
		-exec sed -i "s${d}__CROSS_COMPILER_DEB_PACKAGE__${d}${CROSS_COMPILER_DEB_PACKAGE}${d}g" {} \; \
		\
		-exec sed -i "s${d}__ATF_IS_REQUIRED__${d}${ATF_IS_REQUIRED}${d}g" {} \; \
		-exec sed -i "s${d}__ATF_GIT_SOURCE__${d}${ATF_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__ATF_GIT_BRANCH__${d}${ATF_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__ATF_PLATFORM__${d}${ATF_PLATFORM}${d}g" {} \; \
		-exec sed -i "s${d}__ATF_DEBUG_LEVEL__${d}${ATF_DEBUG_LEVEL}${d}g" {} \; \
		\
		-exec sed -i "s${d}__SCP_IS_REQUIRED__${d}${SCP_IS_REQUIRED}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_GIT_SOURCE__${d}${SCP_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_GIT_BRANCH__${d}${SCP_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_DEFCONFIG__${d}${SCP_DEFCONFIG}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_CROSS_COMPILER__${d}${SCP_CROSS_COMPILER}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_CROSS_COMPILER_DEB_PACKAGE__${d}${SCP_CROSS_COMPILER_DEB_PACKAGE}${d}g" {} \; \
		\
		-exec sed -i "s${d}__PARTITION_SCHEMA__${d}${PARTITION_SCHEMA}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_GIT_SOURCE__${d}${BOOTLOADER_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_GIT_BRANCH__${d}${BOOTLOADER_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_DEFCONFIG__${d}${BOOTLOADER_DEFCONFIG}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_BINARY__${d}${BOOTLOADER_BINARY}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_OFFSET__${d}${BOOTLOADER_OFFSET}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_MAX_SIZE__${d}${BOOTLOADER_MAX_SIZE}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_BOOTARGS__${d}${BOOTLOADER_BOOTARGS}${d}g" {} \; \
		\
		-exec sed -i "s${d}__FIP_IS_REQUIRED__${d}${FIP_IS_REQUIRED}${d}g" {} \; \
		-exec sed -i "s${d}__FIP_GIT_SOURCE__${d}${FIP_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__FIP_GIT_BRANCH__${d}${FIP_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__FIP_PLATFORM__${d}${FIP_PLATFORM}${d}g" {} \; \
		-exec sed -i "s${d}__FIP_OUTPUT_BINARY__${d}${FIP_OUTPUT_BINARY}${d}g" {} \; \
		\
		-exec sed -i "s${d}__MMC_DEV_NUM__${d}${MMC_DEV_NUM}${d}g" {} \; \
		-exec sed -i "s${d}__KERNEL_LOAD_ADDR__${d}${KERNEL_LOAD_ADDR}${d}g" {} \; \
		-exec sed -i "s${d}__RAMDISK_LOAD_ADDR__${d}${RAMDISK_LOAD_ADDR}${d}g" {} \; \
		-exec sed -i "s${d}__FDT_LOAD_ADDR__${d}${FDT_LOAD_ADDR}${d}g" {} \; \
		-exec sed -i "s${d}__FIT_LOAD_ADDR__${d}${FIT_LOAD_ADDR}${d}g" {} \; \
		\
		-exec sed -i "s${d}__ITS_KERNEL_COMPRESSION__${d}${ITS_KERNEL_COMPRESSION}${d}g" {} \; \
		-exec sed -i "s${d}__ITS_FDT_NAME__${d}${ITS_FDT_NAME}${d}g" {} \; \
		-exec sed -i "s${d}__ITS_FDT_PATH__${d}${ITS_FDT_PATH}${d}g" {} \; \
		\
		-exec sed -i "s${d}__KERNEL_GIT_SOURCE__${d}${KERNEL_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__KERNEL_GIT_BRANCH__${d}${KERNEL_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__KERNEL_DEFCONFIG__${d}${KERNEL_DEFCONFIG}${d}g" {} \;
}

function build_gadget_snap()
{
	cd ${BOARD_BUILD_DIR}/${GADGET_SNAP_DIR}
	sudo snapcraft --build-for=${ARCH} --destructive-mode
	cd ${ROOR_DIR}
}

function build_kernel_snap()
{
	cd ${BOARD_BUILD_DIR}/${KERNEL_SNAP_DIR}
	sudo snapcraft --build-for=${ARCH} --destructive-mode --enable-experimental-plugins
	cd ${ROOR_DIR}
}

function build_ubuntu_core_image()
{
	cd ${BOARD_BUILD_DIR}
	sudo rm -rf work
	gadget_snap=$(find ${GADGET_SNAP_DIR} -name "*.snap")
	kernel_snap=$(find ${KERNEL_SNAP_DIR} -name "*.snap")
	/snap/bin/ubuntu-image snap -d -O out -w work assertions/${ASSERTION_FILE} \
		--snap=${gadget_snap} --snap=${kernel_snap} ${ARG_EXTRA_SNAPS}
	cd out/

	local output_image_name="${DEVICE}_Ubuntu_Core_22_${ARCH}.img"
	mv ubuntu-core.img ${output_image_name}
	xz -T0 -z ${output_image_name}

	[ -d ${OUTPUT_DIR} ] || mkdir -p ${OUTPUT_DIR}
	mv ${output_image_name}.xz ${OUTPUT_DIR}
}

# Parsing arguments
while [ -n "$1" ]; do
	case "$1" in
		--snap=*)
			ARG_EXTRA_SNAPS="${ARG_EXTRA_SNAPS}--snap=${1#*=} "
		;;
		* )
			echo "ERROR: unknown option $1"
		;;
	esac
	shift
done


ROOT_DIR=$(pwd)
OUTPUT_DIR=$(pwd)/out
ROOT_BUILD_DIR=${ROOT_DIR}/"cache"
GADGET_SNAP_DIR=gadget_snap
KERNEL_SNAP_DIR=kernel_snap
ASSERT_DIR=assertions
CONFIG_DIR=${ROOT_DIR}/configs

prepare_build_env
choose_board
create_build_dir
load_config
build_gadget_snap
build_kernel_snap
build_ubuntu_core_image

echo "Build successfully, output file is under ${OUTPUT_DIR}"
