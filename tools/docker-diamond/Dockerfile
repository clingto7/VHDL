# Lattice Diamond headless build image for the MachXO2 course board.
# Runs under Rosetta on Apple Silicon (Diamond ships x86_64 Linux only).
#
# Before building, drop the Diamond Linux rpm into ./rpm/ (Lattice gate
# software downloads behind an account login; docs are free, installers
# are not). The file lands as "Diamond 3.14 64-bit for Linux".
#
# License: mount a node-locked license at /work/license/license.dat and
# run the container with --mac-address=02:50:F2:00:00:42 (see run-synth.sh
# and README.md).
FROM --platform=linux/amd64 rockylinux:8

# Dependency set trimmed from Gekkio/docker-fpga (no ModelSim 32-bit libs,
# no firefox): Diamond LSE/synpwrap + Xvfb fallback for batch Tcl.
RUN yum update -y && \
  yum install -y glibc nss-softokn-freebl libjpeg libtiff zlib glib2 libselinux \
    gamin libusb freetype fontconfig expat libX11 libxcb libXau libICE libSM \
    libuuid libXt libXext libXrender libXi libXft && \
  yum install -y perl tcsh libXScrnSaver xorg-x11-server-Xvfb && \
  yum clean all -y

COPY rpm/*.rpm /tmp/diamond.rpm
RUN yum install -y /tmp/diamond.rpm && rm -f /tmp/diamond.rpm && yum clean all -y

COPY build.sh /opt/build.sh
COPY build.tcl /opt/build.tcl
RUN chmod +x /opt/build.sh

ENV LM_LICENSE_FILE=/work/license/license.dat
WORKDIR /work/project
CMD ["/bin/bash"]
