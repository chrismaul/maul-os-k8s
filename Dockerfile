FROM archlinux/base AS root
ARG ARCH_MIRROR=http://mirror.math.princeton.edu/pub/archlinux
RUN sed -i "1s|^|Server = $ARCH_MIRROR/\$repo/os/\$arch\n|" /etc/pacman.d/mirrorlist

RUN echo "[archzfs]" >> /etc/pacman.conf && \
  echo "Server = https://archzfs.com/\$repo/\$arch" >> /etc/pacman.conf && \
  pacman-key --init && \
  pacman-key -r DDF7DB817396A49B2A2723F7403BD972F75D9D76 --keyserver hkp://ipv4.pool.sks-keyservers.net:11371 && \
  pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76


RUN pacman -Syyu --needed --noconfirm \
  dhcpcd \
  openssh \
  nfs-utils \
  grub \
  ebtables \
  ethtool \
  socat \
  nfs-utils \
  linux-lts \
  linux-lts-headers \
  tcpdump \
  netplan \
  cloud-init \
  zfs-dkms \
  zfs-utils \
  xfsprogs \
  dracut \
  base \
  base-devel \
  squashfs-tools \
  acpi \
  man-db \
  man-pages \
  binutils \
  expect \
  which \
  bind-tools \
  bc \
  cpio \
  ca-certificates \
  jq \
  rsync \
  vim \
  wget \
  curl \
  cryptsetup \
  device-mapper \
  dhcpcd \
  e2fsprogs \
  efibootmgr \
  intel-ucode \
  linux-firmware \
  systemd \
  sudo \
  lvm2 \
  usbutils \
  inetutils \
  fwupd \
  efitools \
  sbsigntools \
  python-netifaces \
  tpm2-tools \
  tpm2-abrmd \
  screen \
  multipath-tools \
  btrfs-progs \
  mtools \
  busybox

RUN mkdir -p /tmp/download

# export CRI_VERSION="$( curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases | jq -r " map(select(.prerelease == false)) | sort_by(.tag_name) | reverse | .[0].tag_name" )" && \
RUN export CRI_URL=$(curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases | jq -r 'map(select(.prerelease == false)) | sort_by(.tag_name) | reverse | .[0].assets | map(select(.name | test("^crictl-.*linux-amd64.tar.gz$"))) |.[0].browser_download_url ') && \
  curl -L $CRI_URL -o /tmp/download/cri.tar.gz && \
  tar zxvf /tmp/download/cri.tar.gz -C /usr/bin && \
  rm -f /tmp/download/cri.tar.gz

#ARG CONTAINERD_VERS=1.3.2
RUN export CONTAINERD_URL=$(curl -s https://api.github.com/repos/containerd/containerd/releases | jq -r 'map(select(.prerelease == false)) | sort_by(.tag_name) | reverse | .[0].assets | map(select(.name | test("^containerd-.*linux-amd64.tar.gz$"))) |.[0].browser_download_url ') && \
  curl -L $CONTAINERD_URL -o /tmp/download/containerd.tar.gz && \
  tar xf /tmp/download/containerd.tar.gz -C /usr && \
  curl -L https://github.com/containerd/containerd/raw/master/containerd.service -o /usr/lib/systemd/system/containerd.service && \
  sed -i -e 's|/usr/local/bin/containerd|/usr/bin/containerd|' /usr/lib/systemd/system/containerd.service && \
  rm /tmp/download/containerd.tar.gz

#ARG KUBE_VERS=1.16.4
RUN export KUBE_VERS="$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases | jq -r " map(select(.prerelease == false)) | sort_by(.tag_name) | reverse | .[0].tag_name")" && \
  curl -L https://dl.k8s.io/$KUBE_VERS/kubernetes-server-linux-amd64.tar.gz -o /tmp/download/kube.tar.gz && \
  tar xf /tmp/download/kube.tar.gz --strip-components=2 -C /usr \
    kubernetes/server/bin/kubelet \
    kubernetes/server/bin/kube-scheduler \
    kubernetes/server/bin/mounter \
    kubernetes/server/bin/apiextensions-apiserver \
    kubernetes/server/bin/kube-proxy \
    kubernetes/server/bin/kubeadm \
    kubernetes/server/bin/kube-controller-manager \
    kubernetes/server/bin/kube-apiserver \
    kubernetes/server/bin/kubectl

#ARG RUNC_VERS=v1.0.0-rc9
RUN cd /tmp/download && \
  curl -s https://api.github.com/repos/opencontainers/runc/releases | jq -r 'map(select(.prerelease == false)) | sort_by(.tag_name) | reverse | .[0].assets[] | .browser_download_url ' | xargs -n 1 curl -OL  && \
  sha256sum -c runc.sha256sum --ignore-missing && \
  mv runc.amd64 /usr/bin/runc && \
  chmod 755 /usr/bin/runc

COPY files /

RUN for i in \
  etc/environment \
  etc/xdg/ \
  etc/cloud/ \
  etc/security/ \
  etc/ca-certificates/ \
  etc/ssl/ \
  etc/ssh/ \
  etc/pam.d/ \
  etc/profile.d/ \
  etc/bash.bashrc \
  etc/ethertypes \
  etc/netconfig \
  etc/services \
  etc/rpc \
  etc/zfs/ \
  etc/gssproxy/ \
  ; \
do \
  [ -e "/$i" ] && rsync -av /$i /usr/share/factory/$i ; \
done

RUN echo etc-cni.mount \
    etc-kubernetes.mount \
    var-lib-calico.mount \
    var-lib-etcd.mount \
    var-lib-kubelet.mount \
    systemd-networkd.service \
    systemd-resolved.service \
    sshd.service \
    kubelet.service \
    containerd.service \
    cloud-init.service \
    cloud-final.service \
    coldplug.service \
    zfs-import-scan.service \
  | xargs -n 1 systemctl enable && \
  echo cloud-init-local.service \
  | xargs -n 1 systemctl mask

RUN rsync --ignore-existing -av /etc/systemd/ /usr/lib/systemd/

RUN ln -s /var/lib/kubelet/usr /usr/libexec && \
  mkdir -p /usr/local/share/containerd-shims && \
  cd /usr/bin && \
  for i in containerd-shim*; do \
  mv -i $i /usr/local/share/containerd-shims && \
  ln -s /var/run/containerd-shims/latest/$i $i; \
  done

RUN sed -e 's|C! /etc/pam.d|C /etc/pam.d|' -i /usr/lib/tmpfiles.d/etc.conf && \
  cd /usr/lib/firmware && mkdir -p intel-ucode && \
  cat /boot/intel-ucode.img | cpio -idmv && \
  mv kernel/x86/microcode/GenuineIntel.bin intel-ucode/ && \
  rm -r kernel

ARG VERS=dev
RUN sed -e "s/%VERS%/$VERS/g" < /etc/os-release.template > /usr/lib/os-release && cat /usr/lib/os-release

FROM root AS build

RUN mkdir -p /output

RUN cp /usr/lib/os-release /output

RUN mv /usr/lib/modules /modules && \
  ln -s /modules /usr/lib/modules && \
  cd /modules && \
  for MOD_DIR in *; do \
    cd /modules/${MOD_DIR} && \
    mksquashfs * /output/modules_${MOD_DIR}_squashfs && \
    veritysetup format /output/modules_${MOD_DIR}_squashfs /output/modules_${MOD_DIR}_verity > /output/modules_${MOD_DIR}_verity-info.txt; \
  done && \
  mkdir -p /usr/lib/systemd/system/systemd-modules-load.service.wants && \
  ln -s /usr/lib/systemd/system/mount-modules.service /usr/lib/systemd/system/systemd-modules-load.service.wants/mount-modules.service && \
  ln -s /usr/lib/systemd/system/mount-modules.service /usr/lib/systemd/system/multi-user.target.wants/mount-modules.service

RUN mksquashfs usr etc /output/root.squashfs && \
  veritysetup format /output/root.squashfs /output/root.verity > /output/root.verity-info.txt

COPY secureboot /etc/secureboot

RUN KER_VER=$(ls /usr/lib/modules/| head -n1) && dracut --force --uefi --kver $KER_VER /output/kernel.efi

FROM alpine as installer
RUN apk add --no-cache lvm2 coreutils util-linux cryptsetup bash psmisc device-mapper

COPY --from=build /output /output

COPY install/install.sh /install.sh

ENTRYPOINT ["/install.sh"]
