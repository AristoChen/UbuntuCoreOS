# Ubuntu Core 22 U-Boot script (for armhf and arm64)

setenv bootargs "__BOOTLOADER_BOOTARGS__"

setenv devtype mmc
setenv mmc_dev_num __MMC_DEV_NUM__
setenv mmc_seed_part 1
setenv mmc_boot_part 2
setenv fitloadaddr __FIT_LOAD_ADDR__

setenv core_state "/uboot/ubuntu/boot.sel"
setenv kernel_bootpart ${mmc_seed_part}

load ${devtype} ${mmc_dev_num}:${distro_bootpart} ${kernel_addr_r} ${core_state}
setenv kernel_filename kernel.img
setenv kernel_vars "snap_kernel snap_try_kernel kernel_status"
setenv recovery_vars "snapd_recovery_mode snapd_recovery_system snapd_recovery_kernel"
setenv snapd_recovery_mode "install"
setenv snapd_standard_params "panic=-1"

env import -c ${kernel_addr_r} ${filesize} ${recovery_vars}
setenv bootargs "${bootargs} snapd_recovery_mode=${snapd_recovery_mode} snapd_recovery_system=${snapd_recovery_system} ${snapd_standard_params}"

if test "${snapd_recovery_mode}" = "run"; then
  setenv kernel_bootpart ${mmc_boot_part}
  load ${devtype} ${mmc_dev_num}:${kernel_bootpart} ${kernel_addr_r} ${core_state}
  env import -c ${kernel_addr_r} ${filesize} ${kernel_vars}
  setenv kernel_name "${snap_kernel}"

  if test -n "${kernel_status}"; then
    if test "${kernel_status}" = "try"; then
      if test -n "${snap_try_kernel}"; then
        setenv kernel_status trying
        setenv kernel_name "${snap_try_kernel}"
      fi
    elif test "${kernel_status}" = "trying"; then
      setenv kernel_status ""
    fi
    env export -c ${kernel_addr_r} ${kernel_vars}
    save ${devtype} ${mmc_dev_num}:${kernel_bootpart} ${kernel_addr_r} ${pathprefix}${core_state} ${filesize}
  fi
  setenv kernel_prefix "uboot/ubuntu/${kernel_name}/"
else
  setenv kernel_prefix "systems/${snapd_recovery_system}/kernel/"
fi

load ${devtype} ${mmc_dev_num}:${kernel_bootpart} ${fitloadaddr} ${kernel_prefix}/${kernel_filename}

bootm ${fitloadaddr}
