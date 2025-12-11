-> copy these tools into usr/bin in redhat vm

-> for enabling the can interfaces on the redhat vm
    modprobe can_raw
    modprobe can
    modprobe vxcan

    ip link add dev vcan0 type vxcan peer name vcan1
    ip link set vcan0 up
    ip link set vcan1 up

-> to run the candump.log file
    canplayer -I candump.log vcan1=elmcan
    currently the can interface inside the log file is elmcan, redirect it to vcan1

-> to see the can frames locally on VM
    candump vcan0

-> to publish signle can frame on specific CAN-id 
    cansend vcan1 123#DEADBEEF

-> Using cangen to send continuous data on fixed CAN ID (0x123):
    cangen vcan0 -I 123

-> Using cangen to send continuous data fixed DLC (data length = 8):
    cangen vcan0 -L 8

-> Using cangen to send continuous data fixed data pattern:
    cangen vcan0 -D DEADBEEF

-> Using cangen to send continuous data send frames at a controlled rate (100 frames/sec):
    cangen vcan0 -g 10