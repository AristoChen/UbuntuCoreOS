# UbuntuCoreOS

**Ubuntu Core** is a version of the Ubuntu operating system designed and engineered for IoT and embedded systems.

Ubuntu Core updates itself and its applications automatically. **Snap packages** are used exclusively to create a confined and transaction-based system. **Security and robustness** are its key features, alongside being easy to install, **easy to maintain, and easy to upgrade**.

Ubuntu Core is ideal for embedded devices because it manages itself. Whether it’s running on a Raspberry Pi hidden for media streaming, or a Qualcomm DragonBoard handling garage door automation, Ubuntu Core remains **transparent, trustworthy and autonomous**.

From Linux and maker space tinkerers, to the robotics, automotive and signage industries; from a single device, to a deployment of thousands: Ubuntu Core can handle it.

Please see official [Ubuntu Core documentation](https://ubuntu.com/core/docs) for more infomation

## Supported devices
- Khadas VIM1
- OrangePi 3
- OrangePi 5
- OrangePi PC
- OrangePi PC2
- OrangePi Zero

## How to use
**Note**: The code is only tested in Ubuntu Jammy environment, other environment are currently not tested.

Step 1: Simply execute
```sh
$ ./build.sh

# If you want to add snaps built-in to the image, please add arguments with the format
# --snap=<SNAP_NAME>=<SNAP_TRACK>/<SNAP_CHANNEL>
$ ./build.sh --snap=network-manager=latest/stable --snap=modem-manager=latest/candidate
```
Step 2: Choose a board in the list

Step 3: flash it to SD card
```
$ sudo xzcat <IMAGE_NAME> | sudo dd bs=4M of=/dev/<SD_CARD_PATH> status=progress conv=fsync;sync
```
Step 4: power on the device, the device will automatically reboot 1 time to finish the installation, then you can login with `ubuntu/ubuntu`.

## Future plan
- Support more embedded systems, feel free to let me know if you want me to support any embedded systems, or I can help you to support it.
- Refactor might be required. Currently some codes are platform specific, other platforms might do things differently, will need to handle them in a better way.
