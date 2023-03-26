# UbuntuCoreOS

**Ubuntu Core** is a version of the Ubuntu operating system designed and engineered for IoT and embedded systems.

Ubuntu Core updates itself and its applications automatically. **Snap packages** are used exclusively to create a confined and transaction-based system. **Security and robustness** are its key features, alongside being easy to install, **easy to maintain, and easy to upgrade**.

Ubuntu Core is ideal for embedded devices because it manages itself. Whether it’s running on a Raspberry Pi hidden for media streaming, or a Qualcomm DragonBoard handling garage door automation, Ubuntu Core remains **transparent, trustworthy and autonomous**.

From Linux and maker space tinkerers, to the robotics, automotive and signage industries; from a single device, to a deployment of thousands: Ubuntu Core can handle it.

Please see official [Ubuntu Core documentation](https://ubuntu.com/core/docs) for more infomation

---

## How to use
**Note**: The code is only tested in Ubuntu Jammy environment, other environment are currently not tested.

Step 1: Simply execute
```sh
$ ./build.sh
```
Step 2: Choose a board in the list

Step 3: flash it to SD card
```
$ sudo xzcat OrangePi_PC_Ubuntu_Core_22_armhf.img.xz | sudo dd bs=4M of=/dev/sdX status=progress conv=fsync;sync
```

---

## Future plan
- Support more embedded systems, feel free to let me know if you want me to support any embedded systems, or I can help you to support it.