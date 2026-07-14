#!/bin/bash
# Force PCIe Gen 5 link training on AMD WRX90 upstream bridges.
# Workaround for a motherboard/BIOS bifurcation bug that leaves some
# Gen5-capable GPUs (e.g. Blackwell RTX PRO 6000 / RTX 5090) stuck below Gen5.
#
# It re-programs each PCIe bridge that feeds a Gen5 GPU:
#   CAP_EXP+30.W = 0005  -> Link Control 2: Target Link Speed = Gen5 (0x5)
#   CAP_EXP+10.W = 0c60  -> Link Control:   set Retrain Link bit
#
# HOW TO FIND YOUR BRIDGE IDs (do this once, per machine):
#   lspci -tv                       # show the PCIe tree; note the bridge ABOVE each Gen5 GPU
#   lspci -vv -s <gpu>  | grep LnkCap   # confirm the GPU is Gen5-capable (Speed 32GT/s)
# The bridge is the "PCI bridge" one level up from the GPU (e.g. GPU c1:00.0 -> bridge c0:01.1).
# List every such bridge in BRIDGES below.

BRIDGES="c0:01.1 e0:01.1"   # <-- EDIT: your Gen5 GPU upstream bridges

for b in $BRIDGES; do
    if lspci -s "$b" > /dev/null 2>&1; then
        setpci -s "$b" CAP_EXP+30.W=0005   # Target Link Speed = Gen5
        setpci -s "$b" CAP_EXP+10.W=0c60   # Retrain link
        logger "PCIe Gen5: forced + retrained bridge $b"
    fi
done

# Retrain once more after a moment so the new speed sticks
sleep 1
for b in $BRIDGES; do
    setpci -s "$b" CAP_EXP+10.W=0c60 2>/dev/null
done

logger "PCIe Gen5 fix applied"
