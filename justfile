set shell := ["bash", "-cu"]

image := source_dir() / "atomvm.img"

# List /dev/cu.usb* devices: auto-pick if there's exactly one,
# otherwise prompt (menu goes to stderr, choice to stdout).

pick_device := '''
    devices=(/dev/cu.usb*)
    if [ ! -e "${devices[0]}" ]; then
        echo "no /dev/cu.usb* device found" >&2
        exit 1
    elif [ ${#devices[@]} -eq 1 ]; then
        echo "${devices[0]}"
    else
        PS3="Port> "
        select d in "${devices[@]}"; do
            [ -n "$d" ] && echo "$d" && break
        done < /dev/tty
    fi
'''

# Build the AtomVM source code and create a release image.
build-atomvm:
    #!/bin/bash
    set -euo pipefail

    # generic build: configure, then build the Erlang/Elixir stdlib beams.
    # mkimage packs build/libs/esp32boot/elixir_esp32boot.avm, so without
    # this make step, edits under AtomVM/libs/ never reach the image.
    cd AtomVM
    mkdir -p build
    cd build
    cmake ..
    make elixir_esp32boot
    cd ..

    # esp32 build
    . $HOME/esp/esp-idf/export.sh
    cd src/platforms/esp32
    idf.py -DATOMVM_ELIXIR_SUPPORT=on set-target esp32
    idf.py build
    # build release image
    cd build
    ./mkimage.sh

    # copy the image to the root
    cp atomvm-esp32-elixir.img  "{{ source_dir() }}/atomvm.img"

# Build the host (generic_unix) AtomVM binary and the boot lib, for `just run-local`.
# net_kernel needs the crypto NIF, so the VM must link mbedTLS: brew install mbedtls@3
# (keg-only, hence the explicit MbedTLS_DIR; mbedtls 4.x has a layout AtomVM can't use).
build-atomvm-host:
    #!/bin/bash
    set -euo pipefail
    mkdir -p AtomVM/build
    cd AtomVM/build
    mbedtls="$(brew --prefix mbedtls@3 2>/dev/null || true)/lib/cmake/MbedTLS"
    if [ -d "$mbedtls" ]; then
        cmake .. -DMbedTLS_DIR="$mbedtls"
    else
        echo "warning: mbedtls@3 not found - building without crypto (net_kernel will not start)" >&2
        cmake ..
    fi
    make -j8 AtomVM elixir_esp32boot

# Run the app on this machine under AtomVM generic_unix, to catch functions the
# device image doesn't have before flashing. WiFi is skipped (Wifi.connect returns
# loopback on generic_unix), everything else boots for real: distribution, UDP
# discovery, work queue, web API on port 8123. The boot lib is cut down to the same
# 512KB the boot.avm partition holds - whole modules only, then a zeroed section
# header, because the VM scans the pack until a zero header and would otherwise
# run off the end of the file (the flashed board stops at the partition edge).
run-local:
    #!/bin/bash
    set -euo pipefail
    vm=AtomVM/build/src/AtomVM
    boot=AtomVM/build/libs/esp32boot/elixir_esp32boot.avm
    boot_512k="${boot%.avm}-512k.avm"
    [ -x "$vm" ] && [ -f "$boot" ] || { echo "host VM or boot lib missing - run 'just build-atomvm-host' first" >&2; exit 1; }
    (cd nano_cluster && mix atomvm.packbeam)
    python3 - "$boot" "$boot_512k" <<'EOF'
    import sys
    PARTITION = 0x80000
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    assert data[:21] == b"#!/usr/bin/env AtomVM", f"{src} is not an avm pack"
    out, off = bytearray(data[:24]), 24
    while off + 12 <= len(data):
        size = int.from_bytes(data[off:off + 4], "big")
        if size == 0 or off + size > PARTITION:  # end marker, or cut off by the partition edge
            break
        out += data[off:off + size]
        off += size
    # names of what fell past the partition edge, for visibility
    dropped, o = [], off
    while o + 12 <= len(data):
        size = int.from_bytes(data[o:o + 4], "big")
        if size == 0:
            break
        dropped.append(data[o + 12:data.index(b"\0", o + 12)].decode())
        o += size
    out += b"\0" * 12
    open(dst, "wb").write(out)
    print(f"boot lib: kept {off - 24} bytes; not on the device: {', '.join(dropped) or 'nothing'}")
    EOF
    exec "$vm" nano_cluster/nano_cluster.avm "$boot_512k"

# Flash the AtomVM image to the ESP32 (wipes WiFi NVS and the app partition head - run set-wifi, then flash-app after)
flash port=shell(pick_device):
    esptool.py \
        --chip auto \
        --port {{ port }} --baud 921600 \
        --before default_reset --after hard_reset \
        write_flash -u \
        --flash_mode dio --flash_freq 40m --flash_size detect \
        0x1000 \
        atomvm.img

# Build and flash the nano_cluster app (VM stays untouched)
flash-app port=shell(pick_device):
    #!/bin/bash
    cd nano_cluster
    mix atomvm.esp32.flash --port {{ port }} --baud 921600

# Watch serial output from the board (quit with Ctrl-]). Output stays in
# the terminal's own scrollback and is appended to serial.log for later:

# less +G serial.log
monitor port=shell(pick_device):
    python3 -u -m serial.tools.miniterm {{ port }} 115200 --raw | tee -a serial.log

# only update the elixir code
reinstall port=shell(pick_device): (flash port) (flash-app port) (monitor port)

# only update the elixir code
update port=shell(pick_device): (flash-app port) (monitor port)

# Open the cluster overview page in the browser (runs on this machine, not on the nodes)
overview:
    open overview/index.html

# One-shot: store WiFi credentials in NVS on the board, then reflash the app
set-wifi ssid psk port=shell(pick_device):
    cd nano_cluster && WIFI_SSID='{{ ssid }}' WIFI_PSK='{{ psk }}' mix do compile --force + atomvm.esp32.flash --port {{ port }} --baud 921600
