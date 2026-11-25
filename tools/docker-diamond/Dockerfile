# Lattice Diamond headless build image for the MachXO2 course board.
# Runs under Rosetta on Apple Silicon (Diamond ships x86_64 Linux only).
#
# The vendor installer (Qt IFW GUI) cannot run unattended here, so this
# image assembles Diamond directly from the 7z package segments carved out
# of the installer file (installer/carved/, produced by a carve script;
# questasim and micosystem segments skipped).
#
# License: mount a node-locked license at /work/license/license.dat and
# run the container with --mac-address=00:0c:29:d5:14:8e (see run-synth.sh
# and README.md).
FROM rockylinux:8

# Dependency set per the Diamond 3.14 Linux install guide (trimmed: no
# ModelSim 32-bit libs, no firefox). libXss comes from libXScrnSaver.
RUN yum update -y && \
  yum install -y glibc nss-softokn-freebl libjpeg libtiff zlib glib2 libselinux \
    gamin libusb freetype fontconfig expat libX11 libxcb libXau libICE libSM \
    libuuid libXt libXext libXrender libXi libXft && \
  yum install -y perl tcsh libXScrnSaver xorg-x11-server-Xvfb && \
  yum install -y epel-release && yum install -y p7zip-plugins && \
  yum clean all -y

COPY installer/carved/ /tmp/segs/
RUN mkdir -p /opt/lscc/diamond/3.14 && cd /opt/lscc/diamond/3.14 && \
  for s in /tmp/segs/seg*.7z; do \
    case "$s" in \
      *seg08*|*seg13*) ;; \
      *) 7z x -y "$s" > /dev/null ;; \
    esac; \
  done && \
  ls bin/lin64/ | head -5 && \
  rm -rf /tmp/segs && \
  yum remove -y p7zip-plugins epel-release && yum clean all -y

COPY build.sh /opt/build.sh
COPY build.tcl /opt/build.tcl
RUN chmod +x /opt/build.sh

ENV DIA_DIR=/opt/lscc/diamond/3.14
ENV DIA_BIN=/opt/lscc/diamond/3.14/bin/lin64
ENV PATH="$DIA_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LM_LICENSE_FILE=/work/license/license.dat
WORKDIR /work/project
CMD ["/bin/bash"]
