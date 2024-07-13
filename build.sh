#!/bin/bash

set -e

function prepare_build_env()
{
	snap list snapcraft && sudo snap refresh snapcraft --channel=latest/stable --classic \
		|| sudo snap install snapcraft --channel=latest/stable --classic
	snap list ubuntu-image && sudo snap refresh ubuntu-image --channel=latest/stable --classic \
		|| sudo snap install ubuntu-image --channel=latest/stable --classic
	snap list yq && sudo snap refresh yq --channel=latest/stable --devmode \
		|| sudo snap install yq --channel=latest/stable --devmode

	if [ "$(uname -p)" == "x86_64" ] && [ "$(dpkg --print-foreign-architectures | grep -c -E "armhf|arm64")" -ne 2 ] ; then
		sudo cp /etc/apt/sources.list /etc/apt/sources-list-backup
		sudo dpkg --add-architecture armhf
		sudo dpkg --add-architecture arm64
		sudo sed -i 's/^deb \(.*\)/deb [arch=amd64] \1/g' /etc/apt/sources.list
	fi
	if [ "$(uname -p)" == "aarch64" ] && [ "$(dpkg --print-foreign-architectures | grep -c -E "armhf")" -ne 1 ] ; then
		sudo cp /etc/apt/sources.list /etc/apt/sources-list-backup
		sudo dpkg --add-architecture armhf
		sudo sed -i 's/^deb \(.*\)/deb [arch=arm64] \1/g' /etc/apt/sources.list
	fi
	sudo apt update
	sudo apt install -y dialog dosfstools
}

function choose_board()
{
	options=()
	for board in "${CONFIG_DIR}"/*.conf; do
		options+=("$(basename "${board}" | cut -d'.' -f1)" "$(head -1 "${board}" | cut -d'#' -f2)")
	done

	TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
	TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
	BOARD=$(DIALOGRC= dialog --stdout --title "Choose a board" --scrollbar --colors \
		--menu "Select the target board.\n" ${TTY_Y} ${TTY_X} $((TTY_Y - 8)) "${options[@]}")
}

function create_build_dir()
{
	BOARD_BUILD_DIR="${ROOT_BUILD_DIR}/${BOARD}"
	[ -d "${BOARD_BUILD_DIR}" ] || mkdir -p "${BOARD_BUILD_DIR}"
	[ -d "${BOARD_BUILD_DIR}/${GADGET_SNAP_DIR}" ] || cp -r "${GADGET_SNAP_DIR}" "${BOARD_BUILD_DIR}"
	[ -d "${BOARD_BUILD_DIR}/${KERNEL_SNAP_DIR}" ] || cp -r "${KERNEL_SNAP_DIR}" "${BOARD_BUILD_DIR}"
	[ -d "${BOARD_BUILD_DIR}/${ASSERT_DIR}" ] || cp -r "${ASSERT_DIR}" "${BOARD_BUILD_DIR}"
}

function update_gadget_yaml()
{
	source_yaml=$1
	target_yaml=$2
	partition_list=( ubuntu-seed ubuntu-boot ubuntu-save ubuntu-data )
	for part in "${partition_list[@]}"; do
		length=$(yq ".volumes.ubuntu-core.structure[] | select(.name == \"${part}\") | .content | length" \
				"${source_yaml}")
		if [ -z "$length" ]; then
			length=0
		fi
		echo "Found ${length} item(s) to be appended"
		for (( i=0; i<${length}; i++)); do
			source=$(yq ".volumes.ubuntu-core.structure[] | select(.name == \"${part}\")" \
					"${source_yaml}" | yq ".content[$i].source")
			target=$(yq ".volumes.ubuntu-core.structure[] | select(.name == \"${part}\")" \
					"${source_yaml}" | yq ".content[$i].target")
			idx=$(($(grep "\- name:" "${target_yaml}" | grep -Fn "${part}" | cut -d ':' -f 1) - 1))
			yq -i ".volumes.ubuntu-core.structure[${idx}].content += {\"source\": \"${source}\", \"target\": \"${target}\"}" \
				"${target_yaml}"
		done
		yq -i "del(.volumes.ubuntu-core.structure[] | select(.name == \"${part}\"))" "${source_yaml}"
	done

	yq ". *+ load(\"${target_yaml}\")" "${source_yaml}" \
		> tmp.yaml
	mv tmp.yaml "${target_yaml}"
}

function apply_patches()
{
	CACHE_DIR="${ROOT_DIR}/cache/${BOARD}"
	PATCH_DIR="${CACHE_DIR}/patch"
	mkdir -p "${PATCH_DIR}"
	cp -r "${ROOT_DIR}/configs/patch/${BOARD}/"* "${PATCH_DIR}"

	if [ -d "${PATCH_DIR}"/gadget_snap/additional ]; then
		cp -r "${PATCH_DIR}"/gadget_snap/additional/* "${CACHE_DIR}"/gadget_snap/
	fi

	if [ ! -f "${CACHE_DIR}/.done_apply_patch" ]; then
		# For gadget.yaml in gadget_snap
		if [ -f "${PATCH_DIR}/${GADGET_SNAP_GADGET_YAML}" ]; then
			update_gadget_yaml "${PATCH_DIR}/${GADGET_SNAP_GADGET_YAML}" "${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		fi
		# For snapcraft.yaml in gadget_snap
		if [ -f "${PATCH_DIR}/${GADGET_SNAP_SNAPCRAFT_YAML}" ]; then
			yq ". *+ load(\"${PATCH_DIR}/${GADGET_SNAP_SNAPCRAFT_YAML}\")" "${CACHE_DIR}/${GADGET_SNAP_SNAPCRAFT_YAML}" \
				> tmp.yaml
			mv tmp.yaml "${CACHE_DIR}/${GADGET_SNAP_SNAPCRAFT_YAML}"
		fi

		# For snapcraft.yaml in kernel_snap
		if [ -f "${PATCH_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}" ]; then
			yq ". *+ load(\"${PATCH_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}\")" "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}" \
				> tmp.yaml
			mv tmp.yaml "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		fi

		touch "${CACHE_DIR}"/.done_apply_patch
		echo "Done applying patches for YAML files"
	else
		echo "Skip applying patches for YAML files"
	fi
}

function modify_for_uefi()
{
	CACHE_DIR="${ROOT_DIR}/cache/${BOARD}"
	PATCH_DIR="${CACHE_DIR}/patch"
	mkdir -p "${PATCH_DIR}"
	cp -r "${ROOT_DIR}/configs/patch/uefi/" "${PATCH_DIR}"

	if [ ! -f "${CACHE_DIR}/.done_apply_patch_uefi" ]; then
		# For gadget.yaml in gadget snap
		yq -i 'del(.volumes.ubuntu-core.structure[] | select(.name == "ubuntu-seed") | .[][] | select(.source == "boot.scr"))' \
			"${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		yq -i 'del(.volumes.ubuntu-core.structure[] | select(.name == "ubuntu-boot") | .[][] | select(.source == "boot.sel"))' \
			"${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		yq -i '.volumes.ubuntu-core.bootloader = "grub"' "${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		# UEFI will boot the ESP partition first by default
		yq -i '.volumes.ubuntu-core.structure[] |= select(.name == "ubuntu-seed").type = "EF,C12A7328-F81F-11D2-BA4B-00A0C93EC93B"' \
			"${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		yq -i '.volumes.ubuntu-core.structure[] |= select(.name == "ubuntu-boot").filesystem = "ext4"' \
			"${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		if [ -f "${PATCH_DIR}/uefi/${GADGET_SNAP_GADGET_YAML}" ]; then
			update_gadget_yaml "${PATCH_DIR}/uefi/${GADGET_SNAP_GADGET_YAML}" "${CACHE_DIR}/${GADGET_SNAP_GADGET_YAML}"
		fi

		# For snapcraft.yaml in gadget snap
		if [ -f "${PATCH_DIR}/uefi/${GADGET_SNAP_SNAPCRAFT_YAML}" ]; then
			yq ". *+ load(\"${PATCH_DIR}/uefi/${GADGET_SNAP_SNAPCRAFT_YAML}\")" \
				"${CACHE_DIR}/${GADGET_SNAP_SNAPCRAFT_YAML}" \
				> tmp.yaml
			mv tmp.yaml "${CACHE_DIR}/${GADGET_SNAP_SNAPCRAFT_YAML}"
		fi

		# For snapcraft.yaml in kernel snap
		KERNEL_CONFIG_LIST=( "CONFIG_EFI_STUB=y" "CONFIG_EFI=y" "CONFIG_DMI=y" )
		for config in "${KERNEL_CONFIG_LIST[@]}"; do
			yq -i ".parts.kernel.kernel-kconfigs += \"${config}\"" "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		done
		yq -i '.parts.kernel.stage += "kernel.efi"' "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		yq -i '.parts.kernel.kernel-build-efi-image = true' "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		yq -i 'del(.parts.fit-image)' "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		yq -i 'del(.parts.kernel.prime)' "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		yq -i 'del(.parts.kernel.stage[] | select(. == "Image"))' "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"
		yq -i 'del(.parts.kernel.stage[] | select(. == "initrd.img"))' "${CACHE_DIR}/${KERNEL_SNAP_SNAPCRAFT_YAML}"

		touch "${CACHE_DIR}/.done_apply_patch_uefi"
		echo "Done modifying YAML files for boot with UEFI"
	else
		echo "Skip modifying YAML files for boot with UEFI"
	fi
}

function load_config()
{
	# Load and replace configs
	CONFIG="${BOARD}.conf"
	GADGET_SNAP_SNAPCRAFT_YAML="${GADGET_SNAP_DIR}/snap/snapcraft.yaml"
	GADGET_SNAP_GADGET_YAML="${GADGET_SNAP_DIR}/gadget.yaml"
	KERNEL_SNAP_SNAPCRAFT_YAML="${KERNEL_SNAP_DIR}/snap/snapcraft.yaml"
	source "${CONFIG_DIR}/${CONFIG}"

	# If CROSS_COMPILE related variables are not set in config, then
	# use default value
	if [ "${ARCH}" == "armhf" ]; then
		if [ -z "${CROSS_COMPILE}" ]; then
			CROSS_COMPILE=arm-linux-gnueabihf-
		fi
		if [ -z "${CROSS_COMPILE_DEB_PACKAGE}" ]; then
			CROSS_COMPILE_DEB_PACKAGE=gcc-arm-linux-gnueabihf
		fi
	elif [ "${ARCH}" == "arm64" ]; then
		if [ -z "${CROSS_COMPILE}" ]; then
			CROSS_COMPILE=aarch64-linux-gnu-
		fi
		if [ -z "${CROSS_COMPILE_DEB_PACKAGE}" ]; then
			CROSS_COMPILE_DEB_PACKAGE=gcc-aarch64-linux-gnu
		fi
	elif [ "${ARCH}" == "riscv64" ]; then
		if [ -z "${CROSS_COMPILE}" ]; then
			CROSS_COMPILE=riscv64-linux-gnu-
		fi
		if [ -z "${CROSS_COMPILE_DEB_PACKAGE}" ]; then
			CROSS_COMPILE_DEB_PACKAGE=gcc-riscv64-linux-gnu
		fi
	fi

	if [ -d "${ROOT_DIR}/configs/patch/${BOARD}/" ]; then
		apply_patches
	fi

	if [ -z "${BOOT_PROCESS}" ]; then
		BOOT_PROCESS="U-Boot"
		if [ "${UEFI_SUPPORT}" == "true" ]; then
			options=()
			options+=("U-Boot" "U-Boot -> kernel")
			options+=("UEFI" "U-Boot -> shim -> GRUB -> kernel")

			TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
			TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
			BOOT_PROCESS=$(DIALOGRC= dialog --stdout --title "Choose a boot process" --scrollbar --colors \
				--menu "Select the target boot process.\n" ${TTY_Y} ${TTY_X} $((TTY_Y - 8)) "${options[@]}")
		fi
	fi

	if [ "${BOOT_PROCESS}" == "UEFI" ]; then
		if [ "${UEFI_SUPPORT}" != "true" ]; then
			echo "UEFI is not supported for ${BOARD} yet"
			exit 1
		fi
		if [ "${ARCH}" == "arm64" ] && [ "$(uname -p)" != "aarch64" ]; then
			echo "Currently we can not cross-build kernel.efi if using UEFI bootl process"
			exit
		fi
		modify_for_uefi
	fi

	cd "${BOARD_BUILD_DIR}"

	if [ "${SCP_IS_REQUIRED}" != "true" ]; then
		# Delete the scp related code in snapcraft.yaml
		cross_compiler="__SCP_CROSS_COMPILE_DEB_PACKAGE__" yq -i \
			'del(.["build-packages"][] | select(has("on amd64")) | .[][] | select(. == strenv(cross_compiler)))' \
			"${GADGET_SNAP_SNAPCRAFT_YAML}"
		yq -i 'del(.["build-packages"][] | select(has("on arm64")))' "${GADGET_SNAP_SNAPCRAFT_YAML}"
	fi

	if [ "${CLOUD_INIT_ENABLED}" != "true" ]; then
		# Delete the cloud-init related code in snapcraft.yaml
		yq -i 'del(.parts.cloud-init-conf)' "${GADGET_SNAP_SNAPCRAFT_YAML}"
		yq -i 'del(.defaults)' "${GADGET_SNAP_GADGET_YAML}"
		yq -i 'del(.volumes.ubuntu-core.structure[] | select(.name == "ubuntu-seed") | .[][] | select(.source == "cloud.conf"))' \
			"${GADGET_SNAP_GADGET_YAML}"
	fi

	local d=$'\x03'
	if [ -n "${BOOTLOADER_BOOTCMD}" ]; then
		sed -i "s${d}bootm \${fitloadaddr}\$${d}$BOOTLOADER_BOOTCMD${d}g" "${GADGET_SNAP_DIR}/boot-script/boot.cmd"
	fi
	find . \( -path '*/parts' -prune -o -path '*/stage' -prune -o -path '*/prime' -prune \
		-o -path './work' -prune -o -path './out' -prune -o -path './*.snap' -prune \) \
		-o -print -type f \
		-exec sed -i "s${d}__DEVICE__${d}${DEVICE}${d}g" {} \; \
		-exec sed -i "s${d}__ARCH__${d}${ARCH}${d}g" {} \; \
		-exec sed -i "s${d}__CROSS_COMPILE__${d}${CROSS_COMPILE}${d}g" {} \; \
		-exec sed -i "s${d}__CROSS_COMPILE_DEB_PACKAGE__${d}${CROSS_COMPILE_DEB_PACKAGE}${d}g" {} \; \
		\
		-exec sed -i "s${d}__ATF_IS_REQUIRED__${d}${ATF_IS_REQUIRED}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_IS_REQUIRED__${d}${SCP_IS_REQUIRED}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_CROSS_COMPILE__${d}${SCP_CROSS_COMPILE}${d}g" {} \; \
		-exec sed -i "s${d}__SCP_CROSS_COMPILE_DEB_PACKAGE__${d}${SCP_CROSS_COMPILE_DEB_PACKAGE}${d}g" {} \; \
		\
		-exec sed -i "s${d}__PARTITION_SCHEMA__${d}${PARTITION_SCHEMA}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_GIT_SOURCE__${d}${BOOTLOADER_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_GIT_BRANCH__${d}${BOOTLOADER_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_DEFCONFIG__${d}${BOOTLOADER_DEFCONFIG}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_BINARY__${d}${BOOTLOADER_BINARY}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_BINARY_RENAME__${d}${BOOTLOADER_BINARY_RENAME}${d}g" {} \; \
		-exec sed -i "s${d}__BOOTLOADER_BOOTARGS__${d}${BOOTLOADER_BOOTARGS}${d}g" {} \; \
		-exec sed -i "s${d}__BOOT_PROCESS__${d}${BOOT_PROCESS}${d}g" {} \; \
		\
		-exec sed -i "s${d}__MMC_DEV_NUM__${d}${MMC_DEV_NUM}${d}g" {} \; \
		-exec sed -i "s${d}__KERNEL_LOAD_ADDR__${d}${KERNEL_LOAD_ADDR}${d}g" {} \; \
		-exec sed -i "s${d}__RAMDISK_LOAD_ADDR__${d}${RAMDISK_LOAD_ADDR}${d}g" {} \; \
		-exec sed -i "s${d}__FDT_LOAD_ADDR__${d}${FDT_LOAD_ADDR}${d}g" {} \; \
		-exec sed -i "s${d}__FIT_LOAD_ADDR__${d}${FIT_LOAD_ADDR}${d}g" {} \; \
		\
		-exec sed -i "s${d}__ITS_KERNEL_COMPRESSION__${d}${ITS_KERNEL_COMPRESSION}${d}g" {} \; \
		-exec sed -i "s${d}__ITS_ARCH__${d}${ITS_ARCH}${d}g" {} \; \
		-exec sed -i "s${d}__ITS_FDT_NAME__${d}${ITS_FDT_NAME}${d}g" {} \; \
		\
		-exec sed -i "s${d}__KERNEL_GIT_SOURCE__${d}${KERNEL_GIT_SOURCE}${d}g" {} \; \
		-exec sed -i "s${d}__KERNEL_GIT_BRANCH__${d}${KERNEL_GIT_BRANCH}${d}g" {} \; \
		-exec sed -i "s${d}__KERNEL_DEFCONFIG__${d}${KERNEL_DEFCONFIG}${d}g" {} \;
}

function build_gadget_snap()
{
	cd "${BOARD_BUILD_DIR}/${GADGET_SNAP_DIR}"
	sudo snapcraft --build-for="${ARCH}" --destructive-mode --enable-manifest
	cd "${ROOT_DIR}"
}

function build_kernel_snap()
{
	cd "${BOARD_BUILD_DIR}/${KERNEL_SNAP_DIR}"
	sudo snapcraft --build-for="${ARCH}" --destructive-mode --enable-manifest \
		--enable-experimental-plugins
	cd "${ROOT_DIR}"
}

function build_ubuntu_core_image()
{
	cd "${BOARD_BUILD_DIR}"
	sudo rm -rf work
	gadget_snap=$(find "${GADGET_SNAP_DIR}" -name "*.snap")
	kernel_snap=$(find "${KERNEL_SNAP_DIR}" -name "*.snap")

	ASSERTION_FILE="ubuntu-core-22-dangerous-model-${ARCH}.assert"
	/snap/bin/ubuntu-image snap -O out -w work "${ASSERT_DIR}/${ASSERTION_FILE}" \
		--snap="${gadget_snap}" --snap="${kernel_snap}" "${ARG_EXTRA_SNAPS}" --debug
	cd out/

	local output_image_name="${DEVICE}_Ubuntu_Core_22_${BOOT_PROCESS}_${ARCH}.img"
	mv ubuntu-core.img "${output_image_name}"
	echo "Compressing image file..."
	xz -T0 -z "${output_image_name}"

	[ -d "${OUTPUT_DIR}" ] || mkdir -p "${OUTPUT_DIR}"
	mv "${output_image_name}.xz" "${OUTPUT_DIR}"
}

# Parsing arguments
while [ -n "$1" ]; do
	case "$1" in
		--snap=*)
			ARG_EXTRA_SNAPS="${ARG_EXTRA_SNAPS}--snap=${1#*=} "
		;;
		--board=*)
			BOARD="${1#*=}"
		;;
		--boot-process=*)
			BOOT_PROCESS="${1#*=}"
		;;
		--debug)
			set -x
		;;
		* )
			echo "ERROR: unknown option ${1}"
			exit 1
		;;
	esac
	shift
done


ROOT_DIR=$(pwd)
OUTPUT_DIR="${ROOT_DIR}/out"
ROOT_BUILD_DIR="${ROOT_DIR}/cache"
GADGET_SNAP_DIR=gadget_snap
KERNEL_SNAP_DIR=kernel_snap
ASSERT_DIR=assertions
CONFIG_DIR="${ROOT_DIR}/configs"

prepare_build_env
if [ -z "${BOARD}" ]; then
	choose_board
fi
create_build_dir
load_config
build_gadget_snap
build_kernel_snap
build_ubuntu_core_image

echo "Build successfully, output file is under ${OUTPUT_DIR}"
